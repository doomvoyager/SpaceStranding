extends Node3D
## Regression test for the pad cursor — pointing and clicking in panels with a
## controller. See [[The-Map]].
##
## What this exists to catch:
##
##   1. **It must only exist while a panel is up.** A pointer that warps the
##      mouse while you are driving would fight the camera for the same input
##      and be very hard to diagnose from the symptom.
##
##   2. **The stick curve must actually be a curve.** Half a stick has to be
##      much less than half speed, or the thing is unusable for pointing at a
##      button — which is the entire reason it exists. A linear ramp passes
##      every "does it move" test and fails the only one that matters.
##
##   3. **The deadzone must be a floor, not a scale.** `Input.get_action_strength`
##      rescales by the deadzone and this does not use it; a resting stick has
##      to produce exactly zero, or the pointer creeps across the screen while
##      nobody is touching it.
##
##   4. **A click must be a real mouse event.** The whole design is that panels
##      keep their mouse handling and learn nothing about the pad. If the
##      synthesised event is not a genuine left click at the pointer, every
##      panel needs a second input path.
##
##   5. **And it must actually reach the panel.** The point above checks the
##      shape of the event; this one checks that pointing at the map and
##      pressing A plants a stop, which is the only thing a player cares about
##      and the only part that goes through Godot's whole input pipeline.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_pad_cursor.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const BUDGET := 400
const SETTLE := 60

var _astronaut: Astronaut
var _panel: MapPanel
var _cursor: PadCursor
var _clicks: Array = []
var _frames := 0
var _stage := 0
var _waited := 0
var _ready_for := -1
var _failures: Array[String] = []


func _ready() -> void:
	add_child(WORLD.instantiate())
	Route.clear()


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE:
		return
	if _cursor == null and not _find_the_pieces():
		if _frames > BUDGET:
			_expect(false, "never found the pad cursor in the world")
			_finish()
		return
	match _stage:
		0: _stage_the_curve()
		1: _stage_asleep_until_a_panel_opens()
		2: _stage_awake_with_a_panel()
		3: _stage_a_click_is_a_mouse_event()
		4: _stage_the_button_is_actually_bound()
		5: _stage_the_stick_does_not_pan()
		6: _stage_a_click_plants_a_stop()
		7: _finish()


func _find_the_pieces() -> bool:
	_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_panel = get_tree().get_first_node_in_group("map_panel") as MapPanel
	_cursor = get_tree().get_first_node_in_group("pad_cursor") as PadCursor
	if _cursor != null:
		_cursor.clicked.connect(func(at: Vector2) -> void: _clicks.append(at))
	return _astronaut != null and _panel != null and _cursor != null


func _first_time() -> bool:
	if _ready_for == _stage:
		return false
	_ready_for = _stage
	_waited = 0
	return true


## 2 and 3. The feel, checked as arithmetic rather than by hand.
func _stage_the_curve() -> void:
	var dt := 1.0 / 60.0
	_expect(_cursor.step_for(Vector2.ZERO, dt) == Vector2.ZERO,
		"a centred stick moved the pointer")
	_expect(_cursor.step_for(Vector2(_cursor.deadzone * 0.9, 0.0), dt) == Vector2.ZERO,
		"a stick inside the deadzone moved the pointer")

	var full := _cursor.step_for(Vector2(1.0, 0.0), dt).length()
	var half := _cursor.step_for(Vector2(0.5, 0.0), dt).length()
	_expect(full > 0.0, "a full stick did not move the pointer at all")
	_expect(is_equal_approx(full, _cursor.speed * dt),
		"a full stick moves %.2f px, not the %.2f the speed says"
			% [full, _cursor.speed * dt])
	# The point of the curve: half deflection is much less than half speed.
	_expect(half < full * 0.4,
		"half a stick moves %.0f%% of full speed — that is a ramp, not a curve"
			% [100.0 * half / maxf(full, 0.001)])
	_expect(half > 0.0, "half a stick did not move the pointer")

	# Direction is preserved, not just magnitude.
	var diagonal := _cursor.step_for(Vector2(0.7, -0.7), dt)
	_expect(diagonal.x > 0.0 and diagonal.y < 0.0,
		"a diagonal stick moved the pointer to %s" % diagonal)
	_stage = 1


## 1. Nothing while the world has the screen.
func _stage_asleep_until_a_panel_opens() -> void:
	if _first_time():
		if _panel.is_open():
			_panel.close()
		return
	if not _settled(not _cursor.is_active()):
		return
	_expect(not _cursor.is_active(),
		"the pad cursor was live with no panel open")
	_stage = 2


func _stage_awake_with_a_panel() -> void:
	if _first_time():
		_panel.open()
		return
	if not _settled(_cursor.is_active()):
		return
	_expect(_astronaut.is_menu_open(), "the map did not take the screen")
	_expect(_cursor.is_active(), "the pad cursor stayed asleep behind an open panel")
	_stage = 3


## 4. The click has to be a real left click where the pointer is.
func _stage_a_click_is_a_mouse_event() -> void:
	if _first_time():
		_clicks.clear()
		return
	if _waited == 0:
		# Straight at the private sender, because a headless run has no pad to
		# press A on. What is being checked is the shape of what it emits, not
		# the binding — the binding is one line and `ui_accept` is Godot's.
		_cursor._send_click(true)
		_cursor._send_click(false)
	if not _settled(not _clicks.is_empty()):
		return
	_expect(_clicks.size() == 1,
		"%d clicks emitted for one press" % _clicks.size())
	if not _clicks.is_empty():
		_expect(_clicks[0] == _cursor.cursor_position(),
			"the click landed at %s, the pointer is at %s"
				% [_clicks[0], _cursor.cursor_position()])
	_stage = 4


## 6. The button the stage above deliberately did not check.
##
## It said so out loud: "the binding is one line and `ui_accept` is Godot's."
## Both halves were wrong. Measured in 4.7.1, `ui_accept` carries Enter, KP
## Enter and Space and **no joypad event at all**, so A did nothing in a panel
## for as long as `PadCursor` had existed — the one input a pad-only feature has
## to have. It read as untestable because the *end-to-end* click is: no window,
## no hit-test, no `gui_input`. But the press itself is an ordinary event, and
## `Input.parse_input_event` delivers those headless perfectly well. Only the
## last few centimetres were ever out of reach, and the whole thing was
## abandoned on account of them.
func _stage_the_button_is_actually_bound() -> void:
	if _first_time():
		_clicks.clear()
		return
	if _waited == 0:
		_press_pad_button(JOY_BUTTON_A, true)
		_press_pad_button(JOY_BUTTON_A, false)
	if not _settled(not _clicks.is_empty()):
		return
	_expect(_clicks.size() == 1,
		"pressing A in an open panel emitted %d clicks" % _clicks.size())
	_stage = 5


## 7. The left stick must move the pointer and nothing else.
##
## `map_panel.gd` panned on `Input.get_vector("ui_left", …)` under a comment
## saying pan was "on the d-pad, not the left stick". Godot's built-in UI
## actions never appear in `project.godot` unless overridden, so nobody wrote
## that binding and nobody read it — and its engine default carries the left
## stick *as well as* the d-pad. One deflection therefore drove the pointer and
## swept the map out from under it at the same time.
##
## What is asserted is the trap rather than the fix: `_dpad()` reads button
## state, and `Input.is_joy_button_pressed` answers for real pads only, so with
## no controller attached it is zero however it is written and the assertion
## would pass vacuously. `Input.get_vector` does respond to a synthesised axis,
## so the thing that *can* be pinned down is that `ui_*` still means the left
## stick — which is what makes reading it a bug. If a future Godot changes that
## default, this fires and the comment above becomes wrong rather than silently
## unnecessary.
func _stage_the_stick_does_not_pan() -> void:
	if _first_time():
		return
	if _waited == 0:
		var push := InputEventJoypadMotion.new()
		push.axis = JOY_AXIS_LEFT_X
		push.axis_value = 1.0
		Input.parse_input_event(push)
	if not _settled(_waited > 2):
		return
	var ui := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_expect(ui.length() > 0.5,
		"`ui_*` no longer follows the left stick (read %s) — the reason " % ui
			+ "map_panel reads the d-pad directly is gone, and the comment "
			+ "explaining it is now wrong")
	_expect(_panel._dpad() == Vector2.ZERO,
		"the left stick panned the map: _dpad() returned %s" % _panel._dpad())
	var release := InputEventJoypadMotion.new()
	release.axis = JOY_AXIS_LEFT_X
	release.axis_value = 0.0
	Input.parse_input_event(release)
	if Input.get_connected_joypads().is_empty():
		print("SKIP: no pad attached, so _dpad() is zero however it is written —")
		print("      run this test with a controller plugged in to mean it.")
	_stage = 6


func _press_pad_button(index: int, pressed: bool) -> void:
	var button := InputEventJoypadButton.new()
	button.button_index = index
	button.pressed = pressed
	Input.parse_input_event(button)


## 5. The end of the whole design: point at the map, press A, get a stop.
func _stage_a_click_plants_a_stop() -> void:
	if _first_time():
		Route.clear()
		return
	if _waited == 0:
		# Park the pointer in the middle of the map view and click it the way
		# the pad would. Nothing about the panel was changed to accept this.
		var rect := _panel.view_rect()
		_cursor._position = rect.position + rect.size * 0.5
		_cursor._send_click(true)
		_cursor._send_click(false)
	if not _settled(not Route.is_empty()):
		return
	if DisplayServer.get_name() == "headless":
		# **A synthesised mouse event does not reach the GUI under --headless.**
		# There is no window to hit-test against, so Godot never finds the
		# Control under the pointer and `gui_input` is never emitted — the event
		# arrives in `_unhandled_input` and stops there. Verified by running this
		# same test windowed, where it passes. So the claim is made, and skipped
		# rather than quietly weakened, when there is nothing to click on.
		print("SKIP: synthesised clicks do not reach the GUI headless —")
		print("      run this test windowed to check the end-to-end path.")
	else:
		_expect(not Route.is_empty(),
			"a click in the middle of the map planted no stop")
	_panel.close()
	_stage = 7


func _settled(condition: bool) -> bool:
	_waited += 1
	return condition or _waited > BUDGET


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	Route.clear()
	if _failures.is_empty():
		print("PASS: the pad cursor sleeps outside panels, curves, and clicks for real.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
