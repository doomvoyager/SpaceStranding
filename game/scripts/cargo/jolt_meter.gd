extends RefCounted
class_name JoltMeter
## Measures **proper acceleration** from a stream of velocity samples — what an
## accelerometer bolted to a thing would actually read.
##
## Proper acceleration, not coordinate acceleration, because that is what cargo
## feels. In free fall an accelerometer reads zero and a falling crate is
## perfectly comfortable; the damage happens on the landing. Parked on the
## ground it reads one gravity. Subtracting the gravity vector is what buys us
## that distinction for free:
##
##     jolt = |dv/dt - g|
##
## Gravity is passed in rather than read from `World`, so the meter stays a pure
## function of its inputs and can be exercised from a probe that has no
## autoloads. Callers living in scenes read `World.gravity_vector()` and hand it
## over; the constant still lives in exactly one place.

## Gravity vector, m/s^2, pointing down. Set by the owner from World.
var gravity := Vector3.ZERO

## Time constant, seconds, for the smoothing applied to the raw signal.
##
## Not cosmetic. A CharacterBody3D landing has its velocity zeroed by
## `move_and_slide` in a single frame, so the raw signal is a one-frame spike
## whose height depends on the tick rate rather than on the severity of the
## landing. A rigid body's solver spreads the same event over several frames.
## Smoothing makes the two comparable, and models the real thing it stands in
## for: straps and packing have give, so cargo never feels an infinitely sharp
## edge. It is also what makes the damage integral meaningful — an impact is
## brief, and without smoothing it would be integrated over one frame.
var smoothing := 0.05

## Smoothed proper acceleration, m/s^2. This is the number to damage against.
var jolt := 0.0
## The current frame's unsmoothed value. Diagnostics only.
var raw_jolt := 0.0

var _last_velocity := Vector3.ZERO
var _primed := false


## Discard history. Call when the sampled thing teleports, is reparented, or
## otherwise changes velocity for reasons that are not physics — the velocity
## step across such a change is not a jolt anything experienced.
func reset(velocity := Vector3.ZERO) -> void:
	_last_velocity = velocity
	_primed = false
	jolt = 0.0
	raw_jolt = 0.0


## Feed one physics frame. Returns the smoothed jolt.
func sample(velocity: Vector3, delta: float) -> float:
	if delta <= 0.0:
		return jolt

	# The first sample has no predecessor, so it would read the whole of the
	# current velocity as a step change. Prime and report nothing.
	if not _primed:
		_last_velocity = velocity
		_primed = true
		return jolt

	var accel := (velocity - _last_velocity) / delta
	_last_velocity = velocity
	raw_jolt = (accel - gravity).length()

	# Exponential smoothing, framed in seconds so the tick rate cannot change
	# how much damage a given event does.
	var alpha := 1.0 - exp(-delta / maxf(smoothing, 0.0001))
	jolt = lerpf(jolt, raw_jolt, alpha)
	return jolt
