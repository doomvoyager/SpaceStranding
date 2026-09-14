extends Node3D
## Regression test for the first/third-person toggle, on foot and in the rover.
##
## One key, `toggle_view` (V / D-pad up), and two rigs that each remember their
## own answer. What has to hold:
##
##   - The eye is at the visor, not the chest: between the head bone and the
##     crown, read off the skeleton rather than typed into the test.
##   - In first person the suit is not drawn but still casts: every mesh of it
##     is SHADOWS_ONLY, and the eye's cull mask still includes its layers. Not
##     a cull mask on the eye - a camera's cull mask culls shadow casters from
##     its own view too, measured in `probe_sun_shadow.tscn`.
##   - Switching views changes nothing about what E would do: the aim reads
##     the pivot both cameras hang off.
##   - Pitch reaches both cameras, clamped once.
##   - In first person the body turns to face the look; in third it does not
##     turn while standing still.
##   - Boarding shows the rover's own remembered view, not the astronaut's; the
##     rover's eye rides the chassis unclamped while the chase pivot is clamped;
##     the hull is shadows-only from the cab and drawn again on the way out.
##   - Climbing out restores the astronaut's view, facing the way the driver was
##     looking.
##   - Behind a panel the key does nothing, and setting `first_person` the way
##     the F1 panel does switches the view without a key.
##
## Presses go through `Input.parse_input_event`, because the toggle is an
## event: `Input.action_press` only sets the polled state, which a one-shot
## `is_action_pressed` in `_unhandled_input` never sees.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_view_toggle.tscn

const F_SETUP := 30
const F_FIRST := 36
const F_TURNED := 72
const F_MENU := 78
const F_STILL := 114
const F_BOARDED := 120
const F_ROVER_FIRST := 126
const F_EXITED := 132

var _astronaut: Astronaut
var _rover: Rover
var _frames := 0
var _failures: Array[String] = []
var _body_yaw_before := 0.0


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	# The rover beside the astronaut, inside the interact sphere, so the aim
	# check has something real to aim at.
	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(2.6, 1.0, 0.0)
	add_child(_rover)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(0.0, 0.05, 0.0)
	add_child(_astronaut)


func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		F_SETUP:
			_check_starts_third_person()
			_check_eye_is_at_the_visor()
			_check_suit(GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "in third person")
			_astronaut.aim_at(_rover.global_position)
			_expect(_astronaut.interact_prompt() == "Board the rover",
				"before the toggle E should board the rover; the prompt is \"%s\""
					% _astronaut.interact_prompt())
			_press("toggle_view")
		F_FIRST:
			_check_first_person_on_foot()
			_check_suit(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "in first person")
			_check_pitch_reaches_both()
			# Look along +X and give the body time to come round.
			_astronaut.aim_at(_astronaut.global_position + Vector3(100.0, 0.0, 0.0))
		F_TURNED:
			_check_body_faces_the_look()
			_astronaut.set_menu_open(true)
			_press("toggle_view")
		F_MENU:
			_expect(_astronaut.is_first_person(),
				"the toggle went through a full-screen panel")
			_astronaut.set_menu_open(false)
			_check_panel_switches_without_a_key()
			# Third person, looking the other way, standing still: the body stays.
			_astronaut.first_person = false
			_astronaut.aim_at(_astronaut.global_position + Vector3(-100.0, 0.0, 0.0))
			_body_yaw_before = _body().rotation.y
		F_STILL:
			_check_body_stays_in_third_person()
			_astronaut.first_person = true
			_rover.enter(_astronaut)
		F_BOARDED:
			_check_boarding_shows_the_rovers_view()
			_check_hull(GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "in the rover's third person")
			_press("toggle_view")
		F_ROVER_FIRST:
			_check_first_person_in_the_cab()
			_check_hull(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "from the cab")
			_check_eye_rides_the_chassis()
			_leave_looking_left()
		F_EXITED:
			_check_climbing_out()
			_check_hull(GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "after climbing out")
			_finish()


# --- On foot ------------------------------------------------------------

func _check_starts_third_person() -> void:
	_expect(not _astronaut.is_first_person(),
		"the astronaut should start in third person")
	_expect(_current() == _astronaut.view_camera() and _current() != _astronaut.eye(),
		"on foot the viewport should show the chase camera, shows %s"
			% _describe(_current()))


func _check_eye_is_at_the_visor() -> void:
	var rig := _astronaut.get_node_or_null("Body/Rig") as AstronautRig
	var skeleton: Skeleton3D = rig.skeleton() if rig != null else null
	if skeleton == null:
		_expect(false, "no skeleton to measure the eye against")
		return
	var head := _bone_height(skeleton, "mixamorig_Head")
	var crown := _bone_height(skeleton, "mixamorig_HeadTop_End")
	var eye := _astronaut.eye().global_position.y - _astronaut.global_position.y
	print("eye %.2f m above the feet; head bone %.2f, crown %.2f" % [eye, head, crown])
	_expect(eye > head and eye < crown,
		"the eye sits %.2f m up, outside the head (%.2f to %.2f)" % [eye, head, crown])


## Every mesh of the figure casts the way the view asks, and the eye's mask
## still covers it - a caster the camera culls casts nothing into its view.
func _check_suit(mode: GeometryInstance3D.ShadowCastingSetting, when: String) -> void:
	var rig := _astronaut.get_node("Body/Rig")
	var meshes := rig.find_children("*", "GeometryInstance3D", true, false)
	_expect(not meshes.is_empty(), "no meshes under the rig to check")
	for m in meshes:
		var g := m as GeometryInstance3D
		_expect(g.cast_shadow == mode,
			"%s: %s casts as %d, expected %d" % [when, g.name, g.cast_shadow, mode])
		_expect((_astronaut.eye().cull_mask & g.layers) != 0,
			"%s: the eye's cull mask leaves out %s's layers, which would cull its shadow"
				% [when, g.name])


func _check_first_person_on_foot() -> void:
	_expect(_astronaut.is_first_person(), "V did not switch to first person")
	_expect(_current() == _astronaut.eye(),
		"first person should put the eye on screen, viewport shows %s"
			% _describe(_current()))
	_expect(_astronaut.interact_prompt() == "Board the rover",
		"the view changed what E would do; the prompt is \"%s\"" % _astronaut.interact_prompt())


func _check_pitch_reaches_both() -> void:
	var arm := _astronaut.get_node("CamPivot/SpringArm3D") as Node3D
	_astronaut._pitch_by(deg_to_rad(-30.0))
	_expect(_close(arm.rotation.x, deg_to_rad(-30.0)) and _close(_astronaut.eye().rotation.x, deg_to_rad(-30.0)),
		"pitching 30 deg down set the arm to %.1f and the eye to %.1f"
			% [rad_to_deg(arm.rotation.x), rad_to_deg(_astronaut.eye().rotation.x)])
	_astronaut._pitch_by(deg_to_rad(-90.0))
	var floor_ := deg_to_rad(_astronaut.pitch_min)
	_expect(_close(arm.rotation.x, floor_) and _close(_astronaut.eye().rotation.x, floor_),
		"past the limit the arm is at %.1f and the eye at %.1f, limit %.0f"
			% [rad_to_deg(arm.rotation.x), rad_to_deg(_astronaut.eye().rotation.x), _astronaut.pitch_min])
	_astronaut._pitch_by(-floor_)


func _check_body_faces_the_look() -> void:
	var off := rad_to_deg(absf(angle_difference(_body().rotation.y, _pivot().rotation.y)))
	print("first person: body %.1f deg off the look" % off)
	_expect(off < 1.0, "in first person the body is %.1f deg off the look" % off)


func _check_panel_switches_without_a_key() -> void:
	_astronaut.first_person = false
	_expect(not _astronaut.is_first_person() and _current() != _astronaut.eye(),
		"clearing first_person did not bring the chase camera back")
	_astronaut.first_person = true
	_expect(_current() == _astronaut.eye(),
		"setting first_person did not put the eye on screen")


func _check_body_stays_in_third_person() -> void:
	var moved := rad_to_deg(absf(angle_difference(_body().rotation.y, _body_yaw_before)))
	print("third person, standing still: body turned %.1f deg" % moved)
	_expect(moved < 0.5,
		"standing still in third person the body turned %.1f deg to follow the look" % moved)


# --- In the rover -------------------------------------------------------

func _check_boarding_shows_the_rovers_view() -> void:
	_expect(_astronaut.is_first_person(), "boarding forgot the astronaut's view")
	_expect(not _rover.is_first_person(), "the rover should start in third person")
	_expect(_current() == _rover.view_camera() and _current() != _rover.eye(),
		"boarding in first person on foot should show the rover's own third-person view, shows %s"
			% _describe(_current()))


## Every mesh on the hull layers casts the way the view asks, the eye's mask
## still covers them, and there is at least one - a scene with no marked
## exterior would pass a check over an empty list.
func _check_hull(mode: GeometryInstance3D.ShadowCastingSetting, when: String) -> void:
	var marked := 0
	for m in _rover.find_children("*", "GeometryInstance3D", true, false):
		var g := m as GeometryInstance3D
		if (g.layers & _rover.hull_layers) == 0:
			continue
		marked += 1
		_expect(g.cast_shadow == mode,
			"%s: %s casts as %d, expected %d" % [when, g.name, g.cast_shadow, mode])
		_expect((_rover.eye().cull_mask & g.layers) != 0,
			"%s: the driver's eye culls %s's layers, which would cull its shadow" % [when, g.name])
	_expect(marked > 0, "no rover mesh is on the hull layers %d" % _rover.hull_layers)


func _check_first_person_in_the_cab() -> void:
	_expect(_rover.is_first_person(), "V in the rover did not switch to first person")
	_expect(_current() == _rover.eye(),
		"first person in the rover should put its eye on screen, shows %s"
			% _describe(_current()))


## Frozen and rolled 40 degrees: the chase pivot stops at its limit, the eye
## goes the whole way, because a cab is inside the thing that is rolling.
func _check_eye_rides_the_chassis() -> void:
	_rover.freeze = true
	_rover.tilt_smoothing = 0.0
	_rover._look_yaw = 0.0
	_pose_rover(Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(40.0))))
	var eye_tilt := rad_to_deg(_rover.eye().global_basis.y.angle_to(Vector3.UP))
	var chase_tilt := rad_to_deg(
		(_rover.get_node("CamPivot") as Node3D).global_basis.y.angle_to(Vector3.UP))
	print("rolled 40 deg: eye tilts %.1f, chase pivot %.1f (limit %.0f)"
		% [eye_tilt, chase_tilt, _rover.tilt_limit_deg])
	_expect(absf(eye_tilt - 40.0) < 0.5,
		"the eye should roll with the chassis; on a 40 deg roll it tilted %.1f" % eye_tilt)
	_expect(chase_tilt <= _rover.tilt_limit_deg + 0.5,
		"the chase pivot should stop at %.0f, tilted %.1f" % [_rover.tilt_limit_deg, chase_tilt])


## Level again, look a quarter turn left of the nose, and climb out.
func _leave_looking_left() -> void:
	_rover._look_yaw = deg_to_rad(90.0)
	_pose_rover(Basis.IDENTITY)
	_rover.freeze = false
	var heading := _rover.view_heading()
	print("view heading on exit %.1f deg" % rad_to_deg(heading))
	_expect(absf(rad_to_deg(angle_difference(heading, deg_to_rad(90.0)))) < 0.5,
		"nose on -Z and the look a quarter turn left should read 90 deg, got %.1f"
			% rad_to_deg(heading))
	_rover.exit()


func _check_climbing_out() -> void:
	_expect(_current() == _astronaut.eye(),
		"climbing out should restore the astronaut's first person, viewport shows %s"
			% _describe(_current()))
	_expect(_rover.is_first_person(), "the rover forgot its own view on exit")
	var fwd := -_pivot().global_basis.z
	var off := rad_to_deg(Vector3.LEFT.angle_to(Vector3(fwd.x, 0.0, fwd.z).normalized()))
	print("on the ground looking %.1f deg off the driver's heading" % off)
	_expect(off < 0.5, "climbed out looking %.1f deg off where the driver was looking" % off)


# --- Helpers ------------------------------------------------------------

func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _pose_rover(basis: Basis) -> void:
	var xform := _rover.global_transform
	xform.basis = basis
	_rover.global_transform = xform
	# Smoothing is off, so one call each is the settled answer.
	_rover._level_camera(1.0)
	_rover._aim_eye()


func _bone_height(skeleton: Skeleton3D, bone: String) -> float:
	var i := skeleton.find_bone(bone)
	if i < 0:
		_expect(false, "no bone called %s" % bone)
		return NAN
	var world := skeleton.global_transform * skeleton.get_bone_global_rest(i).origin
	return world.y - _astronaut.global_position.y


func _current() -> Camera3D:
	return get_viewport().get_camera_3d()


func _describe(camera: Camera3D) -> String:
	if camera == null:
		return "no camera"
	return "%s/%s" % [camera.get_parent().name, camera.name]


func _body() -> Node3D:
	return _astronaut.get_node("Body") as Node3D


func _pivot() -> Node3D:
	return _astronaut.get_node("CamPivot") as Node3D


func _close(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: one key, two views, each context remembering its own; the eye at the visor, the suit and the hull shadows-only from it, the aim untouched.")
		# quit() only schedules the exit, so this must return.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
