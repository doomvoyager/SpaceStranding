@tool
extends Node3D
class_name RockScatter
## Boulders scattered over the terrain patch, in distance-culled cells.
##
## **Cells are the whole design, not an optimisation detail.** A MultiMesh is
## one instance holding thousands of transforms, so a single MultiMesh covering
## the patch has one patch-sized AABB — the camera is always inside it, so it
## can never be frustum-culled and `visibility_range_end` never fires. Measured
## in `tests/probe_scatter_cull.gd`: a 120 m range on a whole-patch MultiMesh
## dropped exactly zero of its 1,376,256 primitives. Split into 32 m cells the
## same scatter draws 96,768.
##
## The other end bites too: cells cost a draw call each, and 16 m cells with no
## range measured *worse* than doing nothing at all. Cells only pay while
## culling is eating them.
##
## And a MultiMesh holds exactly **one** mesh, so every rock variant is its own
## instance in every cell — six variants at two detail tiers is up to twelve
## multimeshes per cell. That multiplier is why `cell_size` defaults to 48 and
## not to the 32 the synthetic probe found: measured on the real scatter in
## `tests/probe_scatter_cost.gd`, 48 m cells draw the same primitives as 32 m
## for a quarter fewer draw calls.
##
## Nothing here runs per frame. Culling is `visibility_range_*` on each cell,
## which the render server does on its own.

## Emitted after a rebuild, with the number of rocks actually placed.
signal scattered(placed: int)

@export_group("Source")
## The terrain to sit on. Heights come from `ProceduralTerrain.height_at()`
## rather than from physics queries, the same way test_world places the rover.
@export var terrain_path := NodePath("../Terrain"):
	set(v):
		terrain_path = v
		_queue_rebuild()

@export_group("Density")
## Placements *attempted*. Slope and clump rejection means fewer land — the
## `scattered` signal reports how many.
@export_range(0, 30000, 1) var count := 9000:
	set(v):
		count = v
		_queue_rebuild()
## Named to avoid shadowing GDScript's built-in seed(), as in terrain.gd.
@export var noise_seed := 20260831:
	set(v):
		noise_seed = v
		_meshes.clear()
		_queue_rebuild()

@export_group("Distance culling")
## Side of one cell, in metres. Bigger culls less, smaller spends more draw
## calls than it saves. The knee is 48 once the per-variant multimeshes are
## counted — see the note at the top.
@export_range(8.0, 128.0, 1.0) var cell_size := 48.0:
	set(v):
		cell_size = maxf(v, 4.0)
		_queue_rebuild()
## Where the detailed mesh hands over to the low-poly one.
@export_range(10.0, 400.0, 1.0) var near_distance := 55.0:
	set(v):
		near_distance = v
		_apply_ranges()
## Past this, cells are not drawn at all.
@export_range(20.0, 1000.0, 1.0) var cull_distance := 170.0:
	set(v):
		cull_distance = v
		_apply_ranges()
## Distance over which a cell dithers out instead of popping.
@export_range(0.0, 100.0, 1.0) var fade_margin := 18.0:
	set(v):
		fade_margin = v
		_apply_ranges()

@export_group("Shape")
@export_range(0.1, 20.0, 0.05) var size_min := 0.5:
	set(v):
		size_min = v
		_queue_rebuild()
@export_range(0.1, 20.0, 0.05) var size_max := 4.5:
	set(v):
		size_max = v
		_queue_rebuild()
## Above 1 the roll is biased toward `size_min`, so the field is mostly gravel
## with the occasional boulder. A flat distribution reads as an even hail of
## identically-sized lumps.
@export_range(0.2, 6.0, 0.1) var size_bias := 2.2:
	set(v):
		size_bias = v
		_queue_rebuild()
## Fraction of its own **half-height** each rock is buried, so they read as
## sitting in the regolith rather than resting on it.
##
## Measured against the mesh's real height, not its diameter. Boulders are
## squashed on Y, so a half-height is barely a third of a diameter — sinking by
## a fraction of the diameter buried about 70% of every rock and the field read
## as flat plates lying on the sand.
@export_range(0.0, 0.9, 0.01) var sink := 0.3:
	set(v):
		sink = v
		_queue_rebuild()
## How many distinct rock meshes to generate. Each is reused thousands of times.
@export_range(1, 16, 1) var variants := 6:
	set(v):
		variants = v
		_meshes.clear()
		_queue_rebuild()

@export_group("Placement")
## Rocks are rejected above this ground slope. Measured in **world** space: the
## Terrain node carries a Y scale that flattens the map, so a local slope is
## not the slope you see.
@export_range(0.0, 90.0, 1.0) var max_slope_deg := 38.0:
	set(v):
		max_slope_deg = v
		_queue_rebuild()
## 0 sprinkles rocks evenly, which reads as procedural wallpaper. Higher values
## thin them into fields with bare ground between.
@export_range(0.0, 1.0, 0.01) var clump_amount := 0.55:
	set(v):
		clump_amount = v
		_queue_rebuild()
## Metres per clump feature.
@export_range(5.0, 400.0, 1.0) var clump_scale := 70.0:
	set(v):
		clump_scale = v
		_queue_rebuild()
## How far each rock leans with the ground. 1 stands every rock perpendicular to
## the slope, which looks combed; 0 leaves them all plumb.
@export_range(0.0, 1.0, 0.01) var normal_align := 0.55:
	set(v):
		normal_align = v
		_queue_rebuild()
@export_range(0.0, 30.0, 0.5) var tilt_jitter_deg := 8.0:
	set(v):
		tilt_jitter_deg = v
		_queue_rebuild()

@export_group("Collision")
## Rocks at least this many metres across get a convex shape. Everything below
## is visual only — a scatter where every pebble is solid is both expensive and
## horrible to drive over.
@export_range(0.0, 20.0, 0.05) var collision_above := 1.4:
	set(v):
		collision_above = v
		_queue_rebuild()

@export_group("Look")
@export var material: Material = preload("res://materials/rock.tres"):
	set(v):
		material = v
		_apply_material()
## Authored meshes, when there are any. Empty means the procedural placeholders
## in RockMesh — drop real models in here and the scatter uses those instead.
@export var rock_meshes: Array[Mesh] = []:
	set(v):
		rock_meshes = v
		_meshes.clear()
		_queue_rebuild()

@export_group("Actions")
## Inspector button: ticking this regenerates and immediately unticks itself.
@export var rebuild := false:
	set(_v):
		rebuild = false
		_build()

var _terrain: ProceduralTerrain
var _cells: Node3D
## [[near, far], ...] per variant. Rebuilt only when the variant set changes.
var _meshes: Array = []
var _shapes: Array[Shape3D] = []
## Each variant's Y half-extent at unit scale, for sinking rocks by their real
## height rather than by their diameter.
var _half_heights := PackedFloat32Array()
var _rebuild_queued := false
var _placed := 0

## Where the rocks ended up, in this node's local space, and how big each is.
##
## The MultiMesh is otherwise the only record, and **a MultiMesh's per-instance
## transforms do not survive a headless run** — the dummy renderer takes the
## write without error and returns identity, measured in
## `probe_multimesh_readback.gd`. Nothing outside the renderer can ask a
## MultiMesh where its instances are, so anything that needs to know — a test,
## or later a spawn rule that would rather not drop a crate inside a boulder —
## reads these instead. 4000 rocks is 64 KB.
var _positions := PackedVector3Array()
var _sizes := PackedFloat32Array()


func _ready() -> void:
	# Deferred rather than immediate: the terrain generates its heightfield in
	# its own _ready(), and a scatter that samples it first gets nothing.
	_queue_rebuild()


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


# --- Build --------------------------------------------------------------

func _build() -> void:
	if not is_inside_tree():
		return
	_terrain = get_node_or_null(terrain_path) as ProceduralTerrain
	if _terrain == null:
		_clear()
		return

	if not _terrain.rebuilt.is_connected(_on_terrain_rebuilt):
		_terrain.rebuilt.connect(_on_terrain_rebuilt)

	_ensure_meshes()
	_clear()

	# Deliberately no owner on anything below: a @tool script that owns its
	# generated nodes serialises them into the .tscn, which would bake every
	# rock in the field into the scene file on every save.
	_cells = Node3D.new()
	_cells.name = "Cells"
	add_child(_cells)

	var buckets := _scatter()
	_placed = 0
	for key in buckets:
		var rocks: Array = buckets[key]
		_placed += rocks.size()
		_build_cell(key, rocks)

	_apply_ranges()
	scattered.emit(_placed)


func _on_terrain_rebuilt() -> void:
	# The ground moved out from under the rocks.
	_queue_rebuild()


func _clear() -> void:
	if _cells != null and is_instance_valid(_cells):
		# remove_child before freeing, so the replacement can take the same name
		# without Godot appending a suffix to it.
		remove_child(_cells)
		_cells.queue_free()
	_cells = null


## Rolls candidate positions and buckets the survivors by cell.
## Returns { Vector2i cell -> Array[Dictionary] }.
func _scatter() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed

	var clump := FastNoiseLite.new()
	clump.seed = noise_seed + 5501
	clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clump.frequency = 1.0 / maxf(clump_scale, 1.0)

	var half: float = _terrain.size * 0.5
	# Scatter over where the terrain actually *is*, not over the world origin.
	# Those were the same thing for as long as there was one procedural patch
	# centred on nothing in particular. The authored map is offset so the spawn
	# is not on a cliff face, and rocks placed on the old range would fall off
	# the patch edge, where height_at() clamps and leaves them hanging.
	var patch := _terrain.global_position
	var cos_limit := cos(deg_to_rad(max_slope_deg))
	var lo := minf(size_min, size_max)
	var hi := maxf(size_min, size_max)

	_positions = PackedVector3Array()
	_sizes = PackedFloat32Array()

	var buckets := {}
	for i in count:
		# Inset by a metre so the sampler never reaches past the patch edge.
		var wx := patch.x + rng.randf_range(-half + 1.0, half - 1.0)
		var wz := patch.z + rng.randf_range(-half + 1.0, half - 1.0)

		# Clump mask first: it is the cheapest of the three tests.
		if clump_amount > 0.0:
			var mask := clump.get_noise_2d(wx, wz) * 0.5 + 0.5
			if mask < clump_amount:
				continue

		var normal := _ground_normal(wx, wz)
		if normal.y < cos_limit:
			continue

		var size := lerpf(lo, hi, pow(rng.randf(), size_bias))
		# Variant first: how deep the rock sits depends on how tall that
		# particular mesh is.
		var variant := rng.randi() % _meshes.size()
		var xform := _rock_transform(
			rng, _surface(wx, wz), normal, size, _half_heights[variant]
		)

		var cell := Vector2i(
			int(floorf(xform.origin.x / cell_size)),
			int(floorf(xform.origin.z / cell_size))
		)
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append({
			"xform": xform,
			"variant": variant,
			"size": size,
		})
		_positions.append(xform.origin)
		_sizes.append(size)
	return buckets


## The rock's transform in this node's local space, already sunk into the
## ground. `half_height` is the mesh's own Y half-extent at unit scale.
func _rock_transform(
	rng: RandomNumberGenerator,
	surface: Vector3,
	normal: Vector3,
	size: float,
	half_height: float
) -> Transform3D:
	var up := Vector3.UP.lerp(normal, normal_align).normalized()

	var yaw := rng.randf() * TAU
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := up.cross(fwd)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var back := right.cross(up).normalized()
	var basis := Basis(right, up, back)

	if tilt_jitter_deg > 0.0:
		var tilt := deg_to_rad(rng.randf_range(-tilt_jitter_deg, tilt_jitter_deg))
		basis = basis.rotated(right, tilt)

	var xform := Transform3D(basis.scaled(Vector3(size, size, size)), surface)
	xform.origin -= up * (size * half_height * sink)
	# Everything above is world space; the cells live under this node.
	return global_transform.affine_inverse() * xform


func _build_cell(cell: Vector2i, rocks: Array) -> void:
	var centre := Vector3(
		(cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size
	)
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [cell.x, cell.y]
	node.position = centre
	_cells.add_child(node)

	# One MultiMesh per variant per detail level: a MultiMesh holds exactly one
	# mesh, so a cell with six rock shapes is six instances however few rocks of
	# each it happens to hold.
	for v in _meshes.size():
		var of_variant: Array = rocks.filter(
			func(r: Dictionary) -> bool: return int(r["variant"]) == v
		)
		if of_variant.is_empty():
			continue
		_add_multimesh(node, "Near_%d" % v, _meshes[v][0], of_variant, centre)
		_add_multimesh(node, "Far_%d" % v, _meshes[v][1], of_variant, centre)

	_add_collision(node, rocks, centre)


func _add_multimesh(
	parent: Node3D, node_name: String, mesh: Mesh, rocks: Array, centre: Vector3
) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Both of these have to be set while instance_count is still 0. The engine
	# refuses the change afterwards, and every write then fails - loudly for the
	# transform format, silently for custom data.
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = rocks.size()

	var bounds := AABB()
	for i in rocks.size():
		var xform: Transform3D = rocks[i]["xform"]
		xform.origin -= centre
		mm.set_instance_transform(i, xform)
		# Red channel carries "this one is big enough to be an obstacle", using
		# exactly the threshold that decides whether it gets a collision shape.
		# The scanner outlines what you can actually hit rather than what
		# happens to be visible, and it costs no extra draw call: splitting big
		# rocks into their own MultiMesh would have doubled the instance count
		# per cell per variant, which is the cost the whole cell design exists
		# to avoid. See docs/02-Systems/Scatter.md.
		var solid := 1.0 if float(rocks[i]["size"]) >= collision_above else 0.0
		mm.set_instance_custom_data(i, Color(solid, 0.0, 0.0, 0.0))
		var reach: float = rocks[i]["size"]
		var box := AABB(xform.origin - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
		bounds = box if i == 0 else bounds.merge(box)
	# Set explicitly rather than trusting the derived bounds: this AABB is what
	# frustum and distance culling test against, so a wrong one either pops the
	# cell out early or defeats the culling entirely.
	mm.custom_aabb = bounds

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)


## Convex shapes for the big rocks only. Static bodies are cheap in Jolt, but a
## shape per pebble is neither cheap nor pleasant to drive over.
func _add_collision(parent: Node3D, rocks: Array, centre: Vector3) -> void:
	var solid: Array = rocks.filter(
		func(r: Dictionary) -> bool: return float(r["size"]) >= collision_above
	)
	if solid.is_empty():
		return

	var body := StaticBody3D.new()
	body.name = "Solid"
	parent.add_child(body)

	for r in solid:
		var xform: Transform3D = r["xform"]
		xform.origin -= centre
		var shape := CollisionShape3D.new()
		shape.shape = _shapes[int(r["variant"])]
		# The hull is built at unit size, so the instance's own uniform scale
		# carries it. Uniform only — Jolt rejects non-uniformly scaled shapes.
		shape.transform = xform
		body.add_child(shape)


# --- Terrain sampling ---------------------------------------------------

## World-space point on the terrain surface under (wx, wz).
##
## height_at() reports a height in the terrain's **local** space and the Terrain
## node carries a Y scale, so the round trip through its transform is not
## optional — see the same warning in test_world.gd.
func _surface(wx: float, wz: float) -> Vector3:
	var local := _terrain.to_local(Vector3(wx, 0.0, wz))
	var h := _terrain.height_at(local.x, local.z)
	return _terrain.to_global(Vector3(local.x, h, local.z))


## Ground normal in world space, from two finite differences on the surface.
func _ground_normal(wx: float, wz: float) -> Vector3:
	const STEP := 1.0
	var p := _surface(wx, wz)
	var px := _surface(wx + STEP, wz)
	var pz := _surface(wx, wz + STEP)
	return (pz - p).cross(px - p).normalized()


# --- Meshes -------------------------------------------------------------

func _ensure_meshes() -> void:
	if not _meshes.is_empty():
		return
	_shapes.clear()
	_half_heights = PackedFloat32Array()

	if not rock_meshes.is_empty():
		# Authored meshes carry their own detail and have no low-poly twin to
		# swap to, so both tiers draw the same mesh and only the far range
		# culls. Supply LODs on the imported mesh for the rest.
		for m in rock_meshes:
			if m == null:
				continue
			_meshes.append([m, m])
			_shapes.append(_hull(m))
			_half_heights.append(_half_height(m))
	if _meshes.is_empty():
		for i in variants:
			var near := RockMesh.build(noise_seed + i * 313, RockMesh.NEAR_SUBDIVISIONS)
			var far := RockMesh.build(noise_seed + i * 313, RockMesh.FAR_SUBDIVISIONS)
			_meshes.append([near, far])
			_shapes.append(_hull(far))
			_half_heights.append(_half_height(near))


## The mesh's own Y half-extent at unit scale, read off the geometry rather than
## assumed. Boulders are squashed, so this is nowhere near half the diameter,
## and authored meshes will not match the procedural ones either.
func _half_height(mesh: Mesh) -> float:
	return maxf(mesh.get_aabb().size.y * 0.5, 0.01)


func _hull(mesh: Mesh) -> Shape3D:
	var shape := mesh.create_convex_shape(true, true)
	return shape if shape != null else SphereShape3D.new()


# --- Live tuning --------------------------------------------------------

## Distances are the one thing that does not need a rebuild — they are
## properties on instances that already exist, so they retune while driving.
func _apply_ranges() -> void:
	if _cells == null or not is_instance_valid(_cells):
		return
	var near := maxf(near_distance, 1.0)
	var far := maxf(cull_distance, near + 1.0)
	var fade := (
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fade_margin > 0.0
		else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	)
	for cell in _cells.get_children():
		for child in cell.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi == null:
				continue
			var is_near := String(mmi.name).begins_with("Near_")
			mmi.visibility_range_begin = 0.0 if is_near else near
			mmi.visibility_range_end = near if is_near else far
			mmi.visibility_range_begin_margin = 0.0 if is_near else fade_margin
			mmi.visibility_range_end_margin = fade_margin
			mmi.visibility_range_fade_mode = fade


func _apply_material() -> void:
	if _cells == null or not is_instance_valid(_cells):
		return
	for cell in _cells.get_children():
		for child in cell.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi != null:
				mmi.material_override = material


## How many rocks the last rebuild actually placed, after slope and clump
## rejection. `count` is what it tried.
func placed() -> int:
	return _placed


## Every rock's centre, in this node's local space. Parallel to `rock_sizes()`.
func rock_positions() -> PackedVector3Array:
	return _positions


## Every rock's diameter in metres, parallel to `rock_positions()`.
func rock_sizes() -> PackedFloat32Array:
	return _sizes
