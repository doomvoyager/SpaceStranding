extends Node
## What the pad's left stick actually drives, measured through the real InputMap.
##
## `map_panel.gd` moved pan onto the d-pad on the stated grounds that "the left
## stick drives the pointer now" - but Godot's *built-in* `ui_*` actions are not
## written into `project.godot` unless they have been overridden, and their
## engine defaults carry the left stick alongside the d-pad. So the claim was
## never true, and nothing measured it.
##
## Two readings: the events behind each action, and the value the panel's own
## `Input.get_vector` call returns for a synthesised left-stick deflection.

const PAN := ["ui_left", "ui_right", "ui_up", "ui_down"]
const ORBIT := ["look_left", "look_right", "look_up", "look_down"]

var _stage := 0


func _ready() -> void:
	var axis_names := {0: "LEFT_X", 1: "LEFT_Y", 2: "RIGHT_X", 3: "RIGHT_Y",
		4: "TRIGGER_LEFT", 5: "TRIGGER_RIGHT"}
	print("--- what each action listens to ---")
	for action: String in PAN + ORBIT + ["move_left", "move_forward"]:
		var parts: Array[String] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				var motion := event as InputEventJoypadMotion
				parts.append("axis %s %+.0f" % [
					axis_names.get(motion.axis, str(motion.axis)),
					motion.axis_value])
			elif event is InputEventJoypadButton:
				parts.append("dpad/button %d" % (event as InputEventJoypadButton).button_index)
			elif event is InputEventKey:
				parts.append("key %s" % OS.get_keycode_string(
					(event as InputEventKey).physical_keycode))
		print("  %-14s %s" % [action, ", ".join(parts)])


func _push(axis: int, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	Input.parse_input_event(motion)


## Staged over frames because Input only settles its action state on a tick.
func _process(_delta: float) -> void:
	_stage += 1
	match _stage:
		1:
			print("")
			print("--- left stick pushed fully right ---")
			_push(JOY_AXIS_LEFT_X, 1.0)
		3:
			_report()
			_push(JOY_AXIS_LEFT_X, 0.0)
		4:
			print("")
			print("--- right stick pushed fully right ---")
			_push(JOY_AXIS_RIGHT_X, 1.0)
		6:
			_report()
			get_tree().quit(0)


func _report() -> void:
	# Exactly the two calls map_panel.gd makes each frame.
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var orbit := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	# And exactly the call PadCursor makes.
	print("  map pan    (ui_*)    = %s" % pan)
	print("  map orbit  (look_*)  = %s" % orbit)
	print("  cursor     (raw axis) = %.2f" % Input.get_joy_axis(0, JOY_AXIS_LEFT_X))
