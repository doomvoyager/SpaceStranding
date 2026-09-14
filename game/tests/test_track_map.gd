extends Node3D
## The wheel-track map's bookkeeping, headless.
##
## What can be held here is the arithmetic - where a world point lands on the
## toroidal map, the heading encoding, when the window moves and which strips
## it wipes - and the node's plumbing: that it follows the rover, pushes its
## globals, and queues stamps and wipes. What cannot is the picture: the
## dummy renderer never emits `frame_post_draw`, so nothing drawn can be read
## back, and `track_capture.tscn` is the only witness to the rut and the tread.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_track_map.tscn

var _fails := 0
var _checks := 0


func _ready() -> void:
	_arithmetic()
	await _node()
	print("%d checks, %d failed" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
		get_tree().quit(0)
		return
	print("FAIL")
	get_tree().quit(1)


func _arithmetic() -> void:
	# --- pixel_of: toroidal, origin-free
	var n := 4096
	var ts := 0.08
	_expect_vec("origin lands on texel 0", TrackMap.pixel_of(Vector2.ZERO, ts, n), Vector2.ZERO)
	_expect_vec("a texel west wraps to the far edge",
		TrackMap.pixel_of(Vector2(-ts, 0.0), ts, n), Vector2(n - 1, 0))
	_expect_vec("half a texel resolves",
		TrackMap.pixel_of(Vector2(ts * 0.5, ts * 2.5), ts, n), Vector2(0.5, 2.5))
	var over_px := TrackMap.pixel_of(Vector2(n * ts + 0.8, 0.8), ts, n)
	_expect("a window over lands on the same texel, to a thousandth",
		over_px.distance_to(Vector2(10, 10)) < 1e-3)

	# --- heading: doubled, so a wheel going the other way writes the same
	for i in 12:
		var h := i * PI / 6.0 - PI
		var enc := TrackMap.encode_heading(h)
		var back := TrackMap.encode_heading(h + PI)
		_expect("heading %.2f and its reverse encode alike" % h, enc.is_equal_approx(back))
		_expect_near("heading %.2f round-trips mod PI" % h,
			TrackMap.decode_heading(enc), fposmod(h, PI), 1e-4)
	var neutral := TrackMap.encode_heading(0.0)
	_expect("encoding stays in 0..1", neutral.x >= 0.0 and neutral.x <= 1.0
		and neutral.y >= 0.0 and neutral.y <= 1.0)

	# --- advance_origin
	var extent := n * ts
	var origin := Vector2(-extent * 0.5, -extent * 0.5)
	var same := TrackMap.advance_origin(origin, Vector2(3.0, -3.0), extent, 8.0, ts)
	_expect_vec("inside the band the window holds", same, origin)
	var moved := TrackMap.advance_origin(origin, Vector2(9.0, 0.0), extent, 8.0, ts)
	_expect("the window moves on the axis that strayed", moved.x > origin.x)
	_expect_near("and not on the other", moved.y, origin.y, 1e-6)
	_expect_near("in whole texels", fposmod(moved.x / ts + 0.5, 1.0), 0.5, 1e-3)
	var centre := moved + Vector2.ONE * extent * 0.5
	_expect("the target is back inside the band", absf(9.0 - centre.x) <= 8.0)
	var back_west := TrackMap.advance_origin(origin, Vector2(-20.0, 0.0), extent, 8.0, ts)
	_expect("it moves west too", back_west.x < origin.x)

	# --- wrap_strips
	var east := origin + Vector2(112 * ts, 0.0)
	var strips := TrackMap.wrap_strips(origin, east, extent, ts, n)
	_expect_near("an eastward move wipes shift x height", _area(strips), 112.0 * n, 0.5)
	_expect("wipes stay inside the map", _inside(strips, n))
	# A seam case: the strip the window rolls onto straddles the wrap. With the
	# origin at -extent/2, the far edge sits at texel n/2, so move the window
	# so the new range crosses texel n... put the origin so old far edge is
	# at texel n - 5 and shift by 12.
	var near_seam := Vector2((n - 5) * ts - extent, 0.0)
	var over := near_seam + Vector2(12 * ts, 0.0)
	var seam := TrackMap.wrap_strips(near_seam, over, extent, ts, n)
	_expect("a strip across the seam is two rects", seam.size() == 2)
	_expect_near("and still shift x height", _area(seam), 12.0 * n, 0.5)
	_expect("wipes across the seam stay inside", _inside(seam, n))
	var both := TrackMap.wrap_strips(origin, origin + Vector2(10 * ts, -7 * ts), extent, ts, n)
	_expect_near("a diagonal move wipes both strips", _area(both), 17.0 * n, 0.5)
	var jump := TrackMap.wrap_strips(origin, origin + Vector2(extent * 2.0, 0.0), extent, ts, n)
	_expect("a jump of a window wipes everything", jump.size() == 1
		and is_equal_approx(_area(jump), float(n) * n))
	_expect("no move wipes nothing", TrackMap.wrap_strips(origin, origin, extent, ts, n).is_empty())


func _node() -> void:
	for key in ["track_map", "track_origin", "track_extent", "track_texel", "track_active"]:
		_expect("project.godot declares %s" % key,
			RenderingServer.global_shader_parameter_get_list().has(key))

	var rover := Node3D.new()
	rover.name = "Rover"
	rover.add_to_group("rover")
	add_child(rover)
	var map := TrackMap.new()
	map.texels = 256
	map.texel_size = 0.5
	map.advance_step = 8.0
	add_child(map)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	# The dummy renderer returns null for every global, the scanner's declared
	# ones included, so what was pushed can only be read back in a window.
	# Skip the claim loudly rather than weaken it.
	var globals_readable := RenderingServer.global_shader_parameter_get("scan_radius") != null
	if not globals_readable:
		print("  SKIP: global read-back - %s returns null for every global"
			% DisplayServer.get_name())
	if globals_readable:
		_expect("the map is active",
			RenderingServer.global_shader_parameter_get("track_active") == true)
		var pushed = RenderingServer.global_shader_parameter_get("track_extent")
		_expect("and the extent is pushed", pushed is float and is_equal_approx(pushed, 128.0))
		_expect("the map is a texture",
			RenderingServer.global_shader_parameter_get("track_map") is Texture2D)
	_expect_near("the extent is texels x texel", map.extent(), 128.0, 1e-6)
	_expect("the map has a texture", map.texture() is ViewportTexture)
	var o: Vector2 = map.origin()
	var centre := o + Vector2.ONE * 64.0
	_expect("the window is centred on the rover", centre.length() <= 8.0)
	if globals_readable:
		_expect_vec("the origin is pushed",
			RenderingServer.global_shader_parameter_get("track_origin"), o)

	var before_clears := map.pending_clears()
	map.stamp(Vector2(3.0, 4.0), 0.3, 0.8)
	_expect("a stamp queues", map.pending_stamps() >= 1)

	rover.global_position = Vector3(50.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var o2: Vector2 = map.origin()
	_expect("moving the rover moves the window", o2.x > o.x)
	_expect("in whole texels", is_equal_approx(fposmod(o2.x / 0.5 + 0.5, 1.0), 0.5))
	if globals_readable:
		_expect_vec("and pushes the new origin",
			RenderingServer.global_shader_parameter_get("track_origin"), o2)
	_expect("a move queues a wipe, unless the frame already drew it",
		map.pending_clears() > before_clears or map.pending_clears() == 0)
	print("headless: %d stamps drawn (0 means _draw never ran, which is the dummy renderer, not a bug)"
		% map.stamps_drawn())

	map.queue_free()
	rover.queue_free()
	await get_tree().process_frame
	if globals_readable:
		_expect("leaving the tree deactivates the map",
			RenderingServer.global_shader_parameter_get("track_active") == false)


func _area(rects: Array[Rect2]) -> float:
	var total := 0.0
	for r in rects:
		total += r.size.x * r.size.y
	return total


func _inside(rects: Array[Rect2], n: int) -> bool:
	for r in rects:
		if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > n + 0.001 or r.end.y > n + 0.001:
			return false
	return true


func _expect(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: %s" % label)


func _expect_near(label: String, got: float, want: float, tol: float) -> void:
	_checks += 1
	if absf(got - want) > tol:
		_fails += 1
		print("  FAIL: %s - got %s, wanted %s" % [label, got, want])


func _expect_vec(label: String, got: Vector2, want: Vector2) -> void:
	_checks += 1
	if not got.is_equal_approx(want):
		_fails += 1
		print("  FAIL: %s - got %s, wanted %s" % [label, got, want])
