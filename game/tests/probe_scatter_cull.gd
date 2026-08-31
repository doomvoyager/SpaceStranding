extends Node3D
## Does distance culling actually reach a MultiMeshInstance3D, and what does
## splitting a scatter into cells buy?
##
## The whole rock-scatter design rests on two claims about the renderer, so
## measure them before building on them:
##
##   1. `visibility_range_end` is a GeometryInstance3D property and
##      MultiMeshInstance3D inherits it - but a MultiMesh is *one* instance
##      holding thousands of transforms, so it is not obvious the range applies
##      to anything useful.
##   2. One MultiMesh covering the whole patch has one patch-sized AABB, so it
##      can never be frustum-culled however little of it is on screen.
##      Splitting the same instances into a lattice of cells should let the
##      frustum throw most of them away.
##
## Cell size is the tunable that matters and it cuts both ways: smaller cells
## cull harder but cost one draw call each. This sweeps four lattices to find
## where that crosses over.
##
## Camera sits at player eye height in the middle of the field, so every case
## is the view you actually have while driving.
##
## Must run windowed - --headless is the dummy renderer and counts nothing.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_scatter_cull.tscn

## Matches the terrain patch in test_world.
const FIELD := 512.0
const ROCKS := 8192
## Lattices to compare: 4x4 is 128 m cells, 32x32 is 16 m.
const GRIDS := [4, 8, 16, 32]
const CULL_AT := 120.0
const WARMUP := 30
const TIMED := 120

var _camera: Camera3D
var _mesh: Mesh
var _material: StandardMaterial3D


func _ready() -> void:
	# Vsync pins every case to the refresh rate and the ms column becomes a
	# measurement of the monitor. Off, so the numbers are the renderer's.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# A plausible low-poly rock rather than a box: 144 triangles, so the
	# primitive counts are representative of what a real scatter costs.
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.radius = 0.5
	sphere.height = 1.0
	_mesh = sphere
	_material = StandardMaterial3D.new()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.7, 0.0)
	_camera.far = 2000.0
	add_child(_camera)

	_run()


func _run() -> void:
	print("\n--- scatter culling: %d instances over %.0f m ---" % [ROCKS, FIELD])
	print("%-32s %8s %9s %7s %8s" % ["case", "objects", "prims", "draws", "ms"])

	var base := await _measure("00 empty scene", {})

	var single := _build_single(-1.0)
	await _measure("one multimesh, no range", base)
	_free(single)

	var single_culled := _build_single(CULL_AT)
	await _measure("one multimesh, range %.0f" % CULL_AT, base)
	_free(single_culled)

	for grid in GRIDS:
		var n: int = grid * grid
		var cell_m := FIELD / float(grid)

		var cells := _build_cells(-1.0, grid)
		await _measure("%4d cells of %3.0f m, no range" % [n, cell_m], base)
		_free(cells)

		var culled := _build_cells(CULL_AT, grid)
		await _measure("%4d cells of %3.0f m, range %.0f" % [n, cell_m, CULL_AT], base)
		_free(culled)

	# The opening baseline is measured on a cold GPU, before it has clocked up,
	# so it reads high and flatters everything after it. Re-measure an empty
	# scene at the end: the honest noise floor is the pair of them.
	await _measure("00 empty scene (again)", {})

	print("\n(deltas against the empty scene; camera at eye height, field centre)")
	get_tree().quit(0)
	return


# --- Builders -----------------------------------------------------------

## Every rock in one MultiMesh: one AABB the size of the whole patch.
func _build_single(range_end: float) -> Array[Node3D]:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh(ROCKS, 0, FIELD)
	mmi.material_override = _material
	if range_end > 0.0:
		mmi.visibility_range_end = range_end
	add_child(mmi)
	var out: Array[Node3D] = [mmi]
	return out


## The same rocks bucketed into a grid x grid lattice of cells.
func _build_cells(range_end: float, grid: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var per_cell := ROCKS / (grid * grid)
	var cell := FIELD / float(grid)
	for cz in grid:
		for cx in grid:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = _multimesh(per_cell, cz * grid + cx, cell)
			mmi.material_override = _material
			mmi.position = Vector3(
				(cx + 0.5) * cell - FIELD * 0.5,
				0.0,
				(cz + 0.5) * cell - FIELD * 0.5
			)
			if range_end > 0.0:
				mmi.visibility_range_end = range_end
			add_child(mmi)
			out.append(mmi)
	return out


## `spread` is the side of the square the instances fill, centred on the node.
func _multimesh(count: int, rng_seed: int, spread: float) -> MultiMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + rng_seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = count
	for i in count:
		var t := Transform3D.IDENTITY
		t.origin = Vector3(
			rng.randf_range(-spread, spread) * 0.5,
			0.5,
			rng.randf_range(-spread, spread) * 0.5
		)
		mm.set_instance_transform(i, t)
	return mm


func _free(nodes: Array[Node3D]) -> void:
	for n in nodes:
		n.queue_free()


# --- Measurement --------------------------------------------------------

## Renders WARMUP frames, then times TIMED and samples the render counters.
func _measure(label: String, base: Dictionary) -> Dictionary:
	for i in WARMUP:
		await RenderingServer.frame_post_draw

	var started := Time.get_ticks_usec()
	for i in TIMED:
		await RenderingServer.frame_post_draw
	var elapsed := Time.get_ticks_usec() - started

	var out := {
		"objects": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"draws": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"ms": float(elapsed) / 1000.0 / TIMED,
	}
	var d := func(k: String) -> int:
		return int(out[k]) - (int(base[k]) if base.has(k) else 0)
	print("%-32s %8d %9d %7d %8.3f" % [
		label, d.call("objects"), d.call("prims"), d.call("draws"), out["ms"]
	])
	return out
