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

	# The outer edge, from high enough that the whole reach is in frame. A low
	# vantage cannot show it at all, which is why the first pass at this feature
	# shipped with a hard circular cut nobody had looked at.
	scanner.max_tags = 0
	_cam.position = here + Vector3(0.0, 62.0, 46.0)
	_cam.look_at(here, Vector3.UP)
	for width: float in [0.0, 12.0, 22.0, 40.0]:
		scanner.edge_fade = width
		scanner.ping()
		for i in 40:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/edge_%02.0f.png" % [OUT_DIR, width])
	print("edge fades captured at 0, 12, 22 and 40 m of a %.0f m reach" % scanner.reach)

	# The obstacle outline, framed on the biggest rock the scatter placed. A
	# vantage picked by hand would as likely as not be looking at gravel, which
	# is exactly what does NOT get an outline.
	var scatter := world.find_child("RockScatter", true, false) as RockScatter
	var positions := scatter.rock_positions()
	var sizes := scatter.rock_sizes()
	var best := -1
	for i in sizes.size():
		if best < 0 or sizes[i] > sizes[best]:
			best = i
	if best >= 0:
		var rock: Vector3 = scatter.to_global(positions[best])
		print("biggest rock %.2f m at %s, collision above %.2f"
			% [sizes[best], rock, scatter.collision_above])
		scanner.edge_fade = 22.0
		scanner.max_tags = 0
		# The pulse comes from the player, so setting _origin by hand achieves
		# nothing - ping() overwrites it. Move the astronaut to the rock, which
		# is also what a player standing here would be doing.
		scanner.cooldown = 0.0
		# Off to the side, not between the camera and the rock. Still well
		# inside reach, so the pulse covers the shot either way.
		astronaut.global_position = rock + Vector3(16.0, 1.2, 2.0)
		for strength: float in [0.0, 1.6, 3.5]:
			scanner.outline_strength = strength
			_cam.position = rock + Vector3(6.0, 2.6, 7.5)
			_cam.look_at(rock, Vector3.UP)
			scanner.ping()
			for i in 40:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/outline_%.1f.png" % [OUT_DIR, strength])
		scanner.outline_strength = 1.6

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
