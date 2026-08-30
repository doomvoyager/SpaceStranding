extends Node3D
## Look-dev capture harness. Boots the real world scene, plants a camera at a
## few chosen vantage points and writes a PNG of each to user://look_dev/.
##
## Must run as a scene, not --script: everything it loads reaches for World.
## Runs windowed on purpose — --headless uses the dummy renderer and produces
## no image.

const WORLD := preload("res://scenes/world/test_world.tscn")
const HULL_MAT := preload("res://materials/hull_painterly.tres")
const OUT_DIR := "user://look_dev"

## Off isolates the shader's own output from volumetric fog's frame jitter.
@export var volumetric_fog := true

var _terrain: ProceduralTerrain
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)

	# Terrain builds in its own _ready and the mesh lands a frame later.
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = world.find_child("Terrain", true, false) as ProceduralTerrain

	# Any camera baked into the astronaut or rover would otherwise win.
	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	_add_hull_props()

	# Volumetric fog uses temporally-jittered froxels, so a single captured frame
	# shows its noise at full strength where motion would average it away. Toggle
	# it off to tell shader stipple apart from fog jitter.
	if not volumetric_fog:
		var we := world.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.volumetric_fog_enabled = false

	# Star azimuth is 0, so it sits toward +Z. Shots chosen to put the
	# terminator across the frame rather than straight up or down the light.
	await _shot("01_ground_close", Vector3(0, 2.0, 18), Vector3(0, 0.4, 0))
	await _shot("02_raking_across", Vector3(-70, 14, 40), Vector3(30, -6, 40))
	await _shot("03_into_the_star", Vector3(0, 3.5, -60), Vector3(0, 6.0, 200))
	await _shot("04_wide_lod", Vector3(-120, 70, -120), Vector3(20, 0, 40))
	await _shot("05_hull_rim", Vector3(6, 2.2, 12), Vector3(0, 1.6, 0))

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out


## A couple of blocky stand-ins so the hull material is visible before Mac has
## authored real props. Boxes are enough to judge banding and rim.
func _add_hull_props() -> void:
	var sizes := [Vector3(2.2, 3.0, 2.2), Vector3(4.0, 1.2, 1.6), Vector3(1.0, 5.0, 1.0)]
	var spots := [Vector3(0, 0, 0), Vector3(-4.5, 0, 2.0), Vector3(4.0, 0, -1.5)]
	for i in sizes.size():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sizes[i]
		mi.mesh = bm
		mi.material_override = HULL_MAT
		var p: Vector3 = spots[i]
		p.y = _ground(p.x, p.z) + sizes[i].y * 0.5
		mi.position = p
		add_child(mi)


func _ground(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain != null else 0.0


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	# Offsets are given relative to the ground so the framing survives a reseed.
	eye.y += _ground(eye.x, eye.z)
	look.y += _ground(look.x, look.z)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	# Let shadow atlas, fog and the frame settle before grabbing it.
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
