class_name StickLook
extends RefCounted
## Right-stick camera look, shared by the astronaut and the rover.
##
## Mouse look arrives as motion events and is handled in _unhandled_input. A
## stick reports a held position rather than a delta, so it has to be polled
## every frame instead. This lives here so both camera rigs turn at the same
## rate and clamp pitch the same way.

static func apply(
	pivot: Node3D,
	arm: Node3D,
	speed: float,
	pitch_min_deg: float,
	pitch_max_deg: float,
	delta: float
) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.is_zero_approx():
		return
	pivot.rotate_y(-look.x * speed * delta)
	arm.rotate_x(-look.y * speed * delta)
	arm.rotation.x = clampf(
		arm.rotation.x, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg)
	)
