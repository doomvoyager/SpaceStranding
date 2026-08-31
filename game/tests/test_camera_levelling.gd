extends Node3D
## Regression test for the rover camera's tilt clamp.
##
## The camera pivot is a child of the chassis, so by default it inherits the
## body's basis whole — roll the rover and the horizon rolls with it, and on its
## roof the player is upside down. The clamp keeps the lean, which is what makes
## a side slope read as a side slope, and throws away everything past the limit.
##
## Three things are easy to get wrong here and all of them look plausible in
## motion:
##
##   1. The clamp is applied but *compounds*, because the correction is written
##      back into the same local basis it was read from. Symptom: the camera
##      slowly winds itself round over a few seconds of driving.
##   2. The camera is levelled so hard it stops leaning at all, which is a
##      different feature from the one that was asked for.
##   3. Levelling eats the heading, so the camera no longer sits behind the
##      rover through a turn.
##
## Camera basis is a real node transform, so unlike a MultiMesh's instances it
## reads back correctly headless — see the note in test_rock_scatter.gd.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_camera_levelling.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const SETTLE := 30
## Frames to let the spring arm's own cast catch up after posing.
const ARM_SETTLE := 15
## Roll angles to put the chassis through, in degrees. 180 is on its roof.
const ROLLS := [0.0, 10.0, 18.0, 45.0, 90.0, 135.0, 180.0, -45.0, -90.0]
## Pitch angles, nose up and nose down.
const PITCHES := [0.0, 20.0, 60.0, 90.0, -60.0]

var _failures: Array[String] = []
var _frames := 0
var _rover: Rover
var _astronaut: Astronaut
var _pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D


func _ready() -> void:
	add_child(WORLD.instantiate())


func _physics_process(_delta: float) -> void:
	_frames += 1
	# The spring arm casts in its own _physics_process, so the inversion tests
	# need frames to settle rather than a single posed step.
	if _frames == SETTLE + ARM_SETTLE:
		_test_arm_survives_inversion()
		# Level again, camera pitched hard, which swings the arm down behind the
		# rover and straight through its own chassis.
		_pose(Vector3.ZERO)
		_spring_arm.rotation.x = deg_to_rad(_rover.pitch_max)
		return
	if _frames == SETTLE + ARM_SETTLE * 2:
		_test_chassis_does_not_shove_the_camera(_rover.pitch_max)
		_spring_arm.rotation.x = deg_to_rad(_rover.pitch_min)
		return
	if _frames == SETTLE + ARM_SETTLE * 3:
		_test_chassis_does_not_shove_the_camera(_rover.pitch_min)
		_finish()
		return
	if _frames != SETTLE:
		return

	var world := get_child(0)
	_rover = world.find_child("Rover", true, false) as Rover
	_astronaut = world.find_child("Astronaut", true, false) as Astronaut
	if _rover == null or _astronaut == null:
		_expect(false, "could not find the rover and astronaut in test_world")
		_finish()
		return
	_pivot = _rover.get_node("CamPivot")
	_spring_arm = _rover.get_node("CamPivot/SpringArm3D")
	_camera = _rover.get_node("CamPivot/SpringArm3D/Camera3D")

	# Freeze so the transform can be posed directly; a live rigid body fights
	# every write. Smoothing off so one frame is the settled answer.
	_rover.freeze = true
	_rover.tilt_smoothing = 0.0
	_rover.enter(_astronaut)

	_test_roll_is_clamped()
	_test_pitch_is_clamped()
	_test_it_still_leans()
	_test_it_does_not_compound()
	_test_heading_is_kept()
	_test_follow_fraction()

	# Leaves the rover inverted and well clear of the ground; the arm is
	# measured ARM_SETTLE frames later, once its cast has caught up.
	_rover.tilt_follow = 1.0
	_rover._look_yaw = 0.0
	var lifted := _rover.global_position
	lifted.y += 40.0
	_rover.global_position = lifted
	_pose(Vector3(0.0, 0.0, deg_to_rad(180.0)))


# --- The clamp ----------------------------------------------------------

func _test_roll_is_clamped() -> void:
	var limit := _rover.tilt_limit_deg
	for roll in ROLLS:
		var tilt := _pose_and_measure(Vector3(0.0, 0.0, deg_to_rad(roll)))
		_expect(tilt <= limit + 0.5,
			"rolled %.0f deg and the camera tilted %.1f, past the %.0f limit"
				% [roll, tilt, limit])


func _test_pitch_is_clamped() -> void:
	var limit := _rover.tilt_limit_deg
	for pitch in PITCHES:
		var tilt := _pose_and_measure(Vector3(deg_to_rad(pitch), 0.0, 0.0))
		_expect(tilt <= limit + 0.5,
			"pitched %.0f deg and the camera tilted %.1f, past the %.0f limit"
				% [pitch, tilt, limit])


## The point is a clamp, not a gyro. A camera pinned to horizontal would pass
## every assertion above and be the wrong feature.
func _test_it_still_leans() -> void:
	var gentle := _pose_and_measure(Vector3(0.0, 0.0, deg_to_rad(10.0)))
	_expect(is_equal_approx_deg(gentle, 10.0, 0.6),
		"a 10 deg roll should lean the camera 10 deg, got %.1f" % gentle)

	var at_limit := _pose_and_measure(Vector3(0.0, 0.0, deg_to_rad(90.0)))
	_expect(at_limit > _rover.tilt_limit_deg - 0.5,
		"on its side the camera should sit at the limit, got %.1f" % at_limit)


## Holding one attitude for many frames must not wind the camera round. This is
## the failure a counter-rotation would have.
func _test_it_does_not_compound() -> void:
	# Level once before taking the baseline. The pivot is a *child* of the body,
	# so re-posing the chassis drags its global basis along and reading the tilt
	# before levelling reports the previous test's leftovers.
	var first := _pose_and_measure(Vector3(0.0, 0.0, deg_to_rad(60.0)))
	for i in 120:
		_rover._level_camera(1.0 / 60.0)
	var after := _tilt_deg()
	_expect(absf(after - first) < 0.1,
		"tilt drifted from %.2f to %.2f over 120 frames at a fixed attitude"
			% [first, after])


## Levelling must not eat the heading: the camera still sits behind the rover.
func _test_heading_is_kept() -> void:
	_rover._look_yaw = 0.0
	for yaw in [0.0, 60.0, -120.0, 179.0]:
		_pose(Vector3(0.0, deg_to_rad(yaw), deg_to_rad(12.0)))
		_rover._level_camera(1.0)
		# Both flattened to the horizontal plane: the camera's forward should
		# still point where the rover's nose points.
		var rover_fwd := _flat(-_rover.global_basis.z)
		var cam_fwd := _flat(-_pivot.global_basis.z)
		var off := rad_to_deg(rover_fwd.angle_to(cam_fwd))
		_expect(off < 2.0,
			"at yaw %.0f the camera is %.1f deg off the rover's heading" % [yaw, off])


## `tilt_follow` below 1 should lean less than the chassis does.
func _test_follow_fraction() -> void:
	_rover.tilt_follow = 0.5
	var half := _pose_and_measure(Vector3(0.0, 0.0, deg_to_rad(20.0)))
	_rover.tilt_follow = 1.0
	var full := _pose_and_measure(Vector3(0.0, 0.0, deg_to_rad(20.0)))
	_expect(is_equal_approx_deg(half, 10.0, 0.6),
		"half follow on a 20 deg roll should lean 10, got %.1f" % half)
	_expect(full > half + 4.0,
		"full follow (%.1f) should lean further than half (%.1f)" % [full, half])


## On its roof, the camera must still be behind and above the rover at a usable
## distance. Two separate ways this fails: the arm treats the chassis as an
## obstacle and collapses to nothing, and the mount - if it is left in body
## space - flips underneath the rover and sweeps the arm into the ground.
func _test_arm_survives_inversion() -> void:
	var reach := _arm_reach()
	_expect(reach > _spring_arm.spring_length * 0.75,
		"upside down the arm collapsed to %.2f m of %.2f"
			% [reach, _spring_arm.spring_length])

	_expect(_pivot.global_position.y > _rover.global_position.y + 0.5,
		"upside down the camera mount sank to %.2f, below the rover at %.2f"
			% [_pivot.global_position.y, _rover.global_position.y])

	# And it is still a level view, not a barrel roll.
	_expect(_tilt_deg() <= _rover.tilt_limit_deg + 0.5,
		"upside down the camera tilted %.1f" % _tilt_deg())


## Pitching the view swings the arm down behind the rover and through its own
## chassis. The vehicle you are driving must not be an obstacle to the camera
## filming it, or looking up on the move drags the view into the engine bay.
##
## Nothing is under the rover here - it is still 40 m in the air - so anything
## shortening the arm is the rover itself.
func _test_chassis_does_not_shove_the_camera(pitch_deg: float) -> void:
	var reach := _arm_reach()
	_expect(reach > _spring_arm.spring_length * 0.9,
		"pitched %.0f deg the chassis pushed the arm in to %.2f m of %.2f"
			% [pitch_deg, reach, _spring_arm.spring_length])


func _arm_reach() -> float:
	return _spring_arm.global_position.distance_to(_camera.global_position)


# --- Helpers ------------------------------------------------------------

func _pose(euler: Vector3) -> void:
	var xform := _rover.global_transform
	xform.basis = Basis.from_euler(euler)
	_rover.global_transform = xform


func _pose_and_measure(euler: Vector3) -> float:
	_pose(euler)
	# Smoothing is off, so one call is the settled result.
	_rover._level_camera(1.0)
	return _tilt_deg()


func _tilt_deg() -> float:
	return rad_to_deg(_pivot.global_basis.y.angle_to(Vector3.UP))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


func is_equal_approx_deg(got: float, want: float, tolerance: float) -> bool:
	return absf(got - want) <= tolerance


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: camera clamps at %.0f deg, leans, keeps heading, does not drift, survives inversion."
			% _rover.tilt_limit_deg)
		# quit() only schedules the exit, so this must return.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
