extends Node3D
## Where the frame goes during a scan pulse, with and without the map open.
##
## Mac reported a large drop while scanning, worse with M up. This times the
## real test_world in a set of configurations that each switch off exactly one
## suspect, so the difference between two rows names a cost rather than
## suggesting one. It found the scanner innocent: the tags cost 0.09 ms and the
## dot grid in the terrain shader cost nothing measurable at all. What a pulse
## does is switch on the route reveal, which was rebuilding four hundred
## ground-height lookups every frame — three quarters of which went on *finding
## the terrain*. See [[Scanner]] and [[The-Map]].
##
## Nothing is paused: the whole question is what the per-frame scripts cost, and
## a paused tree runs none of them. The astronaut stands still and the pulse is
## held at full strength (`hold` set enormous) so every row is the same steady
## state rather than a different point on the pulse envelope.
##
## Must run windowed — --headless renders nothing and times nothing.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_scan_cost.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")

const WARMUP := 30
const TIMED := 150

## Stops to plant, relative to where the astronaut starts. Long enough that the
## line has real length, which is the case that hurt.
const STOPS := [
	Vector2(400.0, 300.0), Vector2(-500.0, 700.0), Vector2(900.0, -200.0),
]

var _world: Node
var _scanner: Scanner
var _map: MapPanel
var _marks: RouteMarks
var _astronaut: Astronaut
var _rows: Array = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_world = WORLD.instantiate()
	add_child(_world)
	for i in 120:
		await get_tree().physics_frame

	_scanner = _world.find_child("Scanner", true, false) as Scanner
	_map = _world.find_child("MapPanel", true, false) as MapPanel
	_marks = _world.find_child("RouteMarks", true, false) as RouteMarks
	_astronaut = _world.find_child("Astronaut", true, false) as Astronaut
	# A pulse that never ends, so a timed run is one steady state.
	_scanner.hold = 1.0e9

	print("--- scan cost, %dx%d ---" % [
		get_viewport().size.x, get_viewport().size.y])
	print("  %d stops, %d taggable things in reach, %d nodes in the tree" % [
		STOPS.size(), _scanner.taggable().size(),
		_count_nodes(get_tree().root)])

	await _run("idle", false, false, false)
	await _run("route only", true, false, false)
	await _run("map open", true, false, true)
	await _run("scan", true, true, false)
	await _run("scan + map", true, true, true)

	# Each of these is "scan + map" with one suspect switched off, so the gap
	# between it and that row is what the suspect costs.
	await _run("  no tags", true, true, true, {"tags": false})
	await _run("  no scan grid (gpu)", true, true, true, {"grid": false})
	await _run("  no route marks", true, true, true, {"marks": false})
	await _run("  no route at all", false, true, true)
	await _run("  none of the above", false, true, true,
		{"tags": false, "grid": false, "marks": false})

	_set_route(true)
	_report_hot_path()

	print("")
	print("  %-24s %9s %9s %9s %8s" % [
		"configuration", "ms/frame", "fps", "peak proc", "draws"])
	for row in _rows:
		print("  %-24s %9.3f %9.1f %8.3f %8d" % [
			row["name"], row["ms"], 1000.0 / maxf(row["ms"], 0.0001),
			row["peak"], row["draws"]])
	print("")
	print("  ms/frame is wall clock between two frame_post_draw. `peak proc` is")
	print("  Performance.TIME_PROCESS, which is the *worst* process step of the")
	print("  last second and refreshes only once a second — measured, it changed")
	print("  four times in 600 frames. It is a spike detector, not an average,")
	print("  and can legitimately read higher than the frame time beside it.")
	print("--- end probe ---")
	get_tree().quit(0)


## One timed configuration. `off` names the suspects to switch off; anything not
## named stays on.
func _run(label: String, route: bool, scan: bool, map: bool,
		off: Dictionary = {}) -> void:
	var marks_on: bool = off.get("marks", true)
	_set_route(route)
	_set_grid(off.get("grid", true))
	_scanner.max_tags = 12 if off.get("tags", true) else 0
	_marks.set_process(marks_on)
	_marks.visible = marks_on

	if map and not _map.is_open():
		_map.open()
	elif not map and _map.is_open():
		_map.close()

	if scan:
		# Re-ping so the tag budget is applied fresh, then let the front run out
		# to its full reach before timing anything.
		_scanner._elapsed = -1.0
		_scanner._since_ping = 999.0
		_scanner.ping()
		while _scanner.radius() < _scanner.reach:
			await RenderingServer.frame_post_draw
	else:
		_scanner._elapsed = -1.0
		_scanner._set_pulse(-1.0, 0.0)
		_scanner._clear_tags()

	for i in WARMUP:
		await RenderingServer.frame_post_draw

	var peak := 0.0
	var started := Time.get_ticks_usec()
	for i in TIMED:
		await RenderingServer.frame_post_draw
		peak = maxf(peak, Performance.get_monitor(Performance.TIME_PROCESS))
	var elapsed := Time.get_ticks_usec() - started

	_rows.append({
		"name": label,
		"ms": float(elapsed) / float(TIMED) / 1000.0,
		"peak": 1000.0 * peak,
		"draws": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	})


func _set_route(on: bool) -> void:
	Route.clear()
	if not on:
		return
	var at := _astronaut.vantage()
	for offset: Vector2 in STOPS:
		Route.add(at.x + offset.x, at.z + offset.y)


func _set_grid(on: bool) -> void:
	for path in ["res://materials/regolith_painterly.tres",
			"res://materials/rock_painterly.tres"]:
		var material := load(path) as ShaderMaterial
		if material != null:
			material.set_shader_parameter("scan_grid_enabled", on)


# --- The hot path --------------------------------------------------------

## What the route line's per-sample call costs, and where it goes.
##
## Both route lines walk the same chain at the same 8 m step, so a difference
## between them is in the height lookup rather than in the sampling. This is
## what named the tree walk: `Lattice.terrain()` was three quarters of the cost
## of asking for a height, because nothing had ever joined the `terrain` group
## and the "fallback" walk of every node in the scene ran every time.
func _report_hot_path() -> void:
	var terrain := Lattice.terrain()
	var here := _astronaut.vantage()
	var n := 2000

	var t0 := Time.get_ticks_usec()
	for i in n:
		Lattice.terrain()
	var find_us := float(Time.get_ticks_usec() - t0) / float(n)

	t0 = Time.get_ticks_usec()
	for i in n:
		terrain.world_height_at(here.x + float(i), here.z)
	var height_us := float(Time.get_ticks_usec() - t0) / float(n)

	t0 = Time.get_ticks_usec()
	for i in n:
		Route.ground_height(here.x + float(i), here.z)
	var route_us := float(Time.get_ticks_usec() - t0) / float(n)

	var samples := _line_samples()
	print("")
	print("  --- per call, microseconds ---")
	print("  %-34s %8.3f us" % ["Lattice.terrain()", find_us])
	print("  %-34s %8.3f us" % ["terrain.world_height_at()", height_us])
	print("  %-34s %8.3f us" % ["Route.ground_height()", route_us])
	print("  %-34s %8d" % ["nodes in group 'terrain'",
		get_tree().get_nodes_in_group("terrain").size()])
	print("  %-34s %8d" % ["route line samples", samples])
	print("  %-34s %8.3f ms" % ["  x Route.ground_height() =",
		samples * route_us / 1000.0])
	print("  that last figure is what one rebuild costs. Before the throttle it")
	print("  was also what every frame of a pulse cost.")


## How many vertices a full rebuild of the route line pushes.
func _line_samples() -> int:
	var at := _astronaut.vantage()
	var chain: Array[Vector2] = [Vector2(at.x, at.z)]
	for i in Route.count():
		chain.append(Route.point_2d(i))
	var total := 0
	for leg in range(1, chain.size()):
		total += maxi(int(ceil(chain[leg - 1].distance_to(chain[leg])
			/ Route.SAMPLE_STEP)), 1) + 1
	return total


func _count_nodes(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _count_nodes(child)
	return n
