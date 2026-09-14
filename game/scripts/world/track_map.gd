extends Node3D
class_name TrackMap
## Wheel tracks: painted by the wheels into a map, read by the ground.
##
## Regolith takes a track and keeps it. This is the map of where the wheels
## have been - a texture the rover's wheels stamp into every physics tick, and
## that `surface.gdshader` samples by world position to darken, rut and tread
## the ground. Nothing is added to the scene per stamp: no decals, no ribbon
## meshes, one texture and one extra sample on the terrain.
##
## **The map is a window that follows the rover**, addressed toroidally. A
## world point lands on texel `posmod(xz / texel_size, texels)` no matter where
## the window is, so moving the window copies nothing; it only changes which
## world range is *valid*, and the strip of texels that the window has just
## rolled onto - which still holds whatever was there a window ago - is wiped.
## The shader bound-checks against the same origin, so a point outside the
## window never reads its alias inside it. 4096 texels at 0.08 m is a 328 m
## window, and beyond 160 m a track is two pixels wide anyway.
##
## **The window forgets; the trail remembers.** Every stamp is also recorded
## in a `TrackTrail`, bucketed by position, and when the window rolls onto a
## strip the strip is wiped and then every remembered stamp inside it is
## painted back. Drive back to ground you crossed an hour ago and the tracks
## are there as the window arrives, drawn by the same stamps that made them.
## Persistence over precision was Mac's call; this happens to give both. The
## trail is the storable curve: `save_trail()` and `load_trail()`.
##
## **It lives in a SubViewport that is never cleared.** Measured
## (`tests/probe_track_viewport.tscn`): a draw survives every frame after it,
## the first frame is black, and a `_draw()` holding two stamps lands both -
## so stamps queued over several physics ticks between two rendered frames are
## not lost. The viewport's texture goes to the terrain as a global shader
## uniform, the way the scan pulse does, so one map drives every tile.
##
## **Three channels.** R is depth, 0..1. G and B carry the direction of travel
## as `0.5 + 0.5 * (cos 2t, sin 2t)`, doubled so a wheel going the other way
## writes the same value and so the map filters cleanly; the shader draws the
## tread chevrons from it, which is what lets the map be this coarse. Stamps
## blend in with MIX, so overlapping stamps converge on a value rather than
## piling up, and the empty map is `(0, 0.5, 0.5)` so a soft edge does not drag
## the direction toward a corner.
##
## Anything not a wheel can stamp too - `stamp()` is public - which is where
## footprints would go.

@export_group("Map")
## Texels along each side. The window is `texels * texel_size` metres across;
## at 4096 x 0.08 that is 328 m and 48 MB of texture.
@export_range(256, 8192, 256) var texels := 4096:
	set(v):
		texels = v
		_rebuild()
## Metres per texel. 0.08 gives a 0.32 m tyre four texels of width, and the
## tread is drawn by the shader rather than stored, so it needs no more.
@export_range(0.01, 1.0, 0.005) var texel_size := 0.08:
	set(v):
		texel_size = maxf(v, 0.001)
		_rebuild()
## How far the followed node may stray from the window's centre before the
## window moves, in metres. Each move wipes a strip, so larger is fewer wipes.
@export_range(1.0, 100.0, 1.0) var advance_step := 8.0
## What the window follows and whose wheels stamp. Empty finds the `rover`
## group.
@export var follow_path: NodePath

@export_group("Memory")
## Record every stamp in the trail and paint it back when the window returns.
## Off, the map is a window and nothing more.
@export var remember := true

@export_group("Stamp")
## Width of a wheel's mark on the ground, metres: the tyre's tread width.
@export_range(0.05, 2.0, 0.01) var track_width := 0.32
## Length of one stamp along the travel, metres. A wheel stamps again once it
## has moved a third of this, so stamps always overlap.
@export_range(0.05, 2.0, 0.01) var stamp_length := 0.36
## How deep a stamp presses, 0..1, which the shader reads as a full rut.
@export_range(0.0, 1.0, 0.01) var depth := 0.85
## A skidding wheel presses this much deeper, at full skid.
@export_range(0.0, 1.0, 0.01) var skid_depth := 0.15
## The soft edge of a stamp, as a fraction of its half-width.
@export_range(0.0, 1.0, 0.01) var edge_softness := 0.6
## How much shallower the rut is at the tyre's edge than under its centre,
## 0..1. The depth across a track is then a U, which is what a rut is - and
## it is what tells the shader how far from the centre line a point is, since
## the map does not store that. The chevrons hang off it.
@export_range(0.0, 1.0, 0.01) var rut_profile := 0.6

## What an empty texel holds: no depth, and the direction's neutral value.
const EMPTY := Color(0.0, 0.5, 0.5, 1.0)
## Pixels across the stamp texture; the shape is a soft box, so few are needed.
const STAMP_PIXELS := 64


class Stamp:
	var position: Vector2
	var heading: float
	var length: float
	var strength: float


var _viewport: SubViewport
var _canvas: Node2D
var _stamp_texture: ImageTexture
## World XZ of the window's corner, always a multiple of `texel_size`.
var _origin := Vector2.ZERO
var _pending_stamps: Array[Stamp] = []
var _pending_clears: Array[Rect2] = []
var _follow: Node3D
var _wheels: Array[VehicleWheel3D] = []
## Where each wheel last stamped, so it stamps again only after moving.
var _last_stamp: Dictionary = {}
var _stamps_drawn := 0
var _trail := TrackTrail.new()
## Stamps painted back from the trail, for the test and the readout.
var _replayed := 0


func _ready() -> void:
	_stamp_texture = _make_stamp_texture()
	_rebuild()
	_find_follow()
	RenderingServer.global_shader_parameter_set("track_active", true)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("track_active", false)


func _physics_process(_delta: float) -> void:
	if _follow == null:
		_find_follow()
		if _follow == null:
			return
	var target := Vector2(_follow.global_position.x, _follow.global_position.z)
	_advance_to(target)
	for wheel in _wheels:
		if not wheel.is_in_contact():
			continue
		var p := wheel.get_contact_point()
		var xz := Vector2(p.x, p.z)
		var last: Vector2 = _last_stamp.get(wheel, Vector2.INF)
		if xz.distance_to(last) < stamp_length / 3.0:
			continue
		_last_stamp[wheel] = xz
		# The axle is the wheel's local X, which steering turns and rolling
		# does not; travel on the ground is perpendicular to it. The sign does
		# not matter - the encoding doubles the angle.
		var axle := wheel.global_basis.x
		var heading := atan2(axle.x, -axle.z)
		# get_skidinfo() is 1 with grip and 0 sliding.
		var skid := 1.0 - clampf(wheel.get_skidinfo(), 0.0, 1.0)
		stamp(xz, heading, depth + skid_depth * skid)
	if not _pending_stamps.is_empty() or not _pending_clears.is_empty():
		_canvas.queue_redraw()


## Press a mark into the map: `world_xz` is the centre, `heading` the direction
## of travel in radians on the XZ plane (either way round), `strength` the
## depth 0..1. `length` defaults to `stamp_length`.
func stamp(world_xz: Vector2, heading: float, strength: float, length := -1.0) -> void:
	var l := length if length > 0.0 else stamp_length
	var st := clampf(strength, 0.0, 1.0)
	if remember:
		_trail.add(world_xz, heading, st, l)
	_queue_stamp(world_xz, heading, st, l)


func _queue_stamp(world_xz: Vector2, heading: float, strength: float, length: float) -> void:
	var s := Stamp.new()
	s.position = world_xz
	s.heading = heading
	s.length = length
	s.strength = strength
	_pending_stamps.append(s)
	if _canvas != null:
		_canvas.queue_redraw()


## Everything the wheels have ever stamped.
func trail() -> TrackTrail:
	return _trail


## Stamps painted back from the trail so far.
func replayed() -> int:
	return _replayed


## Forget every track, on the map and in the trail.
func forget() -> void:
	_trail.clear()
	_pending_stamps.clear()
	_pending_clears.append(Rect2(0.0, 0.0, texels, texels))
	if _canvas != null:
		_canvas.queue_redraw()


## Wipe the window and paint the trail back into all of it.
func replay_window() -> void:
	_pending_stamps.clear()
	_pending_clears.append(Rect2(0.0, 0.0, texels, texels))
	_replay(Rect2(_origin, Vector2.ONE * extent()))
	if _canvas != null:
		_canvas.queue_redraw()


func save_trail(path: String) -> Error:
	return _trail.save(path)


## Replace the trail with one from `save_trail()`, and paint it in.
func load_trail(path: String) -> Error:
	var loaded := TrackTrail.load(path)
	if loaded == null:
		return ERR_FILE_CORRUPT
	_trail = loaded
	replay_window()
	return OK


## World XZ of the window's corner.
func origin() -> Vector2:
	return _origin


## Metres across the window.
func extent() -> float:
	return texels * texel_size


## The map itself, for anything that wants to look at it.
func texture() -> ViewportTexture:
	return _viewport.get_texture() if _viewport != null else null


## Stamps queued and not yet drawn.
func pending_stamps() -> int:
	return _pending_stamps.size()


## Wipes queued and not yet drawn.
func pending_clears() -> int:
	return _pending_clears.size()


func stamps_drawn() -> int:
	return _stamps_drawn


# --- The arithmetic, pure so a headless test can hold it ------------------

## Fractional texel a world point lands on, in [0, texels) on each axis, for
## any window: the map is toroidal in world space.
static func pixel_of(world_xz: Vector2, texel: float, count: int) -> Vector2:
	var n := float(count)
	return Vector2(fposmod(world_xz.x / texel, n), fposmod(world_xz.y / texel, n))


## The direction of travel as the map stores it: the angle doubled, so a
## heading and its reverse encode alike, mapped to 0..1.
static func encode_heading(heading: float) -> Vector2:
	return Vector2(0.5 + 0.5 * cos(2.0 * heading), 0.5 + 0.5 * sin(2.0 * heading))


## The heading back, in [0, PI).
static func decode_heading(encoded: Vector2) -> float:
	var v := encoded * 2.0 - Vector2.ONE
	return fposmod(atan2(v.y, v.x) * 0.5, PI)


## The window corner that keeps `target` within `step` of the centre, moving
## in whole texels and only on the axes that need it. `origin` unchanged when
## the target is inside the band.
static func advance_origin(origin: Vector2, target: Vector2, extent: float,
		step: float, texel: float) -> Vector2:
	var centre := origin + Vector2.ONE * extent * 0.5
	var out := origin
	for axis in 2:
		var off: float = target[axis] - centre[axis]
		if absf(off) > step:
			out[axis] += floorf(off / texel) * texel
	return out


## The texel rectangles the window has just rolled onto, which still hold a
## window-old picture and must be wiped. One or two per moved axis, since a
## strip may cross the seam; the whole map if the window jumped a window.
static func wrap_strips(old_origin: Vector2, new_origin: Vector2, extent: float,
		texel: float, count: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := float(count)
	for axis in 2:
		var shift := roundi((new_origin[axis] - old_origin[axis]) / texel)
		if shift == 0:
			continue
		if absi(shift) >= count:
			out.clear()
			out.append(Rect2(0.0, 0.0, n, n))
			return out
		# World range of the new texels, in texel units along this axis.
		var first: float
		if shift > 0:
			first = (old_origin[axis] + extent) / texel
		else:
			first = new_origin[axis] / texel
		var start := fposmod(roundf(first), n)
		var length := float(absi(shift))
		var end := start + length
		if end <= n:
			out.append(_strip(axis, start, length, n))
		else:
			out.append(_strip(axis, start, n - start, n))
			out.append(_strip(axis, 0.0, end - n, n))
	return out


static func _strip(axis: int, start: float, length: float, n: float) -> Rect2:
	if axis == 0:
		return Rect2(start, 0.0, length, n)
	return Rect2(0.0, start, n, length)


# --- Internals ---------------------------------------------------------------


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _viewport != null:
		_viewport.queue_free()
	_viewport = SubViewport.new()
	_viewport.name = "Map"
	_viewport.size = Vector2i(texels, texels)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_canvas = Node2D.new()
	_canvas.name = "Stamps"
	_canvas.draw.connect(_on_draw)
	_viewport.add_child(_canvas)
	# Centre the window here for now; the first tick re-centres on the target.
	_origin = _snap(Vector2(global_position.x, global_position.z) - Vector2.ONE * extent() * 0.5)
	# The first frame of a never-cleared viewport is black, and black is not
	# empty for the direction channels.
	_pending_clears.clear()
	_pending_clears.append(Rect2(0.0, 0.0, texels, texels))
	_pending_stamps.clear()
	_replay(Rect2(_origin, Vector2.ONE * extent()))
	_last_stamp.clear()
	_canvas.queue_redraw()
	RenderingServer.global_shader_parameter_set("track_map", _viewport.get_texture())
	RenderingServer.global_shader_parameter_set("track_extent", extent())
	RenderingServer.global_shader_parameter_set("track_texel", texel_size)
	RenderingServer.global_shader_parameter_set("track_origin", _origin)


func _find_follow() -> void:
	if not follow_path.is_empty():
		_follow = get_node_or_null(follow_path) as Node3D
	if _follow == null:
		_follow = get_tree().get_first_node_in_group("rover") as Node3D
	_wheels.clear()
	if _follow != null:
		for child in _follow.find_children("*", "VehicleWheel3D", true, false):
			_wheels.append(child)


func _snap(v: Vector2) -> Vector2:
	return (v / texel_size).floor() * texel_size


func _advance_to(target: Vector2) -> void:
	var next := advance_origin(_origin, target, extent(), advance_step, texel_size)
	if next == _origin:
		return
	_pending_clears.append_array(wrap_strips(_origin, next, extent(), texel_size, texels))
	for r in new_ground(_origin, next, extent(), texels * texel_size):
		_replay(r)
	_origin = next
	RenderingServer.global_shader_parameter_set("track_origin", _origin)


## The world rectangles the window has just rolled onto: what was wiped, in
## metres, one per moved axis, or the whole window after a jump. The other
## axis spans the *new* window, since that is where the strip now is.
static func new_ground(old_origin: Vector2, new_origin: Vector2, extent: float,
		whole_from: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var moved := new_origin - old_origin
	if absf(moved.x) >= whole_from or absf(moved.y) >= whole_from:
		out.append(Rect2(new_origin, Vector2.ONE * extent))
		return out
	if moved.x > 0.0:
		out.append(Rect2(old_origin.x + extent, new_origin.y, moved.x, extent))
	elif moved.x < 0.0:
		out.append(Rect2(new_origin.x, new_origin.y, -moved.x, extent))
	if moved.y > 0.0:
		out.append(Rect2(new_origin.x, old_origin.y + extent, extent, moved.y))
	elif moved.y < 0.0:
		out.append(Rect2(new_origin.x, new_origin.y, extent, -moved.y))
	return out


## Paint every remembered stamp inside `rect` back in. The rect is grown by a
## stamp length so a stamp straddling its edge is repainted whole.
func _replay(rect: Rect2) -> void:
	if not remember or _trail.size() == 0:
		return
	var grown := rect.grow(stamp_length)
	for i in _trail.in_rect(grown):
		_queue_stamp(_trail.position_at(i), _trail.heading_at(i),
			_trail.strength_at(i), _trail.length_at(i))
		_replayed += 1


func _on_draw() -> void:
	# Wipes first, then the stamps: a stamp queued this tick is inside the
	# window, and the strips being wiped are not.
	for r in _pending_clears:
		_canvas.draw_rect(r, EMPTY)
	_pending_clears.clear()
	var n := float(texels)
	for s in _pending_stamps:
		var enc := encode_heading(s.heading)
		var colour := Color(s.strength, enc.x, enc.y, 1.0)
		var px := pixel_of(s.position, texel_size, texels)
		var size := Vector2(s.length, track_width) / texel_size
		# A stamp at the seam has to land on both sides of it.
		for dx in [0.0, -n, n]:
			for dy in [0.0, -n, n]:
				var at := px + Vector2(dx, dy)
				if at.x + size.x < 0.0 or at.x - size.x > n \
						or at.y + size.y < 0.0 or at.y - size.y > n:
					continue
				_canvas.draw_set_transform(at, s.heading, Vector2.ONE)
				_canvas.draw_texture_rect(_stamp_texture,
					Rect2(-size * 0.5, size), false, colour)
		_stamps_drawn += 1
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_pending_stamps.clear()


## A box with soft edges in its alpha and the rut's U in its red; `modulate`
## supplies the depth and the direction. X is along the travel, Y across.
func _make_stamp_texture() -> ImageTexture:
	var img := Image.create(STAMP_PIXELS, STAMP_PIXELS, false, Image.FORMAT_RGBA8)
	var soft := maxf(edge_softness, 0.001)
	for y in STAMP_PIXELS:
		for x in STAMP_PIXELS:
			var u := absf((x + 0.5) / STAMP_PIXELS * 2.0 - 1.0)
			var v := absf((y + 0.5) / STAMP_PIXELS * 2.0 - 1.0)
			var a := (1.0 - smoothstep(1.0 - soft, 1.0, u)) * (1.0 - smoothstep(1.0 - soft, 1.0, v))
			var profile := 1.0 - rut_profile * v * v
			img.set_pixel(x, y, Color(profile, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
