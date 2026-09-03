extends SkeletonModifier3D
class_name UpperArmUntwist
## Damps the upper arm's roll while the elbow is near straight, so the elbow
## keeps hinging the way it was modelled to.
##
## **The roll is on the upper arm, not the forearm.** That distinction cost a
## first version of this file. Measured against the bind pose, the idle clip
## rolls `mixamorig_Arm` by +14.9 degrees on the left and -27.0 on the right,
## while the forearm's own roll is -0.3 and +1.5 - nothing at all. A
## global-space measurement blames the forearm, because it accumulates
## everything above it; only the bone-local one says where the rotation lives.
##
## What that roll does is swing the **elbow's hinge axis 43 to 47 degrees away
## from the rest pose**. On a bare arm that is just how a relaxed arm hangs. On
## a suit whose elbow is a modelled hinge with armour on the back of it, the
## armour ends up on the side of the joint - and with the elbow also held nearly
## straight, 1.4 and 6.4 degrees of fold, there is no visible bend left to say
## which way it really folds. The arm reads as bending the wrong way.
##
## **The correction fades out as the elbow closes, and that is the whole trick.**
## Two reasons, and they agree. Roll is only legible on a straight arm: once the
## joint is folded the bend itself says which way the hinge runs. And rolling a
## *straight* arm barely moves the hand, because the hand sits almost on the
## roll axis - so the fix is close to invisible except for the thing it fixes.
## Fold the elbow and the same roll swings the forearm right across the body,
## which is real motion the run depends on. The gate is not a safety margin, it
## is the definition of where this correction means anything.
##
## A `SkeletonModifier3D` rather than a write in `_process`, because the pose has
## to be corrected *after* the AnimationTree has written it and the modifier
## stack is the one place with that ordering guaranteed. Measured not to
## compound: holding one frame for 120 ticks leaves the result identical, and
## turning it off restores the authored pose exactly.

const SIDES: Array[String] = ["Left", "Right"]

## Set by AstronautRig, which owns the tunables so there is one place to find
## them and the F1 panel already reaches it.
var rig: AstronautRig

var _arm := {}
var _fore := {}
## Direction from shoulder to elbow, in the upper arm's own frame: the axis its
## roll happens about. A property of the rest pose, so it is resolved once.
var _roll_axis := {}
## Direction from elbow to wrist, in the forearm's frame. Only used to measure
## how folded the elbow is.
var _fore_axis := {}
var _resolved := false


func _resolve() -> bool:
	var skel := get_skeleton()
	if skel == null:
		return false
	for side: String in SIDES:
		_arm[side] = skel.find_bone("mixamorig_%sArm" % side)
		_fore[side] = skel.find_bone("mixamorig_%sForeArm" % side)
		var hand := skel.find_bone("mixamorig_%sHand" % side)
		if int(_arm[side]) < 0 or int(_fore[side]) < 0 or hand < 0:
			push_warning("UpperArmUntwist: %s arm bones not found; doing nothing" % side)
			return false
		_roll_axis[side] = skel.get_bone_rest(_fore[side]).origin.normalized()
		_fore_axis[side] = skel.get_bone_rest(hand).origin.normalized()
	return true


func _process_modification() -> void:
	if rig == null:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	if not _resolved:
		_resolved = _resolve()
		if not _resolved:
			return
	for side: String in SIDES:
		_apply(skel, side)


## How far this elbow is from straight, in degrees. Zero is a straight arm.
##
## Read off local poses: the answer is the angle between two bones and nothing
## above the shoulder can change it, so there is no reason to ask the skeleton
## to resolve a global transform in the middle of its own update.
func fold_degrees(side: String) -> float:
	var skel := get_skeleton()
	if skel == null or not _resolved:
		return 0.0
	var upper: Vector3 = _roll_axis[side]
	var fore: Vector3 = (skel.get_bone_pose(_fore[side]).basis * _fore_axis[side]).normalized()
	return rad_to_deg(upper.angle_to(fore))


## How much of the roll to remove on this side right now, 0 to 1.
func correction(side: String) -> float:
	if rig == null:
		return 0.0
	var straight := 1.0 - clampf(
		fold_degrees(side) / maxf(rig.untwist_fold_limit, 0.1), 0.0, 1.0)
	return clampf(rig.arm_untwist, 0.0, 1.0) * straight


func _apply(skel: Skeleton3D, side: String) -> void:
	var amount := correction(side)
	if amount <= 0.001:
		return
	var arm: int = _arm[side]
	var rest_rotation := skel.get_bone_rest(arm).basis.get_rotation_quaternion()
	# The pose as a rotation away from this bone's own rest, which is the frame
	# the roll axis is expressed in.
	var delta := rest_rotation.inverse() * skel.get_bone_pose_rotation(arm)
	var axis: Vector3 = _roll_axis[side]

	# Swing-twist split: the part of `delta` about `axis` is the roll, the rest
	# is where the arm is pointing. Only the roll is touched, so the arm stays
	# exactly where the animation put it and only its rotation about its own
	# length is pulled back toward the bind pose.
	var projected := Vector3(delta.x, delta.y, delta.z).dot(axis)
	var twist := Quaternion(axis.x * projected, axis.y * projected, axis.z * projected, delta.w)
	if twist.length_squared() < 1e-8:
		return  # a half turn square to the axis: no roll component to speak of
	twist = twist.normalized()
	if twist.w < 0.0:
		twist = -twist  # shortest way round, or the slerp below takes the long one
	var swing := delta * twist.inverse()
	var reduced := Quaternion.IDENTITY.slerp(twist, 1.0 - amount)
	skel.set_bone_pose_rotation(arm, rest_rotation * (swing * reduced))


## The roll currently on one upper arm, in degrees - before or after correction
## depending on when it is asked. Tests and diagnostics; nothing in the game
## reads it.
func roll_degrees(side: String) -> float:
	var skel := get_skeleton()
	if skel == null or not _resolved:
		return 0.0
	var arm: int = _arm[side]
	var rest_rotation := skel.get_bone_rest(arm).basis.get_rotation_quaternion()
	var delta := rest_rotation.inverse() * skel.get_bone_pose_rotation(arm)
	var axis: Vector3 = _roll_axis[side]
	var projected := Vector3(delta.x, delta.y, delta.z).dot(axis)
	var twist := Quaternion(axis.x * projected, axis.y * projected, axis.z * projected, delta.w)
	if twist.length_squared() < 1e-8:
		return 0.0
	twist = twist.normalized()
	return rad_to_deg(2.0 * atan2(
		Vector3(twist.x, twist.y, twist.z).length() * signf(projected), twist.w))
