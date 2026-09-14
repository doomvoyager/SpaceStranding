extends Node3D
class_name Footprints
## Boot prints, read off the skeleton and pressed into the track map.
##
## A child of the astronaut. Every physics tick it takes the two toe bones'
## world positions, asks the ground under each how far away it is, and calls
## a foot *down* when the toe is within `contact_height` of the ground and
## moving slower than `contact_speed`. The moment a foot goes from up to down
## is a landing, and a landing stamps a print into the [[Tracks]] map, one
## boot long and wide, headed the way the foot points.
##
## **The animation is not consulted**, on purpose (2026-09-14, with new
## animations coming). Where and when a foot lands comes from wherever the
## clip actually puts it, so a new walk, a run, a hop or a moonwalk backwards
## stamps correctly with nothing re-authored. What the rig has to keep is the
## four bone names below, which are exports; and its feet have to reach the
## ground, which a slider forgives. `probe_astronaut_clips` reads the same
## bones the same way to measure stride.
##
## Only ground in the `terrain` group takes a print: a facility deck does
## not. Nothing stamps while the astronaut is hidden aboard the rover.

@export_group("Rig")
## The skeleton, or empty for the first Skeleton3D under the parent.
@export var skeleton_path: NodePath
@export var left_foot_bone := "mixamorig_LeftFoot"
@export var left_toe_bone := "mixamorig_LeftToe_End"
@export var right_foot_bone := "mixamorig_RightFoot"
@export var right_toe_bone := "mixamorig_RightToe_End"

@export_group("Landing")
## A toe this close to the ground, metres, counts as down.
@export_range(0.0, 0.5, 0.005) var contact_height := 0.08
## And moving slower than this across the ground, m/s. The swinging foot
## moves at about twice the walking speed, so there is room; the planted one
## is not quite still, because the clip slides a little under a body moving
## at 3 m/s, and at 0.8 that flutter double-stamped a foot every few strides.
@export_range(0.0, 5.0, 0.05) var contact_speed := 1.5
## A foot prints again only this far from its last print: an idle bob across
## the threshold does not stamp in place, and a stride is over a metre.
@export_range(0.0, 2.0, 0.01) var min_step := 0.5

@export_group("Print")
## The boot, metres: an Apollo overshoe is about 0.33 by 0.16. The map's
## 8 cm texels resolve the length and barely the width, so a print is a
## dash at any distance and a boot up close; finer texels cost window.
@export_range(0.05, 1.0, 0.01) var print_length := 0.33
@export_range(0.05, 1.0, 0.01) var print_width := 0.17
## How hard it presses, 0..1, as the map reads it.
@export_range(0.0, 1.0, 0.01) var depth := 0.9


class Foot:
	var name: String
	var foot := -1
	var toe := -1
	var down := false
	var last_print := Vector2.INF
	var last_toe := Vector3.ZERO
	var seen := false


var _body: Node3D
var _skeleton: Skeleton3D
var _feet: Array[Foot] = []
var _map: TrackMap
var _prints := 0
## The last few prints, oldest first: [foot name, centre XZ]. For the test.
var _recent: Array = []
## The lowest a toe has been above the ground, for tuning `contact_height`.
var _lowest_toe := INF


func _ready() -> void:
	_body = get_parent() as Node3D
	# The rig is an instanced scene under the parent, built before this node
	# runs, but the astronaut dresses it in its own _ready; bind after that.
	call_deferred("_bind")


func _physics_process(delta: float) -> void:
	if _skeleton == null:
		return
	if _map == null:
		_map = get_tree().get_first_node_in_group("track_map") as TrackMap
		if _map == null:
			return
	if _body != null and not _body.visible:
		for f in _feet:
			f.down = false
			f.seen = false
		return
	var space := get_world_3d().direct_space_state
	for f in _feet:
		var toe := _bone_world(f.toe)
		var heel := _bone_world(f.foot)
		var speed := 0.0
		if f.seen and delta > 0.0:
			var moved := toe - f.last_toe
			moved.y = 0.0
			speed = moved.length() / delta
		f.last_toe = toe
		f.seen = true

		var ground := _ground_under(space, toe)
		var down := false
		if ground.hit:
			var height: float = toe.y - ground.y
			_lowest_toe = minf(_lowest_toe, height)
			down = is_down(height, speed, contact_height, contact_speed)
		if down and not f.down and ground.on_terrain:
			var pose := print_pose(Vector2(heel.x, heel.z), Vector2(toe.x, toe.z), print_length)
			var centre: Vector2 = pose.centre
			if centre.distance_to(f.last_print) >= min_step:
				_map.stamp(centre, pose.heading, depth, print_length, print_width)
				f.last_print = centre
				_prints += 1
				_recent.append([f.name, centre])
				if _recent.size() > 64:
					_recent.pop_front()
		f.down = down


## Prints stamped so far.
func prints() -> int:
	return _prints


## The last prints, oldest first, as [foot name, centre XZ].
func recent() -> Array:
	return _recent.duplicate()


## The lowest a toe has come to the ground so far, metres. INF until a toe
## has been over ground.
func lowest_toe() -> float:
	return _lowest_toe


## Whether the skeleton and all four bones were found.
func is_bound() -> bool:
	return _skeleton != null and _feet.size() == 2


# --- The rules, pure so the test can hold them ------------------------------

## A foot is down when it is close to the ground and nearly still.
static func is_down(height: float, speed: float, max_height: float, max_speed: float) -> bool:
	return height <= max_height and speed <= max_speed


## Where a print goes and which way it points, from the heel and toe on the
## ground plane: centred under the foot, headed heel to toe. A foot with no
## length - the bones on top of each other - points along +X, which is a
## print rather than none.
static func print_pose(heel_xz: Vector2, toe_xz: Vector2, length: float) -> Dictionary:
	var dir := toe_xz - heel_xz
	if dir.length_squared() < 1e-8:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	return {
		"centre": toe_xz - dir * length * 0.5,
		"heading": atan2(dir.y, dir.x),
	}


# --- Internals ------------------------------------------------------------------


func _bind() -> void:
	if not skeleton_path.is_empty():
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null and _body != null:
		var found := _body.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_skeleton = found[0] as Skeleton3D
	if _skeleton == null:
		push_warning("Footprints: no Skeleton3D under %s" % (_body.name if _body else "nothing"))
		return
	_feet.clear()
	for spec in [["left", left_foot_bone, left_toe_bone], ["right", right_foot_bone, right_toe_bone]]:
		var f := Foot.new()
		f.name = spec[0]
		f.foot = _skeleton.find_bone(spec[1])
		f.toe = _skeleton.find_bone(spec[2])
		if f.foot < 0 or f.toe < 0:
			push_warning("Footprints: %s foot bones '%s' / '%s' not in the skeleton"
				% [spec[0], spec[1], spec[2]])
			continue
		_feet.append(f)
	_map = get_tree().get_first_node_in_group("track_map") as TrackMap


func _bone_world(bone: int) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


## The ground under a toe: whether anything is there within half a metre
## either way, how high it is, and whether it is terrain.
func _ground_under(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 0.5, at + Vector3.DOWN * 0.6)
	if _body is CollisionObject3D:
		query.exclude = [(_body as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "y": 0.0, "on_terrain": false}
	return {
		"hit": true,
		"y": (hit.position as Vector3).y,
		"on_terrain": _is_terrain(hit.collider as Node),
	}


## Terrain is whatever is in the `terrain` group, or has an ancestor in it:
## the ground's collider is a StaticBody3D under the terrain node.
static func _is_terrain(node: Node) -> bool:
	var n := node
	for i in 4:
		if n == null:
			return false
		if n.is_in_group("terrain"):
			return true
		n = n.get_parent()
	return false
