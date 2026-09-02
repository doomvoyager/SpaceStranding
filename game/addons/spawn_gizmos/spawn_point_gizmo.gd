@tool
extends EditorNode3DGizmoPlugin
## Draws spawn markers, and the tether that shows how far anything anchored is
## sitting off the ground.
##
## Two kinds of node get a gizmo:
##
## * A [SpawnPoint] gets the full marker — a stake, a contact ring, a facing
##   arrow and its id — because nothing else in the scene represents it. It has
##   no mesh and no collision; without this it is an empty Node3D and the thing
##   it stands for is invisible until the game runs.
## * Anything else carrying `ground_clearance` — a facility, a relay, a crate —
##   gets just the tether and ring. Those already have meshes; what they lack is
##   any way to see the *ground* under them, which is the number that was wrong
##   the day the Hearth ended up 13.6 m underground.
##
## Drawn straight into the viewport, so none of this is a node and none of it
## can be serialised into the scene. Everything below is in the gizmo node's own
## local space, and world-space offsets are pushed back through the inverse
## basis so a rotated crate still gets a tether pointing at the ground rather
## than at its own idea of down.

const ANCHOR_PROPERTY := "ground_clearance"

const MARKER := "spawn_marker"
const TETHER := "ground_tether"
const HANDLE := "spawn_handles"

## Which handle is which. There is only one, and naming it beats a bare 0.
const HANDLE_CLEARANCE := 0

const RING_SEGMENTS := 24
const RING_RADIUS := 0.9
const STAKE_HEIGHT := 2.2
const ARROW_LENGTH := 1.8
## Sideways offset of the clearance handle, so grabbing it is not a fight with
## the translate gizmo sitting on the origin.
const HANDLE_OFFSET := 0.75

## Set by plugin.gd. Handle drags are a user edit like any other and belong in
## the undo history; a gizmo plugin has no way to reach one on its own.
var undo_redo: EditorUndoRedoManager


func _init() -> void:
	create_material(MARKER, Color(1.0, 0.72, 0.25))
	create_material(TETHER, Color(0.42, 0.82, 1.0))
	create_handle_material(HANDLE)


func _get_gizmo_name() -> String:
	return "SpawnPoint"


## Drawn under other geometry rather than over it, so a marker standing in a dip
## reads as being in a dip instead of floating in front of the hill.
func _get_priority() -> int:
	return -1


func _has_gizmo(node: Node3D) -> bool:
	return node is SpawnPoint or node.get(ANCHOR_PROPERTY) != null


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if node == null:
		return
	var clearance := float(node.get(ANCHOR_PROPERTY))
	# World-space offsets have to come back through the inverse basis: a crate
	# tipped on its side still hangs off ground that is below it in *world*
	# terms, not below it in its own.
	var inv := node.global_transform.basis.inverse()
	var contact := inv * (Vector3.DOWN * clearance)

	var point := node as SpawnPoint
	if point == null:
		_draw_tether(gizmo, inv, contact, TETHER, 0.45)
		return

	_draw_tether(gizmo, inv, contact, MARKER, 1.0)
	_draw_stake(gizmo, inv, contact)
	_draw_facing(gizmo, inv)
	_draw_id(gizmo, point)
	gizmo.add_handles(
		PackedVector3Array([Vector3(HANDLE_OFFSET, 0.0, 0.0)]),
		get_material(HANDLE, gizmo),
		PackedInt32Array([HANDLE_CLEARANCE])
	)


# --- Pieces -------------------------------------------------------------

## The line down to the ground and the ring where it lands. This is the whole
## gizmo for a facility or a crate: it answers "how far off the ground is this",
## which is the one thing the mesh itself cannot tell you.
func _draw_tether(gizmo: EditorNode3DGizmo, inv: Basis, contact: Vector3,
		material: String, scale: float) -> void:
	var lines := PackedVector3Array([Vector3.ZERO, contact])
	var radius := RING_RADIUS * scale
	for i in RING_SEGMENTS:
		lines.append(contact + inv * _ring_point(i, radius))
		lines.append(contact + inv * _ring_point(i + 1, radius))
	gizmo.add_lines(lines, get_material(material, gizmo))


## A mast tall enough to pick out from across a valley, plus a cross at the
## spawn height itself so the two are not confused at a glance.
func _draw_stake(gizmo: EditorNode3DGizmo, inv: Basis, contact: Vector3) -> void:
	var top := inv * (Vector3.UP * STAKE_HEIGHT)
	var arm := inv * (Vector3.RIGHT * 0.35)
	var fwd := inv * (Vector3.FORWARD * 0.35)
	gizmo.add_lines(PackedVector3Array([
		contact, top,
		-arm, arm,
		-fwd, fwd,
	]), get_material(MARKER, gizmo))


## Which way the spawned thing will face. -Z, like every other node in Godot.
func _draw_facing(gizmo: EditorNode3DGizmo, inv: Basis) -> void:
	var base := inv * (Vector3.UP * 0.15)
	var tip := base + inv * (Vector3.FORWARD * ARROW_LENGTH)
	var barb := ARROW_LENGTH * 0.25
	gizmo.add_lines(PackedVector3Array([
		base, tip,
		tip, tip + inv * Vector3(barb, 0.0, barb),
		tip, tip + inv * Vector3(-barb, 0.0, barb),
	]), get_material(MARKER, gizmo))


## The id, as real geometry — Godot 4 gizmos have no text call, and a marker you
## cannot identify without clicking it is half a gizmo. TextMesh is a mesh like
## any other, so it goes through add_mesh.
func _draw_id(gizmo: EditorNode3DGizmo, point: SpawnPoint) -> void:
	if point.spawn_id == "":
		return
	var text := TextMesh.new()
	text.text = point.spawn_id
	text.font_size = 48
	text.pixel_size = 0.008
	text.depth = 0.0

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.72, 0.25)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var at := Transform3D(Basis.IDENTITY, Vector3(0.0, STAKE_HEIGHT + 0.35, 0.0))
	gizmo.add_mesh(text, mat, at)


func _ring_point(i: int, radius: float) -> Vector3:
	var a := TAU * float(i) / float(RING_SEGMENTS)
	return Vector3(cos(a) * radius, 0.0, sin(a) * radius)


# --- The clearance handle -----------------------------------------------
##
## Dragging it vertically sets `ground_clearance`, which moves the node, because
## the invariant the snapper keeps is `y == ground + clearance`. The ground
## height never has to be looked up: it is `y - clearance` by that same rule, so
## the gizmo needs no reference to the terrain at all.

func _get_handle_name(_gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> String:
	return "Ground clearance"


func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	var node := gizmo.get_node_3d()
	return 0.0 if node == null else float(node.get(ANCHOR_PROPERTY))


func _set_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool,
		camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	if node == null:
		return
	var origin := node.global_position
	var ground := origin.y - float(node.get(ANCHOR_PROPERTY))

	# Closest approach between the mouse ray and the vertical line through the
	# node. Segments rather than an analytic ray-line solve because Geometry3D
	# already has it, and the ends only have to reach further than the map.
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var pair := Geometry3D.get_closest_points_between_segments(
		origin - Vector3.UP * 4096.0, origin + Vector3.UP * 4096.0,
		from, from + dir * 8192.0)

	var clearance: float = pair[0].y - ground
	node.set(ANCHOR_PROPERTY, clearance)
	node.global_position = Vector3(origin.x, ground + clearance, origin.z)


func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool,
		restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	if node == null:
		return
	var clearance := float(node.get(ANCHOR_PROPERTY))
	var origin := node.global_position
	var ground := origin.y - clearance
	var was := float(restore)

	if cancel:
		node.set(ANCHOR_PROPERTY, was)
		node.global_position = Vector3(origin.x, ground + was, origin.z)
		return
	if undo_redo == null:
		return

	# The drag has already moved the node. Both halves are written out in full
	# so undo restores the pair together — a clearance that disagreed with the
	# height would be exactly the drift this gizmo exists to make impossible.
	undo_redo.create_action("Set ground clearance")
	undo_redo.add_do_property(node, ANCHOR_PROPERTY, clearance)
	undo_redo.add_do_property(node, "global_position", origin)
	undo_redo.add_undo_property(node, ANCHOR_PROPERTY, was)
	undo_redo.add_undo_property(node, "global_position",
		Vector3(origin.x, ground + was, origin.z))
	undo_redo.commit_action(false)
