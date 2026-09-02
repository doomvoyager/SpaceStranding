extends Node3D
## Stills of the route in the world: the light pillar and the scan reveal.
## See [[The-Map]].
##
## `test_route_marks` proves the beam is in the right place and that arrival
## clears the right stops. It proves nothing about whether any of it is *drawn*:
## the beam is an additive billboard with its own shader, and `--headless` is
## the dummy renderer, so every assertion there can pass with nothing on screen.
##
## Four shots: the beam at range, the beam close to, the route revealed by a
## pulse with the pointer at your feet, and the same framing after the pulse has
## gone — because "it fades" and "it never drew" look identical in one picture.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/route_marks_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://route"

var _terrain: ProceduralTerrain
var _astronaut: Astronaut
var _marks: RouteMarks
var _scanner: Node
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 12:
		await get_tree().process_frame
	_terrain = Lattice.terrain()
	_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_marks = get_tree().get_first_node_in_group("route_marks") as RouteMarks
	_scanner = get_tree().get_first_node_in_group("scanner")
	if _terrain == null or _astronaut == null or _marks == null or _scanner == null:
		printerr("CAPTURE: the world is missing a piece")
		get_tree().quit(1)
		return

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	# Stand on the playa and put a stop out on the flat, then one further on, so
	# the beam has open ground between it and the camera.
	Route.clear()
	_stand(0.0, 0.0)
	Route.add(160.0, 90.0)
	Route.add(320.0, -60.0)
	await _settle()
	print("beam visible: %s at %s" % [_marks.beacon_visible(), _marks.beacon_foot()])

	await _shot("01_beam_at_range", Vector3(-40.0, 14.0, -50.0),
		Vector3(160.0, 40.0, 90.0))
	await _shot("02_beam_from_the_side", Vector3(90.0, 6.0, 30.0),
		Vector3(160.0, 30.0, 90.0))

	_scanner.call("ping")
	await _settle()
	await _shot("03_scan_reveal", Vector3(-30.0, 22.0, -40.0),
		Vector3(120.0, 0.0, 40.0))

	# Let the pulse die, then shoot the same framing. A reveal that never drew
	# and a reveal that has faded look the same in a single picture.
	var waited := 0
	while _marks.reveal_visible() and waited < 900:
		waited += 1
		await get_tree().process_frame
	await _shot("04_after_the_pulse", Vector3(-30.0, 22.0, -40.0),
		Vector3(120.0, 0.0, 40.0))

	Route.clear()
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _stand(x: float, z: float) -> void:
	_astronaut.global_position = Vector3(x, _terrain.world_height_at(x, z) + 1.0, z)


func _settle() -> void:
	for i in 20:
		await get_tree().process_frame


func _shot(shot_name: String, eye: Vector3, look: Vector3) -> void:
	eye.y += _terrain.world_height_at(eye.x, eye.z)
	look.y += _terrain.world_height_at(look.x, look.z)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("  %s" % shot_name)


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
