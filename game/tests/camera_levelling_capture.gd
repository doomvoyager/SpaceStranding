extends Node3D
## Stills through the rover's own camera with the chassis posed at increasing
## roll, so the horizon can be looked at rather than asserted about.
##
## The test proves the number. Whether an 18 degree ceiling reads as "leaning
## with the rover" or as "the camera is stuck" is a judgement, and this is what
## it is judged from.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/camera_levelling_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://camera_levelling"

## name, roll in degrees, pitch in degrees.
const POSES := [
	["00_level", 0.0, 0.0],
	["01_roll_15", 15.0, 0.0],
	["02_roll_45", 45.0, 0.0],
	["03_roll_90", 90.0, 0.0],
	["04_upside_down", 180.0, 0.0],
	["05_nose_down_40", 0.0, -40.0],
]

var _rover: Rover
var _astronaut: Astronaut


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	_rover = world.find_child("Rover", true, false) as Rover
	_astronaut = world.find_child("Astronaut", true, false) as Astronaut

	# Frozen so the pose sticks; a live rigid body rights itself immediately.
	_rover.freeze = true
	_rover.tilt_smoothing = 0.0
	_rover.enter(_astronaut)

	# Lift it clear of the ground so a rolled chassis is not buried in a dune.
	var lifted := _rover.global_position
	lifted.y += 3.0
	_rover.global_position = lifted

	for pose in POSES:
		await _capture(pose[0], pose[1], pose[2])

	print("stills in %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)
	return


func _capture(shot_name: String, roll: float, pitch: float) -> void:
	var xform := _rover.global_transform
	xform.basis = Basis.from_euler(
		Vector3(deg_to_rad(pitch), 0.0, deg_to_rad(roll))
	)
	_rover.global_transform = xform

	for i in 10:
		await RenderingServer.frame_post_draw
	var tilt := rad_to_deg(
		_rover.get_node("CamPivot").global_basis.y.angle_to(Vector3.UP)
	)
	print("%-16s chassis roll %6.1f pitch %6.1f -> camera tilt %5.1f"
		% [shot_name, roll, pitch, tilt])
	get_viewport().get_texture().get_image().save_png(
		"%s/%s.png" % [OUT_DIR, shot_name]
	)
