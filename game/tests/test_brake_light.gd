extends Node3D
## Regression test for the rover's brake light.
##
## The interesting assertion is the one that says the bar stays *dark*. Engine
## braking is applied whenever the throttle is closed, so a light wired to
## `brake > 0` rather than to the pedals is lit almost permanently - and a
## brake light that is always on is indistinguishable, in a screenshot, from a
## brake light that works.
##
## Asserts on the material's emission energy rather than on the boolean, because
## a state that is right and a material that never moves is exactly the shape of
## bug this project keeps meeting.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_brake_light.tscn

const SETTLE_FRAMES := 60
const DRIVE_FRAMES := 120
const COAST_FRAMES := 60
const HOLD_FRAMES := 30
## Long enough for the decelerate pedal to take the rover through a standstill
## and into reverse.
const REVERSE_FRAMES := 240

const F_THROTTLE := SETTLE_FRAMES
const F_COAST := F_THROTTLE + DRIVE_FRAMES
const F_BRAKE := F_COAST + COAST_FRAMES
const F_REGAIN := F_BRAKE + HOLD_FRAMES
const F_DECELERATE := F_REGAIN + DRIVE_FRAMES
const F_REVERSE := F_DECELERATE + HOLD_FRAMES
const F_EXIT := F_REVERSE + REVERSE_FRAMES
const F_END := F_EXIT + 5

var _rover: Rover
var _astronaut: Astronaut
var _frames := 0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var g_col := CollisionShape3D.new()
	var g_shape := BoxShape3D.new()
	g_shape.size = Vector3(600.0, 2.0, 600.0)
	g_col.shape = g_shape
	ground.add_child(g_col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(20.0, 1.0, 0.0)
	add_child(_astronaut)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.0, 0.0)
	add_child(_rover)

	if _rover.brake_light_output() < 0.0:
		_failures.append(
			"the rover has no brake light material to drive - check "
			+ "brake_light_path and that the bar carries a StandardMaterial3D"
		)

	_rover.enter(_astronaut)


func _physics_process(_delta: float) -> void:
	_frames += 1

	match _frames:
		F_THROTTLE:
			Input.action_press("drive_forward")

		F_COAST:
			_expect_dark("under throttle")
			Input.action_release("drive_forward")

		F_BRAKE:
			# The pedals are all released, so the drivetrain is applying
			# engine_braking. That is not a brake light.
			_expect_dark("coasting under engine braking")
			Input.action_press("brake")

		F_REGAIN:
			_expect_lit("on the full brake")
			Input.action_release("brake")
			Input.action_press("drive_forward")

		F_DECELERATE:
			_expect_dark("back on the throttle")
			Input.action_release("drive_forward")
			Input.action_press("drive_back")

		F_REVERSE:
			_expect_lit("on the decelerate pedal while rolling forward")

		F_EXIT:
			# Held this long the pedal has become reverse, not brake.
			if _rover.forward_speed() > -0.5:
				_failures.append(
					"decelerate held for %d frames reached only %.2f m/s; the"
					% [REVERSE_FRAMES, _rover.forward_speed()]
					+ " reverse half of this test never happened"
				)
			elif _rover.brake_light_on_reverse:
				_expect_lit("reversing, with brake_light_on_reverse set")
			else:
				_expect_dark("reversing, with brake_light_on_reverse clear")
			Input.action_release("drive_back")
			_rover.exit()

		F_END:
			_expect_dark("parked, with nobody driving")
			_finish()


func _expect_lit(when: String) -> void:
	var energy := _rover.brake_light_output()
	print("%s: emission %.2f (lit=%s)" % [when, energy, _rover.brake_light_on()])
	if not _rover.brake_light_on():
		_failures.append("brake light is off %s" % when)
	if energy < _rover.brake_light_energy - 0.001:
		_failures.append(
			"brake light material reads %.2f %s, expected %.2f"
			% [energy, when, _rover.brake_light_energy]
		)


func _expect_dark(when: String) -> void:
	var energy := _rover.brake_light_output()
	print("%s: emission %.2f (lit=%s)" % [when, energy, _rover.brake_light_on()])
	if _rover.brake_light_on():
		_failures.append("brake light is on %s" % when)
	if energy > _rover.brake_light_idle_energy + 0.001:
		_failures.append(
			"brake light material reads %.2f %s, expected the idle %.2f"
			% [energy, when, _rover.brake_light_idle_energy]
		)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the brake light follows the pedals.")
		# quit() only schedules the exit, so this must return.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
