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

@export_group("Ownership")
## Who this crate belongs to. **Not** what is in it — contents are the order's
## `type`, and conflating the two makes "why can I not use this one" a rule to
## memorise instead of a label to read. Can the player build with it? Only if
## it is PLAYER. See docs/02-Systems/Orders.md.
##
## Note the name: `owner` is taken by Node, and shadowing it would break scene
## serialisation in ways that do not announce themselves.
@export var cargo_owner: Owner = Owner.PLAYER

## Facility id when FACILITY-owned; the order code as text when ORDER-owned.
## Blank otherwise. One field rather than two, so the two can never disagree.
@export var owner_id := ""

## What a pristine one of these is worth. Zero means "the pad decides", which
## is what unowned world crates do — order cargo is priced by data/orders.tsv.
@export var value := 0.0

enum Owner {
	## Lying in the world, belonging to nobody yet.
	NONE,
	## The player's, and usable for construction once that exists.
	PLAYER,
	## Stock sitting in a facility.
	FACILITY,
	## Cargo attached to an order, until it is delivered.
	ORDER,
}

@export_group("Fragility")
## Per-crate multiplier on every bit of damage taken. 0 is indestructible; 2 is
## twice as delicate as the baseline. This is the knob that makes a crate of
## instruments different from a crate of pipe.
@export_range(0.0, 4.0) var fragility := 1.0

## Jolt (m/s^2 of proper acceleration) the contents shrug off entirely.
##
## Not guessed. tests/probe_carrier_jolt.tscn drives the loaded rover over the
## real terrain and reports the distribution. Re-measured at 0.55 g, because
## every one of these numbers scales with the planet: a parked rover idles at
## 5.44 and tops out at 7.37, and ten seconds of full throttle over broken
## ground peaks at 6.94. Impacts still start an order of magnitude higher — a
## 7 m drop runs 54.6 at p99. Twelve still sits clear of everything ordinary,
## with less headroom than it had at 0.34 g but enough that a full-throttle
## run over the worst ground leaves the load pristine — verified, not assumed.
@export var jolt_floor := 12.0

## The jolt that would destroy a fragility-1 crate in one second of sustained
## exposure. Damage rises with the *square* of the excess above the floor, so
## half this jolt does a quarter of the damage — which is what makes a single
## hard landing matter more than a long rough drive.
##
## Impacts last a tenth of a second, not a second, so nothing survivable gets
## close to a full second of this. Left where it was when gravity went from
## 0.34 g to 0.55 g: the threshold is in absolute m/s^2, and a heavier planet
## making a drop more expensive is the physics doing its job rather than a
## calibration going stale. The same 7 m drop of the loaded rover went from
## costing roughly a tenth of the load's condition to costing 0.22.
@export var jolt_ruin := 45.0

@export_group("Deployment")
## What this crate becomes when it is raised in the field, or null for
## ordinary freight — which is nearly all of it.
##
## A mast is the first cargo that is not just weight with an address: where it
## ends up is the decision, not the errand. Setting this is what turns a crate
## from something you deliver into something you site, and it is what the HUD
## keys its survey readout off.
##
## A property rather than a subclass or a type list, for the same reason
## ground_clearance is one: a new deployable opts in by declaring what it
## becomes, without anything anywhere else learning it exists.
@export var deploys_as: PackedScene

@export_group("Placement")
## Metres between the terrain surface and this crate's origin, when it is
## authored into a scene rather than issued by a facility.
##
## Half the 0.6 m crate plus a hair, so a world crate starts *resting* instead
## of falling. Cargo takes damage from being dropped and one spawned even 15 cm
## up lands hard enough to register, so the whole world would begin the session
## pre-scuffed for no reason the player could see. See [[Cargo]].
##
## The editor reads this too: `res://addons/spawn_gizmos` keeps the crate at
## exactly this height above the ground while you drag it, so the height in the
## scene file is the height you will get.
@export var ground_clearance := 0.31

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
	_meter.gravity = World.gravity_vector()
	_meter.reset(linear_velocity)
	# Gravity is tunable at runtime from the debug panel, and the meter holds a
	# cached copy. Without this, retuning the planet leaves every crate
	# measuring jolt against the old gravity.
	World.changed.connect(_on_world_changed)


func _physics_process(delta: float) -> void:
	# A stowed crate is frozen with its velocity zeroed, so sampling it here
	# would read a permanent, comfortable nothing. Its rack drives it instead.
	if is_stowed():
		return
	apply_jolt(_meter.sample(linear_velocity, delta), delta)


## The structure this crate was raised into, or null. A crate inside a mast is
## as inert as one strapped to a rack, and nothing that walks racks would ever
## find it — so without this it would report itself loose and go on measuring
## its own jolt from inside a static mast.
var _raised_into: Node3D = null


## True while riding in a rack, or inside something it was raised into,
## rather than lying loose in the world.
func is_stowed() -> bool:
	return rack() != null or _raised_into != null


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


func _on_world_changed() -> void:
	_meter.gravity = World.gravity_vector()


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


## The order this crate belongs to, or 0 if it belongs to nobody.
func order_code() -> int:
	return int(owner_id) if cargo_owner == Owner.ORDER else 0



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
	_raised_into = null
	_move_to(world)
	global_transform = at
	_shape.disabled = false
	collision_layer = _loose_layer
	collision_mask = _loose_mask
	freeze = false
	# In 0.55 g a dropped crate still falls softly. Give it nothing extra.
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


## Whether this crate is something you raise rather than something you drop
## off. See `deploys_as`.
func is_deployable() -> bool:
	return deploys_as != null


## Become what `deploys_as` says, standing at `at`, parented under `parent`.
## Returns the new structure, or null if this crate does not deploy into
## anything.
##
## The crate is not consumed. It is stowed inside the structure and hidden, the
## same freeze-and-reparent a rack does, so lowering the mast later hands back
## this exact node with its damage and its owner intact.
func raise_into(parent: Node, at: Vector3) -> Node3D:
	if deploys_as == null or parent == null:
		return null
	var structure := deploys_as.instantiate() as Node3D
	if structure == null:
		return null
	# Named *before* it enters the tree. _ready() runs on add_child, and a Relay
	# with no id refuses to register — it would stand there looking like a mast
	# and be absent from the graph.
	#
	# Named *unconditionally*, not just when the id is blank. relay.tscn carries
	# "relay" as its authored default, so a blank check never fires and every
	# mast anyone raised would come out sharing one id — the second silently
	# replacing the first in the graph. A raised mast is never the scene's
	# relay, so it never wants the scene's name.
	if structure is Relay:
		(structure as Relay).relay_id = Lattice.unique_site_id("mast")
	structure.position = at
	parent.add_child(structure)
	# Authoritative, in case `parent` carries a transform of its own. The graph
	# rebuild is deferred, so it still solves against this and not against the
	# origin the node briefly sat at.
	structure.global_position = at
	_raised_into = structure
	if structure is Relay:
		(structure as Relay).raised_from = self
	stow(structure)
	visible = false
	return structure