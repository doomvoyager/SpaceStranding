extends Node3D
## What the real RockScatter costs on the real terrain, and how the two knobs
## that drive draw calls trade against each other.
##
## `probe_scatter_cull.gd` proved the mechanism on synthetic multimeshes: cells
## are what make distance culling possible, and 32 m is the knee. This one runs
## the actual scatter, where a second multiplier appears that the synthetic test
## did not have - **a MultiMesh holds exactly one mesh, so every rock variant is
## its own instance in every cell.** Six variants at two detail tiers is up to
## twelve multimeshes per cell, and the draw calls multiply accordingly.
##
## Camera at eye height in the middle of the patch, looking along the ground:
## the view you have while driving.
##
## Must run windowed - --headless is the dummy renderer and counts nothing.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_scatter_cost.tscn

const WARMUP := 30
const TIMED := 120
## Variant counts to sweep at the default cell size.
const VARIANTS := [2, 4, 6, 8]
## Cell sizes to sweep at the default variant count.
const CELLS := [32.0, 48.0, 64.0]
## How far you can see rocks. Cost grows with the area, so roughly as the
## square - this is the row to read before pushing the draw distance out.
const RANGES := [120.0, 170.0, 250.0, 350.0]

var _terrain: ProceduralTerrain
var _scatter: RockScatter
var _camera: Camera3D


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30.0, 20.0, 0.0)
	add_child(light)

	_terrain = ProceduralTerrain.new()
	_terrain.name = "Terrain"
	_terrain.size = 512.0
	_terrain.resolution = 2.0
	_terrain.scale = Vector3(1.0, 0.5, 1.0)
	add_child(_terrain)

	_scatter = RockScatter.new()
	_scatter.name = "Scatter"
	add_child(_scatter)

	_camera = Camera3D.new()
	_camera.far = 2000.0
	add_child(_camera)

	_run()


func _run() -> void:
	await get_tree().process_frame
	# Eye height above whatever the generator produced under the origin.
	var local := _terrain.to_local(Vector3.ZERO)
	var ground := _terrain.to_global(
		Vector3(0.0, _terrain.height_at(local.x, local.z), 0.0)
	).y
	_camera.position = Vector3(0.0, ground + 1.7, 0.0)

	print("\n--- rock scatter on the 512 m patch, camera at eye height ---")
	print("%-38s %7s %7s %9s %7s %8s" % [
		"case", "rocks", "cells", "prims", "draws", "ms"
	])

	_scatter.visible = false
	var base := await _measure("terrain only, scatter hidden", {})
	_scatter.visible = true

	for v in VARIANTS:
		_scatter.variants = v
		await _scatter.scattered
		await _measure("%d variants, %.0f m cells" % [v, _scatter.cell_size], base)

	_scatter.variants = 6
	await _scatter.scattered
	for c in CELLS:
		_scatter.cell_size = c
		await _scatter.scattered
		await _measure("6 variants, %.0f m cells" % c, base)

	_scatter.cell_size = 48.0
	await _scatter.scattered
	for r in RANGES:
		_scatter.cull_distance = r
		await _measure("48 m cells, %.0f m draw distance" % r, base)

	# Worst case: the culling switched off entirely, for scale.
	_scatter.cull_distance = 1000.0
	_scatter.near_distance = 999.0
	await _measure("48 m cells, culling off", base)

	print("\n(prims and draws are deltas against terrain-only; ms is absolute)")
	get_tree().quit(0)
	return


func _measure(label: String, base: Dictionary) -> Dictionary:
	for i in WARMUP:
		await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	for i in TIMED:
		await RenderingServer.frame_post_draw
	var elapsed := Time.get_ticks_usec() - started

	var out := {
		"prims": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"draws": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"ms": float(elapsed) / 1000.0 / TIMED,
	}
	var d := func(k: String) -> int:
		return int(out[k]) - (int(base[k]) if base.has(k) else 0)
	var cells := _scatter.get_node_or_null("Cells")
	print("%-38s %7d %7d %9d %7d %8.3f" % [
		label,
		_scatter.placed(),
		cells.get_child_count() if cells != null else 0,
		d.call("prims"), d.call("draws"), out["ms"],
	])
	return out
