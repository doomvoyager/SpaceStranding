class_name StickLook
extends RefCounted
## Right-stick camera look, shared by the astronaut and the rover.
##
## Mouse look arrives as motion events and is handled in _unhandled_input. A
## stick reports a held position rather than a delta, so it has to be polled
## every frame instead. This lives here so both camera rigs turn at the same
## rate.


## The rotation the stick is asking for this frame, in radians: `x` is yaw and
## `y` is pitch, both already signed the way the rigs want them.
##
## Deltas rather than writes to a node, because neither rig can take them
## straight. The rover rebuilds its pivot's basis from scratch every frame to
## clamp the chassis tilt out of it, so its yaw lives as a number it
## accumulates itself; and both rigs pitch two cameras at once - the chase arm
## and a first-person eye - so the clamp is theirs to apply, in one place each.
static func read(speed: float, delta: float) -> Vector2:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.is_zero_approx():
		return Vector2.ZERO
	return Vector2(-look.x, -look.y) * speed * delta
