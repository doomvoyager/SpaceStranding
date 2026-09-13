extends Node3D
## Regression test: while a text field has the keyboard, the controls stand down.
##
## **A focused field swallows a key as an event but not as a poll.** Walking,
## jumping and the rover's pedals are all polled, so without this every letter
## typed into the F1 panel's search box also drives: "speed" walks you backwards
## and jumps, "wheel" opens the throttle. Measured in
## `tests/probe_panel_focus.tscn` before this was written.
##
## Uses a plain LineEdit rather than the panel's, because the rule is about any
## field with focus. Each half is checked both ways - held still while typing,
## moving once the field lets go - so a gate that simply froze the controls
## would fail too.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_typing_gate.tscn

const F_WALK_TYPING := 30
const F_WALK_FREE := 60
const F_WALK_DONE := 90
const F_JUMP_TYPING := 120
const F_JUMP_DONE := 140
const F_BOARD := 150
const F_DRIVE_TYPING := 180
const F_DRIVE_FREE := 240
const F_DRIVE_DONE := 300

var _astronaut: Astronaut
var _rover: Rover
var _field: LineEdit
var _mark := Vector3.ZERO
var _peak_y := 0.0
var _frames := 0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 2.0, 600.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(0.0, 1.0, 0.0)
	add_child(_astronaut)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(12.0, 1.0, 0.0)
	add_child(_rover)

	var layer := CanvasLayer.new()
	add_child(layer)
	_field = LineEdit.new()
	layer.add_child(_field)


func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		F_WALK_TYPING:
			_field.grab_focus()
			_mark = _astronaut.global_position
			Input.action_press("move_forward")
		F_WALK_FREE:
			var moved := _flat(_astronaut.global_position - _mark)
			print("walking while typing: %.3f m" % moved)
			_expect(_astronaut.is_typing(), "is_typing() is false with a LineEdit focused")
			_expect(moved < 0.05, "W held into a focused field walked the astronaut %.2f m" % moved)
			_field.release_focus()
			_mark = _astronaut.global_position
		F_WALK_DONE:
			var moved := _flat(_astronaut.global_position - _mark)
			print("walking once the field let go: %.3f m" % moved)
			_expect(moved > 0.3, "the astronaut walked only %.2f m once the field let go" % moved)
			Input.action_release("move_forward")
		F_JUMP_TYPING:
			_field.grab_focus()
			_mark = _astronaut.global_position
			_peak_y = _mark.y
			Input.action_press("jump")
		F_JUMP_DONE:
			print("jump while typing rose %.3f m" % (_peak_y - _mark.y))
			_expect(_peak_y - _mark.y < 0.05,
				"Space into a focused field jumped the astronaut %.2f m" % (_peak_y - _mark.y))
			Input.action_release("jump")
			_field.release_focus()
		F_BOARD:
			_rover.enter(_astronaut)
		F_DRIVE_TYPING:
			_field.grab_focus()
			_mark = _rover.global_position
			Input.action_press("drive_forward")
		F_DRIVE_FREE:
			var moved := _flat(_rover.global_position - _mark)
			print("throttle while typing: %.3f m" % moved)
			_expect(moved < 0.2, "W into a focused field drove the rover %.2f m" % moved)
			_field.release_focus()
			_mark = _rover.global_position
		F_DRIVE_DONE:
			# A second of throttle from rest: 0.87 m on the lunar drivetrain, and
			# nothing at all while typing. The bar is "it moved", not a speed.
			var moved := _flat(_rover.global_position - _mark)
			print("throttle once the field let go: %.3f m" % moved)
			_expect(moved > 0.3, "the rover drove only %.2f m once the field let go" % moved)
			Input.action_release("drive_forward")
			_finish()
	if _frames > F_JUMP_TYPING and _frames < F_JUMP_DONE:
		_peak_y = maxf(_peak_y, _astronaut.global_position.y)


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: a focused text field holds walking, jumping and the throttle, and lets go.")
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
