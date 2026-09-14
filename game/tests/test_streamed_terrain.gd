extends Node3D
## Regression test for `StreamedTerrain` - one resident heightfield and a
## quadtree of tiles streamed around a viewer. See [[Terrain]].
##
## What this exists to catch:
##
##   1. **The seam.** `extent()`, `sample_step()`, `world_height_at()` are the
##      contract everything else was narrowed onto, and they are answered by
##      the data rather than the tiles. Checked on a terrain that has been
##      **moved** off the origin, where a local/world mix-up shows.
##   2. **The tile selection tiles the ground.** The chosen tiles cover the
##      extent exactly once - no gap, no overlap - with the finest level under
##      the viewer and coarser ones away from it. A wrong index here draws
##      ground twice or not at all.
##   3. **Mesh and data agree.** Every vertex of a built tile, at any level,
##      sits exactly on `world_height_at`. That is what makes a crate placed
##      on the seam rest on the mesh, and a coarse tile's edge pass through
##      its finer neighbour's points.
##   4. **The winding is the one Godot draws.** Copied from terrain.gd; a
##      terrain wound the other way is an invisible world you fall through.
##   5. **Streaming settles, and never shows a hole.** After the viewer moves,
##      the resident set converges on the wanted set within a frame budget,
##      and at no frame in between is any point of the ground uncovered.
##   6. **The ground under the viewer is solid immediately**, and collision
##      follows the viewer: a raycast lands on the trimesh at ready, and
##      after the move the bodies are on the tiles near the new position.
##   7. **The Lattice finds the terrain, not a tile.**
##   8. **The real file loads** and says what the bake said.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_streamed_terrain.tscn

## The fixture field: 257 samples at 8 m is 2048 m, one root of four levels
## of 33-sample tiles (32 quads x 8 m x 2^3 = 2048 m). The viewer stands
## near one corner so the opposite one is 2.4 km off and three levels show,
## at a split ratio of 1 - the fixture is too small for the default 1.5.
const FIELD_SAMPLES := 257
const FIELD_SPACING := 8.0
const TILE_SAMPLES := 33
const LEVELS := 4
const COLLISION_RADIUS := 300.0
const OFFSET := Vector3(1000.0, 50.0, -700.0)
const SPLIT_RATIO := 1.0
const VIEWER_START := Vector3(-900.0, 30.0, 800.0)
const VIEWER_MOVED := Vector3(800.0, 30.0, -700.0)
const FRAME_BUDGET := 400
const REAL_FILE := "res://assets/terrain/lola_pole_24k.hf"

var _terrain: StreamedTerrain
var _viewer: Node3D
var _field: Heightfield
var _failures: Array[String] = []


func _ready() -> void:
	_field = Heightfield.from_data(_fixture(), FIELD_SAMPLES, FIELD_SAMPLES, FIELD_SPACING)
	_viewer = Node3D.new()
	_viewer.name = "Viewer"
	add_child(_viewer)
	_viewer.global_position = OFFSET + VIEWER_START

	_terrain = StreamedTerrain.new()
	_terrain.name = "Terrain"
	_terrain.tile_samples = TILE_SAMPLES
	_terrain.leaf_spacing = FIELD_SPACING
	_terrain.levels = LEVELS
	_terrain.collision_radius = COLLISION_RADIUS
	_terrain.split_ratio = SPLIT_RATIO
	_terrain.builds_per_frame = 4
	_terrain.position = OFFSET
	add_child(_terrain)
	_terrain.viewer_path = _terrain.get_path_to(_viewer)
	_terrain.set_heightfield(_field)

	_check_the_seam()
	_check_selection_tiles_the_ground()
	_check_solid_at_ready()
	# Nothing but the ground under the viewer exists yet, so the first fill
	# is allowed holes; only a swap is not.
	await _settle("first settle", false)
	_check_mesh_matches_data()
	_check_winding()
	_check_lattice_finds_it()
	await _check_move_streams_without_holes()
	await _check_collision_followed()
	_check_real_file_loads()
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)


# --- Fixture ------------------------------------------------------------

## Relief with structure at every level: long swells for the coarse tiles
## and a fast ripple the fine ones resolve.
static func _relief(x: float, z: float) -> float:
	return 40.0 * sin(x / 300.0) * cos(z / 260.0) + 6.0 * sin(x / 37.0) * sin(z / 41.0)


func _fixture() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(FIELD_SAMPLES * FIELD_SAMPLES)
	var half := float(FIELD_SAMPLES - 1) * FIELD_SPACING * 0.5
	for z in FIELD_SAMPLES:
		for x in FIELD_SAMPLES:
			data[z * FIELD_SAMPLES + x] = _relief(x * FIELD_SPACING - half, z * FIELD_SPACING - half)
	return data


# --- 1. The seam --------------------------------------------------------

func _check_the_seam() -> void:
	if not _terrain.is_built():
		_fail("the terrain reports it is not built after set_heightfield")
		return
	var span := float(FIELD_SAMPLES - 1) * FIELD_SPACING
	var want := Rect2(OFFSET.x - span * 0.5, OFFSET.z - span * 0.5, span, span)
	var got := _terrain.extent()
	if not got.is_equal_approx(want):
		_fail("extent() is %s, expected %s" % [got, want])
	if not is_equal_approx(_terrain.sample_step(), FIELD_SPACING):
		_fail("sample_step() is %f, expected %f" % [_terrain.sample_step(), FIELD_SPACING])

	# On a sample: exact. Between samples: Catmull-Rom through the sixteen
	# around it, which is what the data says and not what the analytic relief
	# says - the terrain is the data. The reference cubic here is written
	# out on its own so the field's is checked against something.
	var half := span * 0.5
	for probe: Vector2i in [Vector2i(0, 0), Vector2i(17, 40), Vector2i(256, 256), Vector2i(100, 3)]:
		var lx := probe.x * FIELD_SPACING - half
		var lz := probe.y * FIELD_SPACING - half
		var want_h := _field.height_at_index(probe.x, probe.y) + OFFSET.y
		var got_h := _terrain.world_height_at(OFFSET.x + lx, OFFSET.z + lz)
		if absf(got_h - want_h) > 1e-3:
			_fail("world_height_at on sample %s: %f, expected %f" % [probe, got_h, want_h])
	var rows := []
	for j in range(-1, 3):
		rows.append(_catmull(
			_field.height_at_index(9, 20 + j), _field.height_at_index(10, 20 + j),
			_field.height_at_index(11, 20 + j), _field.height_at_index(12, 20 + j), 0.5))
	var mid_want: float = _catmull(rows[0], rows[1], rows[2], rows[3], 0.5) + OFFSET.y
	var mid_got := _terrain.world_height_at(OFFSET.x + 10.5 * FIELD_SPACING - half,
		OFFSET.z + 20.5 * FIELD_SPACING - half)
	if absf(mid_got - mid_want) > 1e-3:
		_fail("world_height_at between samples: %f, expected %f" % [mid_got, mid_want])
	# And the slope is continuous across a sample line, which bilinear's is
	# not: the step across a data row shrinks in proportion to the straddle,
	# the way a slope's does and a crease's does not.
	var at_x := OFFSET.x + 40.0 * FIELD_SPACING - half
	var at_z := OFFSET.z + 60.0 * FIELD_SPACING - half
	var wide := _terrain.world_height_at(at_x, at_z + 0.4) - _terrain.world_height_at(at_x, at_z - 0.4)
	var narrow := _terrain.world_height_at(at_x, at_z + 0.04) - _terrain.world_height_at(at_x, at_z - 0.04)
	if absf(wide) > 1e-4 and absf(narrow * 10.0 - wide) > absf(wide) * 0.05:
		_fail("slope is not continuous across a data row: %f over 0.8 m, %f over 0.08 m"
			% [wide, narrow])


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return 0.5 * (2.0 * p1 + (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)


# --- 2. Selection -------------------------------------------------------

func _check_selection_tiles_the_ground() -> void:
	var viewer := _viewer_local()
	var keys := _terrain.select_tiles(viewer)
	if keys.is_empty():
		_fail("select_tiles chose nothing")
		return
	_expect_tiling(keys, "selection")

	var under := _key_under(keys, viewer)
	if under.x != 0:
		_fail("the tile under the viewer is level %d, expected 0" % under.x)
	var far_corner := _field.rect().end - Vector2(1.0, 1.0)
	var far := _key_under(keys, far_corner)
	if far.x == 0:
		_fail("the far corner is at the finest level; the split ratio is not doing anything")
	var levels_seen := {}
	for key in keys:
		levels_seen[key.x] = true
	if levels_seen.size() < 3:
		_fail("only %d levels in the selection; expected a ring at each" % levels_seen.size())


## Every point of the extent is under exactly one of `keys`: their areas sum
## to the extent's, and no two overlap.
func _expect_tiling(keys: Array[Vector3i], what: String) -> void:
	var ground := _field.rect()
	var area := 0.0
	for i in keys.size():
		var a := _terrain.tile_rect(keys[i]).intersection(ground)
		area += a.get_area()
		for j in range(i + 1, keys.size()):
			var overlap := a.intersection(_terrain.tile_rect(keys[j]))
			if overlap.get_area() > 1e-3:
				_fail("%s: tiles %s and %s overlap by %f m²"
					% [what, keys[i], keys[j], overlap.get_area()])
				return
	if absf(area - ground.get_area()) > 1e-3:
		_fail("%s: tiles cover %f m² of %f" % [what, area, ground.get_area()])


func _key_under(keys: Array[Vector3i], at: Vector2) -> Vector3i:
	for key in keys:
		if _terrain.tile_rect(key).has_point(at):
			return key
	_fail("no tile under %s" % at)
	return Vector3i(-1, -1, -1)


# --- 3 and 4. What the mesh says ---------------------------------------

func _check_mesh_matches_data() -> void:
	var checked := {}
	for key in _terrain.resident_keys():
		if checked.has(key.x):
			continue
		checked[key.x] = true
		var mi := _tile_node(key)
		if mi == null:
			_fail("resident tile %s has no MeshInstance3D" % key)
			continue
		var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var grid := TILE_SAMPLES * TILE_SAMPLES
		if verts.size() != grid:
			_fail("tile %s has %d vertices, expected %d" % [key, verts.size(), grid])
			continue
		var worst := 0.0
		for i in range(0, grid, 7):
			var world := _terrain.to_global(verts[i])
			worst = maxf(worst, absf(_terrain.world_height_at(world.x, world.z) - world.y))
		if worst > 1e-3:
			_fail("level %d tile %s: vertices are up to %f m off world_height_at"
				% [key.x, key, worst])
		# The skirt is its own mesh under the tile: every rim vertex again,
		# and again straight below it, at least `skirt_margin` down and no
		# deeper than the relief could need.
		var skirt_node := mi.get_node_or_null("Skirt") as MeshInstance3D
		if skirt_node == null:
			_fail("tile %s has no Skirt" % key)
			continue
		if skirt_node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("tile %s skirt casts shadows" % key)
		var sverts: PackedVector3Array = (skirt_node.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if sverts.size() != 8 * TILE_SAMPLES:
			_fail("tile %s skirt has %d vertices, expected %d" % [key, sverts.size(), 8 * TILE_SAMPLES])
			continue
		var rim := sverts[0]
		var drop := sverts[4 * TILE_SAMPLES]
		var depth := rim.y - drop.y
		if not rim.is_equal_approx(verts[0]) or absf(rim.x - drop.x) > 1e-4 \
				or absf(rim.z - drop.z) > 1e-4:
			_fail("level %d skirt: rim %s, dropped %s, not straight below the corner"
				% [key.x, rim, drop])
		if depth < _terrain.skirt_margin - 1e-4 or depth > _terrain.skirt_margin + 100.0:
			_fail("level %d skirt is %f m deep, expected at least the %f margin and nothing wild"
				% [key.x, depth, _terrain.skirt_margin])
	if checked.size() < 2:
		_fail("only %d levels resident to compare against the data" % checked.size())


func _check_winding() -> void:
	var key := _terrain.resident_keys()[0]
	var mi := _tile_node(key)
	var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# The terrain.gd winding, seen from above, has a downward cross product:
	# (+X) x (+Z) is -Y. That is the clockwise Godot draws.
	var a := verts[indices[0]]
	var b := verts[indices[1]]
	var c := verts[indices[2]]
	var n := (b - a).cross(c - a)
	if n.y >= 0.0:
		_fail("first grid triangle is wound the wrong way (cross.y %f)" % n.y)


func _tile_node(key: Vector3i) -> MeshInstance3D:
	return _terrain.get_node_or_null("Tiles/L%d_%d_%d" % [key.x, key.y, key.z]) as MeshInstance3D


# --- 5 and 6. Streaming -------------------------------------------------

func _check_solid_at_ready() -> void:
	# The finest tiles within collision range are built synchronously, so the
	# viewer's own tile is resident before a single frame has run.
	var under := _key_under(_terrain.select_tiles(_viewer_local()), _viewer_local())
	if not under in _terrain.resident_keys():
		_fail("the tile under the viewer (%s) is not resident at ready" % under)
	if _terrain.collided_tiles() == 0:
		_fail("no tile carries collision at ready")


## Runs frames until every wanted tile is resident, failing on the budget.
## The check for holes runs every frame on the way: the union of resident
## tiles has to cover the whole ground while the swap is in flight.
func _settle(what: String, no_holes := true) -> void:
	for frame in FRAME_BUDGET:
		if no_holes:
			_expect_covered("%s, frame %d" % [what, frame])
		if _terrain.is_settled():
			var want := _terrain.desired_keys()
			var got := _terrain.resident_keys()
			if want.size() != got.size():
				_fail("%s: settled with %d resident of %d wanted" % [what, got.size(), want.size()])
			for key in want:
				if not key in got:
					_fail("%s: settled without wanted tile %s" % [what, key])
			print("  %s: %d tiles, %d triangles, %d with collision, after %d frames"
				% [what, got.size(), _terrain.resident_triangles(),
					_terrain.collided_tiles(), frame])
			return
		await get_tree().process_frame
	_fail("%s: not settled after %d frames (%d pending, %d of %d resident)"
		% [what, FRAME_BUDGET, _terrain.pending_tiles(),
			_terrain.resident_keys().size(), _terrain.desired_keys().size()])


func _expect_covered(what: String) -> void:
	var rects: Array[Rect2] = []
	for key in _terrain.resident_keys():
		var mi := _tile_node(key)
		if mi != null and mi.visible:
			rects.append(_terrain.tile_rect(key))
	var ground := _field.rect()
	for j in 12:
		for i in 12:
			var at := ground.position + Vector2(i + 0.5, j + 0.5) * (ground.size / 12.0)
			var covered := false
			for r in rects:
				if r.has_point(at):
					covered = true
					break
			if not covered:
				_fail("%s: ground at local %s is not under any visible tile" % [what, at])
				return


func _check_move_streams_without_holes() -> void:
	var before := _terrain.resident_keys()
	_viewer.global_position = OFFSET + VIEWER_MOVED
	_terrain.refresh()
	await _settle("after the move")
	var under := _key_under(_terrain.select_tiles(_viewer_local()), _viewer_local())
	if under.x != 0 or not under in _terrain.resident_keys():
		_fail("after the move the tile under the viewer is %s, resident %s"
			% [under, under in _terrain.resident_keys()])
	# The old fine tiles are far away now and should have been swapped for
	# coarser ones - and kept, hidden, in the cache.
	var kept := 0
	for key in before:
		if key.x == 0 and key in _terrain.resident_keys():
			var d := StreamedTerrain._distance_to(_viewer_local(), _terrain.tile_rect(key))
			if d > _terrain.tile_size_at(0) * _terrain.split_ratio * 2.0:
				kept += 1
	if kept > 0:
		_fail("%d fine tiles from before the move are still resident far from the viewer" % kept)
	if _terrain.cached_tiles() == 0:
		_fail("nothing went into the cache after the move")
	_expect_tiling(_terrain.desired_keys(), "selection after the move")


func _check_collision_followed() -> void:
	# Bodies are attached in _process; give it a frame, then the physics
	# server a couple to see them.
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var viewer := _viewer_local()
	for key in _terrain.resident_keys():
		var mi := _tile_node(key)
		var has_body := mi.get_node_or_null("Body") != null
		var near := StreamedTerrain._distance_to(viewer, _terrain.tile_rect(key)) < COLLISION_RADIUS
		if near and not has_body:
			_fail("tile %s within collision range has no body" % key)
		if has_body and not near:
			_fail("tile %s carries a body outside collision range" % key)

	var at := _viewer.global_position
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, 200.0, 0.0), at - Vector3(0.0, 400.0, 0.0)))
	if hit.is_empty():
		_fail("a ray down through the viewer misses the ground")
		return
	var y := (hit.position as Vector3).y
	var want := _terrain.world_height_at(at.x, at.z)
	# The mesh is two triangles per quad, the seam is bilinear: a few
	# centimetres apart inside a quad, identical at the corners.
	if absf(y - want) > 0.5:
		_fail("the ray lands at %f, world_height_at says %f" % [y, want])


# --- 7 and 8 ------------------------------------------------------------

func _check_lattice_finds_it() -> void:
	if Lattice.terrain() != _terrain:
		_fail("Lattice.terrain() is %s, expected the StreamedTerrain" % Lattice.terrain())


func _check_real_file_loads() -> void:
	if not FileAccess.file_exists(REAL_FILE):
		_fail("the world's heightfield %s is missing" % REAL_FILE)
		return
	var t0 := Time.get_ticks_usec()
	var hf := Heightfield.load_file(REAL_FILE)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if hf == null or not hf.is_loaded():
		_fail("%s did not load" % REAL_FILE)
		return
	if hf.width != 4917 or hf.height != 4917 or not is_equal_approx(hf.spacing, 5.0):
		_fail("%s is %d x %d at %f m, expected 4917 x 4917 at 5 m"
			% [REAL_FILE, hf.width, hf.height, hf.spacing])
	if hf.highest - hf.lowest < 4000.0:
		_fail("%s has %f m of relief; the bake said 4830" % [REAL_FILE, hf.highest - hf.lowest])
	print("  real heightfield: %d x %d at %s m, %.0f .. %.0f m, loaded in %.0f ms"
		% [hf.width, hf.height, String.num(hf.spacing, 3), hf.lowest, hf.highest, ms])


# --- Plumbing -----------------------------------------------------------

func _viewer_local() -> Vector2:
	var at := _terrain.to_local(_viewer.global_position)
	return Vector2(at.x, at.z)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: test_streamed_terrain")
		get_tree().quit(0)
		return
	print("FAIL: test_streamed_terrain")
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1)
