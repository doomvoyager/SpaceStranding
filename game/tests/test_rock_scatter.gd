extends Node3D
## Regression test for the rock scatter.
##
## Four things here fail silently rather than loudly, so each gets an assertion:
##
##   1. **Winding.** Godot treats clockwise triangles as front faces. Wound the
##      other way every rock is inside-out and invisible, and nothing in a
##      headless run notices. Checked directly against the same convention
##      terrain.gd uses.
##   2. **The Y-scale trap.** The Terrain node carries a Y scale to flatten the
##      map, so `height_at()` is not a world height. test_world.gd got this
##      wrong from the day it was written and spawned everything in mid-air.
##      The terrain here is deliberately scaled 0.5 on Y to reproduce it.
##   3. **Cells.** Distance culling only works because the scatter is split
##      into cells - a single whole-patch MultiMesh drops nothing, measured in
##      probe_scatter_cull.gd. One cell would still look correct and cull
##      nothing at all.
##   4. **Collision.** Big rocks get a convex shape, pebbles do not, and the
##      hulls have to survive being uniformly scaled by Jolt.
##
## **Placement is checked against `rock_positions()`, never against the
## MultiMesh.** Under `--headless` the dummy renderer accepts
## `set_instance_transform()` without error and returns identity from
## `get_instance_transform()`, so an assertion reading instance transforms back
## here passes or fails on the null driver rather than on the scatter. This test
## asserted exactly that and reported every rock 12 m off the ground.
## `instance_count`, `custom_aabb` and `visibility_range_end` do survive -
## measured both ways in `probe_multimesh_readback.gd`.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_rock_scatter.tscn

const PATCH := 256.0
## Deliberately not 1.0: this is the transform that broke every other placement.
const TERRAIN_Y_SCALE := 0.5
const SETTLE := 20

var _failures: Array[String] = []
var _frames := 0
var _terrain: ProceduralTerrain
var _scatter: RockScatter


func _ready() -> void:
	_terrain = ProceduralTerrain.new()
	_terrain.name = "Terrain"
	_terrain.size = PATCH
	_terrain.resolution = 4.0
	_terrain.scale = Vector3(1.0, TERRAIN_Y_SCALE, 1.0)
	add_child(_terrain)

	_scatter = RockScatter.new()
	_scatter.name = "Scatter"
	_scatter.count = 1500
	_scatter.cell_size = 32.0
	add_child(_scatter)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames != SETTLE:
		return
	_test_winding()
	_test_something_landed()
	_test_split_into_cells()
	_test_rocks_sit_on_the_ground()
	_test_slope_rejection()
	_test_visibility_ranges()
	_test_collision_is_for_big_rocks_only()
	_test_ray_hits_a_rock()
	_finish()


# --- 1. Winding ---------------------------------------------------------

## terrain.gd's up-facing quads have (b-a) x (c-a) pointing *down*, because
## Godot's front face is the clockwise one. Every rock triangle must agree:
## the geometric cross product points *inward*, and the outward normal is
## supplied explicitly in ARRAY_NORMAL.
func _test_winding() -> void:
	var mesh := RockMesh.build(4242)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_expect(verts.size() >= 60, "rock mesh has %d vertices" % verts.size())
	_expect(verts.size() % 3 == 0, "rock mesh is not whole triangles")

	var wrong_winding := 0
	var wrong_normal := 0
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var centroid := (a + b + c) / 3.0
		if (b - a).cross(c - a).dot(centroid) > 0.0:
			wrong_winding += 1
		# The supplied normal must face away from the rock's middle, or the
		# lighting is inside-out even where the culling is right.
		if normals[i].dot(centroid) <= 0.0:
			wrong_normal += 1
	_expect(wrong_winding == 0,
		"%d rock triangles are wound the wrong way - they will be culled" % wrong_winding)
	_expect(wrong_normal == 0,
		"%d rock triangles have inward-facing normals" % wrong_normal)


# --- 2, 3. Placement ----------------------------------------------------

func _test_something_landed() -> void:
	_expect(_scatter.placed() > 0, "no rocks were placed at all")
	# Clump and slope rejection should bite, but not eat everything.
	_expect(_scatter.placed() < _scatter.count,
		"every candidate survived - rejection is not running")


func _test_split_into_cells() -> void:
	var cells := _cells()
	_expect(cells.size() > 1,
		"scatter built %d cell(s); distance culling needs more than one" % cells.size())
	for cell in cells:
		var mm := _first_multimesh(cell)
		_expect(mm != null, "cell %s has no MultiMeshInstance3D" % cell.name)


## Every rock must sit on the surface, with the terrain's Y scale applied. An
## off-by-the-transform bug puts them at twice the ground height.
func _test_rocks_sit_on_the_ground() -> void:
	var positions := _scatter.rock_positions()
	var sizes := _scatter.rock_sizes()
	_expect(positions.size() == _scatter.placed(),
		"%d recorded positions for %d placed rocks" % [positions.size(), _scatter.placed()])

	var floating := 0
	var worst := 0.0
	for i in positions.size():
		var p: Vector3 = _scatter.global_transform * positions[i]
		# Positive means the rock's centre is below the surface, which is what
		# `sink` asks for. Each rock sinks along its own up vector, which tilts
		# with the slope, so the band is generous - the failure this guards
		# against is metres wrong, not centimetres.
		var drop := _surface_y(p.x, p.z) - p.y
		if drop < -0.3 or drop > sizes[i] * _scatter.sink + 0.3:
			floating += 1
		worst = maxf(worst, absf(drop))
	_expect(floating == 0,
		"%d of %d rocks are off the surface (worst gap %.2f m) - the terrain transform is being ignored"
			% [floating, positions.size(), worst])


func _test_slope_rejection() -> void:
	var limit := cos(deg_to_rad(_scatter.max_slope_deg))
	var positions := _scatter.rock_positions()
	var too_steep := 0
	for i in positions.size():
		var p: Vector3 = _scatter.global_transform * positions[i]
		if _ground_normal(p.x, p.z).y < limit - 0.02:
			too_steep += 1
	_expect(too_steep == 0,
		"%d of %d rocks landed above the slope limit" % [too_steep, positions.size()])


# --- Culling ------------------------------------------------------------

func _test_visibility_ranges() -> void:
	var near_seen := 0
	var far_seen := 0
	for cell in _cells():
		for child in cell.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi == null:
				continue
			# A range of 0 means "never cull", which is the failure this whole
			# system exists to avoid.
			_expect(mmi.visibility_range_end > 0.0,
				"%s/%s has no cull distance" % [cell.name, mmi.name])
			_expect(mmi.multimesh.custom_aabb.size.length() > 0.0,
				"%s/%s has an empty AABB and will cull wrongly" % [cell.name, mmi.name])
			if String(mmi.name).begins_with("Near_"):
				near_seen += 1
				_expect(is_equal_approx(mmi.visibility_range_end, _scatter.near_distance),
					"near tier does not end at near_distance")
			else:
				far_seen += 1
				_expect(is_equal_approx(mmi.visibility_range_begin, _scatter.near_distance),
					"far tier does not begin where the near tier ends")
	_expect(near_seen > 0 and far_seen > 0,
		"expected both detail tiers, saw %d near and %d far" % [near_seen, far_seen])


# --- 4. Collision -------------------------------------------------------

func _test_collision_is_for_big_rocks_only() -> void:
	var big := 0
	for size in _scatter.rock_sizes():
		if size >= _scatter.collision_above:
			big += 1

	var shapes := 0
	var empty := 0
	var small_with_shape := 0
	for cell in _cells():
		var body := cell.get_node_or_null("Solid") as StaticBody3D
		if body == null:
			continue
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs == null:
				continue
			shapes += 1
			if cs.shape == null:
				empty += 1
			# CollisionShape3D carries a real node transform, so unlike the
			# MultiMesh its scale reads back correctly headless.
			if cs.scale.y < _scatter.collision_above - 0.001:
				small_with_shape += 1

	_expect(big > 0, "the roll produced no rocks over the collision threshold")
	_expect(shapes > 0, "no rock got collision at all")
	_expect(empty == 0, "%d collision shapes are empty" % empty)
	_expect(shapes == big,
		"%d shapes for %d rocks over the threshold" % [shapes, big])
	_expect(small_with_shape == 0,
		"%d pebbles were given collision shapes" % small_with_shape)


## The decisive one: a ray dropped onto a big rock has to stop on the rock, not
## pass through it into the terrain. Catches a hull Jolt silently rejected.
func _test_ray_hits_a_rock() -> void:
	var shape := _first_collision_shape()
	if shape == null:
		_expect(false, "no collision shape to aim at")
		return
	var at := shape.global_position
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 20.0, at - Vector3.UP * 20.0
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_expect(not hit.is_empty(), "a ray onto a boulder hit nothing at all")
	if hit.is_empty():
		return
	_expect(hit["collider"] is StaticBody3D, "ray hit a %s" % hit["collider"].get_class())
	_expect(hit["position"].y > _surface_y(at.x, at.z) - 0.01,
		"the ray fell through the rock to the ground beneath it")


# --- Helpers ------------------------------------------------------------

func _cells() -> Array[Node]:
	var container := _scatter.get_node_or_null("Cells")
	return container.get_children() if container != null else ([] as Array[Node])


func _first_multimesh(cell: Node) -> MultiMeshInstance3D:
	for c in cell.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi != null:
			return mmi
	return null


func _first_collision_shape() -> CollisionShape3D:
	for cell in _cells():
		var body := cell.get_node_or_null("Solid")
		if body == null:
			continue
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs != null:
				return cs
	return null


func _surface_y(wx: float, wz: float) -> float:
	var local := _terrain.to_local(Vector3(wx, 0.0, wz))
	return _terrain.to_global(
		Vector3(local.x, _terrain.height_at(local.x, local.z), local.z)
	).y


func _ground_normal(wx: float, wz: float) -> Vector3:
	var p := Vector3(wx, _surface_y(wx, wz), wz)
	var px := Vector3(wx + 1.0, _surface_y(wx + 1.0, wz), wz)
	var pz := Vector3(wx, _surface_y(wx, wz + 1.0), wz + 1.0)
	return (pz - p).cross(px - p).normalized()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: %d rocks across %d cells, wound right, on the ground, culled and solid."
			% [_scatter.placed(), _cells().size()])
		# quit() only schedules the exit, so this must return.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
