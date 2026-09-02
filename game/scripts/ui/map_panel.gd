extends CanvasLayer
class_name MapPanel
## The map. **M**, and it works while driving.
##
## A 3D relief map in a SubViewport with its own World3D, rather than a camera
## pointed at the real one — see [[MapTerrain]] for why. This script owns the
## camera, the markers, the route line, and the list of legs down the side.
##
## Opening it hands the screen over the same way the order board does, through
## `Astronaut.set_menu_open()`. The world keeps running: this is not a pause,
## and the [[Rover]] lets go of its controls rather than freezing, so a rover
## left rolling coasts to a stop instead of stopping dead in mid-air.

signal closed

@export_group("Camera")
## Metres from the focus at the closest and furthest zoom.
@export var zoom_min := 120.0
@export var zoom_max := 3200.0
@export_range(1.02, 1.4, 0.01) var zoom_step := 1.12
## Degrees. Straight down reads as a flat picture and loses the relief that is
## the whole reason this is 3D, so the camera is not allowed to get there.
@export_range(5.0, 89.0, 1.0) var pitch_min := 12.0
@export_range(5.0, 89.0, 1.0) var pitch_max := 78.0
@export var orbit_sensitivity := 0.4
@export var pad_orbit_speed := 90.0
@export var pad_pan_speed := 0.9
## Zoom steps per second at full trigger.
@export var pad_zoom_speed := 8.0

@export_group("Markers")
@export var marker_lift := 6.0
@export var facility_color := Color(0.98, 0.80, 0.36)
@export var relay_color := Color(0.42, 0.86, 0.94)
@export var player_color := Color(0.86, 0.95, 1.0)
@export var rover_color := Color(0.95, 0.62, 0.42)
@export var route_color := Color(0.55, 0.95, 1.0)
@export var waypoint_color := Color(0.62, 1.0, 0.72)

@onready var _root: Control = $Root
@onready var _view_container: SubViewportContainer = \
	$Root/Frame/Margin/Rows/Panes/View
@onready var _viewport: SubViewport = $Root/Frame/Margin/Rows/Panes/View/Viewport
@onready var _cam: Camera3D = $Root/Frame/Margin/Rows/Panes/View/Viewport/Camera
@onready var _map: MapTerrain = $Root/Frame/Margin/Rows/Panes/View/Viewport/Map
@onready var _markers: Node3D = \
	$Root/Frame/Margin/Rows/Panes/View/Viewport/Markers
@onready var _route_line: MeshInstance3D = \
	$Root/Frame/Margin/Rows/Panes/View/Viewport/RouteLine
@onready var _legs: ItemList = $Root/Frame/Margin/Rows/Panes/Side/Legs
@onready var _summary: Label = $Root/Frame/Margin/Rows/Panes/Side/Summary
@onready var _hint: Label = $Root/Frame/Margin/Rows/Status
@onready var _up_button: Button = $Root/Frame/Margin/Rows/Panes/Side/Actions/Up
@onready var _down_button: Button = \
	$Root/Frame/Margin/Rows/Panes/Side/Actions/Down
@onready var _drop_button: Button = \
	$Root/Frame/Margin/Rows/Panes/Side/Actions/Drop
@onready var _clear_button: Button = \
	$Root/Frame/Margin/Rows/Panes/Side/Actions/Clear

var _open := false
var _focus := Vector3.ZERO
var _yaw := 0.0
var _pitch := 45.0
var _distance := 900.0
var _dragging := false
var _panning := false
## Screen distance the mouse moved during a press. A click that moved is a drag
## and must not also drop a waypoint where it started.
var _drag_travel := 0.0
var _line_mesh: ImmediateMesh
var _astronaut: Astronaut
## Where the player stood when the route line was last drawn, and whether
## anything since would change its shape rather than just where it starts.
var _line_from := Vector2.ZERO
var _line_stale := true


func _ready() -> void:
	add_to_group("map_panel")
	_root.visible = false
	_line_mesh = ImmediateMesh.new()
	_route_line.mesh = _line_mesh
	_view_container.gui_input.connect(_on_view_input)
	_legs.item_selected.connect(func(_i: int) -> void: _refresh_buttons())
	_up_button.pressed.connect(_move_selected.bind(-1))
	_down_button.pressed.connect(_move_selected.bind(1))
	_drop_button.pressed.connect(_drop_selected)
	_clear_button.pressed.connect(func() -> void: Route.clear())
	Route.changed.connect(_on_route_changed)
	Lattice.coverage_changed.connect(_rebuild_markers)
	# A rebuilt relief mesh moves the surface the line is laid on.
	_map.rebuilt.connect(func() -> void: _line_stale = true)
	_drop_focus()


## Nothing in this panel takes keyboard focus.
##
## Everything here is driven by a pointer — a mouse, or the left stick through
## PadCursor — so focus navigation has nothing to add, and leaving it on costs
## two real conflicts: `ui_left`/`ui_right` would move focus instead of panning
## the camera, and `A` would press whichever button happened to be focused *as
## well as* clicking wherever the pointer was.
func _drop_focus() -> void:
	for control in [_legs, _up_button, _down_button, _drop_button, _clear_button]:
		(control as Control).focus_mode = Control.FOCUS_NONE


## On its own key rather than through a verb, and in `_unhandled_input` rather
## than the astronaut, for the same reason the controls card is: it has to work
## while driving and while another panel is up, and neither of those routes
## input through the astronaut.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func toggle() -> void:
	close() if _open else open()


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	if _player() != null:
		_player().set_menu_open(true)
	# Frame the patch on the first open, then keep wherever the player left the
	# camera — coming back to a map you had already positioned and finding it
	# reset is worse than any default.
	if _focus == Vector3.ZERO:
		_focus = _map.centre()
		var span := _map.span()
		if span > 0.0:
			_distance = clampf(span * 0.75, zoom_min, zoom_max)
	_rebuild_markers()
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if _player() != null:
		_player().set_menu_open(false)
	closed.emit()


## Point the camera at a world X/Z from a given distance.
##
## Public for captures and tests, which need a repeatable framing rather than
## wherever the camera happened to be left. Nothing in the game calls it yet;
## "centre on the player" and "frame the whole route" are the obvious two.
func frame_on(world_xz: Vector2, distance: float) -> void:
	_focus = Vector3(world_xz.x, 0.0, world_xz.y)
	_distance = clampf(distance, zoom_min, zoom_max)
	_clamp_focus()
	_place_camera()


## The map view's rectangle on screen. For tests, and for anything that wants to
## aim a pointer at the map rather than at the panel around it.
func view_rect() -> Rect2:
	return _view_container.get_global_rect()


func _player() -> Astronaut:
	if _astronaut == null or not is_instance_valid(_astronaut):
		_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	return _astronaut


# --- Camera --------------------------------------------------------------

func _on_view_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_distance = clampf(_distance / zoom_step, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_distance = clampf(_distance * zoom_step, zoom_min, zoom_max)
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_dragging = true
					_drag_travel = 0.0
				else:
					_dragging = false
					# A press that never moved is a click, and a click plants a
					# waypoint. Anything else was an orbit that happened to
					# start somewhere.
					if _drag_travel < 6.0:
						_plant_at(button.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_drag_travel += motion.relative.length()
			_yaw -= motion.relative.x * orbit_sensitivity
			_pitch = clampf(_pitch + motion.relative.y * orbit_sensitivity,
				pitch_min, pitch_max)
		elif _panning:
			_pan(motion.relative)


## Pan the focus across the ground, scaled by zoom so a drag moves the same
## distance on screen at every altitude.
func _pan(screen_delta: Vector2) -> void:
	var scale := _distance * 0.0016
	var yaw := deg_to_rad(_yaw)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	_focus -= right * screen_delta.x * scale
	_focus -= forward * screen_delta.y * scale
	_clamp_focus()


## Keep the focus over the patch. Losing the map off the side of the screen with
## no way back is a worse failure than not being able to look at the void.
func _clamp_focus() -> void:
	var span := _map.span()
	if span <= 0.0:
		return
	var centre := _map.centre()
	var half := span * 0.5
	_focus.x = clampf(_focus.x, centre.x - half, centre.x + half)
	_focus.z = clampf(_focus.z, centre.z - half, centre.z + half)


func _place_camera() -> void:
	var focus := Vector3(_focus.x, _map.map_height(_focus.x, _focus.z), _focus.z)
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var offset := Vector3(
		sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)
	) * _distance
	_cam.position = focus + offset
	_cam.look_at(focus, Vector3.UP)


func _process(delta: float) -> void:
	if not _open:
		return
	# The pad drives the same camera as the mouse: right stick orbits, left
	# stick pans, shoulders zoom. Read here rather than as events because a
	# stick reports a held position and not a delta — the same reason the
	# astronaut polls its look stick.
	var orbit := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if orbit.length_squared() > 0.0001:
		_yaw -= orbit.x * pad_orbit_speed * delta
		_pitch = clampf(_pitch + orbit.y * pad_orbit_speed * delta,
			pitch_min, pitch_max)
	# Pan is on the d-pad, not the left stick: the left stick drives the pointer
	# now (see PadCursor), and placing a stop matters more than sweeping the
	# camera. `ui_*` is free to use for this because the panel's own controls
	# take no focus — see `_drop_focus()`.
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan.length_squared() > 0.0001:
		# _pan already scales by zoom, so this only has to turn a held direction
		# into the pixels-per-second a drag would have produced.
		_pan(pan * pad_pan_speed * 600.0 * delta)
	# Triggers zoom. Analog, so it is a rate rather than a step.
	var zoom := Input.get_axis("drive_back", "drive_forward")
	if absf(zoom) > 0.01:
		_distance = clampf(_distance * pow(zoom_step, -zoom * pad_zoom_speed * delta),
			zoom_min, zoom_max)
	_place_camera()
	_draw_route()
	_update_live_markers()


# --- Markers -------------------------------------------------------------

func _rebuild_markers() -> void:
	if not is_inside_tree():
		return
	for child in _markers.get_children():
		child.queue_free()
	for node in get_tree().get_nodes_in_group("facility"):
		var facility := node as Facility
		if facility != null:
			_add_marker(facility.global_position, facility.display_name,
				facility_color)
	for node in get_tree().get_nodes_in_group("relay"):
		var relay := node as Relay
		if relay != null:
			_add_marker(relay.global_position, relay.relay_id, relay_color)
	_add_marker(Vector3.ZERO, "You", player_color).name = "Player"
	var rover := get_tree().get_first_node_in_group("rover") as Node3D
	if rover != null:
		_add_marker(rover.global_position, "Rover", rover_color).name = "Rover"
	_rebuild_waypoint_markers()


## The two that move. Rebuilding every marker every frame to follow them would
## be thousands of node allocations a second for two dots.
func _update_live_markers() -> void:
	var player := _markers.get_node_or_null("Player") as Node3D
	if player != null and _player() != null:
		var at := _player().vantage()
		player.position = _map.map_point(at.x, at.z, marker_lift)
	var rover_marker := _markers.get_node_or_null("Rover") as Node3D
	var rover := get_tree().get_first_node_in_group("rover") as Node3D
	if rover_marker != null and rover != null:
		rover_marker.position = _map.map_point(
			rover.global_position.x, rover.global_position.z, marker_lift)


func _rebuild_waypoint_markers() -> void:
	for child in _markers.get_children():
		if String(child.name).begins_with("WP"):
			child.queue_free()
	for i in Route.count():
		var flat := Route.point_2d(i)
		var marker := _add_marker(Vector3(flat.x, 0.0, flat.y),
			"%d" % (i + 1), waypoint_color)
		marker.name = "WP%d" % i


func _add_marker(world: Vector3, text: String, colour: Color) -> Node3D:
	var holder := Node3D.new()
	holder.position = _map.map_point(world.x, world.z, marker_lift)
	_markers.add_child(holder)

	var pin := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, marker_lift * 2.0, 4.0)
	pin.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	pin.material_override = material
	pin.position = Vector3(0.0, -marker_lift, 0.0)
	holder.add_child(pin)

	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.font_size = 64
	label.modulate = colour
	label.position = Vector3(0.0, marker_lift * 0.9, 0.0)
	holder.add_child(label)
	return holder


# --- The route -----------------------------------------------------------

func _on_route_changed() -> void:
	_line_stale = true
	_rebuild_waypoint_markers()
	_refresh()


## Metres the player can move before the route line is redrawn.
##
## The line is hundreds of vertices and only its first one moves — it starts at
## your feet — so redrawing it every frame was a millisecond a frame for a
## picture that had not changed. Scaled by zoom, because a metre is a different
## number of pixels at every altitude: `_pan` already knows what one pixel is
## worth, and this is two of them, which is not a distance anybody can see.
func _line_step() -> float:
	return _distance * 0.0016 * 2.0


## Draw the route as a line that hugs the terrain, sampled the same way the leg
## lengths are measured. A straight line between two waypoints would cut through
## every ridge on the way and would disagree with the distance shown beside it.
##
## Only actually redrawn when it would look different — see `_line_step()`.
## `force` is for a capture or a test, which wants the line the frame it asks
## for it rather than after the player has walked two pixels.
func _draw_route(force := false) -> void:
	if _player() == null:
		return
	var here := _player().vantage()
	var start := Vector2(here.x, here.z)
	var moved := start.distance_to(_line_from)
	if not force and not _line_stale and moved <= _line_step():
		return
	_line_stale = false
	_line_from = start
	_line_mesh.clear_surfaces()
	if Route.is_empty():
		return
	var chain: Array[Vector2] = [start]
	for i in Route.count():
		chain.append(Route.point_2d(i))

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = route_color
	material.vertex_color_use_as_albedo = false

	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for leg in range(1, chain.size()):
		var from := chain[leg - 1]
		var to := chain[leg]
		var span := from.distance_to(to)
		var steps := maxi(int(ceil(span / Route.SAMPLE_STEP)), 1)
		var first := 0 if leg == 1 else 1
		for step in range(first, steps + 1):
			var at := from.lerp(to, float(step) / float(steps))
			_line_mesh.surface_add_vertex(_map.map_point(at.x, at.y, 2.0))
	_line_mesh.surface_end()


## Turn a click in the viewport into a waypoint on the ground.
func _plant_at(local: Vector2) -> void:
	var from := _cam.project_ray_origin(local)
	var direction := _cam.project_ray_normal(local)
	var hit := _map.surface_hit(from, direction)
	if not bool(hit["hit"]):
		_hint.text = "Nothing there — click on the ground."
		return
	var point: Vector3 = hit["point"]
	# Inserted after the selected leg rather than always appended, which is what
	# "I need to stop here on the way" means. With nothing selected it lands on
	# the end, which is what drawing a route forward means.
	var selected := _selected()
	if selected >= 0:
		_legs.select(Route.insert(selected + 1, point.x, point.z))
	else:
		Route.add(point.x, point.z)


func _selected() -> int:
	var rows := _legs.get_selected_items()
	return -1 if rows.is_empty() else rows[0]


func _move_selected(by: int) -> void:
	var at := _selected()
	if at < 0:
		return
	_legs.select(Route.move(at, at + by))
	_refresh_buttons()


func _drop_selected() -> void:
	var at := _selected()
	if at < 0:
		return
	Route.remove_at(at)


# --- The side panel ------------------------------------------------------

func _refresh() -> void:
	var keep := _selected()
	_legs.clear()
	var start := Vector2.ZERO
	if _player() != null:
		var at := _player().vantage()
		start = Vector2(at.x, at.z)
	for i in Route.count():
		var flat := Route.point_2d(i)
		var covered := Lattice.is_covered(flat.x, flat.y)
		# Marked rather than hidden, which was Mac's call for the whole map.
		_legs.add_item("%d   %s   %s" % [
			i + 1,
			_distance_text(Route.leg_length(i, start)),
			"linked" if covered else "dark",
		])
	if keep >= 0 and keep < _legs.item_count:
		_legs.select(keep)
	if Route.is_empty():
		_summary.text = "No route planned."
	else:
		_summary.text = "%d stops · %s over the ground" % [
			Route.count(), _distance_text(Route.total_distance(start)),
		]
	_refresh_buttons()


func _refresh_buttons() -> void:
	var at := _selected()
	_up_button.disabled = at <= 0
	_down_button.disabled = at < 0 or at >= Route.count() - 1
	_drop_button.disabled = at < 0
	_clear_button.disabled = Route.is_empty()


func _distance_text(metres: float) -> String:
	if metres >= 1000.0:
		return "%.2f km" % (metres / 1000.0)
	return "%.0f m" % metres
