@tool
extends EditorPlugin
## Editor-only placement tooling: gizmos for spawn markers, and ground snapping
## for anything authored on X/Z whose height is solved rather than typed.
##
## Everything in this folder is a convenience. The game does not load it, no
## runtime code reaches into it, and turning the plugin off costs you the
## drawing and the snap and nothing else — the positions it writes live in the
## `.tscn` like any other transform.
##
## Why an addon rather than `@tool` scripts on the nodes themselves: a gizmo is
## drawn straight into the viewport, so there are no preview meshes to keep out
## of the scene file. This project has already baked a six-figure-triangle mesh
## into a `.tscn` by giving a generated node an `owner`; gizmo geometry cannot
## make that mistake because it never becomes a node. It also keeps `@tool` off
## `facility.gd`, `relay.gd` and `crate.gd`, which would otherwise start running
## their `_ready()` — and their autoload registrations — inside the editor.

const SpawnPointGizmo := preload("res://addons/spawn_gizmos/spawn_point_gizmo.gd")
const GroundSnapper := preload("res://addons/spawn_gizmos/ground_snapper.gd")

var _gizmo_plugin: EditorNode3DGizmoPlugin
var _snapper: RefCounted
var _snap_button: Button


func _enter_tree() -> void:
	_gizmo_plugin = SpawnPointGizmo.new()
	# A gizmo plugin has no route to the undo history of its own, so the handle
	# drag would otherwise be the one edit in the editor you cannot undo.
	_gizmo_plugin.undo_redo = get_undo_redo()
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	_snapper = GroundSnapper.new()

	# Deliberate re-snap, for the case the drag-follow below cannot cover: a
	# node whose stored height went stale because the terrain was rebuilt under
	# it, not because anybody moved it.
	_snap_button = Button.new()
	_snap_button.text = "Snap to ground"
	_snap_button.tooltip_text = ("Re-solve the height of every selected "
		+ "ground-anchored node against the terrain.")
	_snap_button.pressed.connect(_on_snap_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _snap_button)


func _exit_tree() -> void:
	if _snap_button != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _snap_button)
		_snap_button.queue_free()
		_snap_button = null
	if _gizmo_plugin != null:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null
	_snapper = null


## The drag-follow. Polling the selection each editor frame rather than hooking
## `NOTIFICATION_TRANSFORM_CHANGED` on the nodes, because that notification
## would have to be enabled from a `@tool` script on every anchored type — and
## writing a position from inside the handler re-enters it.
func _process(_delta: float) -> void:
	if _snapper != null:
		_snapper.follow_selection(EditorInterface.get_selection())


func _on_snap_pressed() -> void:
	if _snapper == null:
		return
	var moved: int = _snapper.snap_selection(
		EditorInterface.get_selection(), get_undo_redo())
	if moved == 0:
		push_warning("Snap to ground: nothing selected that sits on the terrain.")
