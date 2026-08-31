extends CharacterBody3D
class_name Astronaut
## Third-person suited-astronaut controller tuned for 0.34 g.
##
## The low-gravity feel comes from three things, in order of importance:
##   1. Almost no air control. A jump is a commitment, not a steering input.
##   2. Slow ground acceleration. The suit has mass and the regolith has no grip.
##   3. Long hang time, which falls out of the project gravity setting for free.

@export_group("Movement")
## Comfortable suited walking pace, m/s.
@export var walk_speed := 3.2
## Assisted lope. The exo can push harder, but not indefinitely.
@export var sprint_speed := 6.4
## How hard we can push against the ground. Low: boots slip.
@export var ground_acceleration := 9.0
@export var ground_friction := 11.0
## Deliberately tiny. Once airborne you are ballistic.
@export var air_acceleration := 1.2

@export_group("Jump")
## Peak height in metres at this planet's gravity.
@export var jump_height := 1.9
## Grace period after leaving a ledge during which a jump still registers.
@export var coyote_time := 0.15

@export_group("Camera")
@export var mouse_sensitivity := 0.0022
## Right-stick turn rate, radians/sec. A stick holds a position rather than
## emitting deltas, so this is a speed where the mouse figure is a multiplier.
@export var stick_sensitivity := 2.6
@export_range(-80.0, 0.0) var pitch_min := -65.0
@export_range(0.0, 80.0) var pitch_max := 45.0
## How fast the body swings to face the direction of travel, radians/sec.
@export var turn_speed := 7.0

@onready var _cam_pivot: Node3D = $CamPivot
@onready var _spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _body: Node3D = $Body
@onready var _interact_zone: Area3D = $InteractZone
@onready var _back_rack: CargoRack = $Body/CargoRack
@onready var _drop_point: Marker3D = $Body/DropPoint

var _time_since_grounded := 0.0
var _mouse_captured := false
## True while we are sitting in a vehicle; suppresses our own look and interact.
var _driving := false
## True while a full-screen panel has the player's attention. Suppresses look,
## movement and both cargo verbs — but not gravity, because standing at a
## terminal on a slope should not make you hover.
var _menu_open := false


func _ready() -> void:
	add_to_group("player")
	_capture_mouse(true)


func _capture_mouse(captured: bool) -> void:
	_mouse_captured = captured
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse"):
		_capture_mouse(not _mouse_captured)
		return

	# While driving, the vehicle owns the camera and the interact key.
	if _driving:
		return

	# A panel owns the whole screen. Deliberately does *not* consume the event:
	# the panel closes itself on the next `interact`, and it can only see the
	# press if we let it past.
	if _menu_open:
		return

	if event is InputEventMouseMotion and _mouse_captured:
		_cam_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x,
			deg_to_rad(pitch_min),
			deg_to_rad(pitch_max)
		)

	if event.is_action_pressed("interact"):
		_interact()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("drop_cargo"):
		_move_cargo()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _driving or _menu_open:
		return
	StickLook.apply(
		_cam_pivot, _spring_arm, stick_sensitivity, pitch_min, pitch_max, delta
	)


func _physics_process(delta: float) -> void:
	var grounded := is_on_floor()
	_time_since_grounded = 0.0 if grounded else _time_since_grounded + delta

	if not grounded:
		velocity.y -= World.surface_gravity * delta

	if _menu_open:
		# Still fall, still collide, but take no input. Coming out of a panel
		# mid-stride and finding yourself somewhere else would be worse than
		# standing still.
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and _time_since_grounded <= coyote_time:
		# v = sqrt(2 * g * h)
		velocity.y = sqrt(2.0 * World.surface_gravity * jump_height)
		_time_since_grounded = coyote_time + 1.0  # consume the coyote window

	_apply_horizontal_movement(delta, grounded)
	move_and_slide()
	_face_travel_direction(delta)


func _apply_horizontal_movement(delta: float, grounded: bool) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# get_vector already clamps to length 1, so its magnitude *is* how far the
	# stick was pushed. Keep it separately: normalising the direction throws it
	# away, which made half a stick walk at full speed. The keyboard produces
	# exactly 1, so nothing changes there.
	var throw := minf(input.length(), 1.0)

	# Movement is relative to where the camera is looking, not where the body faces.
	var basis := _cam_pivot.global_transform.basis
	var wish_dir := (basis.x * input.x + basis.z * input.y)
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_acceleration if grounded else air_acceleration
	var target := wish_dir * speed * throw
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	if wish_dir.is_zero_approx() and grounded:
		horizontal = horizontal.move_toward(Vector3.ZERO, ground_friction * delta)
	else:
		horizontal = horizontal.move_toward(target, accel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _face_travel_direction(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.04:
		return
	var target_yaw := atan2(-horizontal.x, -horizontal.z)
	_body.rotation.y = rotate_toward(_body.rotation.y, target_yaw, turn_speed * delta)


# --- Interaction --------------------------------------------------------
##
## Two verbs, and they never overlap:
##
##   interact (E / A) — deal with the world. Pick up a loose crate if one is in
##                      range, otherwise board the rover.
##   drop_cargo (F / X) — move cargo. Carrying something, it goes on the rover's
##                      rack if you are beside it and there is room, otherwise
##                      on the ground. Empty-handed beside a loaded rover, it
##                      comes off the rack instead.
##
## Boarding therefore never competes with unloading, so walking up to a loaded
## rover to drive it always just drives it.

func _interact() -> void:
	var crate := nearest_loose_crate()
	if crate != null and not _back_rack.is_full():
		_back_rack.load_crate(crate)
		# Cargo lying in the world carries a code but no obligation until it is
		# in someone's hands. Picking it up is what makes its destination
		# readable and lets the pad there take it in.
		Orders.notice_found(crate.order_code())
		return
	var terminal := nearby_terminal()
	if terminal != null:
		_open_board(terminal)
		return
	_try_enter_rover()


func _move_cargo() -> void:
	if _menu_open:
		return
	var rover := nearby_rover()
	var dock := nearby_dock()

	if _back_rack.is_empty():
		# Empty-handed: take one off whatever is holding cargo. The rover wins
		# when both are in reach, because standing between the two you are far
		# more often unloading a haul than restocking a pallet.
		var source := _unload_source(rover, dock)
		if source == null:
			return
		var stowed := source.last_loaded_crate()
		if stowed == null:
			return
		_back_rack.load_crate(stowed)
		if rover != null and source == rover.cargo_rack():
			rover.refresh_load()
		return

	var carried := _back_rack.last_loaded_crate()
	if rover != null and not rover.cargo_rack().is_full():
		rover.cargo_rack().load_crate(carried)
		rover.refresh_load()
		return
	if dock != null and not dock.is_full():
		dock.load_crate(carried)
		return

	carried.release(get_parent(), _drop_point.global_transform)


## Which rack `F` would take a crate off, or null if neither has one.
func _unload_source(rover: Rover, dock: CargoRack) -> CargoRack:
	if rover != null and not rover.cargo_rack().is_empty():
		return rover.cargo_rack()
	if dock != null and not dock.is_empty():
		return dock
	return null


## Nearest crate lying loose within the interact zone, or null.
func nearest_loose_crate() -> Crate:
	var best: Crate = null
	var best_dist := INF
	for body in _interact_zone.get_overlapping_bodies():
		var crate := body as Crate
		if crate == null or crate.is_stowed():
			continue
		var dist := global_position.distance_squared_to(crate.global_position)
		if dist < best_dist:
			best_dist = dist
			best = crate
	return best


## The facility terminal within reach, or null. A terminal is a StaticBody3D
## precisely so it shows up here — an Area3D one would be invisible to the
## interact zone, which reads bodies.
func nearby_terminal() -> FacilityTerminal:
	for body in _interact_zone.get_overlapping_bodies():
		var terminal := body as FacilityTerminal
		if terminal != null and terminal.facility() != null:
			return terminal
	return null


## The facility dock within reach, or null.
##
## Matched off the deck's own body rather than off anything in the facility, so
## standing at the pad does not let you reach a pallet eight metres away.
func nearby_dock() -> CargoRack:
	for body in _interact_zone.get_overlapping_bodies():
		if not body.is_in_group("dock_deck"):
			continue
		var node: Node = body
		while node != null:
			var facility := node as Facility
			if facility != null:
				return facility.dock()
			node = node.get_parent()
	return null


## The rover within reach, or null.
func nearby_rover() -> Rover:
	for body in _interact_zone.get_overlapping_bodies():
		var rover := body as Rover
		if rover != null:
			return rover
	return null


func back_rack() -> CargoRack:
	return _back_rack


## What `interact` would do right now, for the HUD. Empty when there is nothing.
func interact_prompt() -> String:
	if _menu_open:
		return "Close the board"
	if _driving:
		return "Leave the rover"
	var crate := nearest_loose_crate()
	if crate != null and not _back_rack.is_full():
		return "Pick up %s" % crate.cargo_name
	var terminal := nearby_terminal()
	if terminal != null:
		return terminal.interact_prompt()
	if nearby_rover() != null:
		return "Board the rover"
	return ""


## What `drop_cargo` would do right now, for the HUD.
func cargo_prompt() -> String:
	if _driving or _menu_open:
		return ""
	var rover := nearby_rover()
	var dock := nearby_dock()
	if _back_rack.is_empty():
		var source := _unload_source(rover, dock)
		if source == null:
			return ""
		return "Take a crate off the %s" % source.rack_name.to_lower()
	if rover != null and not rover.cargo_rack().is_full():
		return "Stow on the rover"
	if dock != null and not dock.is_full():
		return "Set it on the dock"
	return "Put the crate down"


# --- The order board ----------------------------------------------------
##
## The panel is found by group rather than held as an export, the same way the
## HUD finds the pad: boards are world content and a scene that streams one in
## later should still work.

func _open_board(terminal: FacilityTerminal) -> void:
	var panel := get_tree().get_first_node_in_group("order_panel") as OrderPanel
	if panel == null:
		return
	_menu_open = true
	_capture_mouse(false)
	if not panel.closed.is_connected(_on_board_closed):
		panel.closed.connect(_on_board_closed)
	panel.open(terminal.facility())


func _on_board_closed() -> void:
	_menu_open = false
	_capture_mouse(true)


## True while a panel has the screen. The HUD dims itself on this.
func is_menu_open() -> bool:
	return _menu_open


# --- Vehicles -----------------------------------------------------------

func _try_enter_rover() -> void:
	var rover := nearby_rover()
	if rover == null:
		return
	rover.enter(self)


## Called by the rover when we climb in.
func board_vehicle() -> void:
	_driving = true
	set_physics_process(false)
	_camera.current = false
	visible = false
	# Stop colliding so the rover does not shove a ghost body around.
	collision_layer = 0
	collision_mask = 0


## Called by the rover when we climb out, at the given world position.
func disembark(at: Vector3) -> void:
	_driving = false
	global_position = at
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	visible = true
	_camera.current = true
	set_physics_process(true)
