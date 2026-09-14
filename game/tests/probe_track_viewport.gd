extends Node3D
## Does a never-cleared SubViewport accumulate what is drawn into it?
##
## The wheel-track map is a SubViewport with `render_target_clear_mode` NEVER
## that the wheels stamp into every tick and the terrain shader samples. That
## only works if a draw survives the frames after it, if the first frame is
## something known rather than garbage, and if a `_draw()` that queues stamps
## across two physics ticks lands both. Measured rather than assumed: run it
## windowed (the dummy renderer may return nothing, which is also worth
## knowing - run it headless too).
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game res://tests/probe_track_viewport.tscn
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/probe_track_viewport.tscn

const SIZE := 128

var _viewport: SubViewport
var _canvas: Node2D
var _rects: Array[Rect2] = []


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_canvas = Node2D.new()
	_canvas.draw.connect(_on_draw)
	_viewport.add_child(_canvas)

	print("display server: ", DisplayServer.get_name())
	await RenderingServer.frame_post_draw
	_report("first frame, nothing drawn")

	_rects = [Rect2(10, 10, 20, 20)]
	_canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	_report("after drawing A")

	_rects = [Rect2(60, 60, 20, 20)]
	_canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	_report("after drawing B only")

	_rects = []
	for i in 5:
		await RenderingServer.frame_post_draw
	_report("five frames later, nothing drawn")

	# Two queued stamps in one redraw, as two physics ticks between frames.
	_rects = [Rect2(100, 10, 10, 10), Rect2(100, 100, 10, 10)]
	_canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	_report("after one redraw holding two stamps")

	get_tree().quit()


func _on_draw() -> void:
	for r in _rects:
		_canvas.draw_rect(r, Color.WHITE)


func _report(label: String) -> void:
	var img := _viewport.get_texture().get_image()
	if img == null or img.is_empty():
		print("%s: no image" % label)
		return
	var a := img.get_pixel(20, 20).r
	var b := img.get_pixel(70, 70).r
	var c := img.get_pixel(105, 15).r
	var d := img.get_pixel(105, 105).r
	var bg := img.get_pixel(40, 100)
	print("%s: A=%.2f B=%.2f C=%.2f D=%.2f background=%s"
		% [label, a, b, c, d, bg])
