extends VehicleBody3D
class_name Rover
## Six-wheel pressurised hauler.
##
## Low gravity is unkind to vehicles. Tyre grip scales with normal force, so at
## 0.55 g the rover has roughly half the traction its mass suggests: it
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
##
## Was 900 when the planet was 0.34 g. It does not survive the move to 0.55 g:
## the extra weight costs more in rolling resistance and in climbing out of
## undulations than the extra grip gives back, and ten seconds of full throttle
## over broken ground fell from 4.7 m/s and 29 m to **1.9 m/s and 7 m** — a
## hauler that can no longer haul. Bisected against the old figures with
## tests/probe_carrier_jolt.tscn: 1170 restores the same 29 m with the load
## still pristine, while 1450 covers 37 m and starts scuffing cargo on an
## ordinary drive. Peak speed comes out livelier than it was (6.5 against 4.7)
## because the added grip pays off on the clear stretches.
@export var max_engine_force := 1170.0
## Scaled with the engine by the same 1.3, so the drivetrain keeps its shape.
## Unlike the forward figure this one is reasoned, not measured — no probe
## drives the rover backwards.
@export var max_reverse_force := 585.0
@export var max_brake_force := 26.0
## Passive drag when the throttle is released, in brake units.
@export var engine_braking := 2.5
## Below this forward speed (m/s), the decelerate input stops braking and starts
## reversing. Above it, holding LT or S slows you down instead of fighting the
## wheels with reverse torque - which at just over half Earth's grip still
## spins them.
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

@export_group("Brake light")
## The bar that lights up when the driver asks the rover to slow down.
##
## A path rather than a hardcoded `$BrakeLightBar` so the bar can be moved,
## renamed or replaced with better geometry without touching this script. The
## *colour* of the light lives on the mesh's own material, in the inspector,
## where the person choosing it can see it; this script drives only its
## brightness.
@export var brake_light_path: NodePath = ^"BrakeLightBar"
## Emission energy while the light is on.
##
## **Low, and it has to be.** ACES tonemapping desaturates hardest where the
## image is brightest, so past about 1.2 a saturated red stops being red and
## becomes an orange-white smear that spills over the whole hull - the same
## trap the [[Visual-Direction]] overlays hit. Swept against the real scene at
## twilight, which is the brightest ambient this planet ever has:
##
## | energy | reads as |
## |---|---|
## | 0.5 | red, but flat - paint, not a lamp |
## | **0.9** | **red, with just enough bloom to read as lit** |
## | 1.4 | washing out through the middle of the bar |
## | 5.0 | orange-white, and the hull glows with it |
##
## Re-run `tests/brake_light_capture.tscn` rather than reasoning about it.
@export_range(0.0, 4.0, 0.05) var brake_light_energy := 0.9
## Emission energy the rest of the time. 0 is a dead lens; a small value gives
## the rover a permanent tail light instead.
@export_range(0.0, 4.0, 0.05) var brake_light_idle_energy := 0.0
## Whether the decelerate pedal lights the bar once it has become reverse.
##
## That pedal is a brake above `reverse_threshold` and reverse below it, and
## both are the driver asking not to go forward - so by default the bar follows
## the pedal rather than the force it produces, and does not blink off at the
## moment the rover comes to rest under it. A road vehicle would show white
## here instead; this is one bar.
@export var brake_light_on_reverse := true

@export_group("Rollover recovery")
## Degrees away from upright past which the rover counts as rolled over.
##
## Comfortably past anything driving produces: the speed-sensitive steering
## exists to stop you reaching this, and a side slope steep enough to matter is
## still well under it. It is a wreck, not a lean.
@export_range(30.0, 179.0, 1.0) var rollover_angle_deg := 70.0
## Speed, m/s, below which a rolled rover will accept being righted. A rover
## still tumbling is not something you can get a shoulder under.
@export_range(0.0, 5.0, 0.1) var recovery_max_speed := 1.0
## Seconds the righting takes once it commits.
##
## Slow on purpose. The rover is moved by hand through this rather than by
## physics, so the number is a straight statement of how long a flip costs you
## - and it is the whole reason a full rack survives the recovery. See
## [[Rover]] for the measured jolt.
@export_range(0.2, 10.0, 0.1) var righting_duration := 2.4
## How far above solved ground the wheels are set down, in metres. Small: the
## rover is let go from here, and the drop is the only part of a recovery
## physics sees.
@export_range(0.0, 1.0, 0.01) var righting_clearance := 0.08
## How far up and down to look for the ground the rover is being set on.
@export_range(1.0, 40.0, 0.5) var righting_probe_reach := 12.0
## How far above solved ground the driver is put down when they climb out. The
## astronaut's origin is at its feet, so this is a small number.
@export_range(0.0, 1.0, 0.01) var exit_clearance := 0.1

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
## The bar's own material, duplicated in _ready so that two rovers cannot light
## each other's bar. Null if the bar is missing or is not standard-shaded.
var _brake_material: StandardMaterial3D
## Whether the bar is lit right now. Read by `brake_light_on()`.
var _brake_lit := false
## Whether a righting is in progress. While it is, the body is kinematic and
## this script is driving its transform - physics is not.
var _righting := false
var _righting_elapsed := 0.0
var _righting_from := Transform3D.IDENTITY
var _righting_to := Transform3D.IDENTITY
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
	_setup_brake_light()
	set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return

	# Nothing the rover binds should fire from behind a full-screen panel — E
	# would climb out of it while you were reading the map.
	if driver.is_menu_open():
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
	# Ahead of the driver check on purpose: a recovery happens with nobody
	# aboard, and this is the one thing the rover does for itself.
	if _righting:
		_advance_righting(delta)
		return

	if driver == null:
		return

	# **Hands off while a panel has the screen.** The order board is only
	# reachable on foot at a terminal, so this never came up until the map got
	# its own key and could be opened at speed. The world keeps running — this
	# is not a pause — so the rover coasts under engine braking and holds the
	# steering it had, which is what letting go of the controls actually does.
	if driver.is_menu_open():
		_apply_drivetrain(0.0, false)
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
## At speed, full lock in 0.55 g puts you on your roof - but manoeuvring speed
## has to keep the lock, or parking and turning around feel broken.
func steer_authority() -> float:
	var speed := linear_velocity.length()
	var span := maxf(steer_falloff_speed - steer_falloff_start, 0.001)
	var t := clampf((speed - steer_falloff_start) / span, 0.0, 1.0)
	return lerpf(1.0, steer_falloff_floor, t)


func _apply_drivetrain(throttle: float, braking: bool) -> void:
	_set_brake_light(_wants_brake_light(throttle, braking))

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


## How fast the rover is travelling over the ground, signed by which way it is
## facing. This is what the speedometer reads.
##
## **Horizontal, not `linear_velocity.length()`.** The vertical component is not
## speed you are making toward anywhere, and folding it in means a rover dropped
## off a ledge reads faster the further it falls — a speedometer that peaks
## while you are in the air is reporting the wrong quantity at exactly the
## moment somebody is looking at it.
##
## The sign comes off `forward_speed()` rather than off the flat vector, so a
## rover sliding sideways down a slope still reads positive rather than
## flickering. Reversing is the only thing that makes it negative.
func ground_speed() -> float:
	var flat := Vector2(linear_velocity.x, linear_velocity.z).length()
	return -flat if forward_speed() < 0.0 else flat


# --- Rollover recovery --------------------------------------------------
#
# In 0.55 g a flipped rover used to be permanent, and a loaded roof rack makes
# flipping considerably easier - the load lifts the centre of mass from -0.35 to
# about -0.10, which is exactly the margin the low mass was buying. So a flip
# had to stop being a run-ending event without becoming a keypress.
#
# **The astronaut rights it from outside, by hand.** It is a job you climb out
# and do, which is why the verb is a hold rather than a press and why it lives
# on the astronaut. Nothing here starts itself.
#
# **The righting is driven, not thrown.** The obvious implementation is an
# angular impulse, and it is the wrong one: a 950 kg body in low gravity needs a
# large one to turn over at all, the amount depends on how it happens to be
# lying, and everything it does to the load is an accident. So the body is
# frozen kinematic and its transform is interpolated by hand over
# `righting_duration`, easing at both ends. The load rides through it feeling
# almost nothing, which is the point - a flip already cost you the crash.


## How far from upright the chassis is, as a dot product: 1 is level, 0 is on
## its side, -1 is on its roof.
func upright_dot() -> float:
	return global_basis.y.dot(Vector3.UP)


## Whether the rover is lying past `rollover_angle_deg`.
func is_rolled_over() -> bool:
	return upright_dot() < cos(deg_to_rad(rollover_angle_deg))


## Whether a recovery would be accepted right now. False mid-tumble, and false
## while one is already running.
func can_right() -> bool:
	if _righting:
		return false
	if not is_rolled_over():
		return false
	return linear_velocity.length() <= recovery_max_speed


## Whether a recovery is running.
func is_righting() -> bool:
	return _righting


## Start rolling the rover back onto its wheels. False if it will not accept
## one, so a caller never has to ask twice.
func begin_righting() -> bool:
	if not can_right():
		return false
	_righting = true
	_righting_elapsed = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Kinematic rather than static: the body still pushes what it meets on the
	# way over instead of passing through it.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_righting_from = global_transform
	_righting_to = Transform3D(_upright_basis(), _righting_landing())
	# The driver check below would otherwise leave this unticked with nobody
	# aboard, which is precisely when a recovery happens.
	set_physics_process(true)
	return true


func _advance_righting(delta: float) -> void:
	_righting_elapsed += delta
	var t := clampf(_righting_elapsed / maxf(righting_duration, 0.001), 0.0, 1.0)
	# Eased at both ends. A linear ramp starts and stops with a step change in
	# angular rate, and a step change is exactly what the load measures.
	var s := smoothstep(0.0, 1.0, t)
	global_transform = Transform3D(
		_righting_from.basis.slerp(_righting_to.basis, s),
		_righting_from.origin.lerp(_righting_to.origin, s)
	)
	if t < 1.0:
		return

	_righting = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# The documented thing to do after moving a carrier by hand. Measured to
	# change nothing here, because the velocities are zeroed two lines above
	# and there is no step left for the rack to read - kept because that is an
	# accident of the order, not a property of the recovery.
	_rack.reset_jolt()
	set_physics_process(driver != null)


## Level, facing wherever the rover was already pointing.
##
## Heading is kept rather than reset because it is the one thing about a wreck
## the player still has an opinion on - you flipped going somewhere.
func _upright_basis() -> Basis:
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		# Nose straight up or down, so the forward axis says nothing about
		# heading: the roof is the only direction left to read one from.
		fwd = global_basis.y
		fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	return Basis(fwd.cross(Vector3.UP).normalized(), Vector3.UP, -fwd)


## Where the chassis origin has to sit for the wheels to be just clear of the
## ground below it.
func _righting_landing() -> Vector3:
	# The sentinel is the rover's own position: nothing under it means it is
	# over a drop, or the probe was too short. Leave the origin where it is and
	# let physics sort the fall out - turning it the right way up is still
	# worth doing.
	var lift := Vector3.UP * (_wheel_drop() + righting_clearance)
	var ground := ground_below(global_position, global_position - lift)
	return ground + lift


## How far the lowest wheel's contact point sits below the chassis origin.
##
## Solved from the wheels rather than typed in, so moving a wheel or changing
## its radius cannot leave the rover set down buried or dropped from a height.
func _wheel_drop() -> float:
	var lowest := 0.0
	for child in get_children():
		var wheel := child as VehicleWheel3D
		if wheel == null:
			continue
		lowest = minf(lowest, wheel.position.y - wheel.wheel_radius)
	return -lowest


## The ground under `from`, or `fallback` if the probe finds none.
##
## The fallback is a parameter rather than a null return because a function
## returning `Variant` poisons `:=` at every call site - the inferred type
## becomes Variant and the parse fails two lines later, pointing at the
## variable rather than at this. Public because climbing out needs the same
## answer as setting the rover down - see `exit_position()`.
func ground_below(from: Vector3, fallback: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return fallback
	var top := from + Vector3.UP * righting_probe_reach
	var query := PhysicsRayQueryParameters3D.create(
		top, top + Vector3.DOWN * (righting_probe_reach * 2.0)
	)
	# The rover is not the ground, and neither is anything riding on it.
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return hit["position"] as Vector3


# --- Brake light --------------------------------------------------------

## Take a private copy of the bar's material, so writing to it lights this
## rover and not every rover.
##
## A sub-resource in a scene is shared by every instance of that scene unless
## it is marked local, and a material is exactly the sort of thing nobody
## notices sharing until there are two of something.
func _setup_brake_light() -> void:
	var bar := get_node_or_null(brake_light_path) as MeshInstance3D
	if bar == null:
		push_warning("Rover: no brake light mesh at '%s'." % brake_light_path)
		return
	var authored := bar.get_active_material(0) as StandardMaterial3D
	if authored == null:
		push_warning(
			"Rover: brake light '%s' has no StandardMaterial3D to drive." % bar.name
		)
		return
	_brake_material = authored.duplicate() as StandardMaterial3D
	_brake_material.emission_enabled = true
	bar.set_surface_override_material(0, _brake_material)
	_set_brake_light(false)


## Whether the pedals are asking the rover to slow down.
##
## **Engine braking is deliberately not in here.** It is what happens when you
## stop asking for anything, and a bar that is lit whenever the throttle is
## closed is not a brake light - it is a light that is on. Only the two
## deliberate inputs count: the full brake, and the decelerate pedal.
func _wants_brake_light(throttle: float, braking: bool) -> bool:
	if braking:
		return true
	if throttle >= 0.0:
		return false
	# Below reverse_threshold the same pedal is applying reverse torque rather
	# than brake, which is a separate question - see brake_light_on_reverse.
	return brake_light_on_reverse or forward_speed() > reverse_threshold


## Written every frame rather than only on a change. It is one float on one
## material, and rewriting it means a slider moved in the F1 panel takes effect
## while you are holding the pedal down rather than on the next press.
func _set_brake_light(lit: bool) -> void:
	_brake_lit = lit
	if _brake_material == null:
		return
	_brake_material.emission_energy_multiplier = (
		brake_light_energy if lit else brake_light_idle_energy
	)


## Whether the bar is lit.
func brake_light_on() -> bool:
	return _brake_lit


## The bar's emission energy as the player would actually see it, or -1 if
## there is no material to drive. For tests: a light whose *state* is right and
## whose material never moves is the failure this project keeps meeting, and a
## missing material must not read as a convincing zero.
func brake_light_output() -> float:
	if _brake_material == null:
		return -1.0
	return _brake_material.emission_energy_multiplier


# --- Load ---------------------------------------------------------------

func cargo_rack() -> CargoRack:
	return _rack


## Recompute mass and centre of mass from what is actually on the rack. Called
## by the astronaut after every transfer — cheap, and it means occupancy has
## exactly one source of truth: the scene tree.
##
## Six crates is roughly +22% mass, and because they sit on the roof the centre
## of mass climbs toward them. Load one side only and it moves sideways too,
## which at 0.55 g is the difference between a corner and a slow roll.
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

## Where the driver climbs out to.
##
## The marker gives the offset; the ground gives the height. Read straight off
## the marker in body space it follows every degree of roll the rover has: at
## (-2.1, -0.5, 0) an upside-down rover puts you half a metre *up* on the wrong
## side, and one lying on its flank puts you 2.1 m straight down, which is
## inside the terrain.
##
## Climbing out of a wreck is exactly the case that has to work, because on
## foot is the only place the verb that rights it exists. Same rule the crates
## already followed and nothing else had been given: author the X and Z, solve
## the height.
func exit_position() -> Vector3:
	var offset := _exit_point.position
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		# Nose straight up or down. Any heading will do; the offset is sideways.
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var beside := (
		global_position
		+ fwd.cross(Vector3.UP).normalized() * offset.x
		+ fwd * -offset.z
	)
	var lift := Vector3.UP * exit_clearance
	return ground_below(beside, beside - lift) + lift



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
	# The parking brake is on, but nobody is on the pedal: a rover left parked
	# with its brake light burning would be reporting a driver that has gone.
	_set_brake_light(false)
	_camera.current = false
	astronaut.disembark(exit_position())
