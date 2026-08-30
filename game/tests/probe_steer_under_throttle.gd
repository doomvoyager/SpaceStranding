extends Node3D
## Diagnostic: what happens to the steering angle as the throttle comes on?
##
## The input map was cleared by probe_analog_input.gd - triggers are analog and
## do not leak into the steering actions - so a steering lock under throttle has
## to come from rover.gd itself. Feeds the real rover full analog lock plus
## increasing throttle and reports the angle it actually reaches.
##
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/probe_steer_under_throttle.tscn

const SETTLE_FRAMES := 60
const SAMPLE_FRAMES := 240

var _rover: Rover
var _frames := 0


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4000.0, 2.0, 4000.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	var astronaut: Astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	astronaut.position = Vector3(40.0, 1.0, 0.0)
	add_child(astronaut)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.0, 0.0)
	add_child(_rover)
	_rover.enter(astronaut)

	print("max_steer_angle %.0f deg, full lock below %.0f m/s, falloff to %.2f by %.0f m/s" % [
		_rover.max_steer_angle, _rover.steer_falloff_start,
		_rover.steer_falloff_floor, _rover.steer_falloff_speed
	])
	print("\n speed   authority   steer angle   (full lock held throughout)")


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return

	# Full analog left lock, throttle hard down.
	_stick(0, -1.0)
	_trigger(5, 1.0)

	if (_frames - SETTLE_FRAMES) % 30 == 0:
		print("  %5.2f     %5.3f       %5.2f deg" % [
			_rover.linear_velocity.length(),
			_rover.steer_authority(),
			rad_to_deg(_rover.steering),
		])

	if _frames >= SETTLE_FRAMES + SAMPLE_FRAMES:
		print("\nfull lock at a standstill would be %.1f deg" % _rover.max_steer_angle)
		get_tree().quit()


func _stick(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _trigger(axis: int, value: float) -> void:
	_stick(axis, value)
