extends Node3D
## Can gravity actually be changed at runtime, and by which call?
##
## World.surface_gravity is only read by the astronaut and the jolt meter
## read; every RigidBody3D gets its gravity from project.godot instead. So a
## gravity slider has to drive the physics server as well, and it is worth
## knowing which call really moves a falling body rather than assuming.
##
## Measures acceleration by dropping a body and timing it, before and after
## each candidate.
##
## Runs as a scene.
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##     res://tests/probe_runtime_gravity.tscn

const MEASURE_FRAMES := 30

var _body: RigidBody3D
var _phase := 0
var _frame := 0
var _start_v := 0.0
var _label := ""


func _ready() -> void:
	_body = RigidBody3D.new()
	_body.gravity_scale = 1.0
	# Default linear damp eats into the measurement once the body is fast, and
	# would make a low-gravity reading look lower than it is.
	_body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_body.linear_damp = 0.0
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	col.shape = shape
	_body.add_child(col)
	add_child(_body)
	_body.global_position = Vector3(0.0, 500.0, 0.0)
	print("--- runtime gravity probe ---")
	print("project.godot default_gravity = %s"
		% ProjectSettings.get_setting("physics/3d/default_gravity"))
	print("World.surface_gravity = %.2f" % World.surface_gravity)
	_label = "baseline"


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame == 1:
		_start_v = _body.linear_velocity.y
		return
	if _frame <= MEASURE_FRAMES:
		return

	var measured := absf(_body.linear_velocity.y - _start_v) / (delta * (MEASURE_FRAMES - 1))
	print("  %-46s falls at %6.2f m/s^2" % [_label, measured])

	# Drop from rest again each time, so nothing carries over.
	_body.global_position = Vector3(0.0, 500.0, 0.0)
	_body.linear_velocity = Vector3.ZERO
	_frame = 0
	_phase += 1
	match _phase:
		1:
			_label = "after ProjectSettings.set_setting(default_gravity, 9.8)"
			ProjectSettings.set_setting("physics/3d/default_gravity", 9.8)
		2:
			_label = "after area_set_param(world_3d.space, GRAVITY, 20)"
			PhysicsServer3D.area_set_param(
				get_viewport().find_world_3d().space,
				PhysicsServer3D.AREA_PARAM_GRAVITY,
				20.0
			)
		3:
			_label = "after area_set_param(... GRAVITY, 1.0)"
			PhysicsServer3D.area_set_param(
				get_viewport().find_world_3d().space,
				PhysicsServer3D.AREA_PARAM_GRAVITY,
				1.0
			)
		_:
			print("--- end probe ---")
			get_tree().quit(0)
