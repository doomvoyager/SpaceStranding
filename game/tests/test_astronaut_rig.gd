extends Node3D
## The animated astronaut: does the state machine say what the body is doing,
## and does the figure face the way it walks?
##
## Two of these assertions exist because the mistake was available and cheap to
## make. The facing test is the moonwalk: the model faces +Z, the controller
## drives -Z, and getting the correction wrong looks like inverted movement
## rather than a backwards mesh. The blend-position test is foot slide: the
## blend space is in the clips' own units, so feeding it raw ground speed would
## run the walk cycle in the run's place and nothing would error.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##     res://tests/test_astronaut_rig.tscn

const RIG := preload("res://scenes/player/astronaut_rig.tscn")
## How many frames a transition gets before the test calls it stuck. Generous,
## because _process and _physics_process do not interleave anything like
## realtime headless - the budget is the failure case, not the schedule.
const BUDGET := 240
const TICK := 1.0 / 60.0

var _failures: Array[String] = []
var _rig: AstronautRig


func _ready() -> void:
	_rig = RIG.instantiate()
	add_child(_rig)
	await get_tree().process_frame

	_check_clips()
	_check_facing()
	await _check_locomotion()
	await _check_air()

	if _failures.is_empty():
		print("PASS: astronaut rig")
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: ", f)
	get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _check_clips() -> void:
	var player := _rig.get_node("AnimationPlayer") as AnimationPlayer
	for clip: String in ["idle/idle", "walk/walk", "run/run",
			"jump/jump", "jump/fall", "jump/land"]:
		if not player.has_animation(clip):
			_fail('clip "%s" is missing from the rig' % clip)
			continue
		var anim := player.get_animation(clip)
		if anim.get_track_count() == 0:
			_fail('clip "%s" has no tracks' % clip)
	# The looping ones have to loop, or the walk stops after one stride.
	for clip: String in ["idle/idle", "walk/walk", "run/run"]:
		if player.has_animation(clip) and player.get_animation(clip).loop_mode == Animation.LOOP_NONE:
			_fail('clip "%s" does not loop' % clip)
	# And the jump phases must not, because each is meant to hold its last pose
	# for as long as the hang lasts.
	for clip: String in ["jump/jump", "jump/fall", "jump/land"]:
		if player.has_animation(clip) and player.get_animation(clip).loop_mode != Animation.LOOP_NONE:
			_fail('clip "%s" loops; the jump phases must hold' % clip)

	var skel := _rig.skeleton()
	if skel == null:
		_fail("the rig has no skeleton")
	elif skel.get_bone_count() != 41:
		_fail("skeleton has %d bones, expected 41" % skel.get_bone_count())


## The model must end up facing the controller's forward, which is -Z.
func _check_facing() -> void:
	var model := _rig.get_node("Model") as Node3D
	# The mesh faces its own +Z - measured off the rig's ankle-to-toe vector -
	# so the direction it points in the rig's frame is the model's basis Z.
	var facing := model.transform.basis.z
	if facing.z > -0.99:
		_fail("model faces %s in rig space; expected (0, 0, -1). Moonwalk." % str(facing))


func _check_locomotion() -> void:
	await _drive_for(30, 0.0, true, 0.0)
	if _rig.current_state() != &"Ground":
		_fail('standing still is state "%s", expected "Ground"' % _rig.current_state())

	# Walking and running have to land on their own clips. The blend space is in
	# clip units, so the expected position is ground speed over the suit's boost.
	for pair: Array in [[3.2, _rig.walk_cycle_speed], [6.4, _rig.run_cycle_speed]]:
		var speed: float = pair[0]
		var want: float = pair[1]
		await _drive_for(90, speed, true, 0.0)
		var at: float = _rig.get_node("AnimationTree").get(
			"parameters/Ground/Locomotion/blend_position")
		if absf(at - speed / _rig.stride_scale) > 0.05:
			_fail("at %.1f m/s the blend sits at %.2f, expected %.2f"
				% [speed, at, speed / _rig.stride_scale])
		# Which is only useful if that lands near the clip it is named for.
		if absf(at - want) > 0.4:
			_fail("at %.1f m/s the blend sits at %.2f, %.2f from its clip's own %.2f"
				% [speed, at, absf(at - want), want])


func _check_air() -> void:
	await _settle(6.4, false, 4.0, &"Jump", "pushing off")
	await _settle(6.4, false, -4.0, &"Fall", "coming down")
	await _settle(3.0, true, 0.0, &"Land", "touching down")
	# And Land has to release on its own, or the astronaut crouches forever.
	await _settle(3.0, true, 0.0, &"Ground", "recovering from the landing")


## Drive the rig until it reaches `want`, or give up.
func _settle(speed: float, grounded: bool, vertical: float,
		want: StringName, doing: String) -> void:
	for i in BUDGET:
		_rig.drive(speed, grounded, vertical, TICK)
		await get_tree().process_frame
		if _rig.current_state() == want:
			return
	_fail('%s never reached "%s" (stuck in "%s" after %d frames)'
		% [doing, want, _rig.current_state(), BUDGET])


func _drive_for(frames: int, speed: float, grounded: bool, vertical: float) -> void:
	for i in frames:
		_rig.drive(speed, grounded, vertical, TICK)
		await get_tree().process_frame
