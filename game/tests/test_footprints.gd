extends Node3D
## Footprints, headless: the rules, and a real astronaut walking on a real
## skeleton leaving prints in a real map.
##
## The rules are pure - when a foot is down, where a print goes - and are
## checked directly. Then the astronaut scene is dropped on a flat floor in
## the `terrain` group beside a TrackMap, walked forward for four seconds by
## pressing its own action, and the prints it leaves are read off the
## Footprints node: enough of them, alternating feet, a stride apart for the
## same foot, and none while standing still. The animation is never
## consulted, so this is also the test that a new walk cycle will pass.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_footprints.tscn

var _fails := 0
var _checks := 0


func _ready() -> void:
	_rules()
	await _walk()
	print("%d checks, %d failed" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
		get_tree().quit(0)
		return
	print("FAIL")
	get_tree().quit(1)


func _rules() -> void:
	_expect("low and still is down", Footprints.is_down(0.02, 0.1, 0.08, 0.8))
	_expect("low and swinging is not", not Footprints.is_down(0.02, 2.0, 0.08, 0.8))
	_expect("high and still is not", not Footprints.is_down(0.3, 0.0, 0.08, 0.8))
	var pose := Footprints.print_pose(Vector2(0.0, 0.0), Vector2(0.3, 0.0), 0.32)
	_expect("a print sits under the foot", (pose.centre as Vector2).is_equal_approx(Vector2(0.14, 0.0)))
	_expect_near("and points heel to toe", pose.heading, 0.0, 1e-6)
	var back := Footprints.print_pose(Vector2(0.0, 0.0), Vector2(0.0, -0.3), 0.32)
	_expect_near("in any direction", back.heading, -PI / 2.0, 1e-6)
	var flat := Footprints.print_pose(Vector2(1.0, 1.0), Vector2(1.0, 1.0), 0.32)
	_expect("a foot with no length still prints", (flat.centre as Vector2).is_equal_approx(Vector2(0.84, 1.0)))


func _walk() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	ground.add_to_group("terrain")
	add_child(ground)

	var map := TrackMap.new()
	map.texels = 512
	map.texel_size = 0.25
	add_child(map)

	var astronaut := load("res://scenes/player/astronaut.tscn").instantiate() as Node3D
	astronaut.position = Vector3(0.0, 0.5, 0.0)
	add_child(astronaut)
	var boots := astronaut.find_child("Footprints", true, false) as Footprints
	_expect("the astronaut carries a Footprints node", boots != null)
	if boots == null:
		return
	for i in 60:
		await get_tree().physics_frame
	_expect("it found the skeleton and both feet", boots.is_bound())
	# Dropped half a metre onto the floor, both feet land: two prints, which
	# is right. Standing after that should add none.
	var landed := boots.prints()
	for i in 90:
		await get_tree().physics_frame
	print("landing: %d prints, then standing %d, lowest toe %.3f m over the floor"
		% [landed, boots.prints() - landed, boots.lowest_toe()])
	_expect("the drop onto the floor is a landing per foot", landed <= 2)
	_expect("standing still leaves no prints", boots.prints() == landed)

	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 30:
		await get_tree().physics_frame
	var walked: Vector3 = astronaut.position
	walked.y = 0.0
	var recent := boots.recent()
	print("walked %.1f m: %d prints, lowest toe %.3f m; first are %s" % [
		walked.length(), boots.prints(), boots.lowest_toe(), recent.slice(0, 4)])
	_expect("it walked", walked.length() > 3.0)
	_expect("and left prints: %d" % boots.prints(), boots.prints() >= 4)
	_expect("the map remembered them", map.trail().size() == boots.prints())

	var alternations := 0
	for i in range(1, recent.size()):
		if recent[i][0] != recent[i - 1][0]:
			alternations += 1
	_expect("the feet alternate (%d of %d)" % [alternations, recent.size() - 1],
		recent.size() < 2 or alternations >= (recent.size() - 1) * 0.6)

	var same_foot_gaps: Array[float] = []
	for foot in ["left", "right"]:
		var last := Vector2.INF
		for r in recent:
			if r[0] != foot:
				continue
			if last != Vector2.INF:
				same_foot_gaps.append((r[1] as Vector2).distance_to(last))
			last = r[1]
	var gaps_ok := true
	for g in same_foot_gaps:
		if g < 0.3 or g > 3.0:
			gaps_ok = false
	print("same-foot gaps: %s" % [same_foot_gaps])
	_expect("a foot prints once a stride", gaps_ok)
	if map.trail().size() > 0:
		_expect("a print is a boot, not a tyre",
			is_equal_approx(map.trail().width_at(0), boots.print_width)
			and is_equal_approx(map.trail().length_at(0), boots.print_length))

	var before := boots.prints()
	for i in 120:
		await get_tree().physics_frame
	_expect("and standing still afterwards adds none", boots.prints() == before)

	astronaut.queue_free()
	map.queue_free()
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
