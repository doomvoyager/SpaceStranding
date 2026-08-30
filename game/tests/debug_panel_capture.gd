extends Node3D
## Look-dev capture for the F1 tuning panel. Boots the real world, opens the
## panel, and writes PNGs to user://debug_look/.
##
## The panel is generated at runtime from reflection, so what it actually looks
## like - whether the labels fit, whether 60 rows scroll sensibly, whether the
## groups read - cannot be judged from the code or from a headless test. Both
## of those only prove the rows exist.
##
## Must run as a scene, not --script. Runs windowed on purpose: --headless uses
## the dummy renderer and produces no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/debug_panel_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://debug_look"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	add_child(WORLD.instantiate())
	for i in 90:
		await get_tree().physics_frame

	# What the panel costs to have open, measured before any screenshots -
	# get_image() stalls the GPU hard enough to make the on-screen fps readout
	# meaningless. A tuning panel is used while driving, so this matters.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var closed_ms := await _time_frames()
	Debug.set_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var open_ms := await _time_frames()
	print("panel closed %.3f ms/frame, open %.3f ms/frame (%+.1f%%)"
		% [closed_ms, open_ms, 100.0 * (open_ms - closed_ms) / maxf(closed_ms, 0.0001)])

	var scroll := _find_scroll(Debug)
	await _shot("01_panel_top")

	if scroll != null:
		var max_scroll := maxi(scroll.get_v_scroll_bar().max_value - 400, 0)
		scroll.scroll_vertical = int(max_scroll * 0.33)
		await _shot("02_panel_rover")
		scroll.scroll_vertical = int(max_scroll * 0.72)
		await _shot("03_panel_cargo")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _shot("04_panel_post")

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _time_frames(frames := 200) -> float:
	for i in 30:
		await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - started) / float(frames) / 1000.0


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var found := _find_scroll(c)
		if found != null:
			return found
	return null


func _shot(shot_name: String) -> void:
	for i in 6:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
