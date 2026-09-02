extends Node3D
## Regression test for the map panel and the planned route. See [[The-Map]].
##
## What this exists to catch:
##
##   1. **A waypoint's height must be solved, not stored.** Everything standing
##      on this terrain follows that rule, and the one time three systems broke
##      it the Hearth ended up 13.6 m underground with every test passing. A
##      route is the newest thing that could store a stale Y.
##
##   2. **Leg lengths must be ground distances.** The straight line between two
##      waypoints is what the picture shows and is not what you drive. If these
##      ever come out equal, the number beside the leg is decoration and the
##      route is not worth planning.
##
##   3. **Clicking the map must land where you clicked.** The picker marches the
##      heightfield rather than raycasting a collision shape, so nothing in the
##      physics world will complain if it drifts — it will just quietly plant
##      waypoints somewhere near where you meant.
##
##   4. **Opening the map must take the controls.** The order board is only
##      reachable on foot; the map is on its own key and opens at speed. A rover
##      still reading the throttle behind a full-screen panel is a rover you are
##      driving blind.
##
##   5. **Reordering must actually reorder.** A route is a sequence; if `move`
##      is off by one the trip is planned in the wrong order and every distance
##      beside it is still perfectly correct.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_map_route.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const BUDGET := 600
const SETTLE := 60

var _astronaut: Astronaut
var _rover: Rover
var _panel: MapPanel
var _map: MapTerrain
var _terrain: ProceduralTerrain
var _frames := 0
var _stage := 0
var _waited := 0
var _failures: Array[String] = []


func _ready() -> void:
	add_child(WORLD.instantiate())
	Route.clear()


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE:
		return
	if _astronaut == null and not _find_the_pieces():
		if _frames > BUDGET:
			_expect(false, "never found the astronaut, rover, map panel and terrain")
			_finish()
		return
	match _stage:
		0: _stage_editing()
		1: _stage_height_is_solved()
		2: _stage_legs_are_ground_distances()
		3: _stage_the_mesh_builds()
		4: _stage_clicking_lands_where_you_clicked()
		5: _stage_opening_takes_the_controls()
		6: _finish()


func _find_the_pieces() -> bool:
	_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_rover = get_tree().get_first_node_in_group("rover") as Rover
	_panel = get_tree().get_first_node_in_group("map_panel") as MapPanel
	_map = get_tree().get_first_node_in_group("map_terrain") as MapTerrain
	_terrain = Lattice.terrain()
	return _astronaut != null and _rover != null and _panel != null \
		and _map != null and _terrain != null and _terrain.is_built()


## 5. A route is a sequence, and the operations on it are the easy thing to get
## off by one.
func _stage_editing() -> void:
	Route.clear()
	Route.add(10.0, 0.0)
	Route.add(30.0, 0.0)
	Route.add(50.0, 0.0)
	_expect(Route.count() == 3, "three added, %d present" % Route.count())

	Route.insert(1, 20.0, 0.0)
	_expect(Route.count() == 4, "insert did not add one")
	_expect(is_equal_approx(Route.point_2d(1).x, 20.0),
		"insert put the new stop at x=%.1f, not 20" % Route.point_2d(1).x)

	var landed := Route.move(0, 2)
	_expect(landed == 2, "move reported landing at %d, not 2" % landed)
	_expect(is_equal_approx(Route.point_2d(2).x, 10.0),
		"after moving stop 0 to index 2 it is at x=%.1f" % Route.point_2d(2).x)
	_expect(is_equal_approx(Route.point_2d(0).x, 20.0),
		"the stop behind the moved one did not close up")

	Route.remove_at(0)
	_expect(Route.count() == 3, "remove did not take one out")
	_expect(is_equal_approx(Route.point_2d(0).x, 30.0),
		"remove took out the wrong stop")

	Route.clear()
	_expect(Route.is_empty(), "clear left %d behind" % Route.count())
	_stage = 1


## 1. Solved, never stored.
func _stage_height_is_solved() -> void:
	var at := Vector2(40.0, -25.0)
	Route.add(at.x, at.y)
	var solved := Route.point(0)
	var truth := _terrain.world_height_at(at.x, at.y)
	_expect(is_equal_approx(solved.y, truth),
		"waypoint solved to y=%.3f, terrain says %.3f" % [solved.y, truth])
	_expect(absf(solved.y) > 0.001,
		"the test point is at y=0, which would pass this test for the wrong reason")
	_stage = 2


## 2. What you drive, not what the picture shows.
func _stage_legs_are_ground_distances() -> void:
	Route.clear()
	# Deliberately routed at the massif rather than across the spawn playa. The
	# playa is the flattest ground on the map, and a leg over it beat its own
	# straight line by 0.3% — which passes a `>` test on noise as happily as on
	# a working sampler. A leg that climbs 200 m cannot.
	var from := Vector2(-200.0, 500.0)
	var to := Vector2(-470.0, 1270.0)
	_astronaut.global_position = Vector3(from.x,
		_terrain.world_height_at(from.x, from.y) + 1.0, from.y)
	Route.add(to.x, to.y)
	var flat := from.distance_to(to)
	var over_ground := Route.leg_length(0, from)
	print("leg: %.1f m flat, %.1f m over the ground" % [flat, over_ground])
	_expect(over_ground > flat * 1.02,
		"the ground distance %.1f is barely over the flat %.1f — a climb of 200 m"
			% [over_ground, flat]
			+ " has to cost more than that")
	# A sanity ceiling: terrain adds metres, not multiples. A runaway here means
	# the sampler is walking somewhere other than the leg.
	_expect(over_ground < flat * 1.5,
		"the ground distance is %.2fx the flat one, which is not terrain"
			% (over_ground / flat))
	_expect(is_equal_approx(Route.total_distance(from), over_ground),
		"one leg totalled %.1f but the leg is %.1f"
			% [Route.total_distance(from), over_ground])
	_stage = 3


func _stage_the_mesh_builds() -> void:
	if _map.mesh == null or _map.span() <= 0.0:
		_waited += 1
		if _waited > BUDGET:
			_expect(false, "the map relief mesh never built")
			_finish()
		return
	var verts := _map.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var expected := (_map.grid + 1) * (_map.grid + 1)
	_expect(verts.size() == expected,
		"map mesh has %d vertices, expected %d" % [verts.size(), expected])
	_expect(is_equal_approx(_map.span(), _terrain.size),
		"the map spans %.1f m but the terrain is %.1f" % [_map.span(), _terrain.size])
	# The relief is exaggerated on purpose; the picker has to agree with it or
	# clicks land above or below the surface being drawn.
	var here := Vector2(60.0, 60.0)
	_expect(is_equal_approx(_map.map_height(here.x, here.y),
			_terrain.world_height_at(here.x, here.y) * _map.relief_exaggeration),
		"map_height does not match the exaggeration the mesh was built with")
	_waited = 0
	_stage = 4


## 3. Straight down from above a known spot must come back to that spot.
func _stage_clicking_lands_where_you_clicked() -> void:
	var target := Vector2(80.0, -40.0)
	var above := Vector3(target.x, _map.map_height(target.x, target.y) + 900.0,
		target.y)
	var hit := _map.surface_hit(above, Vector3.DOWN)
	_expect(bool(hit["hit"]), "a ray fired straight down at the map missed it")
	if bool(hit["hit"]):
		var point: Vector3 = hit["point"]
		_expect(Vector2(point.x, point.z).distance_to(target) < 1.0,
			"a ray down at %s came back at (%.1f, %.1f)"
				% [target, point.x, point.z])
		_expect(absf(point.y - _map.map_height(target.x, target.y)) < 1.0,
			"the hit is %.2f m off the drawn surface"
				% absf(point.y - _map.map_height(target.x, target.y)))
	# And a ray fired at the sky has to fail rather than invent a hit.
	var miss := _map.surface_hit(above, Vector3.UP)
	_expect(not bool(miss["hit"]), "a ray fired at the sky reported hitting ground")
	_stage = 5


## 4. The map opens at speed, so it has to take the controls with it.
func _stage_opening_takes_the_controls() -> void:
	if not _panel.is_open():
		_rover.enter(_astronaut)
		_panel.open()
		_waited = 0
		return
	_waited += 1
	if _waited < 4:
		return
	_expect(_astronaut.is_menu_open(),
		"the map is open but the astronaut does not think a menu is")
	_expect(is_zero_approx(_rover.engine_force),
		"the rover is still pulling %.1f N behind a full-screen panel"
			% _rover.engine_force)
	_panel.close()
	_expect(not _astronaut.is_menu_open(),
		"closing the map left the astronaut stuck in a menu")
	_stage = 6


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	Route.clear()
	if _failures.is_empty():
		print("PASS: routes solve their heights, measure the ground, and take the controls.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
