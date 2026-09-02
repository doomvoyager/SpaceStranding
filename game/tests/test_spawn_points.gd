extends Node3D
## Regression test for authored spawn markers and the ground invariant.
##
## The bug this guards against has already happened twice, and both times every
## headless assertion passed: the nodes existed and were exactly where they had
## been told to be. What was wrong was *where they had been told*. So this test
## does not check that things exist — it checks the one rule that ties the
## editor view, the scene file and the running game together:
##
##     global_position.y == world ground at (x, z)  +  ground_clearance
##
## Five things, in the order they can break:
##
##   1. **Markers actually drive the world.** The marker is moved *before* the
##      scene enters the tree, so the astronaut has to land somewhere the old
##      hardcoded literal never would. Asserting against the authored position
##      would pass just as well with the fallback path running, which is how a
##      dead marker would hide.
##   2. **The invariant holds for everything authored** — spawns, facilities,
##      relays and loose cargo alike, against a terrain that is *not* at the
##      origin, which is the arrangement that put the Hearth 13.6 m underground.
##   3. **The editor and the runtime agree.** `ground_snapper.gd` solves height
##      while you drag; `test_world.gd` solves it again on load. Two
##      implementations of one rule is exactly the shape that drifts, and the
##      drift would be invisible until something spawned inside a hill.
##   4. **An unbuilt terrain refuses to answer.** It reports zero for every
##      point, and zero is a plausible height — anything solving against it
##      quietly stacks the whole scene on the terrain's own origin.
##   5. **A missing marker is null, not a crash.** The fallback needs something
##      to test.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_spawn_points.tscn

const WORLD := "res://scenes/world/test_world.tscn"
const SNAPPER := preload("res://addons/spawn_gizmos/ground_snapper.gd")

## Where the astronaut marker is dragged to before the world is allowed to load.
## Far enough from the authored 6, 0, 0 that the fallback cannot be mistaken for
## a hit, and well inside the patch so there is real ground under it.
const DRAGGED_TO := Vector2(-63.0, 88.0)

## Metres of disagreement allowed on the invariant. The two solvers do the same
## bilinear lookup, so this is float noise, not tolerance for a different answer.
const EPSILON := 0.001

var _failures: Array[String] = []


func _ready() -> void:
	var world := _load_world_with_dragged_marker()
	if world != null:
		_check_marker_drove_the_spawn(world)
		_check_invariant_holds(world)
		_report_spawn_heights(world)
	_check_snapper_agrees_with_runtime()
	_check_unbuilt_terrain_refuses()
	_check_missing_marker_is_null()
	_teardown()

	for f in _failures:
		print("FAIL: ", f)
	if _failures.is_empty():
		print("PASS: spawn points")
		get_tree().quit(0)
		return
	get_tree().quit(1)
	return


func _fail(msg: String) -> void:
	_failures.append(msg)


## Instantiate the world, drag the astronaut marker while the scene is still
## detached, and only then let it run. Everything downstream of `_ready` sees a
## marker that was never in the scene file.
func _load_world_with_dragged_marker() -> Node3D:
	var packed := load(WORLD) as PackedScene
	if packed == null:
		_fail("could not load %s" % WORLD)
		return null
	var world := packed.instantiate() as Node3D
	var marker := world.get_node_or_null("Spawns/AstronautSpawn") as SpawnPoint
	if marker == null:
		_fail("the world scene has no Spawns/AstronautSpawn marker")
		return null
	marker.position = Vector3(DRAGGED_TO.x, 0.0, DRAGGED_TO.y)
	add_child(world)
	return world


func _check_marker_drove_the_spawn(world: Node3D) -> void:
	var astronaut := world.get_node_or_null("Astronaut") as Node3D
	if astronaut == null:
		_fail("no Astronaut in the world scene")
		return
	var at := astronaut.global_position
	if absf(at.x - DRAGGED_TO.x) > EPSILON or absf(at.z - DRAGGED_TO.y) > EPSILON:
		_fail("the astronaut ignored its marker: at (%f, %f), marker at (%f, %f)"
			% [at.x, at.z, DRAGGED_TO.x, DRAGGED_TO.y])


## Everything the world settles, checked against the rule it settles by.
func _check_invariant_holds(world: Node3D) -> void:
	var terrain := world.get_node_or_null("Terrain") as ProceduralTerrain
	if terrain == null:
		_fail("no Terrain in the world scene")
		return
	# The world scene translates its terrain by hundreds of metres. If any of
	# this passes with the terrain at the origin it is not testing anything.
	if terrain.global_position.is_equal_approx(Vector3.ZERO):
		_fail("the world terrain is at the origin, so this test proves nothing")

	for spec: Array in [
		["Astronaut", "astronaut"], ["Rover", "rover"], ["Beacon", "beacon"],
	]:
		var node := world.get_node_or_null(NodePath(spec[0])) as Node3D
		var marker := SpawnPoint.find(get_tree(), spec[1])
		if node == null or marker == null:
			_fail("missing node or marker for '%s'" % spec[1])
			continue
		_assert_grounded(terrain, node, marker.ground_clearance, spec[0])

	for group: String in ["facility", "relay", "cargo"]:
		for node in get_tree().get_nodes_in_group(group):
			var n := node as Node3D
			if n == null:
				continue
			# A stowed crate belongs to its rack, not to the ground.
			var crate := n as Crate
			if crate != null and crate.is_stowed():
				continue
			# The property is what the editor tooling recognises — the snapper
			# and the gizmo both key off it and nothing else. A settled type
			# that forgets to declare it still works at runtime and is simply
			# invisible to the editor, which is precisely how three finished
			# systems once failed to reach the debug panel. `get()` answers null
			# for a property that is not there, and `float(null)` is a perfectly
			# convincing 0.0, so this has to be checked and not inferred.
			if n.get("ground_clearance") == null:
				_fail(("%s is settled onto the terrain but declares no "
					+ "ground_clearance, so the editor cannot snap or draw it")
					% n.name)
				continue
			_assert_grounded(terrain, n, float(n.get("ground_clearance")), n.name)


func _assert_grounded(terrain: ProceduralTerrain, node: Node3D,
		clearance: float, label: String) -> void:
	var at := node.global_position
	var want := terrain.world_height_at(at.x, at.z) + clearance
	if absf(at.y - want) > EPSILON:
		_fail("%s sits at y = %f, but ground + clearance is %f (off by %f m)"
			% [label, at.y, want, at.y - want])


## Diagnostic, not an assertion: the height each marker *should* be sitting at.
##
## A marker keeps whatever Y the scene file gave it — nothing repositions the
## marker itself at runtime, only the thing it places — so printing its own
## position would just read the authored number back. This prints the solved
## one, which is what the editor snap writes and what a stale scene file can be
## checked against by eye.
func _report_spawn_heights(world: Node3D) -> void:
	var terrain := world.get_node_or_null("Terrain") as ProceduralTerrain
	if terrain == null:
		return
	print("      terrain origin: ", terrain.global_position)
	for node in get_tree().get_nodes_in_group(SpawnPoint.GROUP):
		var point := node as SpawnPoint
		if point == null or not point.is_inside_tree():
			continue
		var at := point.global_position
		var ground := terrain.world_height_at(at.x, at.z)
		print("      %-10s x %8.2f  z %8.2f  ground %8.3f  + clearance %.2f = %.3f"
			% [point.spawn_id, at.x, at.z, ground, point.ground_clearance,
				ground + point.ground_clearance])


## The editor solver and the runtime solver, on the same terrain, at the same
## point. They are separate code in separate folders and neither imports the
## other, so nothing but this stops them drifting apart.
func _check_snapper_agrees_with_runtime() -> void:
	var terrain := ProceduralTerrain.new()
	terrain.height_source = ProceduralTerrain.HeightSource.PROCEDURAL
	terrain.size = 256.0
	terrain.resolution = 4.0
	# Off the origin and scaled on Y, which is the pair of conditions that made
	# every earlier placement bug invisible.
	terrain.position = Vector3(37.0, 11.0, -19.0)
	terrain.scale = Vector3(1.0, 0.5, 1.0)
	add_child(terrain)

	var point := SpawnPoint.new()
	point.spawn_id = "probe"
	point.ground_clearance = 1.7
	add_child(point)
	point.global_position = Vector3(52.0, 0.0, -41.0)

	var snapper: RefCounted = SNAPPER.new()
	var snapped: Vector3 = snapper._grounded_position(
		terrain, point, point.global_position)
	var runtime := terrain.world_height_at(52.0, -41.0) + 1.7

	if absf(snapped.y - runtime) > EPSILON:
		_fail("the editor snap and the runtime solve disagree: %f vs %f"
			% [snapped.y, runtime])
	if absf(snapped.x - 52.0) > EPSILON or absf(snapped.z + 41.0) > EPSILON:
		_fail("the editor snap moved X/Z, which is the authored half: %s" % snapped)


func _check_unbuilt_terrain_refuses() -> void:
	# Never added to the tree, so `_ready` never ran and nothing was built.
	var bare := ProceduralTerrain.new()
	if bare.is_built():
		_fail("an unbuilt terrain reports is_built()")
	if bare.height_at_index(0, 0) != 0.0 or bare.height_at(0.0, 0.0) != 0.0:
		_fail("an unbuilt terrain returned a height instead of zero")
	# A Node is not reference counted, and this one never had a parent to free
	# it. `_teardown` only reaches children, so it has to go by hand.
	bare.free()

	var built := ProceduralTerrain.new()
	built.size = 64.0
	built.resolution = 4.0
	add_child(built)
	if not built.is_built():
		_fail("a built terrain reports is_built() false")


func _check_missing_marker_is_null() -> void:
	if SpawnPoint.find(get_tree(), "no-such-spawn") != null:
		_fail("find() invented a marker for an id nothing declares")


## Freed by hand, not queued.
##
## `quit()` only schedules the exit, and a `queue_free()` issued in the same
## call is not reliably reached before the rendering servers are torn down — the
## whole world scene and two spare terrains hold materials and meshes, so what
## comes out is a page of RID-leak errors at exit with nothing to say which test
## caused them. Explicit teardown keeps the output to the result.
func _teardown() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
