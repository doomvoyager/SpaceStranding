extends Node3D
## Stills of the authored terrain, at the ranges that actually decide whether
## the bake is any good.
##
## The look-dev shots frame the *material* from a couple of metres up on the
## spawn plain, which is deliberately the flattest ground on the map - they say
## nothing about whether the heightfield read correctly. These face the massif
## instead, at four ranges, because the three ways this pipeline fails all show
## up at a specific distance and nowhere else:
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

## Roughly where the massif peak sits in world space once the terrain offset in
## test_world.tscn is applied. Everything below looks at it.
const PEAK := Vector3(-470.0, 210.0, 1270.0)

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

	# Eye heights are metres above the surface at that point.
	await _shot("01_standing", Vector3(0, 1.7, 0), PEAK)
	await _shot("02_from_the_plain", Vector3(-200, 12, 500), PEAK)
	await _shot("03_massif_flank", Vector3(-470, 60, 600), PEAK)
	await _shot("04_high_overview", Vector3(-470, 900, -400), PEAK)

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
