extends Node3D
class_name AstronautRig
## The suited figure the player sees, and the machine that animates it.
##
## Six clips hang off one 41-bone Mixamo skeleton - idle, walk, run, and the
## jump cut into launch, float and land. They arrive as four AnimationLibraries,
## one per source FBX, so the names read `walk/walk` and `jump/fall`. Nothing is
## copied into an authored resource, which is the point: a re-export changes the
## clip and no second copy of it can be left saying otherwise.
##
## **The controller does not pick an animation.** It reports how fast the body
## is moving, whether it is on the ground, and which way it is going vertically;
## the state machine decides what that looks like. Anything else is two places
## that have to agree about what the astronaut is doing.

## The model faces +Z and the controller yaws the body so that -Z is forward,
## so the mesh is turned to meet it.
##
## Measured, not eyeballed: the rig's own ankle-to-toe vector comes out at
## (0.18, 0, 0.98). Getting this wrong makes the astronaut moonwalk, and the
## tempting fix - flipping the controller's `atan2` instead - would leave the
## camera-relative movement genuinely backwards. Same trap as the rover's
## ENGINE_FORCE_SIGN.
const MODEL_YAW := 180.0

## Below this ground speed the figure is standing rather than travelling, and
## the cycles play at their own pace so a near-still idle is not sped up.
const RESTING_SPEED := 1.0

@export_group("Locomotion")
## Ground speed the walk cycle's own legs are travelling at, m/s.
##
## Measured from the clip rather than guessed: the animations are in-place -
## the hips translate 0.000 m over every one of them - so the only record of
## intended speed is the stride the legs describe. Two steps to a cycle, widest
## toe separation 1.201 m over 1.167 s, so 2.06 m/s.
## `tests/probe_astronaut_clips.gd` prints it.
@export var walk_cycle_speed := 2.06
## The same for the run: 1.746 m over 0.800 s.
@export var run_cycle_speed := 4.36

## How much faster than its own legs the suit carries you.
##
## One number covers both cycles because the game's two speeds happen to sit at
## almost exactly the same multiple of their clips: 3.2 / 2.06 = 1.55 and
## 6.4 / 4.36 = 1.47. The blend space is fed `speed / stride_scale` and played
## back at `stride_scale`, so the legs cover the ground the body actually
## crosses. Raise it and the feet drag; lower it and they skate.
@export_range(0.5, 3.0, 0.05) var stride_scale := 1.5

@export_group("Suit")
## How much of the upper arm's roll to take out when the elbow is straight.
##
## The idle clip rolls the upper arms +14.9 and -27.0 degrees against a bind
## pose of zero, which swings the elbow's hinge axis 43 to 47 degrees off where
## the suit's elbow armour was modelled. Fine on a bare arm; on this one it puts
## the armour on the side of the joint, and with the elbow also nearly straight
## there is no bend left to say which way it folds. 1 restores the bind pose's
## roll exactly, 0 is the animation as authored, and the sweep that settled 0.8
## is in previews/2026-09-03/.
@export_range(0.0, 1.0, 0.01) var arm_untwist := 0.8

## The elbow fold, in degrees, at which the correction has faded to nothing.
##
## Roll only reads as wrong on a straight arm; once the joint is folded the bend
## itself says which way the hinge runs, and rolling a folded arm is real motion
## the run depends on. Below this the fix ramps in; above it the animation is
## untouched. Measured fold: the idle sits at 1-6 degrees, the walk 4-27, the
## run 59-125.
@export_range(5.0, 120.0, 1.0) var untwist_fold_limit := 45.0

@export_group("Blending")
## Seconds to cross from one locomotion speed to another. Only affects the
## blend space's own smoothing, not the state machine's transitions - those are
## on the transitions themselves, where the AnimationTree editor shows them.
@export_range(0.0, 0.5, 0.01) var speed_smoothing := 0.12

@onready var _tree: AnimationTree = $AnimationTree
@onready var _model: Node3D = $Model

## Built here rather than saved into the scene, because it has to be a child of
## the Skeleton3D and that lives inside the imported model. Putting it in the
## scene file would mean turning on editable children for the model instance,
## and an override inside an instanced scene is exactly what breaks when the
## mesh is re-exported - which is meant to stay a drop-in. Every knob it has is
## an `@export` up here, so nothing is hidden from the inspector or from F1.
var _untwist: UpperArmUntwist

## The blend space, held rather than re-fetched: `drive` runs every physics
## frame and walking the tree for it would be a lookup per frame for a node
## that cannot move.
var _locomotion: AnimationNodeBlendSpace1D
## Smoothed ground speed, in the blend space's units.
var _blend_speed := 0.0


func _ready() -> void:
	_model.rotation_degrees.y = MODEL_YAW
	var machine := _tree.tree_root as AnimationNodeStateMachine
	var ground := machine.get_node("Ground") as AnimationNodeBlendTree
	_locomotion = ground.get_node("Locomotion") as AnimationNodeBlendSpace1D
	_apply_cycle_speeds()
	_install_untwist()
	_tree.active = true


func _install_untwist() -> void:
	var skel := skeleton()
	if skel == null:
		push_warning("AstronautRig: no skeleton, arm untwist not installed")
		return
	_untwist = UpperArmUntwist.new()
	_untwist.name = "UpperArmUntwist"
	_untwist.rig = self
	skel.add_child(_untwist)


## The forearm correction, for tests and diagnostics.
func untwist_modifier() -> UpperArmUntwist:
	return _untwist


## Push the exported cycle speeds onto the blend space.
##
## They are `@export`s so the F1 panel can retune them while the game runs, and
## a value that only took effect at load would be a slider that does nothing.
func _apply_cycle_speeds() -> void:
	if _locomotion == null:
		return
	_locomotion.set_blend_point_position(1, walk_cycle_speed)
	_locomotion.set_blend_point_position(2, run_cycle_speed)
	_locomotion.max_space = maxf(run_cycle_speed, walk_cycle_speed)


## Tell the rig what the body is doing. Called once per physics frame.
##
## `vertical_speed` separates a jump from a fall, which is why it is passed
## rather than derived: leaving a ledge and pushing off it are the same
## "airborne" to anything that only looks at the floor.
func drive(speed: float, grounded: bool, vertical_speed: float, delta: float) -> void:
	_apply_cycle_speeds()

	# The blend space is in the clips' own units, so the controller's speed is
	# divided by the boost the suit gives, and the boost is put back as playback
	# rate below. Together they leave the feet where the ground is.
	var target := speed / maxf(stride_scale, 0.01)
	if speed_smoothing <= 0.0:
		_blend_speed = target
	else:
		_blend_speed = lerpf(_blend_speed, target, minf(delta / speed_smoothing, 1.0))
	_tree.set("parameters/Ground/Locomotion/blend_position", _blend_speed)

	# Eased to 1.0 as the figure comes to rest: at a standstill the blend is all
	# idle, and an idle played half again too fast reads as fidgeting.
	var travelling := clampf(speed / RESTING_SPEED, 0.0, 1.0)
	_tree.set("parameters/Ground/Stride/scale", lerpf(1.0, stride_scale, travelling))

	_tree.set("parameters/conditions/grounded", grounded)
	_tree.set("parameters/conditions/rising", not grounded and vertical_speed > 0.0)
	_tree.set("parameters/conditions/falling", not grounded and vertical_speed <= 0.0)


## Stop animating. Called when the player boards a vehicle and the figure is
## hidden - a hidden AnimationTree still evaluates its whole graph every frame.
func set_animating(animating: bool) -> void:
	_tree.active = animating


## Which state the machine is in, for tests and the F1 readout.
func current_state() -> StringName:
	var playback := _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	return playback.get_current_node() if playback != null else &""


## The skeleton, for anything that wants to hang off a bone - a head lamp that
## follows the helmet, a rack that rides the spine.
func skeleton() -> Skeleton3D:
	return _model.find_child("Skeleton3D", true, false) as Skeleton3D
