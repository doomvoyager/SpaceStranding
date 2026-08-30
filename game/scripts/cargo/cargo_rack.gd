extends Node3D
class_name CargoRack
## An ordered set of cargo slots, shared by the rover's roof rack and the
## astronaut's back.
##
## The slots are this node's Node3D children, in tree order. That is the whole
## configuration: to move a slot, drag its marker in the editor; to change the
## capacity, add or delete a marker. No slot count lives in code.
##
## Occupancy is always derived by walking the slots, never cached. There is no
## second copy of the truth to fall out of sync with the scene tree.

## Appears in the HUD readout — "Back 1/2", "Rover 3/6".
@export var rack_name := "Rack"


## Slot markers, in tree order.
func slots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in get_children():
		var node := child as Node3D
		if node != null:
			out.append(node)
	return out


func capacity() -> int:
	return slots().size()


## The crate riding in `slot`, or null.
func crate_in(slot: Node3D) -> Crate:
	for child in slot.get_children():
		var crate := child as Crate
		if crate != null:
			return crate
	return null


func crates() -> Array[Crate]:
	var out: Array[Crate] = []
	for slot in slots():
		var crate := crate_in(slot)
		if crate != null:
			out.append(crate)
	return out


func count() -> int:
	return crates().size()


func is_full() -> bool:
	return first_free_slot() == null


func is_empty() -> bool:
	return count() == 0


func first_free_slot() -> Node3D:
	for slot in slots():
		if crate_in(slot) == null:
			return slot
	return null


## Last-in, first-out: you unload what you loaded most recently.
func last_loaded_crate() -> Crate:
	var found: Crate = null
	for slot in slots():
		var crate := crate_in(slot)
		if crate != null:
			found = crate
	return found


## Put `crate` in the first free slot. False if there is no room.
func load_crate(crate: Crate) -> bool:
	var slot := first_free_slot()
	if slot == null:
		return false
	crate.stow(slot)
	return true


func load_mass() -> float:
	var total := 0.0
	for crate in crates():
		total += crate.mass
	return total


## Mass-weighted centre of the load, expressed in this rack's *parent* space —
## which for the rover's roof rack is chassis space, exactly what
## RigidBody3D.center_of_mass wants. Zero when empty.
func load_centroid() -> Vector3:
	var total := 0.0
	var moment := Vector3.ZERO
	for slot in slots():
		var crate := crate_in(slot)
		if crate == null:
			continue
		total += crate.mass
		moment += crate.mass * (transform * slot.position)
	if total <= 0.0:
		return Vector3.ZERO
	return moment / total
