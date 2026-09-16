extends Node3D
## Lens dust, headless: the rules, then the rover's chase camera dusting over
## while it drives.
##
## The rules are pure - one wheel's share of the spray toward a point, and a
## lens building, holding and fading under an exposure - and checked directly.
## Then the rover scene is dropped on a floor, boarded and driven: its chase
## camera carries a LensDust wired to the WheelDust, the lens dusts over while
## the camera looks on from behind, holds while the cab eye is up, gets nothing
## while reversing, fades once the rover stops, and is wiped when the driver
## climbs out. What the specks look like is `flare_capture`, windowed.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_lens_dust.tscn

const POST := preload("res://scenes/postprocessing_effects.tscn")

var _fails := 0
var _checks := 0


func _ready() -> void:
	_spray_rules()
	_lens_rules()
	await _rover()
	print("%d checks, %d failed" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
		get_tree().quit(0)
		return
	print("FAIL")
	get_tree().quit(1)


func _spray_rules() -> void:
	# Thrown toward +Z, up at 45 degrees.
	var throw := Vector3(0.0, 1.0, 1.0).normalized()
	var behind := WheelDust.spray_toward(1.0, throw, Vector3(0.0, 3.0, 9.0), 10.0, 2.0)
	_expect_near("dead behind at 9 m, a full share counts 1 / (1 + 0.81)",
		behind, 1.0 / 1.81, 1e-5)
	_expect("height does not matter", is_equal_approx(behind,
		WheelDust.spray_toward(1.0, throw, Vector3(0.0, 30.0, 9.0), 10.0, 2.0)))
	_expect("in front, nothing",
		WheelDust.spray_toward(1.0, throw, Vector3(0.0, 3.0, -9.0), 10.0, 2.0) == 0.0)
	_expect("square to the side, nothing",
		WheelDust.spray_toward(1.0, throw, Vector3(9.0, 3.0, 0.0), 10.0, 2.0) == 0.0)
	var off := WheelDust.spray_toward(1.0, throw, Vector3(9.0, 0.0, 9.0), 10.0, 2.0)
	_expect("45 degrees off gets less than dead behind", off > 0.0 and off < behind)
	_expect("and a sharper cone gives it less again",
		WheelDust.spray_toward(1.0, throw, Vector3(9.0, 0.0, 9.0), 10.0, 6.0) < off)
	_expect("further gets less",
		WheelDust.spray_toward(1.0, throw, Vector3(0.0, 0.0, 30.0), 10.0, 2.0) < behind)
	_expect_near("a half-rate wheel counts half",
		WheelDust.spray_toward(0.5, throw, Vector3(0.0, 3.0, 9.0), 10.0, 2.0), behind * 0.5, 1e-5)
	_expect("a quiet wheel counts nothing",
		WheelDust.spray_toward(0.0, throw, Vector3(0.0, 3.0, 9.0), 10.0, 2.0) == 0.0)
	_expect("on top of the wheel, nothing and no division by zero",
		WheelDust.spray_toward(1.0, throw, Vector3(0.0, 3.0, 0.0), 10.0, 2.0) == 0.0)


func _lens_rules() -> void:
	var lens := LensDust.new()
	lens.build_rate = 0.1
	lens.fade_rate = 0.05
	lens.fade_delay = 2.0
	lens.step(0.5, 2.0)
	_expect_near("builds at exposure x rate", lens.coverage, 0.1, 1e-6)
	lens.step(50.0, 1.0)
	_expect("and stops at a full lens", lens.coverage == 1.0)
	lens.step(0.0, 1.5)
	_expect("holds through the delay", lens.coverage == 1.0)
	lens.step(0.0, 1.0)
	_expect("then fades", lens.coverage < 1.0)
	var faded := lens.coverage
	lens.step(0.01, 0.1)
	lens.step(0.0, 1.0)
	_expect("a little more spray restarts the delay", lens.coverage > faded)
	lens.clear()
	_expect("clear is clean glass", lens.coverage == 0.0)
	lens.step(0.0, 100.0)
	_expect("and does not go below it", lens.coverage == 0.0)
	lens.fade_rate = 0.0
	lens.step(1.0, 3.0)
	var held := lens.coverage
	lens.step(0.0, 60.0)
	_expect("with no fade rate it holds", lens.coverage == held and held > 0.0)
	# Never added to the tree, so nothing else will free it.
	lens.free()


func _rover() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 2.0, 600.0)
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
	var post := POST.instantiate() as Lens
	add_child(post)

	var chase := rover.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	var lens := chase.get_node_or_null("LensDust") as LensDust
	_expect("the chase camera carries a LensDust", lens != null)
	if lens == null:
		return
	var dust := rover.find_child("WheelDust", true, false) as WheelDust
	_expect("it finds the rover's WheelDust by itself", lens.source() != null and lens.source() == dust)
	_expect("the cab eye has none", LensDust.coverage_on(rover.eye()) == 0.0
		and rover.eye().get_node_or_null("LensDust") == null)
	for i in 60:
		await get_tree().physics_frame
	_expect("parked, no spray reaches it", dust.exposure_at(chase.global_position, lens.reach, lens.aim_sharpness) == 0.0)

	rover.first_person = false
	rover.enter(astronaut)
	for i in 20:
		await get_tree().physics_frame
	_expect("boarded, the chase camera is on screen", chase.current)
	_expect("and clean", lens.coverage == 0.0)

	Input.action_press("drive_forward")
	for i in 180:
		await get_tree().physics_frame
	var exposure := dust.exposure_at(chase.global_position, lens.reach, lens.aim_sharpness)
	print("driving at %.1f m/s: exposure %.3f, coverage %.4f" % [
		rover.forward_speed(), exposure, lens.coverage])
	_expect("driving, the spray reaches the chase camera", exposure > 0.1)
	_expect("and the lens dusts over", lens.coverage > 0.0)
	post.refresh()
	_expect_near("the post layer sees it", post.dust, lens.coverage, 1e-6)

	# Up into the cab and keep driving: the chase lens is not on screen.
	rover.toggle_view()
	for i in 5:
		await get_tree().physics_frame
	_expect("the cab eye is on screen", rover.eye().current and not chase.current)
	var parked_at := lens.coverage
	for i in 90:
		await get_tree().physics_frame
	_expect("the chase lens holds while you are in the cab: %.4f -> %.4f" % [
		parked_at, lens.coverage], lens.coverage == parked_at)
	post.refresh()
	_expect("and the post layer shows the cab's clean glass", post.dust == 0.0)
	rover.toggle_view()
	for i in 5:
		await get_tree().physics_frame
	_expect("back behind, the dust is where it was", chase.current and lens.coverage >= parked_at)

	# Reverse: the spray goes forward, away from a camera behind.
	Input.action_release("drive_forward")
	Input.action_press("drive_back")
	var reversing := false
	var reached := 0.0
	for i in 600:
		await get_tree().physics_frame
		if rover.forward_speed() < -0.8:
			reversing = true
			reached = maxf(reached, dust.exposure_at(chase.global_position, lens.reach, lens.aim_sharpness))
	Input.action_release("drive_back")
	print("reversing: %s, largest exposure %.4f" % [reversing, reached])
	_expect("it reversed", reversing)
	_expect("reversing throws nothing at the chase camera", reached == 0.0)

	# Stop and wait out the delay: it fades. Reversing took long enough for
	# the first dust to fade already, so give it some to lose.
	Input.action_press("brake")
	for i in 120:
		await get_tree().physics_frame
	lens.coverage = 0.5
	var stopped_at := lens.coverage
	for i in int((lens.fade_delay + 1.0) * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
	print("stopped at %.2f m/s: coverage %.4f -> %.4f" % [
		rover.forward_speed(), stopped_at, lens.coverage])
	_expect("stopped, it fades", lens.coverage < stopped_at)
	Input.action_release("brake")

	lens.coverage = 0.6
	rover.exit()
	await get_tree().physics_frame
	_expect("climbing out wipes it", lens.coverage == 0.0)

	rover.queue_free()
	astronaut.queue_free()
	post.queue_free()
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
