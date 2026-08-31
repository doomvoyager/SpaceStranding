extends Node3D
class_name Relay
## A mast that extends [[The-Lattice]].
##
## It does nothing on its own. Its whole job is to stand somewhere with line of
## sight to another site, so that two places which cannot see each other can see
## the mast instead — which is why relays belong on high ground and why choosing
## where to put one is meant to be gameplay rather than a radius check.
##
## **Authored in the scene for now.** Player-placed relays need the mast to be
## haulable cargo and a placement mode to go with it; the payoff had to exist
## first, or there would be nothing to place one *for*. See
## docs/02-Systems/The-Lattice.md.

## Stable network id. Everything in the graph keys off this.
@export var relay_id := ""

## Metres this mast will reach. Zero takes the network default, so a scene full
## of relays retunes from one place.
@export var range_override := 0.0

@onready var _antenna: Node3D = get_node_or_null("Antenna")


func _ready() -> void:
	add_to_group("relay")
	if relay_id == "":
		printerr("RELAY: '%s' has no relay_id and cannot be linked to" % name)
		return
	Lattice.register_site(self)


func _exit_tree() -> void:
	Lattice.unregister_site(self)


# --- The site interface -------------------------------------------------
##
## Duck-typed rather than inherited: Facility and Relay both extend Node3D, and
## GDScript has single inheritance. Three methods is a small enough contract to
## carry by hand.

func lattice_id() -> String:
	return relay_id


func link_range() -> float:
	return range_override if range_override > 0.0 else Lattice.default_range


## Where the antenna actually is. Height is most of what a relay is for, so this
## is deliberately the top of the mast and not the node's origin.
func mast_point() -> Vector3:
	return _antenna.global_position if _antenna != null else global_position
