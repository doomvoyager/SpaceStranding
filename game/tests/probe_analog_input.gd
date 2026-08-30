extends Node3D
## Diagnostic: is the input map actually analog, and does one axis leak into
## another's actions?
##
## Two symptoms to explain - a trigger that reads as on/off rather than a pedal,
## and steering that pins itself when the throttle is held. Synthesises real
## InputEventJoypadMotion through the real InputMap rather than reasoning about
## Godot's deadzone maths.
##
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/probe_analog_input.tscn

const DRIVE := ["drive_back", "drive_forward"]
const STEER := ["move_right", "move_left"]

# axis: 0/1 left stick, 2/3 right stick, 4 LT, 5 RT
const AXIS_LX := 0
const AXIS_LT := 4
const AXIS_RT := 5


func _ready() -> void:
	print("--- what each action is bound to ---")
	for action in ["move_forward", "move_back", "move_left", "move_right",
			"drive_forward", "drive_back"]:
		var bits := PackedStringArray()
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadMotion:
				bits.append("axis %d @ %+.1f" % [e.axis, e.axis_value])
			elif e is InputEventKey:
				bits.append("key %d" % e.physical_keycode)
			elif e is InputEventJoypadButton:
				bits.append("button %d" % e.button_index)
		print("  %-14s deadzone %.2f  %s" % [
			action, InputMap.action_get_deadzone(action), ", ".join(bits)
		])

	print("\n--- is the trigger analog? RT swept 0 -> 1 ---")
	for v in [0.0, 0.15, 0.25, 0.5, 0.75, 1.0]:
		_axis(AXIS_RT, v)
		print("  RT %.2f -> drive_forward strength %.3f, get_axis %+.3f" % [
			v, Input.get_action_strength("drive_forward"), Input.get_axis(DRIVE[0], DRIVE[1])
		])

	print("\n--- what if a controller rests triggers at -1 instead of 0? ---")
	for v in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		_axis(AXIS_RT, v)
		print("  RT raw %+.2f -> strength %.3f" % [
			v, Input.get_action_strength("drive_forward")
		])

	print("\n--- does the throttle leak into steering? ---")
	_axis(AXIS_RT, 0.0)
	_axis(AXIS_LX, 0.6)
	print("  stick X 0.6, RT 0.0 -> steer %+.3f" % Input.get_axis(STEER[0], STEER[1]))
	_axis(AXIS_RT, 1.0)
	print("  stick X 0.6, RT 1.0 -> steer %+.3f" % Input.get_axis(STEER[0], STEER[1]))
	_axis(AXIS_LT, 1.0)
	print("  stick X 0.6, RT 1.0, LT 1.0 -> steer %+.3f" % Input.get_axis(STEER[0], STEER[1]))

	print("\n--- is the stick analog for walking? ---")
	_axis(AXIS_LT, 0.0)
	_axis(AXIS_RT, 0.0)
	for v in [0.25, 0.5, 0.75, 1.0]:
		_axis(AXIS_LX, v)
		var vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		print("  stick X %.2f -> get_vector %s (len %.3f)" % [v, vec, vec.length()])

	get_tree().quit()


func _axis(which: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = which
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()
