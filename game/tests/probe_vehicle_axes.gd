extends SceneTree
## Diagnostic: determines Godot's VehicleBody3D sign conventions empirically.
##
## Builds a bare vehicle with no project scripts attached (so it runs under
## --script, where autoloads do not exist), drives it with a known positive
## engine_force and steering, and reports which way it actually went.
##
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        --script res://tests/probe_vehicle_axes.gd

const SETTLE_FRAMES := 60
const DRIVE_FRAMES := 240
const TEST_ENGINE_FORCE := 2000.0
const TEST_STEERING := 0.35

var _vehicle: VehicleBody3D
var _start_pos := Vector3.ZERO
var _start_yaw := 0.0
var _frames := 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var ground := StaticBody3D.new()
	var g_col := CollisionShape3D.new()
	var g_shape := BoxShape3D.new()
	g_shape.size = Vector3(600.0, 2.0, 600.0)
	g_col.shape = g_shape
	ground.add_child(g_col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	world.add_child(ground)

	_vehicle = VehicleBody3D.new()
	_vehicle.mass = 950.0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 4.4)
	col.shape = box
	_vehicle.add_child(col)

	# x, z, steers.  z = -1.65 is the end the model treats as the front.
	for spec in [
		[-1.12, -1.65, true], [1.12, -1.65, true],
		[-1.12, 1.65, false], [1.12, 1.65, false],
	]:
		var w := VehicleWheel3D.new()
		w.position = Vector3(spec[0], -0.4, spec[1])
		w.use_as_traction = true
		w.use_as_steering = spec[2]
		w.wheel_radius = 0.5
		w.wheel_rest_length = 0.25
		w.wheel_friction_slip = 6.0
		w.suspension_travel = 0.32
		w.suspension_stiffness = 22.0
		w.suspension_max_force = 12000.0
		w.damping_compression = 1.6
		w.damping_relaxation = 2.2
		_vehicle.add_child(w)

	_vehicle.position = Vector3(0.0, 1.0, 0.0)
	world.add_child(_vehicle)

	print("gravity = ", ProjectSettings.get_setting("physics/3d/default_gravity"))
	print("engine  = ", ProjectSettings.get_setting("physics/3d/physics_engine"))


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == SETTLE_FRAMES:
		_start_pos = _vehicle.global_position
		_start_yaw = _vehicle.global_rotation.y
		_vehicle.engine_force = TEST_ENGINE_FORCE
		_vehicle.steering = TEST_STEERING
		print("settled at y=%.3f, driving..." % _start_pos.y)
		return false

	if _frames == SETTLE_FRAMES + DRIVE_FRAMES:
		var delta_pos := _vehicle.global_position - _start_pos
		var delta_yaw := wrapf(_vehicle.global_rotation.y - _start_yaw, -PI, PI)
		print("--- RESULTS ---")
		print("displacement      = ", delta_pos)
		print("travelled dist    = %.2f m" % Vector2(delta_pos.x, delta_pos.z).length())
		print("dz (world)        = %+.3f" % delta_pos.z)
		print("yaw change        = %+.2f deg" % rad_to_deg(delta_yaw))
		print("")
		print("engine_force %+.0f drives toward %s Z" % [
			TEST_ENGINE_FORCE, "+" if delta_pos.z > 0.0 else "-"
		])
		print("steering %+.2f yaws %s" % [
			TEST_STEERING, "LEFT (+Y)" if delta_yaw > 0.0 else "RIGHT (-Y)"
		])
		return true

	return false
