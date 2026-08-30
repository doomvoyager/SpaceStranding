extends RigidBody3D
class_name Crate
## One unit of cargo.
##
## A crate is a real rigid body in the world and stays the same node its whole
## life. Picking it up freezes it, switches its collision off and reparents it
## into a CargoRack slot; putting it down reverses that. Nothing is destroyed
## and respawned, so a crate can never lose its identity — or its accumulated
## damage — by being carried.
##
## Reparenting a frozen body onto a moving one is measured, not assumed:
## tests/probe_carried_body.gd drives a rotating, translating carrier and
## confirms the crate tracks its slot to 0.0000 m.

## Emitted whenever condition drops. `amount` is the loss, not the new value.
signal damaged(amount: float)

## Shown in the HUD prompt. Mass is the RigidBody3D `mass` property — set it in
## the inspector like any other body; the rover reads it straight off.
@export var cargo_name := "Supply crate"

@export_group("Fragility")
## Per-crate multiplier on every bit of damage taken. 0 is indestructible; 2 is
## twice as delicate as the baseline. This is the knob that makes a crate of
## instruments different from a crate of pipe.
@export_range(0.0, 4.0) var fragility := 1.0

## Jolt (m/s^2 of proper acceleration) the contents shrug off entirely.
##
## Not guessed. tests/probe_carrier_jolt.tscn drives the loaded rover over the
## real terrain and reports the distribution: a parked rover idles at 3.96,
## ten seconds of full throttle over broken ground peaks at 7.44, and a crate
## resting on the ground jitters at 6.32. Impacts start an order of magnitude
## higher — a 7 m drop runs 33 at p99. Twelve sits clear of everything ordinary
## with real headroom, which matters because the shipping terrain and a retuned
## engine will both push the driving numbers up.
@export var jolt_floor := 12.0

## The jolt that would destroy a fragility-1 crate in one second of sustained
## exposure. Damage rises with the *square* of the excess above the floor, so
## half this jolt does a quarter of the damage — which is what makes a single
## hard landing matter more than a long rough drive.
##
## Impacts last a tenth of a second, not a second, so nothing survivable gets
## close to a full second of this. Calibrated so a 7 m drop of the loaded rover
## costs roughly a tenth of the load's condition.
@export var jolt_ruin := 45.0

## 1.0 pristine, 0.0 destroyed. Only ever goes down: there is no field repair,
## and delivery pays on what arrives.
var condition := 1.0

@onready var _shape: CollisionShape3D = $Shape

## Layer/mask as authored, so putting a crate down restores whatever Mac set
## rather than a number hardcoded here.
var _loose_layer := 1
var _loose_mask := 1

## While loose, a crate is its own carrier and measures its own jolt. While
## stowed it is frozen and inert, so its rack measures for it and calls
## apply_jolt(). One damage curve, two sources.
var _meter := JoltMeter.new()


func _ready() -> void:
	add_to_group("cargo")
	_loose_layer = collision_layer
	_loose_mask = collision_mask
	_meter.gravity = Vector3(0.0, -World.SURFACE_GRAVITY, 0.0)
	_meter.reset(linear_velocity)


func _physics_process(delta: float) -> void:
	# A stowed crate is frozen with its velocity zeroed, so sampling it here
	# would read a permanent, comfortable nothing. Its rack drives it instead.
	if is_stowed():
		return
	apply_jolt(_meter.sample(linear_velocity, delta), delta)


## True while riding in a rack rather than lying in the world.
func is_stowed() -> bool:
	return rack() != null


## The rack this crate is riding in, or null if it is loose.
func rack() -> CargoRack:
	var slot := get_parent()
	if slot == null:
		return null
	return slot.get_parent() as CargoRack


# --- Condition ----------------------------------------------------------

## Take one physics frame of `jolt` (m/s^2 of proper acceleration).
##
## Damage is integrated over time rather than applied on a threshold crossing.
## That means no edge detection to get wrong, no double-counting a landing that
## spans several frames, and the same total damage at any tick rate.
func apply_jolt(jolt: float, delta: float) -> void:
	var excess := jolt - jolt_floor
	if excess <= 0.0:
		return
	var span := maxf(jolt_ruin - jolt_floor, 0.001)
	var rate := pow(excess / span, 2.0)
	take_damage(rate * delta)


## Lose `amount` of condition, scaled by this crate's fragility.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or condition <= 0.0:
		return
	var loss := minf(amount * fragility, condition)
	if loss <= 0.0:
		return
	condition -= loss
	damaged.emit(loss)


## Smoothed proper acceleration this crate is riding through, m/s^2. Only
## meaningful while loose; a stowed crate is driven by its rack. Diagnostics.
func jolt() -> float:
	return _meter.jolt


## Coarse word for the HUD and the delivery readout. Deliberately not a
## percentage: the player should be reading the crate, not a number.
##
## Static so a rack can label its worst crate without a second copy of these
## thresholds existing anywhere.
static func label_for(value: float) -> String:
	if value >= 0.99:
		return "pristine"
	elif value >= 0.75:
		return "scuffed"
	elif value >= 0.45:
		return "damaged"
	elif value >= 0.15:
		return "failing"
	return "ruined"


func condition_label() -> String:
	return label_for(condition)


# --- Carrying -----------------------------------------------------------

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
	# Being picked up is not an impact. Without this, stowing a crate while the
	# rover rolls reads the whole of its velocity as a step change and damages
	# cargo for the crime of being loaded.
	_meter.reset()


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
	_meter.reset()


func _move_to(new_parent: Node) -> void:
	var old := get_parent()
	if old == new_parent:
		return
	if old != null:
		old.remove_child(self)
	new_parent.add_child(self)
