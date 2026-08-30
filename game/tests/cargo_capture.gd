extends Node3D
## Look-dev capture for the cargo visuals. Boots the real world scene, loads the
## racks, and writes a PNG of each vantage point to user://cargo_look/.
##
## Slot placement is the one part of the cargo system a headless test cannot
## judge - test_cargo_flow.gd proves a crate is exactly on its slot, not that
## the slot is anywhere sensible. Re-run this after moving any slot marker.
##
## Must run as a scene, not --script. Runs windowed on purpose: --headless uses
## the dummy renderer and produces no image.
##   engine/Godot.app/Contents/MacOS/Godot --path game res://tests/cargo_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://cargo_look"

var _cam: Camera3D
var _astronaut: Astronaut
var _rover: Rover


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)

	# Let terrain build, then let the rover and crates settle onto it.
	for i in 90:
		await get_tree().physics_frame

	_astronaut = world.find_child("Astronaut", true, false) as Astronaut
	_rover = world.find_child("Rover", true, false) as Rover
	var crates := world.find_child("Crates", true, false)

	var loose: Array[Crate] = []
	for child in crates.get_children():
		var crate := child as Crate
		if crate != null:
			loose.append(crate)

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	# All six on the roof first: the 2x3 grid has to fit without intersecting.
	for crate in loose:
		_rover.cargo_rack().load_crate(crate)
	_rover.refresh_load()
	print("full rack: mass %.0f kg, CoM %s" % [_rover.mass, _rover.center_of_mass])

	var r := _rover.global_position
	await _shot("01_rack_full", r + Vector3(4.2, 2.4, 5.2), r + Vector3(0, 0.9, 1.0))
	await _shot("02_rack_full_high", r + Vector3(-0.6, 5.2, 6.0), r + Vector3(0, 0.6, 1.1))

	# Two onto the astronaut's back, so both of those slots are visible too.
	for i in 2:
		_astronaut.back_rack().load_crate(_rover.cargo_rack().last_loaded_crate())
	_rover.refresh_load()
	for i in 10:
		await get_tree().physics_frame

	var a := _astronaut.global_position
	await _shot("03_back_full", a + Vector3(2.4, 2.0, 4.4), a + Vector3(0, 1.2, 0.7))
	await _shot("04_back_side", a + Vector3(4.0, 1.6, 1.2), a + Vector3(0, 1.1, 0.4))

	# Put one down beside the astronaut so the HUD has prompts to show.
	_astronaut._move_cargo()
	for i in 30:
		await get_tree().physics_frame
	a = _astronaut.global_position
	await _shot("05_hud", a + Vector3(0.5, 2.0, 4.8), a + Vector3(0, 1.1, -0.4))

	print("final: rover %d/6, back %d/2, mass %.0f kg, CoM %s" % [
		_rover.cargo_rack().count(),
		_astronaut.back_rack().count(),
		_rover.mass,
		_rover.center_of_mass,
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
