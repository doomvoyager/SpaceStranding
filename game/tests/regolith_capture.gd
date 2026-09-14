extends Node3D
## Stills of the ground as a material: the regolith under the real sun, from
## the directions that decide whether it reads as the Moon.
##
## The terrain capture neutralises the material in memory to look at relief;
## this one shoots the scene exactly as it ships, because it is the look that
## is on trial. The frames are chosen around the sun, which sits on the +Z
## horizon at 5.5 degrees:
##
##   * **down-sun** - the sun behind the camera. On the real Moon this is the
##     washed-out, shadowless view (the opposition surge);
##   * **up-sun** - into the light. Dark ground, every rise a silhouette;
##   * **cross-sun** - the raking view that shows relief and texture;
##   * **the feet** - the material at arm's length, where 5 m data is a sheet;
##   * **the rim** and **from height** - the far ground, which under a grazing
##     sun is where a Lambert surface goes black and the real one does not;
##   * **the sky** - the sun's disc and whatever the sky shows behind it.
##
## Each frame prints its mean luma, so a sweep leaves numbers beside the
## pictures. `-- --tag=name` prefixes the files, so before and after can sit in
## the same folder.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/regolith_capture.tscn -- --tag=before

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://regolith"
## Shackleton's rim from the spawn, as terrain_capture frames it.
const RIM := Vector3(600.0, -50.0, 900.0)
const POLE := Vector3(-374.4, 0.0, 966.9)

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

	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	# `-- --nopost` hides the film stack, to tell shading from post.
	if "--nopost" in OS.get_cmdline_user_args():
		var post := world.find_child("PostprocessingEffects", true, false) as CanvasLayer
		if post != null:
			post.visible = false
	# Sun only. The spawn sits inside the Hearth's orange mast light (34 m)
	# and the relay's cyan beacon (22 m), and the head lamp is brighter than
	# the sun on whatever it points at: the first frames came out salmon with
	# a cyan band under the horizon, and none of it was the material.
	# `-- --lights` keeps them all, to see what the settlement does to the
	# ground; `-- --lamp` keeps just the head lamp.
	var args := OS.get_cmdline_user_args()
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	for light in _find_lights(world):
		if light == sun:
			continue
		var is_lamp := light.name == "HeadLamp"
		light.visible = "--lights" in args or (is_lamp and "--lamp" in args)
	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	# The direction light travels, on the ground plane. Down-sun looks along
	# it; up-sun looks against it.
	var along := -sun.global_basis.z if sun != null else World.sun_direction()
	along.y = 0.0
	along = along.normalized()
	var across := along.cross(Vector3.UP)
	print("light travels along %s" % along.snapped(Vector3.ONE * 0.01))

	var eye := Vector3(0.0, 1.7, -4.0)
	await _shot("01_down_sun", eye, eye + along * 40.0 + Vector3.DOWN * 5.0)
	await _shot("02_up_sun", eye, eye - along * 40.0 + Vector3.DOWN * 5.0)
	await _shot("03_cross_sun", eye, eye + across * 40.0 + Vector3.DOWN * 5.0)
	await _shot("04_feet", eye, eye + across * 3.0 + Vector3.DOWN * 4.0)
	await _shot("05_rim", eye, RIM)
	await _shot("06_high", Vector3(POLE.x, 150.0, POLE.z),
		Vector3(700.0, -900.0, 1900.0))
	await _shot("07_sky", eye, eye - along * 40.0 + Vector3.UP * 6.0)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	eye.y += _terrain.world_height_at(eye.x, eye.z)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s%s.png" % [OUT_DIR, _tag, name])
	print("  %s%s  luma %.3f  eye %s" % [_tag, name, _mean_luma(img),
		eye.snapped(Vector3.ONE * 0.1)])


## Mean luma of the frame, 0..1, sampled on an 8-pixel stride.
func _mean_luma(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return total / maxf(n, 1.0)


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
