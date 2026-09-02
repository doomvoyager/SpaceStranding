@tool
extends Node3D
class_name ProceduralTerrain
## Single-patch heightfield terrain, from either authored art or noise.
##
## Two sources, chosen by `height_source`:
##
## * **Heightmap** — samples the authored Gaea bake. This is what the world uses.
## * **Procedural** — the original three-octave noise. Kept because every test
##   that builds its own ground wants a patch with no 15 MB dependency, and
##   because it is still the fastest way to get arbitrary relief for a probe.
##
## Still a *single patch*: no streaming, no LOD. The shipping terrain will be a
## streamed, chunked setup (Terrain3D or equivalent). Keep gameplay code from
## depending on anything in here.
##
## The class name predates the heightmap source and is now half a lie. Renaming
## it touches sixteen test files, so it is a deliberate TODO rather than drift.

## Emitted after the mesh and collision are rebuilt. Anything that placed
## objects on the surface — RockScatter — has to put them back, or a retune
## leaves them hanging in the air over the new ground.
signal rebuilt

enum HeightSource {
	PROCEDURAL, ## Layered FastNoiseLite. No asset dependency.
	HEIGHTMAP,  ## The authored bake. See tools/bake-terrain.py.
}

## Used when `heightmap` is left empty, so flipping the source on a fresh node
## does something useful instead of nothing. Loaded lazily rather than
## preloaded: `preload()` resolves when the *script* loads, which would drag 50
## MB into every headless test that builds a procedural patch.
const DEFAULT_HEIGHTMAP := "res://assets/terrain/world_01_height_2049.exr"

@export_group("Source")
## Where the heightfield comes from. Defaults to procedural so that a
## bare `ProceduralTerrain.new()` in a test keeps costing nothing; the world
## scene sets this to Heightmap explicitly.
@export var height_source: HeightSource = HeightSource.PROCEDURAL:
	set(v):
		height_source = v
		_queue_rebuild()
## Single-channel float heightfield, values in 0..1. Anything else is remapped
## by its own min and max, so the numbers below are always metres of real
## relief rather than metres per arbitrary unit.
@export var heightmap: Texture2D:
	set(v):
		heightmap = v
		_map_source = null  # force a re-read; the cache is keyed on the texture
		_queue_rebuild()
## Metres from the map's lowest sample to its highest.
##
## Relief, not scale, so it stays meaningful when the map is re-exported with a
## different range. 210 m over the 4096 m patch gives a median grade of about
## 3 degrees and a p99 of 17 — rolling and drivable, with the massif genuinely
## impassable on its steep faces.
@export var height_span := 210.0:
	set(v):
		height_span = v
		_queue_rebuild()
## Local-space height of the map's *lowest* sample. Leave at 0 to have the
## terrain's floor sit on its own origin.
@export var height_floor := 0.0:
	set(v):
		height_floor = v
		_queue_rebuild()

@export_group("Extent")
## Side length of the patch in metres.
@export var size := 512.0:
	set(v):
		size = v
		_queue_rebuild()
## Metres between height samples. Smaller is smoother and far more expensive.
@export var resolution := 2.0:
	set(v):
		resolution = maxf(v, 0.5)
		_queue_rebuild()

@export_group("Shape")
## Everything in this group applies to the Procedural source only.
@export var height_scale := 48.0:
	set(v):
		height_scale = v
		_queue_rebuild()
## Named to avoid shadowing GDScript's built-in seed().
@export var noise_seed := 20260830:
	set(v):
		noise_seed = v
		_queue_rebuild()
## Weight of the ridged layer. High values give sharp, wind-scoured spines.
@export_range(0.0, 1.0) var ridge_weight := 0.55:
	set(v):
		ridge_weight = v
		_queue_rebuild()

@export_group("Look")
## Surface material for the generated mesh. Defaults to the painterly regolith
## resource — open it in the inspector to dial bands, brush stamps and shadow
## hue live. Clear it to fall back to the plain PBR placeholder.
@export var surface_material: Material = preload("res://materials/regolith.tres"):
	set(v):
		surface_material = v
		if _mesh_instance != null:
			_mesh_instance.material_override = _resolve_material()

@export_group("Actions")
## Inspector button: ticking this regenerates and immediately unticks itself.
@export var rebuild := false:
	set(_v):
		rebuild = false
		_build()

var _mesh_instance: MeshInstance3D
var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _heights: PackedFloat32Array
var _samples := 0
var _rebuild_queued := false

# Decoded heightmap, cached across rebuilds. Re-reading costs ~10 ms for the
# pixels and ~150 ms for the range scan, which is a lot to pay on every drag of
# a size slider. Keyed on the texture so swapping maps still refreshes.
var _map_source: Texture2D
var _map_data: PackedFloat32Array
var _map_w := 0
var _map_h := 0
var _map_lo := 0.0
var _map_hi := 1.0


func _ready() -> void:
	# The group is how everything else finds the ground. Nothing joined it
	# until now, so Lattice._terrain()'s fast path missed every time and fell
	# through to a recursive walk of the whole tree - 10 us a call, on a
	# function the route line calls four hundred times a frame. See
	# tests/probe_scan_cost.tscn.
	add_to_group("terrain")
	_build()


func _queue_rebuild() -> void:
	# Setters fire during scene load before children exist; defer until safe,
	# and coalesce the burst of setter calls into a single rebuild.
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_queued_rebuild.call_deferred()


func _do_queued_rebuild() -> void:
	_rebuild_queued = false
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	_samples = int(size / resolution) + 1
	_generate_heights()
	_build_mesh()
	_build_collision()
	rebuilt.emit()


# --- Heightfield --------------------------------------------------------

func _generate_heights() -> void:
	_heights = PackedFloat32Array()
	_heights.resize(_samples * _samples)
	if height_source == HeightSource.HEIGHTMAP and _sample_heightmap():
		return
	_generate_heights_procedural()


## Fills `_heights` from the authored bake. Returns false if there is no usable
## map, in which case the caller falls back to noise rather than to flat ground
## — a terrain that silently becomes a plane is much harder to notice than one
## that looks wrong.
func _sample_heightmap() -> bool:
	var tex := heightmap
	if tex == null:
		tex = load(DEFAULT_HEIGHTMAP) as Texture2D
	if tex == null:
		push_warning("Terrain: heightmap source selected but no map could be "
			+ "loaded; falling back to procedural.")
		return false
	if tex != _map_source and not _read_map(tex):
		return false

	var span := _map_hi - _map_lo
	# A constant map would divide by zero and is a mistake worth reporting
	# rather than flattening.
	if is_zero_approx(span):
		push_warning("Terrain: heightmap has no relief; falling back to procedural.")
		return false
	var scale_to_metres := height_span / span

	# The patch maps onto the whole texture, so the grid steps in texel space by
	# however much the two resolutions differ. When the grid divides the map
	# evenly — 1025 samples into a 2049 map, say — every step lands exactly on a
	# texel and the bilinear blend below collapses to an exact read.
	var last := float(_samples - 1)
	var step_x := float(_map_w - 1) / last
	var step_z := float(_map_h - 1) / last

	for z in _samples:
		var fz := z * step_z
		for x in _samples:
			var raw := _bilinear_map(x * step_x, fz)
			_heights[z * _samples + x] = 				height_floor + (raw - _map_lo) * scale_to_metres
	return true


## Decodes a heightmap texture into a flat float buffer and records its range.
func _read_map(tex: Texture2D) -> bool:
	var img := tex.get_image()
	if img == null:
		push_warning("Terrain: heightmap has no readable image.")
		return false

	# The importer hands back RGBF for a single-channel float EXR — three
	# channels holding the same value, measured in probe_heightmap_import.gd.
	# Convert to RF so the buffer is one float per texel, on a copy, because the
	# Image returned by a CompressedTexture2D may be shared with the resource.
	var work := Image.create_from_data(
		img.get_width(), img.get_height(), false, img.get_format(), img.get_data())
	work.convert(Image.FORMAT_RF)

	_map_data = work.get_data().to_float32_array()
	_map_w = work.get_width()
	_map_h = work.get_height()
	_map_source = tex

	# ~150 ms over a 2049 map, which is why this is cached and not per-rebuild.
	# PackedFloat32Array is a builtin, not an Object: there is no min()/max() to
	# call and no has_method() to test for one.
	_map_lo = INF
	_map_hi = -INF
	for v in _map_data:
		_map_lo = minf(_map_lo, v)
		_map_hi = maxf(_map_hi, v)
	return true


func _bilinear_map(fx: float, fz: float) -> float:
	var x0 := clampi(int(fx), 0, _map_w - 1)
	var z0 := clampi(int(fz), 0, _map_h - 1)
	var x1 := mini(x0 + 1, _map_w - 1)
	var z1 := mini(z0 + 1, _map_h - 1)
	var tx := fx - x0
	var tz := fz - z0
	var row0 := z0 * _map_w
	var row1 := z1 * _map_w
	return lerpf(
		lerpf(_map_data[row0 + x0], _map_data[row0 + x1], tx),
		lerpf(_map_data[row1 + x0], _map_data[row1 + x1], tx),
		tz
	)


func _generate_heights_procedural() -> void:
	var base := FastNoiseLite.new()
	base.seed = noise_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.0018
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 5
	base.fractal_lacunarity = 2.1
	base.fractal_gain = 0.48

	var ridged := FastNoiseLite.new()
	ridged.seed = noise_seed + 977
	ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridged.frequency = 0.0031
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridged.fractal_octaves = 4
	ridged.fractal_lacunarity = 2.0
	ridged.fractal_gain = 0.5

	var detail := FastNoiseLite.new()
	detail.seed = noise_seed + 4231
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = 0.021
	detail.fractal_octaves = 2

	for z in _samples:
		for x in _samples:
			var wx := x * resolution
			var wz := z * resolution
			var b := base.get_noise_2d(wx, wz)              # [-1, 1]
			var r := ridged.get_noise_2d(wx, wz) * 0.5 + 0.5 # [0, 1]
			var h := lerpf(b, r * 2.0 - 1.0, ridge_weight)
			h += detail.get_noise_2d(wx, wz) * 0.06
			_heights[z * _samples + x] = h * height_scale


## Whether there is a heightfield to query yet.
##
## Worth asking before trusting `height_at()`, because an unbuilt terrain
## answers zero for every point rather than failing — and zero is a plausible
## height, so anything solving positions against it silently piles the whole
## scene onto this node's own origin. The editor asks: the ground snapper in
## `res://addons/spawn_gizmos` refuses to move anything until this is true.
func is_built() -> bool:
	return _samples > 0 and _heights.size() == _samples * _samples


func height_at_index(x: int, z: int) -> float:
	if _heights.is_empty():
		return 0.0
	x = clampi(x, 0, _samples - 1)
	z = clampi(z, 0, _samples - 1)
	return _heights[z * _samples + x]


## Bilinear height lookup in the terrain's local space. Handy for dropping
## objects onto the ground without a physics query.
func height_at(local_x: float, local_z: float) -> float:
	var fx := (local_x + size * 0.5) / resolution
	var fz := (local_z + size * 0.5) / resolution
	var x0 := int(floorf(fx))
	var z0 := int(floorf(fz))
	var tx := fx - x0
	var tz := fz - z0
	return lerpf(
		lerpf(height_at_index(x0, z0), height_at_index(x0 + 1, z0), tx),
		lerpf(height_at_index(x0, z0 + 1), height_at_index(x0 + 1, z0 + 1), tx),
		tz
	)


## Ground height in **world** space at a world x/z.
##
## `height_at()` above returns a height in this node's own space, and the Terrain
## in test_world.tscn carries a 0.5 scale on Y because Mac flattens the world by
## scaling it in the editor. Using that number as a world Y puts things at twice
## the ground height, which is a bug this project has already shipped once — see
## docs/02-Systems/Terrain.md. Anything asking "where is the ground" from world
## coordinates should call this and not think about it.
##
## Assumes the terrain is translated and scaled but not rotated, which is what
## `to_local` on a point directly above the query handles; a rotated terrain
## would need a real ray against the mesh.
func world_height_at(world_x: float, world_z: float) -> float:
	var local := to_local(Vector3(world_x, 0.0, world_z))
	return to_global(Vector3(local.x, height_at(local.x, local.z), local.z)).y


## World-space surface point under (world_x, world_z). `world_height_at` with
## the X and Z carried through, which is what most callers actually wanted —
## four of them were building this by hand out of `to_local`, `height_at` and
## `to_global`, each with its own copy of the warning above.
func world_surface_at(world_x: float, world_z: float) -> Vector3:
	return Vector3(world_x, world_height_at(world_x, world_z), world_z)


## Where the ground is, as a footprint in world X/Z.
##
## **This is the seam.** Everything outside this file used to reach for `size`
## and halve it, which silently assumed one patch centred on the terrain node's
## own origin — true only while there is exactly one patch. `rock_scatter.gd`
## already had to be fixed once when the authored map arrived 1.3 km from the
## origin, and the fix was a local patch rather than a contract. With nine
## tiles there is no `size` to halve at all, so asking a *field* where it is has
## to be the question, and this is it.
##
## Position is the minimum corner, size is the span in metres. Assumes the
## terrain is translated and scaled but not rotated, same as `world_height_at`.
func extent() -> Rect2:
	var half := size * 0.5
	var lo := to_global(Vector3(-half, 0.0, -half))
	var hi := to_global(Vector3(half, 0.0, half))
	return Rect2(minf(lo.x, hi.x), minf(lo.z, hi.z),
		absf(hi.x - lo.x), absf(hi.z - lo.z))


## World metres between height samples — the finest detail the field carries,
## and the step anything walking the ground should use rather than inventing
## one. Derived from `extent()` rather than returning `resolution`, because the
## node's scale is part of the answer.
func sample_step() -> float:
	if _samples <= 1:
		return resolution
	return extent().size.x / float(_samples - 1)


# --- Mesh ---------------------------------------------------------------

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	# UV2 spans the patch 0..1, which is what an authored map painted for this
	# terrain needs. UV1 above is world metres over 16 and tiles hundreds of
	# times across the patch, so it can carry detail but never the macro albedo.
	# Deriving one from the other would hard-code the patch size into the
	# material and break silently the next time `size` moves.
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	verts.resize(_samples * _samples)
	normals.resize(_samples * _samples)
	uvs.resize(_samples * _samples)
	uv2s.resize(_samples * _samples)

	var half := size * 0.5
	var inv_2r := 1.0 / (2.0 * resolution)

	for z in _samples:
		for x in _samples:
			var i := z * _samples + x
			verts[i] = Vector3(
				x * resolution - half,
				height_at_index(x, z),
				z * resolution - half
			)
			# Central differences on the heightfield give exact normals cheaply.
			var dx := (height_at_index(x + 1, z) - height_at_index(x - 1, z)) * inv_2r
			var dz := (height_at_index(x, z + 1) - height_at_index(x, z - 1)) * inv_2r
			normals[i] = Vector3(-dx, 1.0, -dz).normalized()
			uvs[i] = Vector2(x * resolution, z * resolution) / 16.0
			uv2s[i] = Vector2(float(x), float(z)) / float(_samples - 1)

	# Godot treats CLOCKWISE-wound triangles as front faces. Wound the other way
	# the whole terrain is backface-culled and you fall through an invisible world.
	for z in _samples - 1:
		for x in _samples - 1:
			var i := z * _samples + x
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + _samples)
			indices.append(i + 1)
			indices.append(i + _samples + 1)
			indices.append(i + _samples)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)
		# Deliberately no owner: this must never be serialised into the .tscn,
		# or every save bakes a six-figure-triangle mesh into the scene file.
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _resolve_material()


func _resolve_material() -> Material:
	return surface_material if surface_material != null else _fallback_material()


## Plain PBR stand-in, kept so the terrain is still visible if the painterly
## material is cleared or fails to load.
func _fallback_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Iron-rich dust under a red sun. Desaturated, not orange-cartoon.
	mat.albedo_color = Color(0.34, 0.24, 0.19)
	mat.roughness = 0.94
	mat.metallic = 0.0
	# Triplanar keeps steep canyon walls from smearing until we have real textures.
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.06, 0.06, 0.06)
	return mat


# --- Collision ----------------------------------------------------------

func _build_collision() -> void:
	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "TerrainBody"
		add_child(_static_body)
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "TerrainCollision"
		_static_body.add_child(_collision_shape)

	# A trimesh of the visual mesh, rather than HeightMapShape3D: the height shape
	# samples on a fixed 1-unit grid, which would force a non-uniform scale on the
	# CollisionShape3D to reach our sample spacing, and Jolt rejects that.
	_collision_shape.shape = _mesh_instance.mesh.create_trimesh_shape()
