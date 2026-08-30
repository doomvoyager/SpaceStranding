extends CharacterBody3D
class_name Astronaut
## Third-person suited-astronaut controller tuned for 0.34 g.
##
## The low-gravity feel comes from three things, in order of importance:
##   1. Almost no air control. A jump is a commitment, not a steering input.
##   2. Slow ground acceleration. The suit has mass and the regolith has no grip.
##   3. Long hang time, which falls out of the project gravity setting for free.

@export_group("Movement")
## Comfortable suited walking pace, m/s.
@export var walk_speed := 3.2
## Assisted lope. The exo can push harder, but not indefinitely.
@export var sprint_speed := 6.4
## How hard we can push against the ground. Low: boots slip.
@export var ground_acceleration := 9.0
@export var ground_friction := 11.0
## Deliberately tiny. Once airborne you are ballistic.
@export var air_acceleration := 1.2

@export_group("Jump")
## Peak height in metres at this planet's gravity.
@export var jump_height := 1.9
## Grace period after leaving a ledge during which a jump still registers.
@export var coyote_time := 0.15

@export_group("Camera")
@export var mouse_sensitivity := 0.0022
@export_range(-80.0, 0.0) var pitch_min := -65.0
@export_range(0.0, 80.0) var pitch_max := 45.0
## How fast the body swings to face the direction of travel, radians/sec.
@export var turn_speed := 7.0

@onready var _cam_pivot: Node3D = $CamPivot
@onready var _spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _body: Node3D = $Body
@onready var _interact_zone: Area3D = $InteractZone

var _time_since_grounded := 0.0
var _mouse_captured := false
## True while we are sitting in a vehicle; suppresses our own look and interact.
var _driving := false


func _ready() -> void:
	_capture_mouse(true)


func _capture_mouse(captured: bool) -> void:
	_mouse_captured = captured
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		_capture_mouse(not _mouse_captured)
		return

	# While driving, the vehicle owns the camera and the interact key.
	if _driving:
		return

	if event is InputEventMouseMotion and _mouse_captured:
		_cam_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x,
			deg_to_rad(pitch_min),
			deg_to_rad(pitch_max)
		)

	if event.is_action_pressed("interact"):
		_try_enter_rover()


func _physics_process(delta: float) -> void:
	var grounded := is_on_floor()
	_time_since_grounded = 0.0 if grounded else _time_since_grounded + delta

	if not grounded:
		velocity.y -= World.SURFACE_GRAVITY * delta

	if Input.is_action_just_pressed("jump") and _time_since_grounded <= coyote_time:
		# v = sqrt(2 * g * h)
		velocity.y = sqrt(2.0 * World.SURFACE_GRAVITY * jump_height)
		_time_since_grounded = coyote_time + 1.0  # consume the coyote window

	_apply_horizontal_movement(delta, grounded)
	move_and_slide()
	_face_travel_direction(delta)


func _apply_horizontal_movement(delta: float, grounded: bool) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Movement is relative to where the camera is looking, not where the body faces.
	var basis := _cam_pivot.global_transform.basis
	var wish_dir := (basis.x * input.x + basis.z * input.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_acceleration if grounded else air_acceleration
	var target := wish_dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if wish_dir.is_zero_approx() and grounded:
		horizontal = horizontal.move_toward(Vector3.ZERO, ground_friction * delta)
	else:
		horizontal = horizontal.move_toward(target, accel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _face_travel_direction(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.04:
		return
	var target_yaw := atan2(-horizontal.x, -horizontal.z)
	_body.rotation.y = rotate_toward(_body.rotation.y, target_yaw, turn_speed * delta)


# --- Vehicles -----------------------------------------------------------

func _try_enter_rover() -> void:
	for body in _interact_zone.get_overlapping_bodies():
		if body.is_in_group("rover") and body.has_method("enter"):
			body.enter(self)
			# Stop the same press reaching the rover, which would exit immediately.
			get_viewport().set_input_as_handled()
			return


## Called by the rover when we climb in.
func board_vehicle() -> void:
	_driving = true
	set_physics_process(false)
	_camera.current = false
	visible = false
	# Stop colliding so the rover does not shove a ghost body around.
	collision_layer = 0
	collision_mask = 0


## Called by the rover when we climb out, at the given world position.
func disembark(at: Vector3) -> void:
	_driving = false
	global_position = at
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	visible = true
	_camera.current = true
	set_physics_process(true)
