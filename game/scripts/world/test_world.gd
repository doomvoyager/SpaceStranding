extends Node3D
## Traversal-slice sandbox. Places the star, then drops the player and rover
## onto whatever the terrain generator produced.

@onready var _terrain: ProceduralTerrain = $Terrain
@onready var _astronaut: Astronaut = $Astronaut
@onready var _rover: Rover = $Rover
@onready var _star: DirectionalLight3D = $Star
@onready var _crates: Node3D = $Crates

## Half the 0.6 m crate, plus enough not to start interpenetrating the ground.
const CRATE_RESTING_CLEARANCE := 0.31


func _ready() -> void:
	_align_star()
	# The star is tunable at runtime from the debug panel, and its aim is baked
	# into the light's transform rather than read every frame.
	World.changed.connect(_align_star)
	_place_on_ground(_astronaut, Vector3(6.0, 0.0, 0.0), 1.2)
	_place_on_ground(_rover, Vector3(-6.0, 0.0, 0.0), 1.6)
	_place_on_ground($Beacon, Vector3(0.0, 0.0, -140.0), 0.0)
	_settle_crates()
	_settle_structures()


## Crates are hand-placed in the editor on X/Z; only their height is solved
## here, against whatever the terrain generator happened to produce.
##
## The clearance is half a crate plus a hair, so they start *resting* rather
## than falling. Cargo now takes damage from being dropped, and a crate spawned
## even 15 cm up lands hard enough to register — every crate in the world would
## start the session pre-scuffed for no reason the player could see. See
## [[Cargo]].
func _settle_crates() -> void:
	for child in _crates.get_children():
		var crate := child as Node3D
		if crate != null:
			_place_on_ground(crate, crate.global_position, CRATE_RESTING_CLEARANCE)


## Facilities and relays are hand-placed on X/Z in the editor exactly like the
## crates, and exactly like the crates only their *height* is solved here. Both
## scenes put their origin at the ground contact point - the facility's apron
## sits at y = 0 and the relay's plinth just above it - so they settle flush.
##
## They carried hand-tuned Y values baked against the procedural patch until the
## authored heightmap moved the ground out from under them and left the Hearth
## 13.6 m underground. The crates already had the fix; the structures were just
## never given it. Group membership rather than a tree walk, because both scenes
## already declare it and a new site should not have to be registered twice.
func _settle_structures() -> void:
	for group: String in ["facility", "relay"]:
		for node in get_tree().get_nodes_in_group(group):
			var n := node as Node3D
			if n != null:
				_place_on_ground(n, n.global_position, 0.0)


## Point the key light along the fixed star direction from World.
func _align_star() -> void:
	_star.look_at_from_position(
		Vector3(0.0, 400.0, 0.0),
		Vector3(0.0, 400.0, 0.0) + World.star_direction(),
		Vector3.UP
	)
	_star.light_color = World.star_color
	_star.light_energy = World.star_energy


## Drop `node` onto the terrain at `at`, `clearance` metres above the surface.
##
## height_at() reports a height in the terrain's **local** space, and the
## Terrain node carries its own transform — it is scaled on Y in the editor to
## flatten the world. Using that local height as a world Y put everything in
## the scene at twice the ground height, so the rover, the astronaut and every
## crate spawned in mid-air and fell. Invisible until cargo started taking
## damage from landing, at which point the world pre-scuffed its own crates.
## Convert back through the transform instead of assuming it is the identity.
func _place_on_ground(node: Node3D, at: Vector3, clearance: float) -> void:
	var local := _terrain.to_local(at)
	var h := _terrain.height_at(local.x, local.z)
	var surface := _terrain.to_global(Vector3(local.x, h, local.z))
	node.global_position = Vector3(at.x, surface.y + clearance, at.z)
