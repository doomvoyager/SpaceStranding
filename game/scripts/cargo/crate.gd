extends RigidBody3D
class_name Crate
## One unit of cargo.
##
## A crate is a real rigid body in the world and stays the same node its whole
## life. Picking it up freezes it, switches its collision off and reparents it
## into a CargoRack slot; putting it down reverses that. Nothing is destroyed
## and respawned, so a crate can never lose its identity — or, later, its
## accumulated damage — by being carried.
##
## Reparenting a frozen body onto a moving one is measured, not assumed:
## tests/probe_carried_body.gd drives a rotating, translating carrier and
## confirms the crate tracks its slot to 0.0000 m.

## Shown in the HUD prompt. Mass is the RigidBody3D `mass` property — set it in
## the inspector like any other body; the rover reads it straight off.
@export var cargo_name := "Supply crate"

@onready var _shape: CollisionShape3D = $Shape

## Layer/mask as authored, so putting a crate down restores whatever Mac set
## rather than a number hardcoded here.
var _loose_layer := 1
var _loose_mask := 1


func _ready() -> void:
	add_to_group("cargo")
	_loose_layer = collision_layer
	_loose_mask = collision_mask


## True while riding in a rack rather than lying in the world.
func is_stowed() -> bool:
	return rack() != null


## The rack this crate is riding in, or null if it is loose.
func rack() -> CargoRack:
	var slot := get_parent()
	if slot == null:
		return null
	return slot.get_parent() as CargoRack


## Ride in `slot`, inert and aligned to it.
func stow(slot: Node3D) -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_shape.disabled = true
	_move_to(slot)
	transform = Transform3D.IDENTITY


## Go back into the world at `at`, simulating again.
func release(world: Node, at: Transform3D) -> void:
	_move_to(world)
	global_transform = at
	_shape.disabled = false
	collision_layer = _loose_layer
	collision_mask = _loose_mask
	freeze = false
	# In 0.34 g a dropped crate drifts down slowly. Give it nothing extra.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _move_to(new_parent: Node) -> void:
	var old := get_parent()
	if old == new_parent:
		return
	if old != null:
		old.remove_child(self)
	new_parent.add_child(self)
