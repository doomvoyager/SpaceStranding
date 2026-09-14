extends Node3D
## Walk the astronaut, then photograph the prints.
##
## The headless test proves the feet land and the map remembers; what a boot
## print looks like in raking light, beside the wheel tracks, is a render.
## The astronaut walks four seconds straight and two sideways, then the
## camera looks at the ground behind it from three places. Sun only, HUD
## hidden, as `regolith_capture` does.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game res://tests/footprint_capture.tscn -- --tag=after

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://footprints"

var _terrain: ProceduralTerrain
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
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var boots := astronaut.find_child("Footprints", true, false) as Footprints
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	for light in _find_lights(world):
		light.visible = light == sun

	var start := astronaut.global_position
	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_press("move_left")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_left")
	for i in 40:
		await get_tree().physics_frame
	var end := astronaut.global_position
	print("walked from %s to %s: %d prints, lowest toe %.3f m" % [
		start.snapped(Vector3.ONE * 0.1), end.snapped(Vector3.ONE * 0.1),
		boots.prints() if boots != null else -1,
		boots.lowest_toe() if boots != null else -1.0])

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	# Frame the prints themselves, off where the feet actually landed, and
	# look down-sun across them: up-sun a print is a dark mark on dark
	# ground, and nobody would see one.
	var recent: Array = boots.recent() if boots != null else []
	var mid := end
	var last := end
	if recent.size() >= 6:
		var m: Vector2 = recent[recent.size() / 2][1]
		var l: Vector2 = recent[recent.size() - 2][1]
		mid = Vector3(m.x, _terrain.world_height_at(m.x, m.y), m.y)
		last = Vector3(l.x, _terrain.world_height_at(l.x, l.y), l.y)
	var along := start - end
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP)
	# The sun travels toward -Z; down-sun is looking that way.
	var down_sun := Vector3(0.0, 0.0, -1.0)
	await _shot("01_along", last + along * -1.5 + Vector3.UP * 1.7, mid)
	await _shot("02_close", last + side * 1.2 + down_sun * -1.4 + Vector3.UP * 1.1, last)
	await _shot("03_from_above", mid + side * 2.0 + Vector3.UP * 7.0, mid)
	await _shot("04_across", mid + side * 6.0 + Vector3.UP * 1.6, mid)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	# The eyes are built off the astronaut's feet, which stand on the ground;
	# only keep them out of a rise between here and there.
	eye.y = maxf(eye.y, _terrain.world_height_at(eye.x, eye.z) + 0.4)
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
