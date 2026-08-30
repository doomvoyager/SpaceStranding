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

	Debug.set_open(true)
	await get_tree().process_frame
	await get_tree().process_frame

	var scroll := _find_scroll(Debug)
	await _shot("01_panel_top")

	if scroll != null:
		var max_scroll := maxi(scroll.get_v_scroll_bar().max_value - 400, 0)
		scroll.scroll_vertical = int(max_scroll * 0.33)
		await _shot("02_panel_rover")
		scroll.scroll_vertical = int(max_scroll * 0.72)
		await _shot("03_panel_cargo")

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


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
