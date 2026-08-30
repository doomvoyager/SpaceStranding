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
##
## The rack is also the cargo's accelerometer. A stowed crate is frozen with its
## collision switched off, so it can never receive a contact event and cannot
## measure anything for itself — which is not a limitation to work around but
## the physically honest case: strapped-down cargo is not hurt by its own
## collisions, it is hurt by the vehicle slamming into things. The rack watches
## what the carrier does and passes it down, so the damage a load takes is a
## direct read on how the rover is being driven.

## Appears in the HUD readout — "Back 1/2", "Rover 3/6".
@export var rack_name := "Rack"

@export_group("Ride")
## Seconds of smoothing on the measured jolt. See JoltMeter — this is what makes
## the astronaut's single-frame landings comparable to the rover's solver-spread
## impacts, and what gives a brief impact enough duration to be integrated.
@export var jolt_smoothing := 0.05

var _meter := JoltMeter.new()
## The body whose motion this rack shares — the rover, or the astronaut.
var _carrier: Node3D = null
var _last_position := Vector3.ZERO


func _ready() -> void:
	_meter.gravity = World.gravity_vector()
	_meter.smoothing = jolt_smoothing
	World.changed.connect(_on_world_changed)
	_carrier = _find_carrier()
	_last_position = global_position
	_meter.reset()


## Gravity is tunable at runtime, and the meter holds a cached copy.
func _on_world_changed() -> void:
	_meter.gravity = World.gravity_vector()


## Walk up the tree for the nearest thing that actually moves under physics.
## Works for both racks without either scene knowing it is being watched: the
## rover *is* the rack's parent, the astronaut is its grandparent.
func _find_carrier() -> Node3D:
	var node := get_parent()
	while node != null:
		if node is RigidBody3D or node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _physics_process(delta: float) -> void:
	# Sampled even when empty, so the meter stays primed and loading a crate
	# mid-drive does not register the carrier's whole velocity as a step change.
	var jolt := _meter.sample(_carrier_velocity(delta), delta)
	var held := crates()
	if held.is_empty():
		return
	for crate in held:
		crate.apply_jolt(jolt, delta)


func _carrier_velocity(delta: float) -> Vector3:
	var rb := _carrier as RigidBody3D
	if rb != null:
		return rb.linear_velocity
	var cb := _carrier as CharacterBody3D
	if cb != null:
		return cb.velocity
	# No physics body above us — a test harness, or an animated platform.
	# Differentiate our own position instead.
	var here := global_position
	var moved := here - _last_position
	_last_position = here
	if delta <= 0.0:
		return Vector3.ZERO
	return moved / delta


## Smoothed proper acceleration the load is currently riding through, m/s^2.
## Diagnostics and HUD. Note this does *not* rest at one gravity on the rover:
## VehicleBody3D's sprung chassis never fully stops moving, so a parked rover
## carries a real idle jitter. Measured by tests/probe_carrier_jolt.tscn.
func jolt() -> float:
	return _meter.jolt


## The unsmoothed signal. Tuning and diagnostics only — damage runs off the
## smoothed value.
func raw_jolt() -> float:
	return _meter.raw_jolt


## Forget the motion history. Call after teleporting the carrier: the velocity
## step across a teleport is not something the cargo experienced.
func reset_jolt() -> void:
	_meter.reset()
	_last_position = global_position


# --- Slots --------------------------------------------------------------

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


# --- Load ---------------------------------------------------------------

func load_mass() -> float:
	var total := 0.0
	for crate in crates():
		total += crate.mass
	return total


## Condition of the worst crate aboard, or 1.0 when empty. What the HUD should
## show: a load is only as good as the item that arrives broken.
func worst_condition() -> float:
	var worst := 1.0
	for crate in crates():
		worst = minf(worst, crate.condition)
	return worst


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
