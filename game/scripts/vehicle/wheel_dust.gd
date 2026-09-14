extends Node3D
class_name WheelDust
## Regolith thrown off the wheels, in a vacuum.
##
## A child of the rover. Makes one `GPUParticles3D` per wheel and, every
## physics tick, parks it at the wheel's contact point aimed backward and up
## off the tyre, with an emission rate that follows the tyre's surface speed
## and its skid: a parked rover throws nothing, a rolling one a little, a
## spinning wheel a spray.
##
## **Dust does not billow here.** There is no air, so every grain flies a
## clean parabola at the Moon's gravity and drops - the Apollo rover's
## rooster tails are sharp sheets of grains, not clouds, and a grain thrown at
## 4 m/s is up for two and a half seconds. So: no drag, no damping, gravity
## read from `World` and refreshed on `World.changed` so the F1 slider bends
## the arcs, and every grain a small opaque sunlit thing that casts a shadow.
## A `GPUParticlesCollisionHeightField3D` rides along under the rover so a
## grain that reaches the ground stops there instead of sinking through it or
## timing out mid-air, and a `GPUParticlesCollisionBox3D` round the hull
## stops the front wheels' throw at the deck rather than through it - the
## fender the blockout does not have.
##
## The look is on `materials/wheel_dust.tres` (the process material: spread,
## scale, colour, the hide-on-contact) and `materials/dust_grain.tres` (what a
## grain is drawn with); the amounts and the throw are here.

@export_group("Throw")
## Grains per second from one wheel at `full_speed`, before skid. A rooster
## tail is a dense sheet; a few hundred a second reads as gravel.
@export_range(0.0, 5000.0, 10.0) var max_rate := 900.0
## Tyre surface speed, m/s, at which the rate stops growing.
@export_range(0.1, 30.0, 0.1) var full_speed := 4.0
## How much more a fully skidding wheel throws, as a multiple on top of 1.
@export_range(0.0, 10.0, 0.1) var skid_boost := 2.0
## A grain leaves at this fraction of the tyre's surface speed. At 1 a grain
## comes off the back of the tyre at the speed the tread carried it, which
## is what a rooster tail is; at 0.6 the spray hugged the wheels.
@export_range(0.0, 3.0, 0.05) var throw_fraction := 1.0
## Up from the ground, degrees, behind the wheel. 45 is the tangent off the
## back of the tyre at mid-height, and the longest arc.
@export_range(0.0, 89.0, 1.0) var throw_angle_deg := 45.0
## Speed spread either side of the throw, as a fraction of it.
@export_range(0.0, 1.0, 0.05) var speed_spread := 0.4

@export_group("Grains")
## Particles an emitter can hold. With `lifetime`, this caps the rate at
## `amount / lifetime` a second.
@export_range(16, 8192, 16) var amount := 3200
## Seconds a grain lives if nothing stops it. A 4 m/s throw at 45 degrees
## lands after 3.5 s at 1.62, having climbed 2.5 m.
@export_range(0.1, 10.0, 0.1) var lifetime := 4.0
## Metres across a grain's quad.
@export_range(0.005, 0.2, 0.005) var grain_size := 0.03
## Where a grain is born: this far above the contact point and behind it,
## metres. Born on the ground, a grain is on the landing field already and
## hidden before it flies - the first capture showed six wheels throwing
## and almost nothing in the air.
@export_range(0.0, 0.5, 0.01) var birth_lift := 0.1
@export_range(0.0, 0.5, 0.01) var birth_back := 0.12
@export var process_material: ParticleProcessMaterial = preload("res://materials/wheel_dust.tres")
@export var grain_material: Material = preload("res://materials/dust_grain.tres")

@export_group("Ground")
## The heightfield the grains land on, metres across, centred under the
## rover and moved along when the rover has gone `ground_step` from it.
@export_range(8.0, 200.0, 1.0) var ground_size := 48.0
@export_range(1.0, 50.0, 0.5) var ground_step := 6.0

## A single-quad mesh shared by every emitter.
var _grain_mesh: QuadMesh
var _emitters: Array[GPUParticles3D] = []
var _wheels: Array[VehicleWheel3D] = []
var _ground: GPUParticlesCollisionHeightField3D
var _ground_at := Vector3.INF
var _hull_box: GPUParticlesCollisionBox3D
var _vehicle: VehicleBody3D


func _ready() -> void:
	_vehicle = get_parent() as VehicleBody3D
	if _vehicle == null:
		push_warning("WheelDust: parent is not a VehicleBody3D; nothing to throw from")
		return
	_grain_mesh = QuadMesh.new()
	_grain_mesh.size = Vector2.ONE * grain_size
	_grain_mesh.material = grain_material
	for child in _vehicle.get_children():
		if child is VehicleWheel3D:
			_wheels.append(child)
			_emitters.append(_make_emitter(child.name))
	_ground = GPUParticlesCollisionHeightField3D.new()
	_ground.name = "Ground"
	_ground.top_level = true
	_ground.size = Vector3(ground_size, ground_size * 0.5, ground_size)
	_ground.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_ground.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	# Layer 1 only: the terrain and the rocks. The hull sits on its own layer
	# and would otherwise be a hump the grains landed on in mid-air.
	_ground.heightfield_mask = 1
	add_child(_ground)
	_hull_box = _make_hull_box()
	_apply_gravity()
	World.changed.connect(_apply_gravity)


func _physics_process(_delta: float) -> void:
	if _vehicle == null:
		return
	_follow_ground()
	for i in _wheels.size():
		var wheel := _wheels[i]
		var emitter := _emitters[i]
		var speed := surface_speed(wheel)
		var skid := 1.0 - clampf(wheel.get_skidinfo(), 0.0, 1.0)
		var wanted := rate(speed, skid, wheel.is_in_contact(), max_rate, full_speed, skid_boost)
		emitter.amount_ratio = ratio_for(wanted, amount, lifetime)
		if wanted <= 0.0:
			continue
		# Aim: behind the wheel along its travel, tilted up. The axle is the
		# wheel's local X; travel on the ground is perpendicular to it, and
		# the sign comes from which way the tyre turns.
		var axle := wheel.global_basis.x
		var travel := Vector3(-axle.z, 0.0, axle.x).normalized()
		if speed < 0.0:
			travel = -travel
		var throw := throw_direction(travel, throw_angle_deg)
		var at := wheel.get_contact_point() + Vector3.UP * birth_lift - travel * birth_back
		emitter.global_transform = Transform3D(Basis.looking_at(throw, Vector3.UP), at)
		var material := emitter.process_material as ParticleProcessMaterial
		var v := absf(speed) * throw_fraction
		material.initial_velocity_min = v * (1.0 - speed_spread)
		material.initial_velocity_max = v * (1.0 + speed_spread)


## Grains a second wanted for a tyre at `speed` m/s with `skid` 0..1: the
## rate ramps to `top` at `saturate` m/s, times 1 plus `boost` at full skid.
static func rate(speed: float, skid: float, in_contact: bool,
		top: float, saturate: float, boost: float) -> float:
	if not in_contact:
		return 0.0
	# Below a crawl nothing lifts; the ramp starts a little off zero so a
	# parked rover with a twitching wheel stays clean.
	var s := absf(speed)
	if s < 0.15:
		return 0.0
	return clampf(s / maxf(saturate, 0.001), 0.0, 1.0) * (1.0 + boost * skid) * top


## The emitter's amount ratio for a wanted rate, given its capacity.
static func ratio_for(wanted: float, capacity: int, life: float) -> float:
	if wanted <= 0.0 or capacity <= 0:
		return 0.0
	return clampf(wanted * life / float(capacity), 0.0, 1.0)


## Where a grain goes: back along the travel and up by the angle.
static func throw_direction(travel: Vector3, angle_deg: float) -> Vector3:
	var flat := -travel
	flat.y = 0.0
	if flat.length_squared() < 1e-8:
		flat = Vector3.BACK
	flat = flat.normalized()
	var a := deg_to_rad(angle_deg)
	return (flat * cos(a) + Vector3.UP * sin(a)).normalized()


## Metres a second the tyre's surface moves: rpm over the wheel's radius.
static func surface_speed(wheel: VehicleWheel3D) -> float:
	return wheel.get_rpm() * TAU / 60.0 * wheel.wheel_radius


func emitters() -> Array[GPUParticles3D]:
	return _emitters


func ground() -> GPUParticlesCollisionHeightField3D:
	return _ground


func hull_box() -> GPUParticlesCollisionBox3D:
	return _hull_box


# --- Internals -----------------------------------------------------------


func _make_emitter(wheel_name: String) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.name = "Dust_" + wheel_name
	e.top_level = true
	e.amount = amount
	e.lifetime = lifetime
	e.emitting = true
	e.amount_ratio = 0.0
	e.randomness = 0.6
	e.fixed_fps = 60
	e.draw_pass_1 = _grain_mesh
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Each wheel gets its own copy: the throw speed is written per tick.
	e.process_material = process_material.duplicate()
	# Grains fly metres from the emitter, in world space.
	e.visibility_aabb = AABB(Vector3(-16.0, -6.0, -16.0), Vector3(32.0, 16.0, 32.0))
	add_child(e)
	return e


## A box round every mesh on the rover that is not a wheel, in the rover's
## own frame, so it rides and turns with the hull.
func _make_hull_box() -> GPUParticlesCollisionBox3D:
	var bounds := AABB()
	var first := true
	for child in _vehicle.get_children():
		if child is VehicleWheel3D or not child is Node3D:
			continue
		for mesh in _meshes_under(child):
			var local := _vehicle.global_transform.affine_inverse() * mesh.global_transform
			var box := local * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	var hull := GPUParticlesCollisionBox3D.new()
	hull.name = "Hull"
	if first:
		hull.size = Vector3(2.0, 1.0, 3.0)
		hull.position = Vector3(0.0, 0.5, 0.0)
	else:
		hull.size = bounds.size
		hull.position = bounds.get_center()
	# Under the rover's own node, not this one, so it follows the chassis.
	_vehicle.add_child.call_deferred(hull)
	return hull


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_meshes_under(child))
	return out


func _apply_gravity() -> void:
	var g := World.gravity_vector()
	for e in _emitters:
		var m := e.process_material as ParticleProcessMaterial
		if m != null:
			m.gravity = g


## Keep the landing heightfield under the rover, moving it in steps so the
## field is re-rendered every few metres rather than every tick.
func _follow_ground() -> void:
	var here := _vehicle.global_position
	if here.distance_to(_ground_at) < ground_step:
		return
	_ground_at = here
	_ground.global_transform = Transform3D(Basis.IDENTITY, here)
