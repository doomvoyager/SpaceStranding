@tool
extends Node3D
class_name ProceduralTerrain
## Placeholder heightfield terrain for the traversal slice.
##
## This exists so there is ground to drive on. It is not the shipping terrain
## system — that will be a streamed, chunked, artist-authored setup (Terrain3D or
## equivalent). Keep gameplay code from depending on anything in here.

## Emitted after the mesh and collision are rebuilt. Anything that placed
## objects on the surface — RockScatter — has to put them back, or a retune
## leaves them hanging in the air over the new ground.
signal rebuilt

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
@export var surface_material: Material = preload("res://materials/regolith_painterly.tres"):
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


func _ready() -> void:
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

	_heights = PackedFloat32Array()
	_heights.resize(_samples * _samples)

	for z in _samples:
		for x in _samples:
			var wx := x * resolution
			var wz := z * resolution
			var b := base.get_noise_2d(wx, wz)              # [-1, 1]
			var r := ridged.get_noise_2d(wx, wz) * 0.5 + 0.5 # [0, 1]
			var h := lerpf(b, r * 2.0 - 1.0, ridge_weight)
			h += detail.get_noise_2d(wx, wz) * 0.06
			_heights[z * _samples + x] = h * height_scale


func height_at_index(x: int, z: int) -> float:
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


# --- Mesh ---------------------------------------------------------------

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	verts.resize(_samples * _samples)
	normals.resize(_samples * _samples)
	uvs.resize(_samples * _samples)

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
