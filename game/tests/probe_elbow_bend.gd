extends Node3D
## Do the elbows leave the plane they are supposed to fold in?
##
## Mac's note: "the elbows in some animations are bent a bit too much in the
## wrong direction."
##
## **The first version of this probe measured the fixture.** It took the bend
## plane in *world* space and called anything more than 90 degrees off the rest
## pose "wrong", which flips sign the moment the shoulder rotates far enough -
## so a smoothly swinging arm read as +45, -51, +84 on consecutive frames while
## the fold magnitude changed by four degrees. Same family as the seam test that
## measured how rough the noise was.
##
## What actually defines an elbow is that it is a **hinge fixed to the upper
## arm**. So the forearm's direction is expressed in the upper arm's own frame,
## where a healthy elbow sweeps in one plane no matter what the shoulder is
## doing. The plane is not assumed: it is fitted from idle, walk and run, which
## Mac reports as fine, and the jump clips are then measured against it. The
## instrument calibrates itself on the good clips, so "wrong" means "unlike the
## animation that looks right" rather than a number someone chose.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##     res://tests/probe_elbow_bend.tscn

const RIG := preload("res://assets/characters/astronaut/Idle_with_skin.fbx")
const LIBS := {
	"idle": preload("res://assets/characters/astronaut/Idle.fbx"),
	"walk": preload("res://assets/characters/astronaut/Standard_Walk.fbx"),
	"run": preload("res://assets/characters/astronaut/Standard_Run.fbx"),
	"jump": preload("res://assets/characters/astronaut/Jump.fbx"),
}
## Clips Mac is happy with. These define what the joint's plane is.
const HEALTHY := ["idle/idle", "walk/walk", "run/run"]
const SUSPECT := ["jump/jump", "jump/fall", "jump/land"]
## First source frame of each jump slice, from Jump.fbx.import - so a finding
## can be reported as a frame to go and fix rather than a time in a slice.
const ORIGIN := {"jump/jump": 18, "jump/fall": 32, "jump/land": 37}
const FPS := 30.0

var _skel: Skeleton3D
var _player: AnimationPlayer
## Hinge normal per side, in upper-arm space, fitted from the healthy clips.
var _hinge := {}


func _ready() -> void:
	var rig := RIG.instantiate()
	add_child(rig)
	_skel = rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_player = AnimationPlayer.new()
	add_child(_player)
	_player.root_node = _player.get_path_to(rig)
	for lib: String in LIBS:
		_player.add_animation_library(lib, LIBS[lib])

	for side: String in ["Left", "Right"]:
		var samples := await _collect(side, HEALTHY)
		_hinge[side] = _fit_normal(samples)
		var spread := _spread(samples, _hinge[side])
		print("%-5s hinge fitted from %d samples of idle/walk/run: out-of-plane %.1f deg max"
			% [side, samples.size(), spread])

	print("")
	print("fold angle in that plane. 0 is a straight arm, negative is past")
	print("straight - the elbow bending backwards. Rest pose is Left %+.1f, Right %+.1f."
		% [_fold_at_rest("Left"), _fold_at_rest("Right")])
	for side: String in ["Left", "Right"]:
		for clip: String in HEALTHY + SUSPECT:
			await _report(side, clip)
	get_tree().quit()


## The forearm's fold away from the upper arm, signed by the hinge. Zero is a
## perfectly straight arm; positive folds the way an elbow folds; negative is
## the joint going past straight, which is what an arm cannot do.
func _fold(side: String) -> float:
	var arm := _skel.find_bone("mixamorig_%sArm" % side)
	var basis := _skel.get_bone_global_pose(arm).basis.orthonormalized()
	var shoulder := _skel.get_bone_global_pose(arm).origin
	var elbow := _skel.get_bone_global_pose(_skel.find_bone("mixamorig_%sForeArm" % side)).origin
	var wrist := _skel.get_bone_global_pose(_skel.find_bone("mixamorig_%sHand" % side)).origin
	var upper := (basis.inverse() * (elbow - shoulder)).normalized()
	var fore := (basis.inverse() * (wrist - elbow)).normalized()
	var angle := rad_to_deg(upper.angle_to(fore))
	return angle * signf(upper.cross(fore).dot(_hinge[side]))


func _fold_at_rest(side: String) -> float:
	var arm := _skel.find_bone("mixamorig_%sArm" % side)
	var basis := _skel.get_bone_global_rest(arm).basis.orthonormalized()
	var shoulder := _skel.get_bone_global_rest(arm).origin
	var elbow := _skel.get_bone_global_rest(_skel.find_bone("mixamorig_%sForeArm" % side)).origin
	var wrist := _skel.get_bone_global_rest(_skel.find_bone("mixamorig_%sHand" % side)).origin
	var upper := (basis.inverse() * (elbow - shoulder)).normalized()
	var fore := (basis.inverse() * (wrist - elbow)).normalized()
	return rad_to_deg(upper.angle_to(fore)) * signf(upper.cross(fore).dot(_hinge[side]))


## The forearm's direction expressed in the upper arm's frame. Shoulder motion
## divides out, which is the whole point.
func _forearm_local(side: String) -> Vector3:
	var arm := _skel.find_bone("mixamorig_%sArm" % side)
	var basis := _skel.get_bone_global_pose(arm).basis.orthonormalized()
	var elbow := _skel.get_bone_global_pose(_skel.find_bone("mixamorig_%sForeArm" % side)).origin
	var wrist := _skel.get_bone_global_pose(_skel.find_bone("mixamorig_%sHand" % side)).origin
	return (basis.inverse() * (wrist - elbow)).normalized()


func _collect(side: String, clips: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for clip: String in clips:
		var anim := _player.get_animation(clip)
		_player.play(clip)
		var frames := maxi(int(round(anim.length * FPS)), 1)
		for f in frames + 1:
			_player.seek(minf(float(f) / FPS, anim.length), true)
			await get_tree().process_frame
			out.append(_forearm_local(side))
	return out


## The direction the samples vary least in - the hinge axis. Unit vectors
## sweeping in a plane have their cross products all parallel to its normal,
## so averaging them with a consistent sign is enough and needs no eigensolver.
func _fit_normal(samples: Array[Vector3]) -> Vector3:
	var normal := Vector3.ZERO
	for i in range(samples.size()):
		for j in range(i + 1, samples.size(), 7):
			var c := samples[i].cross(samples[j])
			if c.length() < 0.15:
				continue  # nearly parallel: says nothing about the plane
			c = c.normalized()
			if normal != Vector3.ZERO and c.dot(normal) < 0.0:
				c = -c
			normal += c
	return normal.normalized() if normal.length() > 1e-6 else Vector3.UP


func _spread(samples: Array[Vector3], normal: Vector3) -> float:
	var worst := 0.0
	for d in samples:
		worst = maxf(worst, absf(rad_to_deg(asin(clampf(d.dot(normal), -1.0, 1.0)))))
	return worst


func _report(side: String, clip: String) -> void:
	var anim := _player.get_animation(clip)
	_player.play(clip)
	var frames := maxi(int(round(anim.length * FPS)), 1)
	var lowest := INF
	var highest := -INF
	var lowest_frame := 0
	var past_straight := 0
	var off_plane := 0.0
	for f in frames + 1:
		_player.seek(minf(float(f) / FPS, anim.length), true)
		await get_tree().process_frame
		var fold := _fold(side)
		off_plane = maxf(off_plane, absf(rad_to_deg(
			asin(clampf(_forearm_local(side).dot(_hinge[side]), -1.0, 1.0)))))
		if fold < lowest:
			lowest = fold
			lowest_frame = int(ORIGIN.get(clip, 0)) + f
		highest = maxf(highest, fold)
		if fold < 0.0:
			past_straight += 1
	var flag := ""
	if past_straight > 0:
		flag = "  <-- %d frames past straight, worst %.1f deg at source frame %d" % [
			past_straight, lowest, lowest_frame]
	print("  %-5s %-11s fold %+6.1f .. %+6.1f deg   out-of-plane %.1f%s"
		% [side, clip, lowest, highest, off_plane, flag])
