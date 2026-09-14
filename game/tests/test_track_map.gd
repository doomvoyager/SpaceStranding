extends Node3D
## The wheel-track map's bookkeeping, headless.
##
## What can be held here is the arithmetic - where a world point lands on the
## toroidal map, the heading encoding, when the window moves and which strips
## it wipes - and the node's plumbing: that it follows the rover, pushes its
## globals, and queues stamps and wipes - and the trail: that stamps are
## remembered by cell, found by rectangle, survive a round trip through bytes
## and a file, and are painted back when the window rolls onto them. What
## cannot is the picture: the dummy renderer never emits `frame_post_draw`,
## so nothing drawn can be read back, and `track_capture.tscn` is the only
## witness to the rut, the tread, and the tracks coming back.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_track_map.tscn

var _fails := 0
var _checks := 0


func _ready() -> void:
	_arithmetic()
	_trail()
	await _node()
	await _memory()
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


func _trail() -> void:
	_expect("cells floor toward minus infinity",
		TrackTrail.cell_of(Vector2(-0.1, 7.9), 8.0) == Vector2i(-1, 0))
	var trail := TrackTrail.new(8.0)
	for i in 40:
		trail.add(Vector2(i * 0.5 - 5.0, 3.0), 0.2, 0.8, 0.36, 0.32)
	_expect("forty samples remembered", trail.size() == 40)
	var hits := trail.in_rect(Rect2(0.0, 0.0, 8.0, 8.0))
	# x in [0, 8): i*0.5 - 5 >= 0 -> i >= 10; < 8 -> i < 26: sixteen.
	_expect("a rect finds exactly the samples inside it: %d" % hits.size(), hits.size() == 16)
	_expect("and not the ones outside", trail.in_rect(Rect2(100.0, 100.0, 8.0, 8.0)).is_empty())
	# x in [-6, 0): i from 0 to 9, ten of them, across the cell boundary at 0.
	_expect("across a negative cell too", trail.in_rect(Rect2(-6.0, 0.0, 6.0, 8.0)).size() == 10)
	_expect("a sample reads back", trail.position_at(0) == Vector2(-5.0, 3.0)
		and is_equal_approx(trail.heading_at(0), 0.2) and is_equal_approx(trail.strength_at(0), 0.8)
		and is_equal_approx(trail.length_at(0), 0.36) and is_equal_approx(trail.width_at(0), 0.32))

	var bytes := trail.to_bytes()
	var back := TrackTrail.from_bytes(bytes)
	_expect("bytes round-trip", back != null and back.size() == 40
		and back.position_at(39) == trail.position_at(39)
		and is_equal_approx(back.width_at(39), 0.32)
		and back.in_rect(Rect2(0.0, 0.0, 8.0, 8.0)).size() == 16)
	# Truly corrupt bytes are refused too, but bytes_to_var says so with an
	# engine error, which is the right noise for a bad save and the wrong noise
	# for a passing test.
	_expect("a wrong dictionary is refused",
		TrackTrail.from_bytes(var_to_bytes({"format": "nope"})) == null)
	var path := "user://test_track_trail.bin"
	_expect("saves", trail.save(path) == OK)
	var loaded := TrackTrail.load(path)
	_expect("and loads", loaded != null and loaded.size() == 40)
	_expect("a missing file loads as null", TrackTrail.load("user://no_such_trail.bin") == null)
	DirAccess.remove_absolute(path)

	# new_ground: the world rects a move rolls onto.
	var o := Vector2(-64.0, -64.0)
	var east := TrackMap.new_ground(o, o + Vector2(10.0, 0.0), 128.0, 128.0)
	_expect("an eastward move rolls onto a strip past the old far edge",
		east.size() == 1 and east[0].is_equal_approx(Rect2(64.0, -64.0, 10.0, 128.0)))
	var west := TrackMap.new_ground(o, o + Vector2(-10.0, 0.0), 128.0, 128.0)
	_expect("a westward move onto a strip at the new near edge",
		west.size() == 1 and west[0].is_equal_approx(Rect2(-74.0, -64.0, 10.0, 128.0)))
	var both := TrackMap.new_ground(o, o + Vector2(4.0, -6.0), 128.0, 128.0)
	_expect("a diagonal move onto two strips in the new window", both.size() == 2
		and both[0].is_equal_approx(Rect2(64.0, -70.0, 4.0, 128.0))
		and both[1].is_equal_approx(Rect2(-60.0, -70.0, 128.0, 6.0)))
	var jump := TrackMap.new_ground(o, o + Vector2(300.0, 0.0), 128.0, 128.0)
	_expect("a jump rolls onto the whole new window",
		jump.size() == 1 and jump[0].is_equal_approx(Rect2(236.0, -64.0, 128.0, 128.0)))


func _memory() -> void:
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

	map.stamp(Vector2(1.0, 1.0), 0.0, 0.8)
	_expect("a stamp is remembered", map.trail().size() == 1)
	var far := map.origin().x + map.extent() + 2.0
	map.trail().add(Vector2(far, 0.0), 0.5, 0.7, 0.36, 0.32)
	var before := map.replayed()
	rover.global_position = Vector3(50.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect("rolling onto remembered ground paints it back: %d" % (map.replayed() - before),
		map.replayed() - before == 1)
	var far_again := map.origin().x + map.extent() + 2.0
	rover.global_position = Vector3(50.0 + 1000.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect("a jump repaints the whole window, which held nothing", map.replayed() - before == 1)
	rover.global_position = Vector3(50.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect("and coming back repaints both stamps: %d" % (map.replayed() - before),
		map.replayed() - before == 3)
	_expect("far_again is unused but honest", far_again > far)

	var path := "user://test_track_map_trail.bin"
	_expect("the map saves its trail", map.save_trail(path) == OK)
	map.forget()
	_expect("forget empties the trail", map.trail().size() == 0)
	var mark := map.replayed()
	_expect("the map loads a trail", map.load_trail(path) == OK)
	_expect("and paints it back into the window", map.trail().size() == 2 and map.replayed() - mark == 2)
	_expect("a missing file is an error", map.load_trail("user://no_such.bin") != OK)
	DirAccess.remove_absolute(path)

	map.remember = true
	map.stamp(Vector2(2.0, 2.0), 0.0, 0.9, 0.32, 0.13)
	var last := map.trail().size() - 1
	_expect("a boot's own length and width are remembered",
		is_equal_approx(map.trail().length_at(last), 0.32)
		and is_equal_approx(map.trail().width_at(last), 0.13))
	map.stamp(Vector2(2.0, 2.0), 0.0, 0.9)
	_expect("and a wheel's default to the tyre",
		is_equal_approx(map.trail().width_at(last + 1), map.track_width))
	map.remember = false
	map.stamp(Vector2(2.0, 2.0), 0.0, 0.8)
	_expect("with remember off nothing is recorded", map.trail().size() == 4)

	map.queue_free()
	rover.queue_free()
	await get_tree().process_frame


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
