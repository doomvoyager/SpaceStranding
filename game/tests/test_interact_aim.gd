extends Node3D
## Regression test for aim-based interaction: which of several things in reach
## a verb acts on is decided by where the astronaut is looking.
##
## The case this exists for is the one Mac hit in play: **a crate lying beside
## the rover.** The old code tried crates first, so walking up to a loaded rover
## intending to drive it handed you a crate instead — the exact failure the
## two-verb split of 2026-08-30 was meant to prevent, surviving inside `E`'s own
## priority list. Nothing was wrong with either verb; the list was.
##
## Everything here is checked twice, once for each thing being aimed at, because
## a scorer that always returned the same answer would pass a one-sided test.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_interact_aim.tscn

const SETTLE_FRAMES := 30

var _astronaut: Astronaut
var _rover: Rover
var _crate: Crate
var _facility: Facility
var _frames := 0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	# The astronaut at the origin, with the rover on one side and a crate on the
	# other. Both well inside the 3.5 m interact sphere, and the *crate is
	# closer* — so anything that still picks by distance fails the rover half.
	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(2.6, 1.0, 0.0)
	add_child(_rover)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(0.0, 1.0, 0.0)
	add_child(_astronaut)

	_crate = load("res://scenes/cargo/crate.tscn").instantiate()
	_crate.position = Vector3(-1.4, 1.0, 0.0)
	add_child(_crate)

	_facility = load("res://scenes/world/facility.tscn").instantiate() as Facility
	_facility.facility_id = "hearth"
	_facility.display_name = "Hearth"
	# Dock at facility x - 3.6, so the dock deck lands 2.6 m behind the
	# astronaut — in reach, opposite the rover.
	_facility.position = Vector3(3.6, 0.0, -2.6)
	add_child(_facility)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames != SETTLE_FRAMES:
		return
	_check_reach_is_mutual()
	_check_aim_picks_the_crate()
	_check_aim_picks_the_rover()
	_check_behind_is_out_of_reach()
	_check_prompt_agrees_with_the_verb()
	_check_the_bug()
	_finish()


## Both are genuinely in reach, or the rest of the test proves nothing.
func _check_reach_is_mutual() -> void:
	_expect(_astronaut.nearby_rover() == _rover,
		"the rover is not in reach; test is invalid")
	_expect(_astronaut.nearest_loose_crate() == _crate,
		"the crate is not in reach; test is invalid")
	var to_crate := _astronaut.global_position.distance_to(_crate.global_position)
	var to_rover := _astronaut.global_position.distance_to(_rover.global_position)
	_expect(to_crate < to_rover,
		"the crate must be the *closer* of the two or the rover case is free: %.2f vs %.2f"
		% [to_crate, to_rover])


func _check_aim_picks_the_crate() -> void:
	_astronaut.aim_at(_crate.global_position)
	var target := _astronaut.interact_target()
	_expect(target != null and target.kind == Astronaut.KIND_CRATE,
		"looking at the crate, E would %s" % _describe(target))


func _check_aim_picks_the_rover() -> void:
	_astronaut.aim_at(_rover.global_position)
	var target := _astronaut.interact_target()
	_expect(target != null and target.kind == Astronaut.KIND_ROVER,
		"looking at the rover, E would %s" % _describe(target))


## Turning your back on everything must reach nothing. Without this the scorer
## could be ignoring the angle entirely and still pass both halves above.
func _check_behind_is_out_of_reach() -> void:
	_astronaut.aim_at(_astronaut.global_position + Vector3(0.0, 0.0, 8.0))
	_expect(_astronaut.interact_target() == null,
		"facing away from both, E would still %s"
		% _describe(_astronaut.interact_target()))
	_expect(_astronaut.interact_prompt() == "",
		"facing away from both, the HUD still offers '%s'" % _astronaut.interact_prompt())


## The HUD asks the astronaut what the key would do, so the two cannot drift —
## but only if they really are the same call. Check the words track the aim.
func _check_prompt_agrees_with_the_verb() -> void:
	_astronaut.aim_at(_crate.global_position)
	_expect(_astronaut.interact_prompt().begins_with("Pick up"),
		"looking at the crate, the prompt says '%s'" % _astronaut.interact_prompt())
	_astronaut.aim_at(_rover.global_position)
	_expect(_astronaut.interact_prompt() == "Board the rover",
		"looking at the rover, the prompt says '%s'" % _astronaut.interact_prompt())


## The bug itself: face the rover with a crate closer, and press E.
func _check_the_bug() -> void:
	_astronaut.aim_at(_rover.global_position)
	_astronaut._interact()
	_expect(_rover.driver == _astronaut,
		"E facing the rover did not board it")
	_expect(not _crate.is_stowed(),
		"E facing the rover picked up the crate instead — the original bug")
	_rover.exit()

	# And the other way round, from the same spot: the crate, not the rover.
	_astronaut.global_position = Vector3(0.0, 1.0, 0.0)
	_astronaut.velocity = Vector3.ZERO
	_astronaut.aim_at(_crate.global_position)
	_astronaut._interact()
	_expect(_crate.is_stowed(), "E facing the crate did not pick it up")
	_expect(_rover.driver == null, "E facing the crate boarded the rover")


func _describe(target) -> String:
	if target == null:
		return "do nothing"
	match target.kind:
		Astronaut.KIND_CRATE:
			return "pick up a crate"
		Astronaut.KIND_TERMINAL:
			return "open a board"
		Astronaut.KIND_ROVER:
			return "board the rover"
		Astronaut.KIND_DOCK:
			return "use a dock"
	return "do something unnamed"


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: interaction follows the look direction, not the priority list.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
