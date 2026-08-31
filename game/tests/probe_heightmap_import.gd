extends SceneTree
## How does Godot actually hand back the baked terrain heightfield?
##
## The bake (tools/bake-terrain.py) writes a single-channel 32-bit float EXR and
## verifies its own round-trip is bit-exact. That says nothing about what Godot's
## importer does to it on the way in, and the answer decides whether the terrain
## can trust the numbers: half-float would put ~0.4 m of quantisation on a 841 m
## relief span, which reads as faint terracing on gentle ground rather than as a
## bug.
##
## Also times the bulk readback, because `get_pixel()` per vertex over a 2049
## grid is four million calls in GDScript and the terrain rebuilds on a slider.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##       --script res://tests/probe_heightmap_import.gd

const PATH := "res://assets/terrain/world_01_height_2049.exr"

# Ground truth read straight out of the .exr by the bake tool's own reader.
const REFERENCE := [
	[0, 0, 0.17323235],
	[1024, 1024, 0.90154803],
	[2048, 2048, 0.19494864],
	[1536, 512, 0.17863843],
	[300, 700, 0.15560403],
]


func _init() -> void:
	var tex := load(PATH) as Texture2D
	if tex == null:
		print("FAIL: could not load ", PATH)
		quit(1)
		return

	var img := tex.get_image()
	print("size            ", img.get_size())
	print("format          ", img.get_format(), "  (8=RF 10=RGBF 12=RH 14=RGBH)")
	print("mipmaps         ", img.has_mipmaps())

	var worst := 0.0
	for r: Array in REFERENCE:
		var got := img.get_pixel(r[0], r[1]).r
		var err: float = absf(got - r[2])
		worst = maxf(worst, err)
		# No %e in GDScript's format, same trap as %g - String.num instead.
		print("px(%4d,%4d)  want %.8f  got %.8f  err " % [r[0], r[1], r[2], got],
			String.num(err, 10))
	print("worst pixel err ", String.num(worst, 10))

	# Bulk path: convert to single-channel float once, then read the whole
	# buffer as floats rather than calling get_pixel() per vertex.
	var t0 := Time.get_ticks_usec()
	var rf := Image.create_from_data(img.get_width(), img.get_height(), false,
		img.get_format(), img.get_data())
	rf.convert(Image.FORMAT_RF)
	var flat := rf.get_data().to_float32_array()
	var t1 := Time.get_ticks_usec()
	print("bulk readback   %d floats in %.1f ms" % [flat.size(), (t1 - t0) / 1000.0])

	var bulk_worst := 0.0
	var w := img.get_width()
	for r: Array in REFERENCE:
		var got: float = flat[int(r[1]) * w + int(r[0])]
		bulk_worst = maxf(bulk_worst, absf(got - r[2]))
	print("worst bulk err  ", String.num(bulk_worst, 10))

	# The terrain has to know the map's range to map it onto metres of relief.
	# Scanning 4.2M floats in GDScript is the obvious way and may be too slow to
	# sit in a rebuild, so check for a built-in first.
	# PackedFloat32Array is a builtin Variant type, not an Object: it has no
	# min()/max(), and no has_method() to probe with either - both are *parse*
	# errors, so guarding the call is not possible. A loop is the only option.
	var t3 := Time.get_ticks_usec()
	var lo := INF
	var hi := -INF
	for v in flat:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("scripted min/max %.6f..%.6f in %.1f ms"
		% [lo, hi, (Time.get_ticks_usec() - t3) / 1000.0])

	# Half-float would land around 5e-4 here; full float should be ~1e-8.
	var ok := worst < 1e-6 and bulk_worst < 1e-6
	print("RESULT: ", "PASS - full float preserved" if ok else "FAIL - precision lost")
	quit(0 if ok else 1)
	return
