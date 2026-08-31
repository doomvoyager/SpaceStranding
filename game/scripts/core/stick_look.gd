class_name StickLook
extends RefCounted
## Right-stick camera look, shared by the astronaut and the rover.
##
## Mouse look arrives as motion events and is handled in _unhandled_input. A
## stick reports a held position rather than a delta, so it has to be polled
## every frame instead. This lives here so both camera rigs turn at the same
## rate and clamp pitch the same way.


## The rotation the stick is asking for this frame, in radians: `x` is yaw and
## `y` is pitch, both already signed the way the rigs want them.
##
## Split out from `apply()` because the rover cannot keep its yaw in the pivot's
## rotation — that basis is rebuilt from scratch every frame to clamp the
## chassis tilt out of it, so the yaw has to live as a number the rover
## accumulates itself. The astronaut has no such problem and still uses
## `apply()`.
static func read(speed: float, delta: float) -> Vector2:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.is_zero_approx():
		return Vector2.ZERO
	return Vector2(-look.x, -look.y) * speed * delta


static func apply(
	pivot: Node3D,
	arm: Node3D,
	speed: float,
	pitch_min_deg: float,
	pitch_max_deg: float,
	delta: float
) -> void:
	var look := read(speed, delta)
	if look == Vector2.ZERO:
		return
	pivot.rotate_y(look.x)
	arm.rotate_x(look.y)
	arm.rotation.x = clampf(
		arm.rotation.x, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg)
	)
