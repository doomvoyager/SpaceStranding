extends Node3D
## What slope the rover can actually get up.
##
## The scanner paints ground red for "difficult", and that word is only worth
## anything if it means *you will not drive up that* rather than *this is
## steepish*. So the threshold is measured here rather than picked: put the
## loaded rover on a slope of a known angle, full throttle, and see whether it
## makes height.
##
## **The rover does not stall.** The first working run climbed every angle up to
## 36 degrees, so a climbed/stalled verdict says nothing: what actually happens
## is that progress falls away smoothly. So the measure is *how far it gets
## up-slope in a fixed run*, against the same run on the flat, and "difficult"
## is where that falls by half.
##
## One long box rotated about X, with the rover placed **on its surface** and
## aligned to it — rather than a flat apron meeting a separate ramp, which is
## what the first version did and which put the rover down beside the ramp
## instead of on it. Eight angles, 0.00 m on every one, and nothing in the
## output said why.
##
## Sampling the procedural terrain for a slope would have been worse again: the
## angle varies along the climb, so the number would not be reproducible.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_rover_climb.tscn

## Zero first: it is the baseline every other row is measured against.
const ANGLES := [0.0, 8.0, 16.0, 24.0, 32.0, 40.0, 48.0, 56.0]
## Fraction of the flat-ground run below which a slope counts as difficult.
const HARD_FRACTION := 0.5
## Physics frames per attempt: a few to settle, then throttle.
const SETTLE_FRAMES := 40
const DRIVE_FRAMES := 300
## Half the ramp's thickness, so the surface can be worked out from the centre.
const RAMP_HALF := 1.0
## How far down-slope of centre the rover starts.
const START_DOWN := 40.0

var _rover: Rover
var _ramp: StaticBody3D
var _index := -1
var _frames := 0
var _start_point := Vector3.ZERO
## Unit vector pointing up the slope, along the surface.
var _uphill := Vector3.FORWARD
var _results: Array = []


func _ready() -> void:
	_ramp = StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, RAMP_HALF * 2.0, 220.0)
	col.shape = shape
	_ramp.add_child(col)
	add_child(_ramp)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	add_child(_rover)

	# The rover ignores the throttle entirely with no driver, which is what the
	# first run of this probe measured: eight ramps, 0.00 m on every one.
	var astronaut: Astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	astronaut.position = Vector3(60.0, 2.0, 0.0)
	add_child(astronaut)
	_rover.enter(astronaut)

	# Loaded, because an empty rover is not the case anybody drives.
	for i in 4:
		var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
		add_child(crate)
		_rover.cargo_rack().load_crate(crate)
	_rover.refresh_load()

	print("loaded rover: %.0f kg, %d crates, %.0f N engine"
		% [_rover.mass, _rover.cargo_rack().count(), _rover.max_engine_force])
	print("")
	print("%8s %12s %10s %12s" % ["slope", "up-slope", "climbed", "vs flat"])
	_next()


func _next() -> void:
	_index += 1
	if _index >= ANGLES.size():
		_report()
		return

	# Rotating about +X by +angle tips the box so its surface rises toward -Z,
	# which is the direction the rover drives.
	#
	# The sign matters and was wrong first time round: with -angle the rover sat
	# on the slope facing *downhill*, and since only height gained is measured,
	# eight angles reported a flat 0.00 m. A stall and a descent look identical
	# to a peak-height measurement, so the direction is asserted below rather
	# than trusted.
	var radians := deg_to_rad(float(ANGLES[_index]))
	var basis := Basis(Vector3.RIGHT, radians)
	_ramp.transform = Transform3D(basis, Vector3.ZERO)

	# Exactly on the surface, START_DOWN metres down-slope, aligned to it.
	var surface := basis * Vector3(0.0, RAMP_HALF, START_DOWN)
	_rover.global_transform = Transform3D(basis, surface + basis.y * 1.1)
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO
	_rover.cargo_rack().reset_jolt()
	_start_point = _rover.global_position
	_uphill = (basis * Vector3.FORWARD).normalized()
	_frames = 0

	# The rover drives toward its own -Z. If that is not gaining height, the
	# ramp is upside down and every row below would read as a stall.
	if ANGLES[_index] > 0.0 and _uphill.y <= 0.0:
		printerr("ramp at %.0f faces downhill (forward.y = %.3f); results are meaningless"
			% [ANGLES[_index], _uphill.y])


func _physics_process(_delta: float) -> void:
	if _index < 0 or _index >= ANGLES.size():
		return
	_frames += 1

	if _frames == SETTLE_FRAMES:
		# Measured from where it has settled, so the drop onto the surface is
		# counted as neither progress nor a loss.
		_start_point = _rover.global_position
		Input.action_press("drive_forward")
	if _frames < SETTLE_FRAMES + DRIVE_FRAMES:
		return

	Input.action_release("drive_forward")
	var degrees: float = ANGLES[_index]
	# Distance along the slope, not height: at zero degrees height says nothing
	# and the baseline is the row everything else is compared against.
	var along := (_rover.global_position - _start_point).dot(_uphill)
	var climbed := along * sin(deg_to_rad(degrees))
	var baseline := float(_results[0][1]) if not _results.is_empty() else along
	_results.append([degrees, along, climbed])
	print("%7.0f° %10.1f m %9.2f m %11.0f%%"
		% [degrees, along, climbed, 100.0 * along / maxf(baseline, 0.001)])
	_next()


func _report() -> void:
	var baseline := float(_results[0][1])
	var threshold := baseline * HARD_FRACTION
	# Linear interpolation between the two rows that straddle the threshold, so
	# the answer is not quantised to whichever angles happen to be in the list.
	var hard_at := -1.0
	for i in range(1, _results.size()):
		var prev: Array = _results[i - 1]
		var here: Array = _results[i]
		if float(prev[1]) >= threshold and float(here[1]) < threshold:
			var span := float(prev[1]) - float(here[1])
			var t := (float(prev[1]) - threshold) / maxf(span, 0.001)
			hard_at = lerpf(float(prev[0]), float(here[0]), t)
			break

	print("")
	print("flat run %.1f m in %d frames; half of that is %.1f m"
		% [baseline, DRIVE_FRAMES, threshold])
	if hard_at < 0.0:
		print("progress never halves inside %.0f degrees - widen ANGLES."
			% float(_results[-1][0]))
		get_tree().quit()
		return

	print("progress halves at %.1f degrees" % hard_at)
	print("")
	print("scanner.max_slope_deg wants %.0f." % round(hard_at))
	print("The rover does not stall on any of these - it slows. So red means")
	print("'this will cost you half your speed or worse', which is the honest")
	print("thing a slope colour can promise.")
	get_tree().quit()
