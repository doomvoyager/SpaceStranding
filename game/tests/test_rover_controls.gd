extends Node3D
## Regression test for the rover control axes, which were inverted once and are
## easy to invert again: throttle must move the real rover toward its own -Z
## (the end the headlights and steering axle are on), and A must yaw it LEFT
## while doing so.
##
## The two are coupled. A backwards-driving rover also reads as inverted
## steering, because you are watching it come at the camera - so a fix that
## inverts both leaves steering genuinely wrong. Test them together.
##
## Also locks in the pedal layout: throttle is `drive_forward`/`drive_back`
## (W/S and RT/LT), NOT `move_forward`/`move_back`, which carry the left stick
## for the astronaut on foot. In the rover the stick steers only. And the
## decelerate pedal brakes while rolling forward, reversing only once stopped.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_rover_controls.tscn

const SETTLE_FRAMES := 60
const DRIVE_FRAMES := 180
const TURN_FRAMES := 180
const COAST_FRAMES := 120
const BRAKE_FRAMES := 45
const REVERSE_FRAMES := 210

const F_DRIVE := SETTLE_FRAMES
const F_TURN := F_DRIVE + DRIVE_FRAMES
const F_COAST := F_TURN + TURN_FRAMES
const F_BRAKE := F_COAST + COAST_FRAMES
const F_DECELERATE := F_BRAKE + DRIVE_FRAMES
const F_REVERSE := F_DECELERATE + BRAKE_FRAMES
const F_END := F_REVERSE + REVERSE_FRAMES
## Metres of forward travel below which we call it a failure.
const MIN_EXPECTED_TRAVEL := 2.0
## Degrees of yaw below which we are not convincingly turning.
const MIN_EXPECTED_YAW := 5.0

var _rover: Rover
var _start_pos := Vector3.ZERO
var _start_basis := Basis.IDENTITY
var _yaw_before_turn := 0.0
var _speed_before_coast := 0.0
var _speed_before_brake := 0.0
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
		F_DRIVE:
			_start_pos = _rover.global_position
			_start_basis = _rover.global_transform.basis
			Input.action_press("drive_forward")

		F_TURN:
			_check_forward()
			_yaw_before_turn = _rover.global_rotation.y
			Input.action_press("move_left")

		F_COAST:
			_check_steering()
			# The stick's own action must do nothing at all in the rover.
			Input.action_release("drive_forward")
			Input.action_release("move_left")
			Input.action_press("move_forward")
			_speed_before_coast = _rover.forward_speed()

		F_BRAKE:
			_check_stick_does_not_drive()
			Input.action_release("move_forward")
			Input.action_press("drive_forward")

		F_DECELERATE:
			Input.action_release("drive_forward")
			Input.action_press("drive_back")
			_speed_before_brake = _rover.forward_speed()

		F_REVERSE:
			_check_decelerates_without_reversing()

		F_END:
			Input.action_release("drive_back")
			_check_reverses_once_stopped()
			_finish()


func _check_forward() -> void:
	var delta_pos := _rover.global_position - _start_pos
	# The rover's own forward is -Z, as it is for every node in Godot.
	var travelled := delta_pos.dot(-_start_basis.z)
	print("throttle: %+.2f m along the rover's own forward axis" % travelled)
	if travelled < MIN_EXPECTED_TRAVEL:
		_failures.append(
			"drive_forward moved the rover %+.2f m along its forward axis, expected >= %.1f"
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


## move_forward carries the left stick, which steers and nothing else in the
## rover. Holding it must leave the rover coasting down, not accelerating.
func _check_stick_does_not_drive() -> void:
	var now := _rover.forward_speed()
	print("stick held: %.2f -> %.2f m/s" % [_speed_before_coast, now])
	if now >= _speed_before_coast:
		_failures.append(
			"move_forward drove the rover: %.2f -> %.2f m/s. The left stick must"
			% [_speed_before_coast, now]
			+ " steer only; throttle is drive_forward."
		)


## Holding decelerate while rolling forward must slow the rover down without
## snapping it into reverse.
func _check_decelerates_without_reversing() -> void:
	var now := _rover.forward_speed()
	var shed := _speed_before_brake - now
	print("decelerate: %.2f -> %.2f m/s (shed %.2f)" % [_speed_before_brake, now, shed])
	if shed < 1.0:
		_failures.append(
			"decelerate shed only %.2f m/s in %d frames; it is not braking"
			% [shed, BRAKE_FRAMES]
		)
	if now < -reverse_slack():
		_failures.append(
			"decelerate snapped straight into reverse (%.2f m/s) instead of braking" % now
		)


## Held past a standstill, it must actually reverse.
func _check_reverses_once_stopped() -> void:
	var now := _rover.forward_speed()
	print("held to reverse: %.2f m/s" % now)
	if now > -0.5:
		_failures.append(
			"decelerate held past a stop reached only %.2f m/s; expected reverse" % now
		)


## Tolerance for overshooting the reverse threshold within one check window.
func reverse_slack() -> float:
	return 0.5


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: rover control axes are correct.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
