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
	await _check_untwist()

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

## The arm-roll correction, which exists because the idle clip rolls the upper
## arms 15 and 27 degrees against a bind pose of zero and puts the suit's elbow
## armour on the side of the joint. See [[Astronaut-Traversal]].
##
## **Asserted on the gate, not on the bones.** A SkeletonModifier3D writes into
## the pose the renderer uses, but the skeleton restores the animated pose
## afterwards - so `get_bone_pose_rotation` from outside the modifier reads what
## the animation wrote, never the correction, and a test that asserted on it
## would pass whatever the modifier did. That restore is also why this cannot
## compound. What is checkable here is the decision: how much correction the
## modifier asks for at a given elbow angle. The picture is in
## previews/2026-09-03/untwist-*.
func _check_untwist() -> void:
	var mod := _rig.untwist_modifier()
	if mod == null:
		_fail("the arm untwist modifier was never installed")
		return
	if mod.get_skeleton() == null:
		_fail("the untwist modifier is not parented to a Skeleton3D, so it will never run")
		return

	# Standing still: elbows nearly straight, so the correction should be close
	# to fully applied.
	await _drive_for(60, 0.0, true, 0.0)
	for side: String in ["Left", "Right"]:
		var fold := mod.fold_degrees(side)
		if fold > 20.0:
			_fail("idle %s elbow reads %.1f deg of fold; expected a near-straight arm"
				% [side, fold])
		if mod.correction(side) < _rig.arm_untwist * 0.5:
			_fail("idle %s correction is %.2f of a possible %.2f - the fix is not reaching the pose it is for"
				% [side, mod.correction(side), _rig.arm_untwist])

	# Running: elbows folded past the limit, so the animation must be untouched.
	# This is the half that protects the run from a fix aimed at the idle.
	await _drive_for(120, 6.4, true, 0.0)
	for side: String in ["Left", "Right"]:
		var fold := mod.fold_degrees(side)
		if fold < _rig.untwist_fold_limit:
			_fail("run %s elbow only folds %.1f deg, under the %.1f limit - this test is not exercising the gate"
				% [side, fold, _rig.untwist_fold_limit])
		elif mod.correction(side) > 0.001:
			_fail("run %s is folded %.1f deg but still taking %.2f of correction"
				% [side, fold, mod.correction(side)])

	# And zero means zero: the animation exactly as authored.
	var was := _rig.arm_untwist
	_rig.arm_untwist = 0.0
	await _drive_for(30, 0.0, true, 0.0)
	for side: String in ["Left", "Right"]:
		if mod.correction(side) != 0.0:
			_fail("%s still corrects %.3f with arm_untwist at 0" % [side, mod.correction(side)])
	_rig.arm_untwist = was
