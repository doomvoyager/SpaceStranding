extends Node3D
## Drive the rover, then photograph what it left behind.
##
## The headless test holds the map's arithmetic; the picture - the rut, the
## chevrons, the darkening down-sun - is only visible in a render, and only
## behind a rover that has actually driven, since the wheels do the stamping.
## So: the astronaut boards, the rover drives cross-sun for four seconds, then
## turns for three, then stops, and the camera looks at the ground behind it
## from four places. Sun only, HUD hidden, as `regolith_capture` does.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game res://tests/track_capture.tscn -- --tag=after

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://tracks"

var _terrain: ProceduralTerrain
var _rover: Rover
var _cam: Camera3D
var _tag := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=") + "-"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 60:
		await get_tree().physics_frame
	_terrain = world.find_child("Terrain", true, false) as ProceduralTerrain
	_rover = world.find_child("Rover", true, false) as Rover
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	for light in _find_lights(world):
		light.visible = light == sun
	var map := world.find_child("TrackMap", true, false) as TrackMap

	_rover.enter(astronaut)
	for i in 30:
		await get_tree().physics_frame

	# Cross-sun first, so the raking light lands across the rut, then a turn
	# so the chevrons swing and a wheel or two scrub.
	Input.action_press("drive_forward")
	for i in 240:
		await get_tree().physics_frame
	Input.action_press("move_left")
	for i in 180:
		await get_tree().physics_frame
	Input.action_release("move_left")
	Input.action_release("drive_forward")
	Input.action_press("drive_back")
	for i in 40:
		await get_tree().physics_frame
	Input.action_release("drive_back")
	for i in 60:
		await get_tree().physics_frame
	print("rover at %s, %d stamps drawn, %.1f m/s" % [
		_rover.global_position.snapped(Vector3.ONE * 0.1),
		map.stamps_drawn() if map != null else -1, _rover.forward_speed()])

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	var r := _rover.global_position
	# The chassis faces -Z, so +Z is behind it.
	var back := _rover.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var right := back.cross(Vector3.UP)

	await _shot("01_behind", r + back * 1.5 + Vector3.UP * 2.6, r + back * 16.0)
	await _shot("02_over_the_track", r + back * 6.0 + Vector3.UP * 1.7, r + back * 8.5 + Vector3.DOWN * 0.2)
	await _shot("03_from_above", r + back * 10.0 + Vector3.UP * 14.0, r + back * 10.5)
	await _shot("04_side", r + back * 9.0 + right * 8.0 + Vector3.UP * 1.8, r + back * 9.0)
	await _shot("05_the_turn", r + back * 25.0 + Vector3.UP * 3.0, r + back * 8.0)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	# Eyes are metres above wherever the ground is under them.
	eye.y = _terrain.world_height_at(eye.x, eye.z) + (eye.y - _rover.global_position.y)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s%s.png" % [OUT_DIR, _tag, name])
	print("  %s%s  eye %s" % [_tag, name, eye.snapped(Vector3.ONE * 0.1)])


func _find_lights(from: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	if from is Light3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_lights(child))
	return out


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
