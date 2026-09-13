extends Node
## Probe: what a focused Control does with keys and sticks that gameplay also
## reads - measured, because the F1 panel is used while driving and every one of
## these would be a control pressing two things at once.
##
##   1. A focused Button, and Space. `ui_accept` is Space (see CLAUDE.md), and
##      Space is also `brake` and `jump`.
##   2. A focused HSlider, and the left stick. `ui_left` carries the stick, and
##      in the rover the stick steers.
##   3. A focused LineEdit, and W. It swallows the key event - but does the
##      `move_forward` POLL still read it?
##   4. A CanvasLayer hidden with a focused LineEdit inside. Does focus go?
##   5. `focus_mode = FOCUS_NONE`, and `grab_focus()`.
##
## Prints; does not fail. Runs as a scene so the project's InputMap exists.
##   engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##     res://tests/probe_panel_focus.tscn

var _layer: CanvasLayer
var _unhandled_keys := 0


func _ready() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	await get_tree().process_frame

	await _button_and_space()
	await _slider_and_stick()
	await _line_edit_and_w()
	await _hidden_layer_keeps_focus()
	await _focus_none()
	print("PROBE DONE")
	get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_unhandled_keys += 1


func _button_and_space() -> void:
	var button := Button.new()
	button.text = "Reset all"
	_layer.add_child(button)
	var presses := [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	button.grab_focus()
	await get_tree().process_frame
	print("1. button has focus: %s (focus_mode %d)" % [button.has_focus(), button.focus_mode])
	await _key(KEY_SPACE)
	print("1. Space on a focused Button: pressed fired %d time(s); jump pressed: %s, brake pressed: %s"
		% [presses[0], Input.is_action_pressed("jump"), Input.is_action_pressed("brake")])
	await _key(KEY_SPACE, false)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER, false)
	print("1. ...and after Enter: pressed fired %d time(s) in total" % presses[0])
	button.queue_free()
	await get_tree().process_frame


func _slider_and_stick() -> void:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 60.0
	slider.step = 0.06
	slider.value = 32.0
	slider.custom_minimum_size = Vector2(200, 20)
	_layer.add_child(slider)
	slider.grab_focus()
	await get_tree().process_frame
	print("2. slider has focus: %s" % slider.has_focus())
	for i in 10:
		var e := InputEventJoypadMotion.new()
		e.device = 0
		e.axis = JOY_AXIS_LEFT_X
		e.axis_value = -1.0
		Input.parse_input_event(e)
		await get_tree().process_frame
	var e2 := InputEventJoypadMotion.new()
	e2.axis = JOY_AXIS_LEFT_X
	e2.axis_value = 0.0
	Input.parse_input_event(e2)
	await get_tree().process_frame
	print("2. left stick held on a focused HSlider for 10 frames: 32.0 -> %s" % slider.value)
	await _key(KEY_LEFT)
	await _key(KEY_LEFT, false)
	print("2. ...then one Left arrow press: -> %s" % slider.value)
	slider.queue_free()
	await get_tree().process_frame


func _line_edit_and_w() -> void:
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(200, 20)
	_layer.add_child(field)
	field.grab_focus()
	await get_tree().process_frame
	_unhandled_keys = 0
	await _key(KEY_W, true, "w")
	print("3. W into a focused LineEdit: text '%s', reached _unhandled_input %d time(s), move_forward POLL reads %s"
		% [field.text, _unhandled_keys, Input.is_action_pressed("move_forward")])
	await _key(KEY_W, false)
	field.queue_free()
	await get_tree().process_frame


func _hidden_layer_keeps_focus() -> void:
	var field := LineEdit.new()
	_layer.add_child(field)
	field.grab_focus()
	await get_tree().process_frame
	var before := get_viewport().gui_get_focus_owner() == field
	_layer.visible = false
	await get_tree().process_frame
	var owner := get_viewport().gui_get_focus_owner()
	print("4. LineEdit focused: %s; after CanvasLayer.visible = false the focus owner is %s, is_visible_in_tree %s"
		% [before, "the field" if owner == field else str(owner), field.is_visible_in_tree()])
	_layer.visible = true
	field.queue_free()
	await get_tree().process_frame


func _focus_none() -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	_layer.add_child(button)
	button.grab_focus()
	await get_tree().process_frame
	print("5. FOCUS_NONE button after grab_focus(): has_focus %s" % button.has_focus())
	button.queue_free()
	await get_tree().process_frame


func _key(code: Key, pressed := true, text := "") -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	if text != "" and pressed:
		e.unicode = text.unicode_at(0)
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame
