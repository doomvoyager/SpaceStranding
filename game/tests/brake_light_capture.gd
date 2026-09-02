extends Node3D
## Look-dev capture for the rover's brake light. Boots the real world scene and
## writes an off/on pair from behind the rover to user://brake_look/.
##
## The one thing a headless test cannot judge. `test_brake_light.tscn` proves
## the emission energy tracks the pedals; it says nothing about whether the bar
## reads as a brake light or as a pink smear. Re-run after touching the material
## or the energies.
##
## Must run as a scene, not --script. Runs windowed on purpose: --headless uses
## the dummy renderer and produces no image.
##   engine/Godot.app/Contents/MacOS/Godot --path game res://tests/brake_light_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://brake_look"

var _cam: Camera3D
var _rover: Rover


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)

	for i in 90:
		await get_tree().physics_frame

	_rover = world.find_child("Rover", true, false) as Rover

	for c in _find_cameras(world):
		c.current = false
	# The controls card sits over the left half of the frame and the bar is
	# what these shots are of.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		(hud as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	# The bar is on the rover's +Z end, which is the back.
	var r := _rover.global_position
	var back := _rover.global_transform.basis.z

	_rover._set_brake_light(false)
	await _shot("01_off", r + back * 6.5 + Vector3(0.0, 1.6, 0.0), r + Vector3(0, 0.3, 0))
	await _shot("02_off_close", r + back * 4.0 + Vector3(1.6, 1.1, 0.0), r + Vector3(0, 0.25, 0))

	_rover._set_brake_light(true)
	await _shot("03_on", r + back * 6.5 + Vector3(0.0, 1.6, 0.0), r + Vector3(0, 0.3, 0))
	await _shot("04_on_close", r + back * 4.0 + Vector3(1.6, 1.1, 0.0), r + Vector3(0, 0.25, 0))

	print("brake light: off %.2f / on %.2f" % [
		_rover.brake_light_idle_energy, _rover.brake_light_energy
	])
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 6:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
