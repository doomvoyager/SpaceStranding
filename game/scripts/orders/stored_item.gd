extends RefCounted
class_name StoredItem
## One thing sitting in a facility's storage.
##
## **Storage holds records, not nodes.** A warehouse full of frozen
## `RigidBody3D`s would be a great deal of physics for cargo nobody can see,
## touch or collide with. Putting a crate in records what it is and frees the
## node; taking it out builds a crate that is identical in every way the game
## reads — including **condition**, which is the one that matters.
##
## That reads against [[Cargo]]'s rule that a crate is the same node its whole
## life, so it is worth saying exactly where the line is: that rule is about
## being *carried*. A crate must not launder its damage by riding on a rack, and
## it does not. Going into a warehouse is not carrying, and `Facility.recall()`
## already established despawn-into-storage as the honest shape for cargo that
## has stopped being a physical object.
##
## See docs/02-Systems/Orders.md.

var cargo_name := "Supply crate"
var mass := 35.0
var fragility := 1.0
var value := 0.0
var condition := 1.0
var cargo_owner := Crate.Owner.PLAYER
## Facility id when FACILITY-owned; the order code as text when ORDER-owned.
var owner_id := ""


## Take a crate's identity. The crate itself is the caller's to dispose of —
## this does not free it, because a record that silently destroyed its subject
## would be a nasty thing to call by accident.
static func from_crate(crate: Crate) -> StoredItem:
	var item := StoredItem.new()
	item.cargo_name = crate.cargo_name
	item.mass = crate.mass
	item.fragility = crate.fragility
	item.value = crate.value
	item.condition = crate.condition
	item.cargo_owner = crate.cargo_owner
	item.owner_id = crate.owner_id
	return item


## Write this identity onto a freshly spawned crate.
func apply_to(crate: Crate) -> void:
	crate.cargo_name = cargo_name
	crate.mass = mass
	crate.fragility = fragility
	crate.value = value
	crate.condition = condition
	crate.cargo_owner = cargo_owner
	crate.owner_id = owner_id


## The order this belongs to, or 0.
func order_code() -> int:
	return int(owner_id) if cargo_owner == Crate.Owner.ORDER else 0


## Whether the player may take this out again. Facility stock is the facility's:
## you can see what a depot is holding without being able to help yourself to it.
func is_withdrawable() -> bool:
	return cargo_owner != Crate.Owner.FACILITY


## Same words as the crate, from the same shared function, so a thing cannot be
## graded one way on the ground and another on the shelf.
func condition_label() -> String:
	return Crate.label_for(condition)


## "Water canister · scuffed · 55 kg" — the line the storage list shows.
func summary() -> String:
	return "%s · %s · %.0f kg" % [cargo_name, condition_label(), mass]
