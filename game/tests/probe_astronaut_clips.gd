extends Node3D
## What speed do the authored walk and run cycles actually travel at?
##
## The clips are in-place - measured, the hips translate 0.000 m over every one
## of them - so nothing in the file says how fast the figure is meant to be
## moving. That number still exists, though: it is the stride the legs are
## describing. Two steps to a cycle, so
##
##     natural speed = 2 x (widest foot separation) / cycle length
##
## and a cycle played at any other ground speed slides its feet in proportion.
## This is what the blend space's points are set from, so the animation the
## controller picks at a given speed is the one whose legs are moving at it.
##
## Also re-checks the jump slices, which were cut from frames this probe's
## earlier form found in the uncut clip: takeoff f25, apex f31, touchdown f37
## of 65 at 30 fps. Those boundaries are now baked into Jump.fbx.import, so the
## check is that "jump" still leaves the ground and "land" still arrives on it.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##     res://tests/probe_astronaut_clips.tscn

const RIG := preload("res://assets/characters/astronaut/Idle_with_skin.fbx")
const LIBS := {
	"idle": preload("res://assets/characters/astronaut/Idle.fbx"),
	"walk": preload("res://assets/characters/astronaut/Standard_Walk.fbx"),
	"run": preload("res://assets/characters/astronaut/Standard_Run.fbx"),
	"jump": preload("res://assets/characters/astronaut/Jump.fbx"),
}
const SAMPLES := 60
## A toe this far off the floor counts as airborne.
const OFF_GROUND := 0.06

var _skel: Skeleton3D
var _player: AnimationPlayer


func _ready() -> void:
	var rig := RIG.instantiate()
	add_child(rig)
	_skel = rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_player = AnimationPlayer.new()
	add_child(_player)
	_player.root_node = _player.get_path_to(rig)
	for lib_name: String in LIBS:
		_player.add_animation_library(lib_name, LIBS[lib_name])

	for clip: String in ["walk/walk", "run/run"]:
		await _stride(clip)
	for clip: String in ["jump/jump", "jump/fall", "jump/land"]:
		await _air(clip)
	get_tree().quit()


## Widest horizontal gap between the toes over a cycle, and the ground speed
## that implies.
func _stride(clip: String) -> void:
	var anim := _player.get_animation(clip)
	var left := _skel.find_bone("mixamorig_LeftToe_End")
	var right := _skel.find_bone("mixamorig_RightToe_End")
	_player.play(clip)
	var widest := 0.0
	var at := 0.0
	for i in SAMPLES + 1:
		var t := anim.length * float(i) / float(SAMPLES)
		_player.seek(t, true)
		await get_tree().process_frame
		var a := _skel.get_bone_global_pose(left).origin
		var b := _skel.get_bone_global_pose(right).origin
		var gap := Vector2(a.x - b.x, a.z - b.z).length()
		if gap > widest:
			widest = gap
			at = t
	var speed := 2.0 * widest / anim.length
	print('%-10s len=%.3fs  widest stride=%.3f m at t=%.2f  => natural %.2f m/s'
		% [clip, anim.length, widest, at, speed])


## Does the clip have the figure off the ground, and at which end?
func _air(clip: String) -> void:
	var anim := _player.get_animation(clip)
	var toes := [_skel.find_bone("mixamorig_LeftToe_End"), _skel.find_bone("mixamorig_RightToe_End")]
	_player.play(clip)
	var first := INF
	var last := -INF
	var peak := 0.0
	for i in SAMPLES + 1:
		var t := anim.length * float(i) / float(SAMPLES)
		_player.seek(t, true)
		await get_tree().process_frame
		var low := INF
		for b: int in toes:
			low = minf(low, _skel.get_bone_global_pose(b).origin.y)
		peak = maxf(peak, low)
		if low > OFF_GROUND:
			first = minf(first, t)
			last = maxf(last, t)
	if first == INF:
		print('%-10s len=%.3fs  never leaves the ground (peak toe %.3f m)' % [clip, anim.length, peak])
	else:
		print('%-10s len=%.3fs  airborne %.3f..%.3f s  peak toe %.3f m'
			% [clip, anim.length, first, last, peak])
