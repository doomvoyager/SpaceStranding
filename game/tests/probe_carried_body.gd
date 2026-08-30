extends SceneTree
## Diagnostic: can a RigidBody3D be reparented onto a moving physics body and
## still track it?
##
## The cargo system wants crates to be real RigidBody3Ds in the world and to
## ride the rover's roof rack once loaded. That only works if a frozen,
## collision-disabled body inherits its parent's transform instead of having it
## overwritten by the physics server. Measured, because getting it wrong means
## crates that silently detach at speed.
##
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        --script res://tests/probe_carried_body.gd

const SETTLE_FRAMES := 30
const CARRY_FRAMES := 120
const SLOT_OFFSET := Vector3(0.0, 1.0, 0.5)

var _carrier: RigidBody3D
var _slot: Node3D
var _static_crate: RigidBody3D
var _kinematic_crate: RigidBody3D
var _plain_node: Node3D
var _frames := 0


func _make_crate(mode: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = 35.0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.6, 0.6)
	col.shape = shape
	body.add_child(col)
	body.set_meta("shape_node", col)
	body.set_meta("freeze_mode", mode)
	return body


## What the cargo script would do on pickup.
func _stow(body: RigidBody3D, slot: Node3D, local: Vector3) -> void:
	body.freeze_mode = body.get_meta("freeze_mode")
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	(body.get_meta("shape_node") as CollisionShape3D).disabled = true
	body.get_parent().remove_child(body)
	slot.add_child(body)
	body.position = local
	body.rotation = Vector3.ZERO


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# A carrier whose transform is driven by the physics server, like the rover.
	_carrier = RigidBody3D.new()
	_carrier.mass = 950.0
	_carrier.gravity_scale = 0.0
	var ccol := CollisionShape3D.new()
	var cshape := BoxShape3D.new()
	cshape.size = Vector3(2.0, 1.0, 4.4)
	ccol.shape = cshape
	_carrier.add_child(ccol)
	world.add_child(_carrier)

	_slot = Node3D.new()
	_slot.position = SLOT_OFFSET
	_carrier.add_child(_slot)

	_static_crate = _make_crate(RigidBody3D.FREEZE_MODE_STATIC)
	_kinematic_crate = _make_crate(RigidBody3D.FREEZE_MODE_KINEMATIC)
	_plain_node = Node3D.new()
	for n in [_static_crate, _kinematic_crate, _plain_node]:
		world.add_child(n)
		n.position = Vector3(20.0, 0.0, 0.0)

	print("engine = ", ProjectSettings.get_setting("physics/3d/physics_engine"))


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == SETTLE_FRAMES:
		_stow(_static_crate, _slot, Vector3(-0.35, 0.0, 0.0))
		_stow(_kinematic_crate, _slot, Vector3(0.35, 0.0, 0.0))
		_plain_node.get_parent().remove_child(_plain_node)
		_slot.add_child(_plain_node)
		_plain_node.position = Vector3(0.0, 0.5, 0.0)
		# Send the carrier off translating AND rotating, the hard case.
		_carrier.linear_velocity = Vector3(0.0, 0.0, -12.0)
		_carrier.angular_velocity = Vector3(0.0, 0.9, 0.0)
		print("stowed; carrier launched")
		return false

	if _frames == SETTLE_FRAMES + CARRY_FRAMES:
		print("--- RESULTS ---")
		print("carrier pos = ", _carrier.global_position)
		print("carrier yaw = %+.1f deg" % rad_to_deg(_carrier.global_rotation.y))
		var ok := true
		for pair in [
			["FREEZE_MODE_STATIC   ", _static_crate, Vector3(-0.35, 0.0, 0.0)],
			["FREEZE_MODE_KINEMATIC", _kinematic_crate, Vector3(0.35, 0.0, 0.0)],
			["plain Node3D (control)", _plain_node, Vector3(0.0, 0.5, 0.0)],
		]:
			var node := pair[1] as Node3D
			var expected: Vector3 = (
				_slot.global_transform * (pair[2] as Vector3)
			)
			var err := node.global_position.distance_to(expected)
			var verdict := "TRACKS" if err < 0.001 else "DETACHED"
			if err >= 0.001:
				ok = false
			print("%s : %s  (error %.4f m, at %s)" % [
				pair[0], verdict, err, node.global_position
			])
		print("")
		print("verdict: ", "reparenting is safe" if ok else "reparenting is NOT safe")
		return true

	return false
