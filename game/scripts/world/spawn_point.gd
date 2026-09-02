extends Node3D
class_name SpawnPoint
## An authored place in the world: an id, a position and a facing.
##
## The three placements `test_world.gd` used to hardcode — the astronaut, the
## rover and the beacon — were `Vector3` literals inside `_ready()`. Invisible
## in the editor, a code edit to move, and written against the *world origin*,
## which stopped meaning anything the moment the authored heightmap put the
## terrain 1.3 km off it. This is the node that replaces them.
##
## A SpawnPoint is a plain `Node3D`. You move it with the ordinary translate
## gizmo and rotate it to set which way the spawned thing faces.
## `res://addons/spawn_gizmos` draws it in the viewport and re-solves its height
## against the heightmap while you drag it across X/Z, so the marker is always
## standing on the ground and what you see is where the thing lands.
##
## **Nothing here depends on the addon.** With the plugin disabled you lose the
## drawing and the live snap; the scene still spawns exactly where the node
## sits, because the solved height is written into the `.tscn` rather than kept
## in the editor's head. The runtime solve in `test_world.gd` stays on as the
## safety net that catches a re-baked or retuned terrain.

## Group every marker joins on ready, so a consumer can find one from anywhere
## in the scene rather than only under an agreed parent node.
const GROUP := "spawn_point"

## What this point is for — `astronaut`, `rover`, `beacon`. Looked up by string,
## so it has to be unique in the scene and match what the code asks for. A blank
## id is a marker nothing will ever find, which is worth complaining about.
@export var spawn_id := ""

## Metres between the terrain surface and this node.
##
## The marker's own position is already the final spot: the editor snap folds
## the clearance in when it solves. This records *how far up* that was, so the
## runtime re-solve lands in the same place after a terrain rebuild, and so
## dragging the marker vertically has somewhere to be stored.
@export var ground_clearance := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if spawn_id == "":
		printerr("SPAWNPOINT: '%s' has no spawn_id and will never be found" % name)


## Move `node` here, taking this marker's yaw as the facing.
##
## Yaw only. A spawn marker tilted by a careless drag should not lay the rover
## on its side, and nothing we spawn wants to follow the slope — the astronaut
## and the rover are bodies that settle, and the beacon is a mast that should
## stand up straight whatever it is standing on.
func place(node: Node3D) -> void:
	node.global_position = global_position
	node.global_rotation = Vector3(0.0, global_rotation.y, 0.0)


## The marker with `id`, or null. Static so a caller does not need to have found
## one already, and tree-wide so markers can be organised however Mac likes.
static func find(tree: SceneTree, id: String) -> SpawnPoint:
	for node in tree.get_nodes_in_group(GROUP):
		var point := node as SpawnPoint
		if point != null and point.spawn_id == id:
			return point
	return null
