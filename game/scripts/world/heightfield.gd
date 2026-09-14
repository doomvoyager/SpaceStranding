class_name Heightfield
extends RefCounted
## A resident grid of heights in metres, and the one function the ground is.
##
## **The heights cannot be streamed, only the meshes can.** The Lattice traces
## line of sight to relays kilometres away, the route planner samples across
## the map and the map panel draws all of it, so `world_height_at` has to
## answer anywhere at any time. This holds the whole window - 97 MB for
## 24.6 km at 5 m - and `StreamedTerrain` builds its tiles by sampling it.
##
## **Not a texture, on purpose.** Godot's EXR importer expands one float
## channel to three, so the same window as a `CompressedTexture2D` would be
## 290 MB and carry the `detect_3d` trap with it. `tools/lola-window.py --raw`
## writes the format read here: a 32-byte header, then little-endian float32
## rows, north up. See the writer for the layout.
##
## Read-only once loaded, which is what lets worker threads sample it while
## tiles are built off the main thread - nothing ever writes to `data` after
## `load_file` or `from_data` returns.

const MAGIC := "SSHF"
const HEADER_BYTES := 32

var data: PackedFloat32Array
var width := 0
var height := 0
## Metres between samples.
var spacing := 1.0
var lowest := 0.0
var highest := 0.0
var path := ""


## Reads a `.hf` file. Returns null, with the reason pushed as an error, when
## the file is missing or not what the header claims - never a flat field,
## because a plane reads as "the map has not loaded yet" and gets ignored.
static func load_file(file_path: String) -> Heightfield:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		push_error("Heightfield: cannot open %s (%s)"
			% [file_path, error_string(FileAccess.get_open_error())])
		return null
	if f.get_buffer(4).get_string_from_ascii() != MAGIC:
		push_error("Heightfield: %s is not a heightfield (bad magic)" % file_path)
		return null
	var hf := Heightfield.new()
	hf.path = file_path
	hf.width = f.get_32()
	hf.height = f.get_32()
	hf.spacing = f.get_float()
	hf.lowest = f.get_float()
	hf.highest = f.get_float()
	f.seek(HEADER_BYTES)
	var count := hf.width * hf.height
	hf.data = f.get_buffer(count * 4).to_float32_array()
	if hf.data.size() != count:
		push_error("Heightfield: %s holds %d samples, header says %d x %d"
			% [file_path, hf.data.size(), hf.width, hf.height])
		return null
	return hf


## A field from values in hand, for tests and probes that want relief with no
## 97 MB dependency. `values` is row-major, `w` samples per row.
static func from_data(values: PackedFloat32Array, w: int, h: int,
		metres_per_sample: float) -> Heightfield:
	if values.size() != w * h:
		push_error("Heightfield.from_data: %d values for %d x %d" % [values.size(), w, h])
		return null
	var hf := Heightfield.new()
	hf.data = values
	hf.width = w
	hf.height = h
	hf.spacing = metres_per_sample
	hf.lowest = INF
	hf.highest = -INF
	for v in values:
		hf.lowest = minf(hf.lowest, v)
		hf.highest = maxf(hf.highest, v)
	return hf


func is_loaded() -> bool:
	return width > 1 and height > 1 and data.size() == width * height


## Metres the field spans along X: samples minus one, times the spacing.
func span_x() -> float:
	return float(width - 1) * spacing


func span_z() -> float:
	return float(height - 1) * spacing


## The field's footprint in its own centred coordinates: (0, 0) is the middle
## sample, X east across columns, Z south down rows.
func rect() -> Rect2:
	return Rect2(-span_x() * 0.5, -span_z() * 0.5, span_x(), span_z())


func height_at_index(x: int, z: int) -> float:
	x = clampi(x, 0, width - 1)
	z = clampi(z, 0, height - 1)
	return data[z * width + x]


## Bilinear height at a centred local position, metres. Clamped at the edges,
## so a query a metre off the field gives the edge's height rather than zero -
## the same rule the single patch had.
func height_at(local_x: float, local_z: float) -> float:
	var fx := (local_x + span_x() * 0.5) / spacing
	var fz := (local_z + span_z() * 0.5) / spacing
	var x0 := int(floorf(fx))
	var z0 := int(floorf(fz))
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	return lerpf(
		lerpf(height_at_index(x0, z0), height_at_index(x0 + 1, z0), tx),
		lerpf(height_at_index(x0, z0 + 1), height_at_index(x0 + 1, z0 + 1), tx),
		tz
	)
