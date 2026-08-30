extends Node3D
## Look-dev capture for the delivery pad and the condition readout. Boots the
## real world scene, drops a pad in beside the beacon, and writes PNGs to
## user://delivery_look/.
##
## The pad is added here at runtime rather than being placed in test_world.tscn,
## which is Mac's scene. Nothing in this script touches a scene file.
##
## What a headless test cannot judge: whether the pad reads at the right scale
## next to the rover, whether a crate sitting on it looks *delivered* rather
## than dumped, and whether the HUD receipt is legible over the terrain.
##
## Must run as a scene, not --script. Runs windowed on purpose: --headless uses
## the dummy renderer and produces no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/delivery_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const PAD := preload("res://scenes/cargo/delivery_pad.tscn")
const OUT_DIR := "user://delivery_look"

var _cam: Camera3D
var _rover: Rover
var _astronaut: Astronaut
var _pad: DeliveryPad


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)

	for i in 90:
		await get_tree().physics_frame

	_astronaut = world.find_child("Astronaut", true, false) as Astronaut
	_rover = world.find_child("Rover", true, false) as Rover
	var terrain := world.find_child("Terrain", true, false) as ProceduralTerrain
	var crates := world.find_child("Crates", true, false)

	# Beside the rover, so the two are in frame together for scale.
	var at := _rover.global_position + Vector3(7.0, 0.0, 0.0)
	_pad = PAD.instantiate()
	world.add_child(_pad)
	_pad.global_position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	var p := _pad.global_position
	await _shot("01_pad_empty", p + Vector3(-5.0, 3.4, 7.0), p + Vector3(0.0, 0.4, 0.0))

	# One pristine and one wrecked, side by side, so the receipt and the HUD
	# grading can be read against crates that visibly differ in nothing but
	# their condition — which is itself worth seeing. Right now they do not
	# differ visually at all, and that is the open question in [[Cargo]].
	var loose: Array[Crate] = []
	for child in crates.get_children():
		var crate := child as Crate
		if crate != null:
			loose.append(crate)

	if loose.size() >= 2:
		var good := loose[0]
		var bad := loose[1]
		bad.cargo_name = "Sample case"
		bad.condition = 0.28
		var t := Transform3D.IDENTITY
		t.origin = p + Vector3(-0.9, 0.31, 0.0)
		good.release(_pad.get_parent(), t)
		t.origin = p + Vector3(0.9, 0.31, 0.0)
		bad.release(_pad.get_parent(), t)

	for i in 30:
		await get_tree().physics_frame

	await _shot("02_pad_delivered", p + Vector3(-4.4, 2.6, 5.6), p + Vector3(0.0, 0.5, 0.0))
	await _shot("03_pad_close", p + Vector3(0.4, 1.9, 4.4), p + Vector3(0.0, 0.5, 0.2))

	# The astronaut standing at the pad, which is the frame the player sees.
	_astronaut.global_position = p + Vector3(0.0, 1.2, 3.4)
	_astronaut.velocity = Vector3.ZERO
	for i in 20:
		await get_tree().physics_frame
	var a := _astronaut.global_position
	await _shot("04_hud_receipt", a + Vector3(0.6, 2.1, 5.0), a + Vector3(0.0, 1.0, -1.2))

	print("pad: %d delivered, %.0f cr total" % [_pad.delivered_count, _pad.total_paid])
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out


func _shot(shot_name: String, eye: Vector3, look: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 6:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
