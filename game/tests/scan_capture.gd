extends Node3D
## Look-dev capture for the scan pulse. Writes PNGs to user://scan_look/.
##
## The whole feature is a picture, so almost nothing about it can be judged
## headlessly. What this is for:
##
##   - does the dot grid read as *ground information* or as a texture bug
##   - is the green/red split legible against ferociously red terrain, which is
##     the hostile case for exactly this palette
##   - does the wave front read as a pulse going out, or as a radius resizing
##   - are the tags readable without burying the world behind them
##
## Runs windowed on purpose: --headless is the dummy renderer and writes no
## image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/scan_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://scan_look"

var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	var hud := world.find_child("HUD", true, false)
	hud._controls_card.visible = false
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var scanner := world.find_child("Scanner", true, false) as Scanner

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	# A vantage looking down a slope, so flat ground and steep ground are both
	# in frame and the colour split has something to say.
	var here := astronaut.global_position
	_cam.position = here + Vector3(6.0, 9.0, 16.0)
	_cam.look_at(here + Vector3(-6.0, 0.0, -18.0), Vector3.UP)

	await _shot("00_before", 0)

	# Ping from where the camera is, which is what the scanner does in play.
	scanner.ping()
	# Frames chosen to catch the wave crossing the frame, then settled.
	for stop in [4, 10, 18, 40]:
		await _shot("%02d_wave" % stop, stop)

	print("radius %.1f m, %d tags" % [scanner.radius(), scanner.tag_count()])
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Let `frames` render, then save. The pulse runs on _process, so real frames
## have to pass rather than physics steps.
func _shot(shot_name: String, frames: int) -> void:
	for i in maxi(frames, 1):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out
