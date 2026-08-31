extends Node3D
class_name Facility
## A place with an identity: a terminal, a dock and a pad.
##
## A **Settlement** is a Facility with people in it. This is the fixture, and
## everything that is not about the people lives here — which is what lets an
## unmanned depot, a relay station and a drop site be the same node with a
## different name. See docs/02-Systems/Orders.md.
##
## Everything is authored in the editor. The parts are found by class among the
## children rather than by NodePath, so moving the dock or deleting the pad is
## a thing you do by dragging, not by also remembering to fix an export.
##
## The `id` is the load-bearing string. data/orders.tsv routes by it, and the
## pad accepts by it, so renaming a facility orphans every order addressed to
## it. Renaming `display_name` is free.

## Emitted when an order accepted here has put its crates on the dock, and when
## an abandoned one has taken them away again.
signal dock_changed

## Stable routing id — `hearth`, `longshadow`. Lowercase, no spaces. Everything
## in data/orders.tsv keys off this.
@export var facility_id := ""

## What the terminal and the board call this place.
@export var display_name := ""

## Scene spawned for every crate this facility issues. Its mass, fragility and
## value are then overwritten from the order — the row is the authoring
## surface, not a second copy of numbers that also live in the inspector.
@export var crate_scene: PackedScene = preload("res://scenes/cargo/crate.tscn")

## Where a crate goes when there is no room left on the dock. Crates are put
## down here rather than refused, because an order that cannot be issued is a
## dead end and a pile on the ground is not.
@onready var _overflow: Node3D = get_node_or_null("Overflow")

var _dock: CargoRack
var _pad: DeliveryPad
var _terminal: Node3D


func _ready() -> void:
	add_to_group("facility")
	if facility_id == "":
		printerr("FACILITY: '%s' has no facility_id and cannot be routed to" % name)
	if display_name == "":
		display_name = facility_id
	_dock = _find_child_of_type("CargoRack") as CargoRack
	_pad = _find_child_of_type("DeliveryPad") as DeliveryPad
	_terminal = _find_child_of_type("FacilityTerminal") as Node3D
	Orders.register_facility(self)


func _exit_tree() -> void:
	Orders.unregister_facility(self)


## Depth-first walk for the first descendant whose class matches. Deliberately
## not an @export NodePath: the parts are children of this node by definition,
## and a path is one more thing to keep in step with the scene.
func _find_child_of_type(type_name: String) -> Node:
	for child in get_children():
		if child.is_class(type_name) or child.get_script() != null and _script_class(child) == type_name:
			return child
		var found := _search(child, type_name)
		if found != null:
			return found
	return null


func _search(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.is_class(type_name) or child.get_script() != null and _script_class(child) == type_name:
			return child
		var found := _search(child, type_name)
		if found != null:
			return found
	return null


func _script_class(node: Node) -> String:
	var script := node.get_script() as Script
	return script.get_global_name() if script != null else ""


func dock() -> CargoRack:
	return _dock


func pad() -> DeliveryPad:
	return _pad


func terminal() -> Node3D:
	return _terminal


# --- Issuing ------------------------------------------------------------

## Accept `order` and put its crates on the dock.
##
## The crates are spawned here rather than existing in the scene, because until
## an order is taken its cargo is *stock* — abstract, in the facility's storage,
## not a rigid body anybody can trip over. Taking the order is what makes it
## real. Loose cargo is the other way round and is authored into the world.
func issue(order: Order) -> Array[Crate]:
	var made: Array[Crate] = []
	if order == null or order.is_loose():
		return made
	for i in order.crates:
		var crate := crate_scene.instantiate() as Crate
		crate.cargo_name = order.title
		crate.mass = order.mass_kg
		crate.fragility = order.fragility
		crate.value = order.value
		crate.cargo_owner = Crate.Owner.ORDER
		crate.owner_id = str(order.code)
		_place(crate)
		made.append(crate)
	dock_changed.emit()
	return made


## Put a crate on the dock if there is a free slot, otherwise on the ground
## beside it.
func _place(crate: Crate) -> void:
	var slot: Node3D = _dock.first_free_slot() if _dock != null else null
	if slot != null:
		slot.add_child(crate)
		crate.stow(slot)
		return
	var at := _overflow if _overflow != null else self
	get_tree().current_scene.add_child(crate)
	crate.global_transform = at.global_transform
	crate.position += Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))


## Take every crate belonging to `code` back, wherever it is. The order's row is
## then free to be taken again, and re-taking it issues pristine cargo.
##
## **The despawn is the reconditioning.** Until an order is accepted its cargo
## is stock — abstract, in storage, not a body anybody can trip over — so
## handing the order back puts it there and taking it again makes it real. That
## is the whole of "the facility reconditions it": there is no repair step,
## because there is nothing physical to repair while it sits on a shelf.
##
## Recall reaches into racks as well as the ground on purpose. A crate at the
## bottom of a ravine nothing can drive back into would otherwise make its order
## permanently unfinishable, which in a game with no combat and no fail state is
## a worse outcome than anything this permits.
##
## **Loose cargo is never recalled.** Its crate is authored into the scene
## rather than issued from here, so freeing it would delete something Mac
## placed and nothing would ever put it back. Found cargo cannot be handed back
## anyway — you were never given it.
func recall(code: int) -> int:
	var order := Orders.get_order(code)
	if order != null and order.is_loose():
		return 0
	var taken := 0
	for node in get_tree().get_nodes_in_group("cargo"):
		var crate := node as Crate
		if crate == null or crate.order_code() != code:
			continue
		_detach(crate)
		crate.queue_free()
		taken += 1
	dock_changed.emit()
	return taken


## Get a crate out of whatever is holding it before freeing it, so a rack does
## not spend a frame with a freed child and a rover does not keep its mass.
func _detach(crate: Crate) -> void:
	var rack := crate.rack()
	var parent := crate.get_parent()
	if parent != null:
		parent.remove_child(crate)
	if rack == null:
		return
	var rover := rack.get_parent() as Rover
	if rover != null:
		rover.refresh_load()


## Crates currently sitting on the dock.
func docked_crates() -> Array[Crate]:
	return _dock.crates() if _dock != null else [] as Array[Crate]
