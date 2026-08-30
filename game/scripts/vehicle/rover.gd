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
## Above this speed (m/s) steering authority is reduced to the floor value below.
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

@onready var _cam_pivot: Node3D = $CamPivot
@onready var _spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _exit_point: Marker3D = $ExitPoint
@onready var _rack: CargoRack = $CargoRack

var driver: Astronaut = null
var _steer_target := 0.0
## Kerb mass, captured from the inspector value before any cargo is counted.
var _empty_mass := 950.0


func _ready() -> void:
	add_to_group("rover")
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# `mass` in the inspector is the *empty* rover; cargo is added on top.
	_empty_mass = mass
	refresh_load()
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x,
			deg_to_rad(pitch_min),
			deg_to_rad(pitch_max)
		)

	if event.is_action_pressed("interact"):
		exit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if driver == null:
		return
	StickLook.apply(
		_cam_pivot, _spring_arm, stick_sensitivity, pitch_min, pitch_max, delta
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
	# Speed-sensitive steering. At speed, full lock in 0.34 g puts you on your roof.
	var speed := linear_velocity.length()
	var authority := lerpf(
		1.0,
		steer_falloff_floor,
		clampf(speed / steer_falloff_speed, 0.0, 1.0)
	)
	_steer_target = steer_input * deg_to_rad(max_steer_angle) * authority
	steering = move_toward(steering, _steer_target, steer_speed * delta)


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
