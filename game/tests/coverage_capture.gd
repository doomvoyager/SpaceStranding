extends Node3D
## Stills of the Lattice coverage boundary on the ground. See [[The-Lattice]].
##
## This exists because the mask is the only half of the feature a headless test
## can reach. `test_coverage_map` proves the numbers are right — that coverage
## follows sight lines and not a radius — and proves nothing whatever about
## whether the shader compiles, because `--headless` is the dummy renderer and
## never builds one. A boundary that is arithmetically perfect and invisible is
## this project's most repeated failure.
##
## Shot from three heights over the Hearth, because the two ways this looks
## wrong show up at different ranges: the **edge band** is tuned in mask units,
## so it is a different apparent width close up than from altitude; and the
## **fill** is the term most likely to fight the macro albedo, which only
## reads at ground level where the albedo is legible.
##
## The last shot turns coverage off from the same camera, so the pair can be
## compared rather than judged from memory.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/coverage_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://coverage"

## Where the Hearth stands once test_world's terrain offset is applied. The
## boundary is a 45 m affair, so every shot is framed on it rather than on the
## map.
const HEARTH := Vector3(8.0, 0.0, -15.9)

var _terrain: ProceduralTerrain
var _map: CoverageMap
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 8:
		await get_tree().process_frame
	_terrain = world.find_child("Terrain", true, false) as ProceduralTerrain
	_map = world.find_child("CoverageMap", true, false) as CoverageMap
	if _terrain == null or _map == null:
		printerr("CAPTURE: no terrain or no coverage map in the world scene")
		get_tree().quit(1)
		return

	# The mask is built deferred off the graph rebuild, so wait for the real
	# thing rather than assuming a frame count was enough.
	var waited := 0
	while _map.mask_texture() == null and waited < 240:
		waited += 1
		await get_tree().process_frame
	if _map.mask_texture() == null:
		printerr("CAPTURE: the coverage mask never built")
		get_tree().quit(1)
		return
	print("mask built: %d texels across, coverage under the Hearth %.2f"
		% [_map.mask_texture().get_width(),
			_map.coverage_at(HEARTH.x, HEARTH.z)])

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	var look := Vector3(HEARTH.x, _terrain.world_height_at(HEARTH.x, HEARTH.z),
		HEARTH.z)
	await _shot("01_standing", Vector3(HEARTH.x + 30.0, 1.7, HEARTH.z + 30.0), look)
	await _shot("02_low_pass", Vector3(HEARTH.x + 55.0, 22.0, HEARTH.z + 55.0), look)
	await _shot("03_overhead", Vector3(HEARTH.x + 10.0, 150.0, HEARTH.z + 60.0), look)
	# The same two framings with the overlay off. The pair is the only honest
	# way to tell a coverage artefact from one the terrain already had — the
	# near-ground rectangles noted on 2026-09-01 being exactly that question.
	_map.intensity = 0.0
	await _shot("04_overhead_coverage_off",
		Vector3(HEARTH.x + 10.0, 150.0, HEARTH.z + 60.0), look)
	await _shot("05_standing_coverage_off",
		Vector3(HEARTH.x + 30.0, 1.7, HEARTH.z + 30.0), look)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(shot_name: String, eye: Vector3, look: Vector3) -> void:
	eye.y += _terrain.world_height_at(eye.x, eye.z)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("  %s  eye %s" % [shot_name, eye])


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
