extends Node3D
## Regression test for analog input scaling.
##
## Two bugs this locks out, both of which made a stick or trigger behave like a
## switch:
##
##   1. The astronaut normalised its wish direction, throwing away the stick's
##      magnitude, so half a stick walked at full speed.
##   2. The rover's steering falloff ramped from 0 m/s, so authority eroded from
##      the first metre per second. Holding the throttle straightened the wheels
##      on its own, which reads as the throttle stealing the steering.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_analog_input.tscn

const AXIS_LX := 0
const AXIS_LY := 1
const AXIS_RT := 5

const SETTLE := 45
const WALK := 150
const SAMPLE := 60

const F_WALK_HALF := SETTLE + WALK
const F_WALK_FULL := F_WALK_HALF + WALK
const F_BOARD := F_WALK_FULL + 5
const F_HALF_THROTTLE := F_BOARD + SAMPLE
const F_FULL_THROTTLE := F_HALF_THROTTLE + SAMPLE
const F_STEER := F_FULL_THROTTLE + 120

var _astronaut: Astronaut
var _rover: Rover
var _half_walk := 0.0
var _half_accel := 0.0
var _frames := 0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4000.0, 2.0, 4000.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(0.0, 1.0, 0.0)
	add_child(_astronaut)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(60.0, 1.0, 0.0)
	add_child(_rover)


func _physics_process(_delta: float) -> void:
	_frames += 1

	match _frames:
		SETTLE:
			_axis(AXIS_LY, -0.5)          # half stick forward

		F_WALK_HALF:
			_half_walk = _speed(_astronaut.velocity)
			_check_half_walk()
			_axis(AXIS_LY, -1.0)          # full stick forward

		F_WALK_FULL:
			_check_full_walk()
			_axis(AXIS_LY, 0.0)
			_astronaut.global_position = _rover.global_position + Vector3(2.5, 0.0, 0.0)

		F_BOARD:
			_rover.enter(_astronaut)
			_reset_rover()
			_axis(AXIS_RT, 0.5)           # half trigger

		F_HALF_THROTTLE:
			_half_accel = _rover.forward_speed()
			_reset_rover()
			_axis(AXIS_RT, 1.0)           # full trigger

		F_FULL_THROTTLE:
			_check_throttle_scales(_rover.forward_speed())
			# Hold full lock at manoeuvring speed and let the wheels get there.
			_axis(AXIS_RT, 0.0)
			_reset_rover()
			_axis(AXIS_RT, 0.35)
			_axis(AXIS_LX, -1.0)

		F_STEER:
			_check_lock_survives_throttle()
			_finish()


## Half a stick must walk at about half speed - not at full speed, which is what
## normalising the wish direction used to produce.
func _check_half_walk() -> void:
	var throw := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	).length()
	var expected := _astronaut.walk_speed * throw
	print("half stick: throw %.3f -> %.2f m/s (expected ~%.2f, full walk is %.2f)" % [
		throw, _half_walk, expected, _astronaut.walk_speed
	])
	if absf(_half_walk - expected) > 0.4:
		_failures.append(
			"half stick walked at %.2f m/s, expected ~%.2f" % [_half_walk, expected]
		)
	if _half_walk > _astronaut.walk_speed * 0.8:
		_failures.append(
			"half stick walked at %.2f m/s, near the full %.2f - the stick is being"
			% [_half_walk, _astronaut.walk_speed]
			+ " treated as a switch"
		)


func _check_full_walk() -> void:
	var full := _speed(_astronaut.velocity)
	print("full stick: %.2f m/s (walk_speed %.2f)" % [full, _astronaut.walk_speed])
	if absf(full - _astronaut.walk_speed) > 0.3:
		_failures.append(
			"full stick walked at %.2f m/s, expected %.2f" % [full, _astronaut.walk_speed]
		)


## Half a trigger must accelerate the rover appreciably less than a full one.
func _check_throttle_scales(full_accel: float) -> void:
	var ratio := _half_accel / full_accel if full_accel > 0.01 else INF
	print("throttle: half %.2f m/s vs full %.2f m/s after %d frames (ratio %.2f)" % [
		_half_accel, full_accel, SAMPLE, ratio
	])
	if full_accel < 0.5:
		_failures.append("full throttle barely moved the rover (%.2f m/s)" % full_accel)
	if ratio > 0.8:
		_failures.append(
			"half throttle gave %.0f%% of full acceleration - the trigger is being"
			% (ratio * 100.0)
			+ " treated as a switch"
		)
	if ratio < 0.2:
		_failures.append("half throttle gave only %.0f%% of full" % (ratio * 100.0))


## Under throttle, at manoeuvring speed, full lock must still be full lock.
func _check_lock_survives_throttle() -> void:
	var speed := _rover.linear_velocity.length()
	var angle := rad_to_deg(absf(_rover.steering))
	print("under throttle at %.2f m/s: %.2f deg of lock (max %.0f, authority %.3f)" % [
		speed, angle, _rover.max_steer_angle, _rover.steer_authority()
	])
	if speed > _rover.steer_falloff_start:
		_failures.append(
			"rover reached %.2f m/s, past the %.2f dead band; test is not measuring"
			% [speed, _rover.steer_falloff_start]
			+ " what it thinks it is"
		)
	if angle < _rover.max_steer_angle - 1.0:
		_failures.append(
			"holding the throttle cut the lock to %.2f deg of %.0f at only %.2f m/s"
			% [angle, _rover.max_steer_angle, speed]
		)


func _reset_rover() -> void:
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO


func _speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _axis(which: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = which
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: analog inputs scale.")
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
