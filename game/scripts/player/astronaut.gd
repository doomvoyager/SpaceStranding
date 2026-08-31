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

@export_group("Interaction")
## How far off the look direction something can be and still be reachable.
## Generous on purpose: this is meant to disambiguate a crate from the rover
## beside it, not to demand precise aim. Past 90 the thing is beside you, and
## past that it is behind you.
@export_range(20.0, 110.0, 1.0) var interact_half_angle := 80.0

## How much being off-axis counts against something, relative to being far away.
##
## Zero is the old behaviour exactly — nearest wins, aim ignored. At 3.0 a crate
## 1.5 m away at 60 degrees loses to the rover 2.5 m away dead ahead, which is
## the case this was built for, while the same crate at 30 degrees still wins.
@export_range(0.0, 8.0, 0.1) var aim_bias := 3.0

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
##   interact (E / A) — deal with the world. A loose crate, a facility terminal,
##                      or the rover.
##   drop_cargo (F / X) — move cargo. Carrying: onto a rack with room, else on
##                      the ground. Empty-handed: off a rack that has something.
##
## Boarding never competes with unloading, so walking up to a loaded rover to
## drive it always just drives it. That was settled 2026-08-30.
##
## **Which of several things a verb acts on is decided by where you are
## looking**, not by a fixed order of preference. The sphere is only the broad
## phase — "what is nearby" — and everything it finds is then scored on how well
## it is lined up. A crate lying beside the rover used to be picked up whatever
## you wanted, because the list tried crates first; now you get whichever one
## you are facing.
##
## Two details that are load-bearing:
##
##   **Camera forward, not body forward.** The body only turns while you are
##   moving (see _face_travel_direction), so aiming off the body would mean
##   standing still and turning the camera changed nothing. Where the camera
##   looks is what the player means.
##
##   **Horizontal only.** A crate at your feet is a long way below the camera's
##   forward ray, and a full 3D dot product would rule it out for being on the
##   ground. Height is not what "in front of me" is about.
##
## A screen-centre raycast — the other standard answer — was rejected: the chase
## camera sits behind and above, so a ray through the reticle spends most of its
## time hitting terrain short of anything worth touching.

## Kinds of thing that can be reached. Plain constants rather than an enum,
## because Reachable is an inner class and reaching an enum from one is more
## ceremony than it is worth.
const KIND_CRATE := 0
const KIND_TERMINAL := 1
const KIND_ROVER := 2
const KIND_DOCK := 3


## One interactable in reach, and how well it is lined up. `score` is
## lower-is-better, so picking a target is a min.
class Reachable:
	var node: Node3D
	var kind: int
	var score: float

	func _init(target: Node3D, target_kind: int, aim_score: float) -> void:
		node = target
		kind = target_kind
		score = aim_score


func _interact() -> void:
	var target := interact_target()
	if target == null:
		return
	match target.kind:
		KIND_CRATE:
			var crate := target.node as Crate
			_back_rack.load_crate(crate)
			# Cargo lying in the world carries a code but no obligation until it
			# is in someone's hands. Picking it up is what makes its destination
			# readable and lets the pad there take it in.
			Orders.notice_found(crate.order_code())
		KIND_TERMINAL:
			_open_board(target.node as FacilityTerminal)
		KIND_ROVER:
			(target.node as Rover).enter(self)


func _move_cargo() -> void:
	if _menu_open:
		return
	var target := cargo_target()

	if _back_rack.is_empty():
		# Empty-handed: take one off whatever you are facing that has cargo.
		if target == null:
			return
		var source := _rack_of(target)
		var stowed := source.last_loaded_crate()
		if stowed == null:
			return
		_back_rack.load_crate(stowed)
		if target.kind == KIND_ROVER:
			(target.node as Rover).refresh_load()
		return

	var carried := _back_rack.last_loaded_crate()
	if target != null:
		_rack_of(target).load_crate(carried)
		if target.kind == KIND_ROVER:
			(target.node as Rover).refresh_load()
		return

	carried.release(get_parent(), _drop_point.global_transform)


# --- Aim ----------------------------------------------------------------

## Everything in reach, scored on how well it is lined up with the look
## direction. Nothing outside `interact_half_angle` is included at all.
func reachable() -> Array[Reachable]:
	var out: Array[Reachable] = []
	var forward := -_cam_pivot.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return out
	forward = forward.normalized()
	var cutoff := cos(deg_to_rad(interact_half_angle))
	var here := global_position

	for body in _interact_zone.get_overlapping_bodies():
		var kind := _kind_of(body)
		if kind < 0:
			continue
		var node := _node_for(body, kind)
		if node == null:
			continue
		var to := body.global_position - here
		to.y = 0.0
		var distance := to.length()
		# Something you are standing on top of is unambiguously the thing you
		# mean, and has no meaningful direction to test.
		var aim := 1.0 if distance < 0.05 else forward.dot(to / distance)
		if aim < cutoff:
			continue
		out.append(Reachable.new(node, kind, distance * (1.0 + aim_bias * (1.0 - aim))))
	return out


func _kind_of(body: Node3D) -> int:
	if body is Crate:
		# A stowed crate is riding in a rack. It is cargo, not scenery, and is
		# moved with F rather than picked up with E.
		return -1 if (body as Crate).is_stowed() else KIND_CRATE
	if body is FacilityTerminal:
		return KIND_TERMINAL
	if body is Rover:
		return KIND_ROVER
	if body.is_in_group("dock_deck"):
		return KIND_DOCK
	return -1


## The node a verb actually wants, which for a dock is the rack rather than the
## deck the astronaut is standing next to.
func _node_for(body: Node3D, kind: int) -> Node3D:
	if kind != KIND_DOCK:
		return body
	var node: Node = body
	while node != null:
		var facility := node as Facility
		if facility != null:
			return facility.dock()
		node = node.get_parent()
	return null


func _rack_of(target: Reachable) -> CargoRack:
	match target.kind:
		KIND_ROVER:
			return (target.node as Rover).cargo_rack()
		KIND_DOCK:
			return target.node as CargoRack
	return null


## What `interact` would act on right now, or null.
##
## A crate is dropped from the running when the back rack is full — otherwise
## facing a crate you cannot carry would do nothing at all, when boarding the
## rover behind it was available the whole time.
func interact_target() -> Reachable:
	var best: Reachable = null
	for r in reachable():
		if r.kind == KIND_DOCK:
			continue
		if r.kind == KIND_CRATE and _back_rack.is_full():
			continue
		if best == null or r.score < best.score:
			best = r
	return best


## What `drop_cargo` would act on right now, or null — a rack to take from when
## empty-handed, a rack with room when carrying. Anything that cannot do the job
## you are asking for is not a candidate, so facing a full rover with a crate on
## your back sets it on the dock rather than doing nothing.
func cargo_target() -> Reachable:
	var taking := _back_rack.is_empty()
	var best: Reachable = null
	for r in reachable():
		var rack := _rack_of(r)
		if rack == null:
			continue
		if taking and rack.is_empty():
			continue
		if not taking and rack.is_full():
			continue
		if best == null or r.score < best.score:
			best = r
	return best


## Point the look direction at a world position. The player does this with the
## mouse or the right stick; this exists so a test can aim before pressing a
## key, which is now part of what a key press means.
func aim_at(point: Vector3) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_cam_pivot.global_rotation = Vector3(0.0, atan2(-to.x, -to.z), 0.0)


# --- Reach, without aim -------------------------------------------------
##
## "Is this near me", as distinct from "is this what I mean". Diagnostics and
## tests; every verb above goes through aim.

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


func nearby_terminal() -> FacilityTerminal:
	for body in _interact_zone.get_overlapping_bodies():
		var terminal := body as FacilityTerminal
		if terminal != null and terminal.facility() != null:
			return terminal
	return null


func nearby_dock() -> CargoRack:
	for body in _interact_zone.get_overlapping_bodies():
		if body.is_in_group("dock_deck"):
			var rack := _node_for(body, KIND_DOCK) as CargoRack
			if rack != null:
				return rack
	return null


func nearby_rover() -> Rover:
	for body in _interact_zone.get_overlapping_bodies():
		var rover := body as Rover
		if rover != null:
			return rover
	return null


func back_rack() -> CargoRack:
	return _back_rack


# --- Prompts ------------------------------------------------------------
##
## The HUD asks what each key *would* do rather than describing the rules, so a
## prompt cannot drift from the behaviour. Both of these run the same target
## selection the verbs do — the same function, not a matching copy of it.

func interact_prompt() -> String:
	if _menu_open:
		return "Close the board"
	if _driving:
		return "Leave the rover"
	var target := interact_target()
	if target == null:
		return ""
	match target.kind:
		KIND_CRATE:
			return "Pick up %s" % (target.node as Crate).cargo_name
		KIND_TERMINAL:
			return (target.node as FacilityTerminal).interact_prompt()
		KIND_ROVER:
			return "Board the rover"
	return ""


func cargo_prompt() -> String:
	if _driving or _menu_open:
		return ""
	var target := cargo_target()
	if _back_rack.is_empty():
		if target == null:
			return ""
		return "Take a crate off the %s" % _rack_of(target).rack_name.to_lower()
	if target == null:
		return "Put the crate down"
	if target.kind == KIND_ROVER:
		return "Stow on the rover"
	return "Set it on the dock"


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
