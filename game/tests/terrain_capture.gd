extends Node3D
## Stills of the terrain, at the ranges that actually decide whether the bake
## is any good.
##
## Since 2026-09-14 the ground is a 4.1 km window of NASA's LOLA 5 m/px model
## centred on the south pole - `tools/lola-window.py` - so the frames face the
## rim of Shackleton, which runs through the pole with the wall falling away
## beyond it. The look-dev shots frame the *material* from a couple of metres
## up on the spawn plain, which is deliberately the flattest ground on the map -
## they say nothing about whether the heightfield read correctly. These look at
## the relief at four ranges, because the three ways this pipeline fails all
## show up at a specific distance and nowhere else:
##
##   * a **texel offset** or a bad decimation shows as terracing on the gentle
##     mid-slopes, invisible up close and invisible from far away;
##   * the **macro albedo sampled through UV1** instead of UV2 tiles hundreds of
##     times, which reads as noise at range and as a kaleidoscope up close;
##   * **1 m/texel albedo** is the real cost of the 4096 m footprint, and the
##     only honest place to judge it is standing on the ground.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/terrain_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://terrain"

## Where the pole sits in world space once the terrain offset in test_world.tscn
## is applied: the patch is centred on it, and Shackleton's rim runs through it
## with the wall falling away toward +x, +z.
const POLE := Vector3(-374.4, 0.0, 966.9)
## A point down the inner wall, past the crest, for the frames that look in.
const INTO_THE_CRATER := Vector3(700.0, -900.0, 1900.0)

var _terrain: ProceduralTerrain
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = world.find_child("Terrain", true, false) as ProceduralTerrain

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	# The default 4000 m still clips the far side of a 4096 m patch.
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	# The colour master is retired with the Gaea ground (2026-09-14); the
	# material still points at its bake, which painted Vesper c's pink over
	# the real pole, and under it the authored base colour is Vesper's red.
	# Both off for the run, in memory only: these frames are about relief, and
	# a neutral grey is the honest ground to read it on.
	var material := _terrain.surface_material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("use_macro_albedo", false)
		material.set_shader_parameter("albedo_color", Color(0.42, 0.41, 0.40))

	# Eye heights are metres above the surface at that point.
	await _shot("01_standing", Vector3(0, 1.7, 0), POLE)
	await _shot("02_toward_the_rim", Vector3(0, 1.7, 0), Vector3(600, -50, 900))
	await _shot("03_over_the_crest", Vector3(POLE.x, 150, POLE.z), INTO_THE_CRATER)
	await _shot("04_high_overview", Vector3(POLE.x, 1500, POLE.z), Vector3(200, -1000, 1600))

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	eye.y += _terrain.world_height_at(eye.x, eye.z)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  %s  eye %s" % [name, eye])


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
