extends Node3D
## Regression test for the HUD's route bearing - "Stop 1/1  120 m  90° left".
##
## **The bearing has to turn with the view.** It is the one instruction the
## route gives you after the map is closed, and "20 degrees left" only means
## anything relative to where you are looking. It used to read the astronaut's
## ROOT node, which nothing rotates after spawning - looking turns `CamPivot`,
## walking turns `Body` - so the bearing was relative to the level's spawn
## heading, on foot and in the rover alike, while its comment said the camera.
##
## Checked on foot looking three ways, then from the rover facing a fourth.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_route_bearing.tscn

const STOP := Vector3(0.0, 0.0, -120.0)
const F_AHEAD := 10
const F_EAST := 20
const F_WEST := 30
const F_BOARD := 40
const F_DRIVING := 80

var _astronaut: Astronaut
var _rover: Rover
var _hud: Node
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
	# Due south of the stop, like the astronaut, so the answer is exactly a
	# quarter turn - parked 8 m to the east it is a true 94 degrees.
	_rover.position = Vector3(0.0, 1.0, 10.0)
	# Nose to +X, so a stop due -Z is a quarter turn to the left of the driver.
	_rover.rotation.y = -PI / 2.0
	add_child(_rover)

	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)

	Route.clear()
	Route.add(STOP.x, STOP.z)


func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		2:
			_astronaut.aim_at(STOP)
		F_AHEAD:
			_expect_bearing("looking at the stop", "ahead")
			_astronaut.aim_at(Vector3(120.0, 0.0, 0.0))
		F_EAST:
			_expect_bearing("looking east, the stop due north", "90° left")
			_astronaut.aim_at(Vector3(-120.0, 0.0, 0.0))
		F_WEST:
			_expect_bearing("looking west, the stop due north", "90° right")
		F_BOARD:
			_rover.enter(_astronaut)
		F_DRIVING:
			_expect_bearing("driving east, the stop due north", "90° left")
			Route.clear()
			_finish()


func _expect_bearing(situation: String, wanted: String) -> void:
	var text: String = _hud._route_text()
	print("%s: \"%s\"" % [situation, text])
	if not text.ends_with(wanted):
		_failures.append("%s the HUD said \"%s\", expected it to end \"%s\""
			% [situation, text, wanted])


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the route bearing turns with the view, on foot and driving.")
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
