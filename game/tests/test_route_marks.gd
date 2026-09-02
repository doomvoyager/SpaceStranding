extends Node3D
## Regression test for the route as it appears in the world: the light pillar,
## arrival, and the scan reveal. See [[The-Map]].
##
## What this exists to catch:
##
##   1. **Reaching a stop must clear everything up to it.** Arriving at the
##      third having skipped the first two leaves those two behind you, and
##      keeping them would point the beam back the way you came. This is the
##      rule most likely to be written as "clear the one you touched" and to
##      look right until the first time somebody takes a shortcut.
##
##   2. **The beam must follow the *nearest* stop, not the next one drawn.**
##      Those are the same thing right up until they are not, and the case
##      where they differ is exactly the case the rule above exists for.
##
##   3. **Arrival must work while driving.** The astronaut's node stops moving
##      the moment you board — `global_position` is wherever you got in — so
##      anything checking "am I there yet" against it ticks off stops at the
##      spot you last parked. The HUD's route bearing was doing exactly that
##      before `vantage()` existed.
##
##   4. **One beam, not one per stop.** The whole point of the pillar is that it
##      answers "which way" without ambiguity.
##
##   5. **The reveal must cost a pulse.** A route line permanently painted over
##      the world is a different feature, and a strictly worse one.
##
##   6. **And it must have a line in it.** The reveal is only rebuilt when the
##      player has moved far enough to change it — it was four hundred height
##      lookups a frame otherwise, see tests/probe_scan_cost.tscn — so
##      `reveal_visible()` is now a claim about a mesh that some *earlier* frame
##      built. A throttle that never lets go leaves a visible node with nothing
##      in it, which is this project's favourite failure and is invisible to
##      every assertion that only asks whether it is on screen.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_route_marks.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const BUDGET := 400
const SETTLE := 60

var _astronaut: Astronaut
var _rover: Rover
var _marks: RouteMarks
var _scanner: Node
var _terrain: ProceduralTerrain
var _frames := 0
var _stage := 0
var _waited := 0
## Whether the current stage has done its one-time setup.
##
## The stages below are driven off the state they assert on, not off a frame
## count: _process and _physics_process do not interleave anything like realtime
## under --headless, and both the beam and arrival are driven from _process. A
## stage that counted physics frames read zero progress every time — and, worse,
## re-ran its own setup on every one of them, clearing and re-adding the route
## faster than Route could ever tick a stop off it.
var _ready_for := -1
var _arrivals: Array = []
var _failures: Array[String] = []


func _ready() -> void:
	add_child(WORLD.instantiate())
	Route.clear()
	Route.arrived.connect(func(i: int, cleared: int) -> void:
		_arrivals.append([i, cleared]))


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE:
		return
	if _astronaut == null and not _find_the_pieces():
		if _frames > BUDGET:
			_expect(false, "never found the world's pieces")
			_finish()
		return
	match _stage:
		0: _stage_beam_follows_the_nearest()
		1: _stage_arriving_in_order()
		2: _stage_skipping_clears_the_lot()
		3: _stage_arrival_while_driving()
		4: _stage_reveal_costs_a_pulse()
		5: _finish()


func _find_the_pieces() -> bool:
	_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_rover = get_tree().get_first_node_in_group("rover") as Rover
	_marks = get_tree().get_first_node_in_group("route_marks") as RouteMarks
	_scanner = get_tree().get_first_node_in_group("scanner")
	_terrain = Lattice.terrain()
	return _astronaut != null and _rover != null and _marks != null \
		and _scanner != null and _terrain != null and _terrain.is_built()


## True once per stage, so setup runs exactly once.
func _first_time() -> bool:
	if _ready_for == _stage:
		return false
	_ready_for = _stage
	_waited = 0
	return true


## Poll for `condition`, giving up after the budget. Returns true when the stage
## should go on to its assertions.
func _settled(condition: bool) -> bool:
	_waited += 1
	return condition or _waited > BUDGET


## Put the astronaut somewhere with a solved height under it.
func _stand_at(x: float, z: float) -> void:
	_astronaut.global_position = Vector3(x,
		_terrain.world_height_at(x, z) + 1.0, z)


## 2 and 4. The beam is on the nearest remaining stop, and there is one of it.
func _stage_beam_follows_the_nearest() -> void:
	if _first_time():
		Route.clear()
		# Drawn in this order, but the second one is much the closest.
		Route.add(300.0, 0.0)
		Route.add(90.0, 0.0)
		Route.add(500.0, 0.0)
		_stand_at(0.0, 0.0)
		return
	if not _settled(_marks.beacon_visible()):
		return
	var from := Vector2(0.0, 0.0)
	_expect(Route.nearest_index(from) == 1,
		"the nearest stop is %d, not the one 90 m away" % Route.nearest_index(from))
	_expect(_marks.beacon_visible(), "no beam with a route 90 m away")
	var foot := _marks.beacon_foot()
	_expect(Vector2(foot.x, foot.z).distance_to(Vector2(90.0, 0.0)) < 1.0,
		"the beam stands at (%.1f, %.1f), not on the nearest stop"
			% [foot.x, foot.z])
	_expect(absf(foot.y - _terrain.world_height_at(90.0, 0.0)) < 1.0,
		"the beam's foot is %.1f m off the ground"
			% absf(foot.y - _terrain.world_height_at(90.0, 0.0)))
	# 4. One beam. RouteMarks owns exactly one pillar; anything that started
	# drawing one per stop would show up here as a second MeshInstance3D.
	var beams := 0
	for child in _marks.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh is QuadMesh:
			beams += 1
	_expect(beams == 1, "%d beams in the world, not one" % beams)
	_stage = 1


## 1a. Walking onto a stop in order clears exactly that one.
func _stage_arriving_in_order() -> void:
	if _first_time():
		Route.clear()
		_arrivals.clear()
		Route.add(60.0, 0.0)
		Route.add(200.0, 0.0)
		_stand_at(60.0, 0.0)
		return
	if not _settled(not _arrivals.is_empty()):
		return
	_expect(Route.count() == 1,
		"arriving at the first of two left %d stops" % Route.count())
	_expect(_arrivals.size() == 1, "%d arrivals fired" % _arrivals.size())
	if not _arrivals.is_empty():
		_expect(_arrivals[0][0] == 0 and _arrivals[0][1] == 1,
			"arrived reported index %d clearing %d" % [_arrivals[0][0], _arrivals[0][1]])
	_expect(is_equal_approx(Route.point_2d(0).x, 200.0),
		"the wrong stop survived")
	_stage = 2


## 1b. The rule that matters: skip two, reach the third, all three go.
func _stage_skipping_clears_the_lot() -> void:
	if _first_time():
		Route.clear()
		_arrivals.clear()
		Route.add(120.0, 0.0)
		Route.add(240.0, 0.0)
		Route.add(-80.0, 0.0)
		_stand_at(-80.0, 0.0)
		return
	if not _settled(not _arrivals.is_empty()):
		return
	_expect(Route.is_empty(),
		"reaching the third stop left %d behind it" % Route.count())
	_expect(_arrivals.size() == 1, "%d arrivals fired" % _arrivals.size())
	if not _arrivals.is_empty():
		_expect(_arrivals[0][0] == 2 and _arrivals[0][1] == 3,
			"skipping to the third reported index %d clearing %d"
				% [_arrivals[0][0], _arrivals[0][1]])
	_expect(not _marks.beacon_visible(), "a beam survived an emptied route")
	_stage = 3


## 3. The astronaut's node does not move while driving.
func _stage_arrival_while_driving() -> void:
	if _first_time():
		Route.clear()
		_arrivals.clear()
		# Park the astronaut a long way from the stop, then drive to it. If
		# anything is reading the astronaut's own position, nothing arrives.
		_stand_at(0.0, 0.0)
		_rover.enter(_astronaut)
		Route.add(150.0, 40.0)
		return
	# Hold the rover on the stop; a teleported body keeps falling otherwise.
	_rover.global_position = Vector3(150.0,
		_terrain.world_height_at(150.0, 40.0) + 1.5, 40.0)
	if not _settled(not _arrivals.is_empty()):
		return
	# Asserted after the poll, not inside it: a check that runs every polling
	# frame writes one failure per frame, and a report four hundred lines long
	# is a report nobody reads.
	_expect(_astronaut.vantage().distance_to(_rover.global_position) < 0.01,
		"vantage() did not follow the rover while driving")
	_expect(Route.is_empty(),
		"driving onto a stop did not clear it — %d left" % Route.count())
	_expect(not _arrivals.is_empty(), "no arrival fired while driving")
	_rover.exit()
	_stage = 4


## 5. The reveal is a pulse, not paint.
func _stage_reveal_costs_a_pulse() -> void:
	if _first_time():
		Route.clear()
		Route.add(120.0, 60.0)
		Route.add(240.0, -40.0)
		_stand_at(0.0, 0.0)
		return
	if _waited == 0:
		_expect(not _marks.reveal_visible(),
			"the route line was drawn without anybody scanning")
		_expect(not _marks.pointer_visible(),
			"the pointer was drawn without anybody scanning")
		_scanner.call("ping")
	if not _settled(_marks.reveal_visible() and _marks.pointer_visible()):
		return
	_expect(_marks.reveal_visible(), "a pulse did not reveal the route line")
	_expect(_marks.pointer_visible(), "a pulse did not draw the pointer")
	_expect(_marks.reveal_vertex_count() > 2,
		"the revealed line is visible but holds %d vertices"
			% _marks.reveal_vertex_count())
	var heading := _marks.pointer_heading()
	var want := (Vector2(120.0, 60.0)).normalized()
	_expect(heading.dot(want) > 0.98,
		"the pointer aims %s, the nearest stop is %s" % [heading, want])
	_stage = 5


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	Route.clear()
	if _failures.is_empty():
		print("PASS: one beam on the nearest stop, arrival clears what is behind it,")
		print("      and the route line costs a pulse.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
