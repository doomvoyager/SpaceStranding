extends RefCounted
class_name TrackTrail
## The track map's memory: every stamp the wheels ever made, by where it is.
##
## The map is a window and forgets what it rolls off. This holds what it
## forgot - one sample per stamp: position, heading, depth, length - bucketed
## into cells so the map can ask for "everything inside this strip" as the
## window rolls onto it, and paint the tracks back in. Persistence over
## precision was Mac's call (2026-09-14), and this gives both: the samples
## *are* the stamps, so a replayed track is the track that was there.
##
## Twenty bytes a sample, six wheels stamping every 12 cm: a 25 km drive is
## about 12 MB. `to_bytes()` and `from_bytes()` are the whole save format, a
## versioned dictionary of packed arrays; `save()` and `load()` wrap them in
## a file. Nothing calls them yet - the game has no save - but the curve is
## storable, which was the other half of the ask.

const FORMAT := "SSTRAIL"
## 2 added the width, for boots (2026-09-14). No 1 was ever written to disk.
const VERSION := 2

## Metres per bucket. The map wipes strips 8 m wide, so a strip is a row of
## cells and the query touches no more cells than it has to.
var cell_size := 8.0

var _positions := PackedVector2Array()
var _headings := PackedFloat32Array()
var _strengths := PackedFloat32Array()
var _lengths := PackedFloat32Array()
var _widths := PackedFloat32Array()
## Vector2i cell -> PackedInt32Array of sample indices.
var _cells: Dictionary = {}


func _init(cell := 8.0) -> void:
	cell_size = maxf(cell, 0.5)


## Remember one stamp. Returns its index.
func add(position: Vector2, heading: float, strength: float, length: float,
		width: float) -> int:
	var index := _positions.size()
	_positions.append(position)
	_headings.append(heading)
	_strengths.append(strength)
	_lengths.append(length)
	_widths.append(width)
	var key := cell_of(position, cell_size)
	if not _cells.has(key):
		_cells[key] = PackedInt32Array()
	var bucket: PackedInt32Array = _cells[key]
	bucket.append(index)
	_cells[key] = bucket
	return index


func size() -> int:
	return _positions.size()


func position_at(i: int) -> Vector2:
	return _positions[i]


func heading_at(i: int) -> float:
	return _headings[i]


func strength_at(i: int) -> float:
	return _strengths[i]


func length_at(i: int) -> float:
	return _lengths[i]


func width_at(i: int) -> float:
	return _widths[i]


## Indices of every sample whose position lies inside `rect`, in world XZ.
## A stamp is up to a length across, so callers wanting everything that
## *touches* a rect should grow it by that first.
func in_rect(rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _cells.is_empty():
		return out
	var lo := cell_of(rect.position, cell_size)
	var hi := cell_of(rect.end, cell_size)
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var key := Vector2i(cx, cy)
			if not _cells.has(key):
				continue
			for i in _cells[key]:
				if rect.has_point(_positions[i]):
					out.append(i)
	return out


func clear() -> void:
	_positions.clear()
	_headings.clear()
	_strengths.clear()
	_lengths.clear()
	_widths.clear()
	_cells.clear()


static func cell_of(position: Vector2, cell: float) -> Vector2i:
	return Vector2i(floori(position.x / cell), floori(position.y / cell))


# --- Storage ------------------------------------------------------------------


func to_bytes() -> PackedByteArray:
	return var_to_bytes({
		"format": FORMAT,
		"version": VERSION,
		"cell_size": cell_size,
		"positions": _positions,
		"headings": _headings,
		"strengths": _strengths,
		"lengths": _lengths,
		"widths": _widths,
	})


## A trail from `to_bytes()` output, or null if the bytes are not one.
static func from_bytes(bytes: PackedByteArray) -> TrackTrail:
	var data = bytes_to_var(bytes)
	if not data is Dictionary:
		return null
	if data.get("format") != FORMAT or int(data.get("version", 0)) != VERSION:
		return null
	var positions = data.get("positions")
	var headings = data.get("headings")
	var strengths = data.get("strengths")
	var lengths = data.get("lengths")
	var widths = data.get("widths")
	if not (positions is PackedVector2Array and headings is PackedFloat32Array
			and strengths is PackedFloat32Array and lengths is PackedFloat32Array
			and widths is PackedFloat32Array):
		return null
	var n: int = positions.size()
	if headings.size() != n or strengths.size() != n or lengths.size() != n \
			or widths.size() != n:
		return null
	var trail := TrackTrail.new(float(data.get("cell_size", 8.0)))
	for i in n:
		trail.add(positions[i], headings[i], strengths[i], lengths[i], widths[i])
	return trail


func save(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(to_bytes())
	file.close()
	return OK


## The trail in a file written by `save()`, or null.
static func load(path: String) -> TrackTrail:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	return from_bytes(bytes)
