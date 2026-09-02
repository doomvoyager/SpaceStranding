extends Node
class_name PadCursor
## A pointer driven by the left stick, for panels built around a mouse.
##
## **It moves the real cursor rather than drawing a fake one.** Every panel in
## the game is already built out of Controls that respond to mouse motion and
## clicks — the map's viewport, the order board's list, every button. Warping
## the actual pointer and synthesising real mouse events means all of that keeps
## working untouched, and there is no second input path to keep in step with the
## first. A drawn cursor would have meant teaching every panel about it.
##
## Active only while a panel has the screen, which is exactly what
## `Astronaut.is_menu_open()` already answers — so this cannot interfere with
## driving or walking, and a panel added later gets pad support for free.
##
## The mouse is not locked out while this runs: the stick only warps the pointer
## when it is actually deflected, so picking up the mouse mid-panel just works.

## Emitted when a synthesised click is sent. Position is in viewport pixels.
## Tests listen for this; nothing in the game needs to.
signal clicked(at: Vector2)

@export_group("Pointer")
## Pixels per second at full deflection.
@export_range(100.0, 4000.0, 10.0) var speed := 1100.0

## Stick throw below this is ignored. Above the pad's own deadzone on purpose:
## a cursor that creeps while you are not touching the stick is worse than one
## that needs a firm push.
@export_range(0.0, 0.6, 0.01) var deadzone := 0.22

## Exponent on the stick throw. Above 1.0 gives fine control near the centre and
## full speed at the edge, which is what makes a stick usable for pointing at a
## button rather than only for shoving a cursor across a screen.
@export_range(1.0, 4.0, 0.1) var precision_curve := 2.0

## Off makes the panels mouse-only again, which is the honest way to check
## whether a change actually needed the pad path.
@export var enabled := true

var _astronaut: Astronaut
var _position := Vector2.ZERO
var _active := false
var _pressed := false
## Last OS pointer position seen, so a mouse that has not moved cannot drag the
## pad's pointer back.
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	add_to_group("pad_cursor")


## Where the emulated pointer is. Tracked here rather than read back from the
## viewport, so it is the authority and a test does not depend on whether the
## platform actually moved an OS cursor.
func cursor_position() -> Vector2:
	return _position


func is_active() -> bool:
	return _active


func _player() -> Astronaut:
	if _astronaut == null or not is_instance_valid(_astronaut):
		_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	return _astronaut


func _panel_open() -> bool:
	var player := _player()
	return player != null and player.is_menu_open()


## The pixels a stick throw is worth this frame. Pure, so the feel can be
## checked without a window.
func step_for(stick: Vector2, delta: float) -> Vector2:
	var throw := stick.length()
	if throw < deadzone:
		return Vector2.ZERO
	# Rescale past the deadzone so the first responsive position is a crawl and
	# not a jump — the same reason the astronaut keeps the stick's magnitude
	# rather than normalising it away.
	var scaled := (throw - deadzone) / maxf(1.0 - deadzone, 0.001)
	return stick.normalized() * pow(clampf(scaled, 0.0, 1.0), precision_curve) \
		* speed * delta


func _process(delta: float) -> void:
	var open := enabled and _panel_open()
	if open != _active:
		_active = open
		if open:
			# Start from wherever the mouse already is, so opening a panel does
			# not teleport the pointer away from what the player was looking at.
			_position = get_viewport().get_mouse_position()
			_last_mouse = _position
	if not _active:
		return

	# **The mouse only takes the pointer back when it actually moves.**
	# Re-reading the OS position every idle frame looks equivalent and is not:
	# it hands authority to whatever the platform last reported, which under
	# --headless is junk and in a window is a stale position the moment the pad
	# is doing the driving. Comparing against the last seen value is what lets
	# a mouse and a stick share one pointer without fighting over it.
	var mouse := get_viewport().get_mouse_position()
	if mouse != _last_mouse:
		_last_mouse = mouse
		_position = mouse

	var step := step_for(_stick(), delta)
	if step == Vector2.ZERO:
		return
	var bounds := get_viewport().get_visible_rect()
	_position = (_position + step).clamp(bounds.position,
		bounds.position + bounds.size)
	Input.warp_mouse(_position)
	_last_mouse = _position


## Read off the pad's axes directly rather than through the InputMap.
##
## `move_left`/`move_right` and friends carry WASD as well as the stick, and a
## panel where W nudges the pointer would be a strange thing to have built. This
## is explicitly a *pad* feature, so it asks the pad. Returns zero with no
## controller attached, which is exactly the right answer.
func _stick() -> Vector2:
	if Input.get_connected_joypads().is_empty():
		return Vector2.ZERO
	var pad: int = Input.get_connected_joypads()[0]
	return Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))


## Enter and Space on a keyboard, and the pad's bottom action button.
##
## **`ui_accept` is not A.** It was written here as though it were, and measured
## in 4.7.1 it carries Enter, KP Enter and Space and *no* joypad binding at all —
## so for as long as this file has existed, pressing A in a panel did nothing.
## The one test that would have caught it is the one that cannot run: a
## synthesised click never reaches the GUI under `--headless`, so the assertion
## is skipped there. Measured by `tests/probe_pad_bindings.tscn`.
##
## The button is read off the pad rather than bound into `ui_accept`, for the
## reason the next paragraph gives: a global binding would make A press a
## *focused* control as well as clicking under the pointer. The map panel drops
## focus so it would survive that; the order board grabs focus and would fire
## twice. Keeping this local means neither panel has to know.
##
## Handled here, in `_input`, and marked handled: the event is turned into a
## mouse click and must not *also* reach the astronaut, which carries `interact`
## on the same physical button.
func _input(event: InputEvent) -> void:
	if not _active:
		return
	if _is_click(event) and not _pressed:
		_pressed = true
		_send_click(true)
		get_viewport().set_input_as_handled()
	elif _is_click_release(event) and _pressed:
		_pressed = false
		_send_click(false)
		get_viewport().set_input_as_handled()


func _is_click(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	var button := event as InputEventJoypadButton
	return button != null and button.pressed \
		and button.button_index == JOY_BUTTON_A


func _is_click_release(event: InputEvent) -> bool:
	if event.is_action_released("ui_accept"):
		return true
	var button := event as InputEventJoypadButton
	return button != null and not button.pressed \
		and button.button_index == JOY_BUTTON_A


func _send_click(pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = _position
	click.global_position = _position
	if pressed:
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(click)
	if pressed:
		clicked.emit(_position)
