extends Node3D
## Traversal-slice sandbox. Places the star, then drops the player and rover
## onto whatever the terrain generator produced.
##
## **Nothing in here decides where anything goes any more.** The astronaut, the
## rover and the beacon used to be `Vector3` literals a few lines below — which
## made them invisible in the editor, a code edit to move, and written against
## the world origin, a point that stopped meaning anything the moment the
## authored heightmap put the terrain 1.3 km off it. They are [SpawnPoint]
## markers now, dragged in the viewport with `res://addons/spawn_gizmos`
## drawing them. This script only looks them up.
##
## What it still does is **solve height**, for markers and authored props alike.
## The editor writes a solved height into the scene, so the two agree on load —
## but a marker's stored Y is only as fresh as the last time the scene was open,
## and the debug panel can retune the terrain mid-session. X/Z is authored;
## height is derived, always, from whatever the ground turned out to be.

@onready var _terrain: ProceduralTerrain = $Terrain
@onready var _astronaut: Astronaut = $Astronaut
@onready var _rover: Rover = $Rover
@onready var _star: DirectionalLight3D = $Star

## Where each spawn goes when the scene carries no marker for it — the literals
## this script used to hold, kept so a stripped-down test scene still works.
## `id -> [offset from the world origin, clearance]`.
const FALLBACKS := {
	"astronaut": [Vector3(6.0, 0.0, 0.0), 1.2],
	"rover": [Vector3(-6.0, 0.0, 0.0), 1.6],
	"beacon": [Vector3(0.0, 0.0, -140.0), 0.0],
}


func _ready() -> void:
	_align_star()
	# The star is tunable at runtime from the debug panel, and its aim is baked
	# into the light's transform rather than read every frame.
	World.changed.connect(_align_star)
	_place_at_spawn(_astronaut, "astronaut")
	_place_at_spawn(_rover, "rover")
	_place_at_spawn($Beacon, "beacon")
	_settle_cargo()
	_settle_structures()


## Put `node` at the marker with `id`, facing the way the marker faces.
##
## The height is re-solved even though the marker already carries one, for the
## same reason the crates and structures below are: the ground can move under an
## authored position, and it has.
func _place_at_spawn(node: Node3D, id: String) -> void:
	var point := SpawnPoint.find(get_tree(), id)
	if point != null:
		point.place(node)
		_place_on_ground(node, node.global_position, point.ground_clearance)
		return
	var fallback: Array = FALLBACKS[id]
	_place_on_ground(node, fallback[0], fallback[1])


## Crates are hand-placed in the editor on X/Z; only their height is solved
## here, against whatever the terrain generator happened to produce.
##
## The clearance is the crate's own `ground_clearance` — half a crate plus a
## hair — so they start *resting* rather than falling. Cargo takes damage from
## being dropped, and a crate spawned even 15 cm up lands hard enough to
## register: every crate in the world would start the session pre-scuffed for no
## reason the player could see. See [[Cargo]].
##
## By group and not by container. This walked the children of `$Crates` alone,
## which quietly meant the recovered mast parked under `$LooseCargo` was the one
## crate in the scene keeping a hand-tuned Y. A stowed crate is riding in a rack
## and belongs to its slot, so it is skipped rather than dropped on the floor.
func _settle_cargo() -> void:
	for node in get_tree().get_nodes_in_group("cargo"):
		var crate := node as Crate
		if crate != null and not crate.is_stowed():
			_place_on_ground(crate, crate.global_position, crate.ground_clearance)


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
				_place_on_ground(n, n.global_position, float(n.get("ground_clearance")))


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
