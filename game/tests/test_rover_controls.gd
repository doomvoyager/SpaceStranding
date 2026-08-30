extends Node3D
## Regression test for the rover control axes, which were inverted once and are
## easy to invert again: pressing W must move the real rover toward its own -Z
## (the end the headlights and steering axle are on), and A must yaw it LEFT
## while doing so.
##
## The two are coupled. A backwards-driving rover also reads as inverted
## steering, because you are watching it come at the camera - so a fix that
## inverts both leaves steering genuinely wrong. Test them together.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_rover_controls.tscn

const SETTLE_FRAMES := 60
const DRIVE_FRAMES := 180
const TURN_FRAMES := 180
## Metres of forward travel below which we call it a failure.
const MIN_EXPECTED_TRAVEL := 2.0
## Degrees of yaw below which we are not convincingly turning.
const MIN_EXPECTED_YAW := 5.0

var _rover: Rover
var _start_pos := Vector3.ZERO
var _start_basis := Basis.IDENTITY
var _yaw_before_turn := 0.0
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

	var astronaut: Astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	astronaut.position = Vector3(20.0, 1.0, 0.0)
	add_child(astronaut)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.0, 0.0)
	add_child(_rover)

	_rover.enter(astronaut)


func _physics_process(_delta: float) -> void:
	_frames += 1

	match _frames:
		SETTLE_FRAMES:
			_start_pos = _rover.global_position
			_start_basis = _rover.global_transform.basis
			Input.action_press("move_forward")

		SETTLE_FRAMES + DRIVE_FRAMES:
			_check_forward()
			_yaw_before_turn = _rover.global_rotation.y
			Input.action_press("move_left")

		SETTLE_FRAMES + DRIVE_FRAMES + TURN_FRAMES:
			_check_steering()
			Input.action_release("move_forward")
			Input.action_release("move_left")
			_finish()


func _check_forward() -> void:
	var delta_pos := _rover.global_position - _start_pos
	# The rover's own forward is -Z, as it is for every node in Godot.
	var travelled := delta_pos.dot(-_start_basis.z)
	print("W: %+.2f m along the rover's own forward axis" % travelled)
	if travelled < MIN_EXPECTED_TRAVEL:
		_failures.append(
			"W moved the rover %+.2f m along its forward axis, expected >= %.1f"
			% [travelled, MIN_EXPECTED_TRAVEL]
		)


func _check_steering() -> void:
	var delta_yaw := rad_to_deg(
		wrapf(_rover.global_rotation.y - _yaw_before_turn, -PI, PI)
	)
	# +Y yaw is counter-clockwise seen from above, i.e. a left turn.
	print("A: %+.2f deg of yaw while driving forward" % delta_yaw)
	if delta_yaw < MIN_EXPECTED_YAW:
		_failures.append(
			"A yawed the rover %+.2f deg, expected >= %.1f (left)"
			% [delta_yaw, MIN_EXPECTED_YAW]
		)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: rover control axes are correct.")
		get_tree().quit(0)
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
