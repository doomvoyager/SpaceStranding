@tool
extends RefCounted
## Keeps ground-anchored nodes sitting on the terrain while you drag them.
##
## The invariant, and the only rule in here:
##
##     global_position.y == terrain height at (x, z)  +  ground_clearance
##
## Both branches below maintain it. Drag a node across X/Z and its height is
## re-solved with the clearance preserved. Drag it *up* and the clearance
## absorbs the difference, because otherwise the number in the inspector and the
## number in the scene file would disagree — and the runtime re-solve, which
## trusts the clearance, would yank the node back down the moment you pressed
## play. The invariant is what makes the editor view and the running game agree.
##
## **Anchored** means "carries a `ground_clearance` property". Not a hand-written
## list of types: `debug_panel.gd` keeps one of those and it has already been
## the reason three finished systems reached nobody. A new node opts in by
## declaring the export, and needs no edit here.
##
## Only the *selection* is followed, which also settles when it is safe to
## write. A node you have not touched is never moved, so the snap can only ever
## piggyback on a drag the editor has already recorded as a change — it cannot
## dirty a scene on its own.

## The property that marks a node as sitting on the terrain.
const ANCHOR_PROPERTY := "ground_clearance"

## Slack on "did this move". Comfortably under a millimetre, and well over the
## float noise of composing a global transform back out of a parent's.
const EPSILON := 0.0001

## instance id -> the global position we last left the node at. A node absent
## from here has only just been selected, and is deliberately *not* snapped:
## selecting something must never edit it.
var _seen: Dictionary = {}


## Called every editor frame from the plugin.
func follow_selection(selection: EditorSelection) -> void:
	if selection == null:
		return
	var terrain := _find_terrain()
	if terrain == null:
		return

	var live: Dictionary = {}
	for node in selection.get_selected_nodes():
		var n := node as Node3D
		if n == null or not _is_anchored(n):
			continue
		var id := n.get_instance_id()
		live[id] = true
		var now := n.global_position
		if not _seen.has(id):
			_seen[id] = now
			continue
		var was: Vector3 = _seen[id]
		if now.is_equal_approx(was):
			continue
		_resolve(terrain, n, was, now)
		_seen[id] = n.global_position

	# Drop anything no longer selected, so re-selecting it starts clean rather
	# than comparing against wherever it was several edits ago.
	for id: int in _seen.keys():
		if not live.has(id):
			_seen.erase(id)


## The toolbar button: re-solve the selection whether or not it has moved, as
## one undoable action. This is the case the drag-follow cannot serve — a node
## whose stored height went stale because the *terrain* changed under it.
## Returns how many nodes were moved.
func snap_selection(selection: EditorSelection, undo_redo: EditorUndoRedoManager) -> int:
	if selection == null:
		return 0
	var terrain := _find_terrain()
	if terrain == null:
		push_warning("Snap to ground: no ProceduralTerrain in the edited scene.")
		return 0

	var targets: Array[Node3D] = []
	for node in selection.get_selected_nodes():
		var n := node as Node3D
		if n != null and _is_anchored(n):
			targets.append(n)
	if targets.is_empty():
		return 0

	undo_redo.create_action("Snap to ground")
	for n in targets:
		var to := _grounded_position(terrain, n, n.global_position)
		undo_redo.add_do_property(n, "global_position", to)
		undo_redo.add_undo_property(n, "global_position", n.global_position)
	undo_redo.commit_action()

	# The commit has already applied the new positions. Record them, or the
	# drag-follow reads its own action as a Y-only drag on the next frame and
	# folds the correction it just made into every clearance.
	for n in targets:
		_seen[n.get_instance_id()] = n.global_position
	return targets.size()


# --- The two branches ---------------------------------------------------

func _resolve(terrain: ProceduralTerrain, n: Node3D, was: Vector3, now: Vector3) -> void:
	var moved_flat := (absf(now.x - was.x) > EPSILON) or (absf(now.z - was.z) > EPSILON)
	if moved_flat:
		n.global_position = _grounded_position(terrain, n, now)
		return
	# Height alone. Whatever the drag produced is the height the author wants,
	# so the clearance moves to match it rather than the node being pulled back.
	var ground := terrain.world_height_at(now.x, now.z)
	n.set(ANCHOR_PROPERTY, now.y - ground)


func _grounded_position(terrain: ProceduralTerrain, n: Node3D, at: Vector3) -> Vector3:
	var clearance := float(n.get(ANCHOR_PROPERTY))
	return Vector3(at.x, terrain.world_height_at(at.x, at.z) + clearance, at.z)


# --- Finding things -----------------------------------------------------

func _is_anchored(n: Node3D) -> bool:
	return n.get(ANCHOR_PROPERTY) != null


## The terrain of the scene currently open, or null.
##
## Deliberately not cached across calls. The edited scene changes under this
## whenever a tab is switched, and a stale terrain would either be a freed
## object or — much worse — the wrong map to solve heights against.
func _find_terrain() -> ProceduralTerrain:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var terrain := _first_terrain(root)
	# An unbuilt terrain reports every height as zero, which would drag the whole
	# selection down to the terrain node's own origin — a destructive edit that
	# looks exactly like a correct one. Refuse instead.
	if terrain != null and not terrain.is_built():
		return null
	return terrain


func _first_terrain(node: Node) -> ProceduralTerrain:
	var terrain := node as ProceduralTerrain
	if terrain != null:
		return terrain
	for child in node.get_children():
		var found := _first_terrain(child)
		if found != null:
			return found
	return null
