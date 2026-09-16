extends Node3D
## Measures what the post stack costs, and proves the merged single-pass shader
## renders what the four-node chain rendered.
##
## Two questions, both answered by rendering rather than by reasoning:
##
##   1. How much does the post layer in test_world cost against one merged
##      pass? It was four ColorRects with a BackBufferCopy between each - three
##      full-screen copies and three mip-chain rebuilds per frame - and it
##      measured 1.174 ms against 0.960 for one pass, with the post work itself
##      dropping from 0.306 ms to 0.092. Now that the scene *is* the single
##      pass, rows 01 and 02 should agree; if 01 ever climbs again, something
##      has put the chain back.
##   2. Does the single pass still get mipmaps? Glow and halation read at LOD
##      3-6, so if the automatic screen texture has no mip chain they collapse
##      to a plain copy and the effect silently vanishes. The four-node version
##      gets its mips from the BackBufferCopy in front of it; the single pass
##      has no node in front of it at all.
##   3. What the camera's glass costs (added 2026-09-16): the same view of the
##      sun with the flare, the dirt and a fully dusted lens, and with all of
##      it skipped. Wall clock cannot see it - five rounds spread 0.3 ms and put
##      the glass on the cheap side - so it reads the viewport's GPU time too:
##      0.658 ms against 0.677, 0.019 ms, on an RTX 4080 at 1600x900, every
##      round within 0.003 of its median. See [[Lens]].
##
## The scene tree is **paused** and the grain's time_scale forced to 0, so every
## configuration renders a byte-comparable frame and the difference between two
## images is the difference between two post stacks - not the rover having
## rolled a metre while the last one was being timed.
##
## Must run windowed - --headless renders nothing and times nothing.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_post_cost.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const FILM := preload("res://shaders/post/film.gdshader")
const OUT_DIR := "user://post_cost"

const WARMUP := 40
const TIMED := 200
## Alternating rounds for the glass comparison; odd, so there is a median.
const GLASS_ROUNDS := 5
## Every Nth pixel on each axis when diffing. 1600x900/16 is plenty to catch a
## missing glow and keeps the comparison to well under a second.
const DIFF_STRIDE := 4

## Exactly what the four-node scene is running today: every shader's own
## defaults, plus the one value Mac changed.
const FILM_PARAMS := {
	"ca_amount": 0.003,
	"lens_softness": 0.6,
	"edge_falloff": 2.0,
	"glow_threshold": 0.75,
	"glow_knee": 0.15,
	"glow_radius": 3.0,
	"glow_intensity": 0.5,
	"halation_threshold": 0.7,
	"halation_knee": 0.2,
	"halation_radius": 5.0,
	"channel_spread": 1.2,
	"halation_intensity": 0.6,
	"grain_intensity": 0.1,
	"grain_saturation": 0.117,
	"min_lum": 0.0,
	"max_lum": 1.0,
	"time_scale": 0.0,
}

var _world: Node
var _existing: CanvasLayer
var _cam: Camera3D
var _shots: Dictionary = {}
## The viewport's own GPU time, averaged over the last `_measure`. Finer than
## wall clock between frames, which carries the whole CPU side's noise.
var _last_gpu_ms := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_world = WORLD.instantiate()
	add_child(_world)
	for i in 120:
		await get_tree().physics_frame

	_existing = _world.find_child("PostprocessingEffects", true, false) as CanvasLayer
	if _existing == null:
		print("no PostprocessingEffects in test_world; nothing to compare")
		get_tree().quit(1)
		return
	_existing.get_parent().remove_child(_existing)
	_freeze_grain(_existing)

	for c in _find_cameras(_world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true
	var rover := _world.find_child("Rover", true, false) as Node3D
	_cam.position = rover.global_position + Vector3(6.0, 3.0, 9.0)
	_cam.look_at(rover.global_position + Vector3(0.0, 0.5, -6.0), Vector3.UP)

	# Nothing moves from here on, so every frame below is the same frame.
	get_tree().paused = true

	print("--- post stack cost, %dx%d ---" % [
		get_viewport().size.x, get_viewport().size.y])

	var single_plain := _build_single(false)
	var single_bbc := _build_single(true)

	var none := await _measure("00_no_post", null)
	var current := await _measure("01_scene_as_authored", _existing)
	var one := await _measure("02_single_pass", single_plain)
	var one_bbc := await _measure("03_single_pass_bbc", single_bbc)

	print("")
	print("  %-28s %9s %11s" % ["configuration", "ms/frame", "vs scene"])
	_report("no post at all", none, current)
	_report("the scene as authored", current, current)
	_report("one ColorRect", one, current)
	_report("one ColorRect + 1 BBC", one_bbc, current)

	print("")
	print("  mean per-channel difference from the scene as authored:")
	_diff("one ColorRect", "01_scene_as_authored", "02_single_pass")
	_diff("one ColorRect + 1 BBC", "01_scene_as_authored", "03_single_pass_bbc")
	_diff("no post at all (control)", "01_scene_as_authored", "00_no_post")

	# The camera's glass at its worst - the sun in the middle of the frame and
	# every speck of dust landed - against the same view with the glass's work
	# skipped: no sun ahead and a clean lens, which is what the shader branches
	# on. The difference is what the flare, the dirt and the dust cost.
	var lens := _existing as Lens
	var dusty := LensDust.new()
	dusty.fade_rate = 0.0
	_cam.add_child(dusty)
	dusty.coverage = 1.0
	_cam.look_at(_cam.global_position - World.sun_direction(), Vector3.UP)
	# A difference this small is inside one run's noise - measured, the rows
	# above can put one pass under no pass at all - so the two alternate over
	# several rounds and the medians are compared.
	var glass: Array[float] = []
	var bare: Array[float] = []
	var glass_gpu: Array[float] = []
	var bare_gpu: Array[float] = []
	for pass_index in GLASS_ROUNDS:
		_set_glass(lens, true)
		glass.append(await _measure("04_glass_sun_and_dust", _existing))
		glass_gpu.append(_last_gpu_ms)
		if pass_index == 0:
			print("")
			print("  glass: sun ahead %s at %s, dust %.2f" % [lens.sun_ahead, lens.sun_uv, lens.dust])
		_set_glass(lens, false)
		bare.append(await _measure("05_same_view_glass_skipped", _existing))
		bare_gpu.append(_last_gpu_ms)
	_set_glass(lens, true)
	for list in [glass, bare, glass_gpu, bare_gpu]:
		list.sort()
	var mid := GLASS_ROUNDS / 2
	print("  median of %d alternating rounds; frame is wall clock, gpu the viewport's own:" % GLASS_ROUNDS)
	print("  %-28s %9s %9s" % ["", "frame ms", "gpu ms"])
	print("  %-28s %9.3f %9.3f" % ["sun view, glass skipped", bare[mid], bare_gpu[mid]])
	print("  %-28s %9.3f %9.3f" % ["sun view, sun and full dust", glass[mid], glass_gpu[mid]])
	print("  gpu rounds, skipped %s" % [bare_gpu])
	print("  gpu rounds, glass   %s" % [glass_gpu])

	print("")
	print("stills in %s" % ProjectSettings.globalize_path(OUT_DIR))
	print("--- end probe ---")

	single_plain.queue_free()
	single_bbc.queue_free()
	_existing.queue_free()
	get_tree().quit(0)


## The Lens pushing the sun and the dust as usual, or held off with the shader
## told there is neither - which is what its branches skip on.
func _set_glass(lens: Lens, on: bool) -> void:
	lens.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not on:
		RenderingServer.global_shader_parameter_set(&"lens_sun_ahead", 0.0)
		RenderingServer.global_shader_parameter_set(&"lens_dust", 0.0)


## The grain animates off TIME, which would make two renders of the same frame
## differ by noise alone and drown the comparison.
func _freeze_grain(layer: CanvasLayer) -> void:
	for child in layer.get_children():
		var rect := child as ColorRect
		if rect == null:
			continue
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		for prop in mat.shader.get_shader_uniform_list():
			if prop["name"] == "time_scale":
				mat.set_shader_parameter("time_scale", 0.0)


func _build_single(with_backbuffer: bool) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 10
	if with_backbuffer:
		var bbc := BackBufferCopy.new()
		bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		layer.add_child(bbc)
	var mat := ShaderMaterial.new()
	mat.shader = FILM
	for key in FILM_PARAMS:
		mat.set_shader_parameter(key, FILM_PARAMS[key])
	mat.set_shader_parameter("glow_tint", Color(1.0, 0.97, 0.9, 1.0))
	mat.set_shader_parameter("halation_tint", Color(1.0, 0.32, 0.12, 1.0))
	var rect := ColorRect.new()
	rect.material = mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return layer


## Average milliseconds per rendered frame for one configuration, with a PNG.
func _measure(shot_name: String, layer: CanvasLayer) -> float:
	if layer != null:
		add_child(layer)
	for i in WARMUP:
		await RenderingServer.frame_post_draw

	var started := Time.get_ticks_usec()
	var gpu := 0.0
	for i in TIMED:
		await RenderingServer.frame_post_draw
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var elapsed := Time.get_ticks_usec() - started
	_last_gpu_ms = gpu / float(TIMED)

	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	_shots[shot_name] = image

	if layer != null:
		remove_child(layer)
	return float(elapsed) / float(TIMED) / 1000.0


func _report(label: String, ms: float, baseline: float) -> void:
	var delta := ""
	if not is_equal_approx(ms, baseline):
		delta = "%+.1f%%" % (100.0 * (ms - baseline) / maxf(baseline, 0.0001))
	print("  %-28s %9.3f %11s" % [label, ms, delta])


## Mean absolute per-channel difference, 0-255. The "no post" row is the control:
## it says how big a difference actually looks like, so a small number on the
## single-pass rows means something.
func _diff(label: String, a_name: String, b_name: String) -> void:
	var a: Image = _shots.get(a_name)
	var b: Image = _shots.get(b_name)
	if a == null or b == null or a.get_size() != b.get_size():
		print("  %-28s (not comparable)" % label)
		return
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), DIFF_STRIDE):
		for x in range(0, a.get_width(), DIFF_STRIDE):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 3
	print("  %-28s %6.2f / 255" % [label, 255.0 * total / maxf(float(count), 1.0)])


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out
