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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
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

	print("")
	print("stills in %s" % ProjectSettings.globalize_path(OUT_DIR))
	print("--- end probe ---")

	single_plain.queue_free()
	single_bbc.queue_free()
	_existing.queue_free()
	get_tree().quit(0)


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
	for i in TIMED:
		await RenderingServer.frame_post_draw
	var elapsed := Time.get_ticks_usec() - started

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
