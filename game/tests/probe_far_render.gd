extends Node3D
## Does the world still *render* correctly 8.7 km from the origin?
##
## `probe_float_precision` answers the arithmetic and the physics — 0.49 mm per
## float step at a centred 3x3 corner, an exact coordinate round trip, and a
## resting body that does not buzz even at 40 km. None of that clears the
## rendering, which is where single precision usually shows first and which
## `--headless` cannot see at all: shadow-map acne, depth fighting on shallow
## surfaces, and vertices visibly snapping as the camera moves.
##
## So: instantiate the real world, translate **the whole thing** — terrain,
## lights, props, camera — and render the same framing at each distance. Moving
## everything together is what keeps this a precision test rather than a test of
## a scene that has been pulled apart.
##
## Windowed on purpose. Run:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_far_render.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT := "user://far_render"
## Origin, a centred 3x3 corner, and one well past it so a trend is visible.
const DISTANCES: Array[float] = [0.0, 8700.0, 40000.0]
## Camera framing, relative to whatever the world has been shifted by.
const EYE := Vector3(26.0, 3.2, 22.0)
const LOOK := Vector3(0.0, 1.0, 0.0)

var _world: Node3D
var _cam: Camera3D
var _index := -1
var _frames := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_world = WORLD.instantiate()
	add_child(_world)
	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 20000.0
	add_child(_cam)
	print("--- rendering at range: same framing, whole world translated ---")


func _process(_delta: float) -> void:
	_frames += 1
	# Let the world build its terrain and settle its props before the first
	# shot; a half-built patch would read as a precision artefact.
	if _frames < 150:
		return
	if _frames % 40 != 0:
		return
	if _index >= 0:
		_shoot()
	_index += 1
	if _index >= DISTANCES.size():
		print("wrote %d frames to %s" % [DISTANCES.size(), OUT])
		get_tree().quit(0)
		return
	_place()


func _place() -> void:
	var d: float = DISTANCES[_index]
	var off := d / sqrt(2.0)
	var shift := Vector3(off, 0.0, off)
	_world.global_position = shift
	_cam.global_position = EYE + shift
	_cam.look_at(LOOK + shift, Vector3.UP)


func _shoot() -> void:
	var d: float = DISTANCES[_index]
	var image := get_viewport().get_texture().get_image()
	var name := "%s/at_%05d_m.png" % [OUT, int(d)]
	image.save_png(name)
	# A mean and a spread give the comparison something numeric to stand on, so
	# "it looks the same" is not the only claim being made.
	var total := 0.0
	var lo := 1.0
	var hi := 0.0
	var w := image.get_width()
	var h := image.get_height()
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var v := image.get_pixel(x, y).get_luminance()
			total += v
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var n := float(int(h / 4.0) * int(w / 4.0))
	print("  %8.0f m   mean luma %s   range %s..%s" % [d,
		String.num(total / n, 5), String.num(lo, 4), String.num(hi, 4)])
