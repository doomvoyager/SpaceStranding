extends StaticBody3D
class_name FacilityTerminal
## The thing you walk up to and press E at.
##
## A StaticBody3D rather than an Area3D, and not by accident: the astronaut's
## interact zone reads `get_overlapping_bodies()`, so an Area3D terminal would
## be invisible to it. A terminal you can walk through would also be a strange
## object. Solid is both the honest shape and the one that works.
##
## The terminal knows almost nothing. It finds the Facility it hangs off and
## hands it to the panel; the board's rules live in OrderBook and the panel's
## layout lives in the panel. This exists so that "press E here" has somewhere
## to be true.

@export var prompt := "Read the order board"


func _ready() -> void:
	add_to_group("terminal")


## The Facility this terminal belongs to, or null if it has been parented
## somewhere that is not one.
func facility() -> Facility:
	var node := get_parent()
	while node != null:
		var found := node as Facility
		if found != null:
			return found
		node = node.get_parent()
	return null


## What the HUD should say E would do. Empty when this terminal is not usable,
## so the prompt can never offer something the key will not deliver.
func interact_prompt() -> String:
	var owner_facility := facility()
	if owner_facility == null:
		return ""
	var board := Orders.board_for(owner_facility.facility_id)
	if board.is_empty():
		return "%s — no orders" % owner_facility.display_name
	return "%s — %d orders" % [owner_facility.display_name, board.size()]
