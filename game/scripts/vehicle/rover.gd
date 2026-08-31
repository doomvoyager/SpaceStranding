extends VehicleBody3D
class_name Rover
## Six-wheel pressurised hauler.
##
## Low gravity is unkind to vehicles. Tyre grip scales with normal force, so at
## 0.34 g the rover has roughly a third of the traction its mass suggests: it
## accelerates poorly, brakes worse, and would rather tip than skid. We lean into
## that rather than fighting it, and only compensate enough to keep it drivable.

## Godot's VehicleBody3D pushes toward +Z on a positive engine_force, while our
## chassis faces -Z like every other node in the engine. Without this the rover
## drives backwards, which also makes the steering read as inverted because you
## are watching it come at the camera. Measured, not guessed — see
## tests/probe_vehicle_axes.gd.
const ENGINE_FORCE_SIGN := -1.0

@export_group("Drivetrain")
## Newtons at the wheels. Modest — this is a work vehicle, not a car.
@export var max_engine_force := 900.0
@export var max_reverse_force := 450.0
@export var max_brake_force := 26.0
## Passive drag when the throttle is released, in brake units.
@export var engine_braking := 2.5
## Below this forward speed (m/s), the decelerate input stops braking and starts
## reversing. Above it, holding LT or S slows you down instead of fighting the
## wheels with reverse torque - which at a third of Earth's grip just spins them.
@export var reverse_threshold := 0.6

@export_group("Steering")
@export_range(0.0, 60.0) var max_steer_angle := 32.0
## Radians/sec the wheels can be turned. Deliberately slow: hydraulic, loaded.
@export var steer_speed := 1.6
## Below this speed (m/s) you get the full lock, and the falloff does not bite
## at all. Without the dead band the ramp starts at a standstill, so the first
## metre per second already eats your lock and the throttle reads as if it were
## stealing the steering. Measured: tests/probe_steer_under_throttle.gd.
@export var steer_falloff_start := 5.0
## By this speed (m/s) steering authority has fallen to the floor value below.
@export var steer_falloff_speed := 14.0
@export_range(0.1, 1.0) var steer_falloff_floor := 0.35

@export_group("Load")
## Where the mass sits when the rack is empty. Low in the chassis, so the rover
## resists rolling on side slopes — and so a loaded roof rack has something to
## fight against.
@export var empty_center_of_mass := Vector3(0.0, -0.35, 0.0)

@export_group("Camera")
@export var mouse_sensitivity := 0.0022
## Right-stick turn rate, radians/sec.
@export var stick_sensitivity := 2.6
@export_range(-80.0, 0.0) var pitch_min := -50.0
@export_range(0.0, 80.0) var pitch_max := 40.0

@export_subgroup("Levelling")
## How far the camera may leave horizontal, in degrees.
##
## The rig hangs off the chassis, so left alone it inherits every degree of roll
## and pitch the body has — put the rover on its roof and the horizon goes with
## it. The camera should still lean while driving, which is what makes a side
## slope read as a side slope, so this clamps rather than levels.
@export_range(0.0, 90.0, 0.5) var tilt_limit_deg := 18.0
## Fraction of the chassis's tilt the camera takes before the limit bites. 1
## tracks the body exactly up to the limit and then stops dead; lower values
## lean more gently and only reach the limit in real trouble.
@export_range(0.0, 1.0, 0.01) var tilt_follow := 1.0
## Seconds for the camera's tilt to catch up with the chassis. Suspension
## chatter is high-frequency and the rig passes it straight through, so a small
## constant here is the difference between leaning and shaking. 0 is rigid.
@export_range(0.0, 1.0, 0.01) var tilt_smoothing := 0.12

@onready var _cam_pivot: Node3D = $CamPivot
@onready var _spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _exit_point: Marker3D = $ExitPoint
@onready var _rack: CargoRack = $CargoRack

var driver: Astronaut = null
## The player's own yaw, around the camera's up, in radians.
##
## Held as a number rather than as the pivot's rotation because the pivot's
## basis is rebuilt from scratch every frame — see `_level_camera()`.
var _look_yaw := 0.0
## The camera's up vector, chasing the clamped chassis up.
var _cam_up := Vector3.UP
## The camera mount, as authored on CamPivot in the scene. Held because the
## pivot's position is driven every frame and the authored value would
## otherwise be overwritten on the first one.
var _mount_offset := Vector3(0.0, 1.2, 0.0)
var _steer_target := 0.0
## Kerb mass, captured from the inspector value before any cargo is counted.
var _empty_mass := 950.0


func _ready() -> void:
	add_to_group("rover")
	_mount_offset = _cam_pivot.position
	# The arm must never be pushed in by the vehicle it is filming. Without
	# this the chassis is just another obstacle: on its roof the arm collapses
	# to nothing and the camera ends up inside the rover.
	_spring_arm.add_excluded_object(get_rid())
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# `mass` in the inspector is the *empty* rover; cargo is added on top.
	_empty_mass = mass
	refresh_load()
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw -= event.relative.x * mouse_sensitivity
		_pitch_by(-event.relative.y * mouse_sensitivity)

	if event.is_action_pressed("interact"):
		exit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if driver == null:
		return
	var look := StickLook.read(stick_sensitivity, delta)
	_look_yaw += look.x
	_pitch_by(look.y)
	_level_camera(delta)


## Pitch lives on the spring arm, below the levelling, so aiming up and down is
## unaffected by what the chassis is doing.
func _pitch_by(radians: float) -> void:
	if radians == 0.0:
		return
	_spring_arm.rotate_x(radians)
	_spring_arm.rotation.x = clampf(
		_spring_arm.rotation.x, deg_to_rad(pitch_min), deg_to_rad(pitch_max)
	)


## Rebuilds the camera pivot's orientation, with the chassis's tilt away from
## vertical clamped out of it.
##
## Rebuilt from scratch rather than counter-rotated: a correction written back
## into the same local basis it was read from compounds frame on frame. So the
## basis is assembled from three parts instead — a clamped up vector, the
## chassis heading projected into that plane so the camera still sits behind the
## rover through a turn, and the player's own yaw on top.
##
## The pivot stays a child of the body, so it still rides with the suspension
## and only its *orientation* is levelled.
func _level_camera(delta: float) -> void:
	var target_up := _clamped_up()
	# A time constant in seconds, so the response is the same at any tick rate.
	var k := 1.0 if tilt_smoothing <= 0.0 else 1.0 - exp(-delta / tilt_smoothing)
	_cam_up = _cam_up.slerp(target_up, k).normalized()

	var up := _cam_up
	var fwd := -global_basis.z
	fwd -= up * fwd.dot(up)
	if fwd.length_squared() < 1e-6:
		# Nose straight up or down: the roof is the only heading left to use.
		fwd = global_basis.y
		fwd -= up * fwd.dot(up)
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var levelled := Basis(fwd.cross(up).normalized(), up, -fwd)

	# The mount hangs off the *levelled* basis, not the chassis's. Left in body
	# space it follows the roll it is there to ignore, so an inverted rover puts
	# the camera under itself and the arm sweeps into the ground. Yaw is
	# deliberately not applied here - the mount stays put on the vehicle while
	# only the view turns around it.
	_cam_pivot.global_position = global_position + levelled * _mount_offset
	_cam_pivot.global_basis = levelled.rotated(up, _look_yaw)


## World up, rotated toward the chassis's up by the followed fraction of its
## tilt and never past the limit.
func _clamped_up() -> Vector3:
	var chassis_up := global_basis.y.normalized()
	var tilt := Vector3.UP.angle_to(chassis_up)
	if tilt < 1e-5:
		return Vector3.UP
	var axis := Vector3.UP.cross(chassis_up)
	if axis.length_squared() < 1e-8:
		# Dead upside down, so every axis is perpendicular and the cross product
		# gives none: take the chassis's own right and roll out the short way.
		axis = global_basis.x
	return Vector3.UP.rotated(
		axis.normalized(), minf(tilt * tilt_follow, deg_to_rad(tilt_limit_deg))
	)


func _physics_process(delta: float) -> void:
	if driver == null:
		return

	# Throttle is deliberately NOT move_forward/move_back: those carry the left
	# stick for the astronaut on foot, and in the rover the stick steers only.
	# RT and LT are analog, so get_axis returns a real pedal position.
	var throttle := Input.get_axis("drive_back", "drive_forward")
	var steer_input := Input.get_axis("move_right", "move_left")
	var braking := Input.is_action_pressed("brake")

	_apply_steering(steer_input, delta)
	_apply_drivetrain(throttle, braking)


func _apply_steering(steer_input: float, delta: float) -> void:
	_steer_target = steer_input * deg_to_rad(max_steer_angle) * steer_authority()
	steering = move_toward(steering, _steer_target, steer_speed * delta)


## Fraction of full lock available at the current speed. Full below
## steer_falloff_start, ramping to steer_falloff_floor by steer_falloff_speed.
## At speed, full lock in 0.34 g puts you on your roof - but manoeuvring speed
## has to keep the lock, or parking and turning around feel broken.
func steer_authority() -> float:
	var speed := linear_velocity.length()
	var span := maxf(steer_falloff_speed - steer_falloff_start, 0.001)
	var t := clampf((speed - steer_falloff_start) / span, 0.0, 1.0)
	return lerpf(1.0, steer_falloff_floor, t)


func _apply_drivetrain(throttle: float, braking: bool) -> void:
	if braking:
		engine_force = 0.0
		brake = max_brake_force
		return

	if is_zero_approx(throttle):
		engine_force = 0.0
		brake = engine_braking
	elif throttle > 0.0:
		engine_force = ENGINE_FORCE_SIGN * throttle * max_engine_force
		brake = 0.0
	elif forward_speed() > reverse_threshold:
		# Still rolling forward: the decelerate pedal is a brake, not reverse.
		engine_force = 0.0
		brake = -throttle * max_brake_force
	else:
		engine_force = ENGINE_FORCE_SIGN * throttle * max_reverse_force
		brake = 0.0


## Speed along the rover's own forward axis. Negative while reversing.
func forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z)


# --- Load ---------------------------------------------------------------

func cargo_rack() -> CargoRack:
	return _rack


## Recompute mass and centre of mass from what is actually on the rack. Called
## by the astronaut after every transfer — cheap, and it means occupancy has
## exactly one source of truth: the scene tree.
##
## Six crates is roughly +22% mass, and because they sit on the roof the centre
## of mass climbs toward them. Load one side only and it moves sideways too,
## which at 0.34 g is the difference between a corner and a slow roll.
func refresh_load() -> void:
	var cargo := _rack.load_mass()
	mass = _empty_mass + cargo
	if cargo <= 0.0:
		center_of_mass = empty_center_of_mass
		return
	center_of_mass = (
		_empty_mass * empty_center_of_mass + cargo * _rack.load_centroid()
	) / mass


# --- Boarding -----------------------------------------------------------

func enter(astronaut: Astronaut) -> void:
	if driver != null:
		return
	driver = astronaut
	astronaut.board_vehicle()
	# Start level with whatever the rover is sitting on rather than easing in
	# from wherever the camera was left at the end of the last drive.
	_cam_up = _clamped_up()
	_camera.current = true
	set_physics_process(true)


func exit() -> void:
	if driver == null:
		return
	var astronaut := driver
	driver = null
	set_physics_process(false)
	engine_force = 0.0
	brake = max_brake_force
	steering = 0.0
	_camera.current = false
	astronaut.disembark(_exit_point.global_position)
