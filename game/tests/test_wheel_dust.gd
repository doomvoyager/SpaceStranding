extends Node3D
## Wheel dust, headless: the rules, and the rover's own emitters doing what
## the wheels do.
##
## The rules are pure - the rate for a speed and a skid, the ratio for a
## capacity, the throw direction - and checked directly. Then the rover scene
## is dropped on a floor and the emitters are read: one per wheel, all quiet
## while parked, throwing once the astronaut boards and drives, aimed behind
## the wheels and up, the gravity tracking World, and a landing field under
## the rover. Nothing about what a grain looks like: that is `dust_capture`.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_wheel_dust.tscn

var _fails := 0
var _checks := 0


func _ready() -> void:
	_rules()
	await _rover()
	print("%d checks, %d failed" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
		get_tree().quit(0)
		return
	print("FAIL")
	get_tree().quit(1)


func _rules() -> void:
	_expect("nothing off the ground", WheelDust.rate(3.0, 0.0, false, 400.0, 4.0, 2.0) == 0.0)
	_expect("nothing parked", WheelDust.rate(0.0, 0.0, true, 400.0, 4.0, 2.0) == 0.0)
	_expect("nothing at a twitch", WheelDust.rate(0.1, 0.0, true, 400.0, 4.0, 2.0) == 0.0)
	_expect_near("half speed, half rate", WheelDust.rate(2.0, 0.0, true, 400.0, 4.0, 2.0), 200.0, 1e-6)
	_expect_near("full speed saturates", WheelDust.rate(9.0, 0.0, true, 400.0, 4.0, 2.0), 400.0, 1e-6)
	_expect_near("reverse throws too", WheelDust.rate(-4.0, 0.0, true, 400.0, 4.0, 2.0), 400.0, 1e-6)
	_expect_near("a full skid boosts by the boost", WheelDust.rate(4.0, 1.0, true, 400.0, 4.0, 2.0), 1200.0, 1e-6)
	_expect_near("a ratio is rate over capacity per lifetime", WheelDust.ratio_for(200.0, 800, 2.0), 0.5, 1e-6)
	_expect("and clamps", WheelDust.ratio_for(9000.0, 800, 2.0) == 1.0 and WheelDust.ratio_for(0.0, 800, 2.0) == 0.0)
	var throw := WheelDust.throw_direction(Vector3(0.0, 0.0, -1.0), 35.0)
	_expect("a grain goes behind the travel", throw.z > 0.0 and absf(throw.x) < 1e-6)
	_expect_near("and up by the angle", rad_to_deg(asin(throw.y)), 35.0, 1e-4)
	_expect("with no travel it still goes somewhere",
		WheelDust.throw_direction(Vector3.ZERO, 35.0).is_normalized())


func _rover() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	var rover := load("res://scenes/vehicle/rover.tscn").instantiate() as Rover
	rover.position = Vector3(0.0, 1.2, 0.0)
	add_child(rover)
	var astronaut := load("res://scenes/player/astronaut.tscn").instantiate() as Astronaut
	astronaut.position = Vector3(5.0, 1.0, 0.0)
	add_child(astronaut)
	var dust := rover.find_child("WheelDust", true, false) as WheelDust
	_expect("the rover carries a WheelDust node", dust != null)
	if dust == null:
		return
	for i in 60:
		await get_tree().physics_frame

	var wheels := rover.find_children("*", "VehicleWheel3D", false, false)
	_expect("one emitter per wheel: %d for %d" % [dust.emitters().size(), wheels.size()],
		dust.emitters().size() == wheels.size() and wheels.size() > 0)
	var quiet := true
	for e in dust.emitters():
		if e.amount_ratio > 0.0:
			quiet = false
	_expect("parked, every emitter is quiet", quiet)
	_expect("there is a landing field, in world space",
		dust.ground() != null and dust.ground().top_level
		and dust.ground().global_position.distance_to(rover.global_position) < 1.0)
	_expect("the field sees layer 1 only", dust.ground().heightfield_mask == 1)
	var hull := dust.hull_box()
	_expect("a box round the hull stops the front wheels' throw",
		hull != null and hull.get_parent() == rover and hull.size.x > 1.0 and hull.size.z > 2.0)
	print("hull box %s at %s" % [hull.size.snapped(Vector3.ONE * 0.01) if hull else Vector3.ZERO,
		hull.position.snapped(Vector3.ONE * 0.01) if hull else Vector3.ZERO])

	var g0 := (dust.emitters()[0].process_material as ParticleProcessMaterial).gravity
	_expect_vec3("gravity is the World's", g0, World.gravity_vector())
	var was := World.surface_gravity
	World.surface_gravity = 3.0
	var g1 := (dust.emitters()[0].process_material as ParticleProcessMaterial).gravity
	_expect_vec3("and follows it when it changes", g1, Vector3(0.0, -3.0, 0.0))
	World.surface_gravity = was
	var m := dust.emitters()[0].process_material as ParticleProcessMaterial
	_expect("no drag in a vacuum", m.damping_min == 0.0 and m.damping_max == 0.0)
	_expect("grains hide when they land", m.collision_mode == ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT)

	rover.enter(astronaut)
	for i in 20:
		await get_tree().physics_frame
	Input.action_press("drive_forward")
	for i in 150:
		await get_tree().physics_frame
	var speed := rover.forward_speed()
	var throwing := 0
	var aimed_back := 0
	var lifted := 0
	for i in dust.emitters().size():
		var e := dust.emitters()[i]
		if e.amount_ratio > 0.0:
			throwing += 1
			# The emitter's -Z is the throw. Driving forward, that should
			# have a component against the rover's travel, and be upward.
			var throw := -e.global_basis.z
			if throw.dot(rover.global_basis.z * -1.0) < 0.0:
				aimed_back += 1
			if throw.y > 0.3:
				lifted += 1
	print("driving at %.1f m/s: %d of %d emitters throwing, %d aimed back, %d up" % [
		speed, throwing, dust.emitters().size(), aimed_back, lifted])
	_expect("it drove", speed > 1.0)
	_expect("driving, the wheels throw", throwing >= 4)
	_expect("aimed behind the travel", aimed_back == throwing)
	_expect("and upward", lifted == throwing)
	var v := (dust.emitters()[0].process_material as ParticleProcessMaterial).initial_velocity_max
	_expect("grains leave at a fraction of the tyre's speed: %.2f m/s" % v, v > 0.5 and v < 15.0)
	Input.action_release("drive_forward")
	Input.action_press("drive_back")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("drive_back")
	for i in 120:
		await get_tree().physics_frame
	var still := true
	for e in dust.emitters():
		if e.amount_ratio > 0.0:
			still = false
	print("stopped at %.2f m/s" % rover.forward_speed())
	_expect("stopped, the wheels are quiet again", still or absf(rover.forward_speed()) > 0.15)

	rover.queue_free()
	astronaut.queue_free()
	ground.queue_free()
	await get_tree().process_frame


func _expect(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: %s" % label)


func _expect_near(label: String, got: float, want: float, tol: float) -> void:
	_checks += 1
	if absf(got - want) > tol:
		_fails += 1
		print("  FAIL: %s - got %s, wanted %s" % [label, got, want])


func _expect_vec3(label: String, got: Vector3, want: Vector3) -> void:
	_checks += 1
	if not got.is_equal_approx(want):
		_fails += 1
		print("  FAIL: %s - got %s, wanted %s" % [label, got, want])
