extends Node3D
## Stills of the rock scatter, in the real world scene with the real materials
## and the real post stack.
##
## Headless renders nothing, and the winding test can only prove the triangles
## face outward - not that the result reads as rock. Look at the pictures.
##
## The scatter is added to the instanced world here rather than authored into
## test_world.tscn, so this works whether or not that scene has one yet.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/scatter_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://scatter"

## name, camera position offset from the ground, look-at offset.
const SHOTS := [
	["01_standing", Vector3(0.0, 1.7, 0.0), Vector3(40.0, -6.0, -40.0)],
	["02_boulders", Vector3(24.0, 3.0, 18.0), Vector3(-30.0, -8.0, -26.0)],
	["03_cull_edge", Vector3(0.0, 30.0, 0.0), Vector3(120.0, -30.0, -120.0)],
]

var _terrain: ProceduralTerrain
var _scatter: RockScatter
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)

	# Terrain builds in its own _ready and the mesh lands a frame later.
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = world.find_child("Terrain", true, false) as ProceduralTerrain

	_scatter = world.find_child("RockScatter", true, false) as RockScatter
	if _scatter == null:
		_scatter = RockScatter.new()
		_scatter.name = "RockScatter"
		world.add_child(_scatter)
		_scatter.terrain_path = _scatter.get_path_to(_terrain)
		await _scatter.scattered

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	print("scatter: %d rocks in %d cells" % [
		_scatter.placed(), _scatter.get_node("Cells").get_child_count()
	])

	await _capture_biggest()
	for shot in SHOTS:
		await _capture(shot[0], shot[1], shot[2])

	print("stills in %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)
	return


## Stand next to the largest boulder in the field. The wide shots say whether
## the scatter reads; only this one says whether a rock reads as a rock.
func _capture_biggest() -> void:
	var positions := _scatter.rock_positions()
	var sizes := _scatter.rock_sizes()
	var best := -1
	for i in sizes.size():
		if best < 0 or sizes[i] > sizes[best]:
			best = i
	if best < 0:
		return
	var at: Vector3 = _scatter.global_transform * positions[best]
	var size := sizes[best]
	print("biggest rock: %.2f m across at %s" % [size, at])

	var back := Vector3(size * 2.2, size * 0.9, size * 2.2)
	_cam.global_position = at + back
	_cam.look_at(at, Vector3.UP)
	for i in 12:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/00_close.png" % OUT_DIR)


func _capture(shot_name: String, offset: Vector3, look: Vector3) -> void:
	var ground := _ground_at(offset.x, offset.z)
	var from := Vector3(offset.x, ground + offset.y, offset.z)
	_cam.global_position = from
	_cam.look_at(from + look, Vector3.UP)

	# Volumetric fog and the post stack both need a few frames to settle.
	for i in 12:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, shot_name])


func _ground_at(wx: float, wz: float) -> float:
	var local := _terrain.to_local(Vector3(wx, 0.0, wz))
	return _terrain.to_global(
		Vector3(local.x, _terrain.height_at(local.x, local.z), local.z)
	).y


func _find_cameras(n: Node, out: Array[Camera3D] = []) -> Array[Camera3D]:
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		_find_cameras(c, out)
	return out
