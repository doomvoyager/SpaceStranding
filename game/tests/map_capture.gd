extends Node3D
## Stills of the map panel. See [[The-Map]].
##
## The map is a SubViewport with its own World3D and its own shader, and none of
## that exists under `--headless`: the dummy renderer builds no shader and the
## viewport draws nothing. `test_map_route` can pass in full with the panel
## rendering a blank rectangle, which is the failure this project keeps meeting.
##
## Four shots: the framed patch, a close orbit over the settlements, the same
## with a route planned across the massif, and one with the relief exaggeration
## dropped to 1.0 — because "is the exaggeration doing anything" is a question
## only a pair answers.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/map_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://map"
## Roughly the massif peak once test_world's terrain offset is applied.
const PEAK := Vector2(-470.0, 1270.0)

var _panel: MapPanel
var _map: MapTerrain


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	add_child(WORLD.instantiate())
	for i in 10:
		await get_tree().process_frame
	_panel = get_tree().get_first_node_in_group("map_panel") as MapPanel
	_map = get_tree().get_first_node_in_group("map_terrain") as MapTerrain
	if _panel == null or _map == null:
		printerr("CAPTURE: no map panel in the world scene")
		get_tree().quit(1)
		return

	var waited := 0
	while (_map.mesh == null or _map.span() <= 0.0) and waited < 240:
		waited += 1
		await get_tree().process_frame
	if _map.mesh == null:
		printerr("CAPTURE: the map relief mesh never built")
		get_tree().quit(1)
		return
	var range := _map.elevation_range()
	print("relief built: %.0f m across, %d vertices, ground from %.1f to %.1f m"
		% [_map.span(),
			(_map.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			range.x, range.y])

	Route.clear()
	_panel.open()
	await _shot("01_whole_patch")

	# Framed on the patch's own centre, not on the world origin. The terrain node
	# carries a 1.3 km offset, so (0,0) is near its edge and a camera there
	# spends most of the frame looking at empty space — which is exactly what
	# the first version of this capture did, and it read as a black map.
	var centre := _map.centre()
	_panel.frame_on(Vector2(centre.x, centre.z), 900.0)
	await _shot("02_settlements")

	# A route worth looking at: out of the settlements and up the massif.
	Route.add(-120.0, 320.0)
	Route.add(-300.0, 780.0)
	Route.add(PEAK.x, PEAK.y)
	_panel.frame_on(Vector2(-300.0, 780.0), 1200.0)
	await _shot("03_route_to_the_massif")

	# Tight on the Hearth. Coverage is a 45 m affair on a 2 km patch, so it is
	# invisible at every other framing here — and "the map draws the same
	# boundary the ground does" is the claim most worth a picture.
	Route.clear()
	_panel.frame_on(Vector2(8.0, -15.9), 200.0)
	await _shot("05_coverage_boundary")

	var was := _map.relief_exaggeration
	_map.relief_exaggeration = 1.0
	var settle := 0
	while settle < 30:
		settle += 1
		await get_tree().process_frame
	await _shot("04_no_exaggeration")
	_map.relief_exaggeration = was

	Route.clear()
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(shot_name: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("  %s" % shot_name)
