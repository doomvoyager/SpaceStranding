extends Node3D
## What float32 costs at 3x3-tile range, measured rather than reasoned about.
##
## Nine tiles of 4096 m is 12,288 m across. Centred, the far corner is about
## **8.7 km** out; uncentred it would be 12.3 km, and 4x4 would have been 11.6 km
## centred. Godot's default build is single precision, so the question is not
## whether error exists — it is whether it is big enough to see, and where.
##
## Three things are measured at each distance, because they fail differently:
##
##   1. **ULP** — the gap between representable floats. Arithmetic, exact, and
##      the floor under everything else.
##   2. **Resting jitter** — a settled rigid body's residual motion. This is the
##      one that decides the answer. Physics solves in world space, so a
##      contact point resolved against a coarse grid buzzes, and a rover that
##      will not sit still at 8 km is a floating-origin conversation.
##   3. **Height query round trip** — `world_height_at` at a far X against the
##      same query at the origin on identical terrain. Separates "the ground
##      moved" from "the ground is noisy".
##
## What this does NOT measure is rendering: shadow acne, z-fighting and vertex
## swim need a window and an eye. If the numbers here are clean, that capture is
## the next step; if they are not, it is moot.
##
## Runs as a scene, not --script, because it needs autoloads and a physics space.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_float_precision.tscn

## Centred 3x3 corner, uncentred 3x3 corner, and a deliberately silly one so the
## trend is visible rather than inferred from two points.
const DISTANCES: Array[float] = [0.0, 4096.0, 8700.0, 12288.0, 40000.0]
const PATCH := 512.0
const SETTLE_FRAMES := 300
const SAMPLE_FRAMES := 60

var _rows: Array[Dictionary] = []
var _index := -1
var _frames := 0
var _terrain: ProceduralTerrain
var _body: RigidBody3D
var _samples: PackedFloat64Array
var _origin_heights := PackedFloat64Array()


func _ready() -> void:
	print("--- float32 at range: 3x3 tiles is 12,288 m, ~8.7 km to a centred corner ---")
	print("%10s %12s %14s %14s %12s" % ["distance", "ULP (m)", "jitter p2p (m)",
		"rest speed", "round trip"])
	_next()


## One terrain and one body per distance, built fresh. Moving a terrain means
## rebuilding its collision anyway, and a fresh pair keeps each row independent.
func _next() -> void:
	if _terrain != null:
		_terrain.queue_free()
		_body.queue_free()
	_index += 1
	if _index >= DISTANCES.size():
		_report()
		return

	var d: float = DISTANCES[_index]
	_terrain = ProceduralTerrain.new()
	_terrain.height_source = ProceduralTerrain.HeightSource.PROCEDURAL
	_terrain.size = PATCH
	_terrain.resolution = 4.0
	# **Flat.** The first version dropped the box on procedural relief and
	# measured 1.8 m of "jitter" at every distance including the origin - a box
	# sliding down a slope, with a rest speed of 2.4 m/s to say so. Terrain
	# shape swamped the effect being looked for by four orders of magnitude.
	_terrain.height_scale = 0.0
	_terrain.ridge_weight = 0.0
	# Diagonal, because error grows with the magnitude of each component and a
	# corner is where a square map is worst.
	var off := d / sqrt(2.0)
	_terrain.position = Vector3(off, 0.0, off)
	add_child(_terrain)

	_body = RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	_body.add_child(shape)
	# **Kept awake.** With sleeping left on, every row read exactly 0.0 for both
	# jitter and rest speed at every distance including 40 km - which is not a
	# clean result, it is Jolt parking the body and zeroing its velocity. The
	# probe was reporting whether the body was asleep. A resting contact only
	# shows solver noise while it is still being solved.
	_body.can_sleep = false
	# Dropped from just above the surface so it settles quickly and the numbers
	# are about resting contact rather than about the impact.
	_body.position = Vector3(off, _terrain.world_height_at(off, off) + 1.5, off)
	add_child(_body)

	_samples = PackedFloat64Array()
	_frames = 0


func _physics_process(_delta: float) -> void:
	if _terrain == null:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	if _samples.size() < SAMPLE_FRAMES:
		_samples.append(_body.global_position.y)
		return
	_record()
	_next()


func _record() -> void:
	var d: float = DISTANCES[_index]
	var off := d / sqrt(2.0)

	var lo := INF
	var hi := -INF
	for v: float in _samples:
		lo = minf(lo, v)
		hi = maxf(hi, v)

	# Coordinate round trip, which is where the transform actually loses bits:
	# a world point converted to the terrain's local space and back. Comparing
	# two height lookups instead was worthless - both sides went through the
	# same to_local, so it returned exact zero at 40 km and proved nothing.
	var worst := 0.0
	for i in 32:
		var p := Vector3(off + float(i) * 8.0 - 128.0, 12.34,
			off + float(i) * 3.0)
		var back := _terrain.to_global(_terrain.to_local(p))
		worst = maxf(worst, (back - p).length())

	_rows.append({
		"d": d,
		"ulp": _ulp(maxf(off, 1.0)),
		"jitter": hi - lo,
		"speed": _body.linear_velocity.length(),
		"herr": worst,
	})
	# Sanity: a body that fell through the world, or never touched it, also
	# reports no jitter. Print where it actually ended up.
	print("      [body y %s, ground %s, sleeping %s]" % [
		String.num(_body.global_position.y, 6),
		String.num(_terrain.world_height_at(off, off), 6),
		_body.sleeping])
	var r: Dictionary = _rows[_rows.size() - 1]
	print("%10.0f %12s %14s %14s %12s" % [r["d"],
		String.num(r["ulp"], 8), String.num(r["jitter"], 8),
		String.num(r["speed"], 6), String.num(r["herr"], 6)])


## The gap to the next representable float32 above v. float32 carries a 24-bit
## significand, so this is 2^(exponent - 23).
func _ulp(v: float) -> float:
	return pow(2.0, floor(log(v) / log(2.0)) - 23.0)


func _report() -> void:
	print("")
	var base: Dictionary = _rows[0]
	var corner: Dictionary = _rows[2]
	print("A centred 3x3 corner sits at 8.7 km, where one float32 step is %s m."
		% String.num(corner["ulp"], 8))
	print("Coordinate round trip there loses %s m." % String.num(corner["herr"], 8))
	print("Resting jitter there is %s m against %s m at the origin."
		% [String.num(corner["jitter"], 8), String.num(base["jitter"], 8)])
	# A tenth of a millimetre of buzz is under the width of the contact skin and
	# will not be seen; a millimetre starts showing on a parked vehicle.
	var verdict := "fine"
	if corner["jitter"] > 0.001 or corner["speed"] > 0.05:
		verdict = "MARGINAL - look at this before committing to 3x3"
	if corner["jitter"] > 0.01 or corner["speed"] > 0.2:
		verdict = "BAD - 3x3 needs a floating origin"
	print("Verdict at 8.7 km: %s" % verdict)
	print("")
	print("Rendering is not measured here. If the above is clean, the remaining")
	print("risk is shadow acne and vertex swim, which need a window and an eye.")
	get_tree().quit(0)
