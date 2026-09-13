extends Node3D
## The rover's spec sheet: what it actually does on flat ground, measured.
##
## Written before the move to the Moon, because the last gravity change broke the
## rover with every regression test green - 29 m of broken ground in ten seconds
## became 7 m, and only a probe that drives noticed. So this prints the numbers
## a driver feels, on ground flat enough that two runs agree:
##
##   - **launch**: acceleration off the line, and speed after one and three
##     seconds. Also the check on a claim read from Godot's source and never
##     measured: `engine_force` goes to *every* driven wheel, so 1170 is 7,020 N.
##   - **brakes**: stopping distance from 4 m/s on the full brake, at 60 Hz and
##     at 120 Hz. The source says `brake` is a per-wheel impulse *per physics
##     tick*, which would make the same number twice as strong at 120 Hz.
##   - **coast**: engine braking alone.
##   - **full lock**: loaded, at rising speeds - whether it turns, slides or
##     goes over.
##   - **parked**: how still it sits, occupied and not.
##
## Prints; does not fail. Gravity and tick rate come from the command line so the
## same sheet can be read at 5.39 and 1.62, and any rover or wheel value can be
## overridden for a sweep without touching the script that authors it:
##   engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##     res://tests/probe_rover_spec.tscn -- --gravity=5.39 --hz=120 \
##     --set=top_speed=4 --wheel=wheel_friction_slip=2

## Frames to let the suspension stop bouncing after a reset. Lunar springs
## are soft - under 1 Hz - and one second left the sag reading still mid-bob.
const SETTLE := 240
const GROUND_SIZE := 4000.0
const BRAKE_FROM := 4.0
const LOCK_SPEEDS := [2.0, 3.0, 4.0, 5.0, 6.0]
const KICKER_SPEEDS := [3.0, 5.0]
const KICKER_RISE := 0.5
const KICKER_LENGTH := 4.0
const KICKER_AT := 40.0
const CRATES := 6

var _rover: Rover
var _astronaut: Astronaut
var _hz := 60
var _crates: Array[Crate] = []
var _rows := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gravity="):
			World.surface_gravity = arg.trim_prefix("--gravity=").to_float()
		elif arg.begins_with("--hz="):
			_hz = arg.trim_prefix("--hz=").to_int()
	Engine.physics_ticks_per_second = _hz

	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.2, 0.0)
	add_child(_rover)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			var kv := arg.trim_prefix("--set=").split("=")
			_rover.set(kv[0], kv[1].to_float())
		elif arg.begins_with("--wheel="):
			var kv := arg.trim_prefix("--wheel=").split("=")
			for w in _wheels():
				w.set(kv[0], kv[1].to_float())
	_rover.refresh_load()
	# The rover ignores its pedals with nobody aboard.
	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(40.0, 1.0, 0.0)
	add_child(_astronaut)
	_rover.enter(_astronaut)

	await _run()
	get_tree().quit(0)


func _run() -> void:
	print("")
	print("ROVER SPEC  g %.2f m/s^2 (%.3f g)  %d Hz  %s" % [World.surface_gravity,
		World.gravity_ratio(), Engine.physics_ticks_per_second, _config()])

	await _launch("empty")
	await _brake_run("empty", false)
	await _brake_run("empty", true)
	await _coast("empty")
	await _parked()

	_load_crates()
	await _launch("loaded")
	await _brake_run("loaded", false)
	for v: float in LOCK_SPEEDS:
		# Past the governor a speed cannot be reached, and the row would only
		# repeat the one below it.
		if _rover.top_speed > 0.0 and v > _rover.top_speed:
			continue
		await _full_lock(v)
	for v: float in KICKER_SPEEDS:
		await _kicker(minf(v, _rover.top_speed) if _rover.top_speed > 0.0 else v)

	print("")
	for row in _rows:
		print(row)
	print("")
	print("PROBE DONE")


func _config() -> String:
	var wheel := _wheels()[0]
	return "mass %.0f kg, drive %.0f N, brake %.0f N, engine braking %.0f N, top speed %s, slip %.2f, stiffness %.2f, damping %.2f/%.2f, travel %.2f" % [
		_rover.mass, _rover.drive_force, _rover.brake_force,
		_rover.engine_braking_force,
		"%.1f" % _rover.top_speed if _rover.top_speed > 0.0 else "off",
		wheel.wheel_friction_slip, wheel.suspension_stiffness,
		wheel.damping_compression, wheel.damping_relaxation, wheel.suspension_travel]


# --- scenarios ----------------------------------------------------------

func _launch(label: String) -> void:
	await _reset()
	var start := _rover.global_position
	var v0 := _rover.forward_speed()
	Input.action_press("drive_forward")
	var t := 0.0
	var at_half := 0.0
	var at_one := 0.0
	var to_four := -1.0
	var frames := int(3.0 * _hz)
	for i in frames:
		await get_tree().physics_frame
		t += 1.0 / _hz
		var v := _rover.forward_speed()
		if at_half == 0.0 and t >= 0.5:
			at_half = v
		if at_one == 0.0 and t >= 1.0:
			at_one = v
		if to_four < 0.0 and v >= 4.0:
			to_four = t
	Input.action_release("drive_forward")
	var v3 := _rover.forward_speed()
	var dist := _flat(_rover.global_position - start)
	var measured_accel := (at_half - v0) / 0.5
	var force_limited := _rover.drive_force / _rover.mass
	_rows.append("launch %-6s  0-0.5 s %.2f m/s^2 (drive force alone would give %.2f)  1 s %.2f m/s  3 s %.2f m/s  3 s %.1f m  to 4 m/s %s" % [
		label, measured_accel, force_limited, at_one, v3, dist,
		"%.2f s" % to_four if to_four >= 0.0 else "never"])


func _brake_run(label: String, fast: bool) -> void:
	var hz := _hz * 2 if fast else _hz
	await _reset()
	await _reach(BRAKE_FROM)
	Engine.physics_ticks_per_second = hz
	await get_tree().physics_frame
	var start := _rover.global_position
	var v0 := _rover.forward_speed()
	Input.action_press("brake")
	var t := 0.0
	var budget := 20 * hz
	for i in budget:
		await get_tree().physics_frame
		t += 1.0 / hz
		if _rover.forward_speed() <= 0.05:
			break
	Input.action_release("brake")
	var dist := _flat(_rover.global_position - start)
	Engine.physics_ticks_per_second = _hz
	_rows.append("brake  %-6s  from %.2f m/s at %3d Hz: stops in %.2f m, %.2f s, %.2f m/s^2 average" % [
		label, v0, hz, dist, t, v0 / maxf(t, 0.001)])


func _coast(label: String) -> void:
	await _reset()
	await _reach(BRAKE_FROM)
	var start := _rover.global_position
	var v0 := _rover.forward_speed()
	var t := 0.0
	for i in 30 * _hz:
		await get_tree().physics_frame
		t += 1.0 / _hz
		if _rover.forward_speed() <= 0.05:
			break
	var dist := _flat(_rover.global_position - start)
	_rows.append("coast  %-6s  from %.2f m/s on engine braking: %.1f m, %.1f s, %.2f m/s^2 average" % [
		label, v0, dist, t, v0 / maxf(t, 0.001)])


## Loaded, because a load lifts the centre of mass and that is the case that
## goes over. Brought up to speed straight, then full lock with the speed held:
## a turn that bleeds speed under engine braking never finds out what the speed
## it started at would have done.
##
## **Slip is read at the rear axle, not the body.** The rear wheels do not steer,
## so a rover turning cleanly pivots about a point on that axle and the axle
## itself moves straight along its heading. The body's centre does not: it sits
## ahead of the pivot and always travels at an angle to the nose - the first
## version of this probe read that geometry as an 18.5 degree slide at every
## speed, walking pace included.
func _full_lock(speed: float) -> void:
	await _reset()
	await _reach(speed)
	var v0 := _rover.forward_speed()
	var yaw_prev := _rover.global_rotation.y
	var yawed := 0.0
	Input.action_press("move_left")
	var worst_roll := 0.0
	var worst_slip := 0.0
	var inside_up := 0.0
	var over := false
	var radius := 0.0
	for i in int(2.5 * _hz):
		_hold(speed)
		await get_tree().physics_frame
		var yaw := _rover.global_rotation.y
		yawed += absf(wrapf(yaw - yaw_prev, -PI, PI))
		yaw_prev = yaw
		worst_roll = maxf(worst_roll, rad_to_deg(acos(clampf(_rover.upright_dot(), -1.0, 1.0))))
		over = over or _rover.is_rolled_over()
		# A left turn loads the right wheels; the left ones are the inside.
		var inside_down := 0
		var inside := 0
		for w in _wheels():
			if w.position.x < 0.0:
				inside += 1
				if w.is_in_contact():
					inside_down += 1
		if inside_down < inside:
			inside_up += 1.0 / _hz
		worst_slip = maxf(worst_slip, _rear_slip_deg())
		if i == int(1.5 * _hz):
			var rate := absf(_rover.angular_velocity.y)
			radius = _rover.ground_speed() / maxf(rate, 0.001)
	Input.action_release("move_left")
	Input.action_release("drive_forward")
	var verdict := "turns"
	if over:
		verdict = "ROLLS OVER"
	elif inside_up > 0.2:
		verdict = "tips, recovers"
	elif worst_slip > 6.0:
		verdict = "slides"
	_rows.append("lock   loaded  %.1f m/s: %-14s turn radius %5.1f m, rear-axle slip %4.1f deg, worst roll %4.1f deg, inside wheels up %.2f s, %4.0f deg of yaw" % [
		v0, verdict, radius, worst_slip, worst_roll, inside_up, rad_to_deg(yawed)])


## Straight at a 0.5 m kicker, loaded, holding a speed: how long every wheel is
## off the ground and what the load feels on landing. "Crests launch you" is the
## claim about low gravity worth having a number for.
func _kicker(speed: float) -> void:
	await _reset()
	var ramp := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 0.2, KICKER_LENGTH)
	col.shape = shape
	ramp.add_child(col)
	add_child(ramp)
	var rise := asin(KICKER_RISE / KICKER_LENGTH)
	# Tilted nose-up toward the rover, which comes at it from +Z; its top edge
	# ends KICKER_RISE above the ground.
	ramp.global_transform = Transform3D(Basis(Vector3.RIGHT, -rise),
		Vector3(0.0, KICKER_RISE * 0.5 - 0.1, -KICKER_AT))
	await get_tree().physics_frame

	var airborne := 0.0
	var longest := 0.0
	var worst_jolt := 0.0
	var done := false
	for i in 30 * _hz:
		_hold(speed)
		await get_tree().physics_frame
		var down := 0
		for w in _wheels():
			if w.is_in_contact():
				down += 1
		if down == 0:
			airborne += 1.0 / _hz
			longest = maxf(longest, airborne)
		else:
			airborne = 0.0
		if _rover.global_position.z < -KICKER_AT:
			worst_jolt = maxf(worst_jolt, _rover.cargo_rack().jolt())
		if _rover.global_position.z < -KICKER_AT - 30.0:
			done = true
			break
	Input.action_release("drive_forward")
	ramp.queue_free()
	_rows.append("kicker loaded  %.1f m/s at a %.1f m lip: longest all-wheels-off %.2f s, worst rack jolt %.1f m/s^2%s" % [
		speed, KICKER_RISE, longest, worst_jolt, "" if done else "  (never cleared it)"])


## Throttle on below `speed`, off above it - a crude cruise control, which is
## all a probe needs to arrive somewhere at a known speed.
func _hold(speed: float) -> void:
	if _rover.forward_speed() < speed:
		Input.action_press("drive_forward")
	else:
		Input.action_release("drive_forward")


func _rear_slip_deg() -> float:
	var rear := Vector3.ZERO
	var n := 0
	for w in _wheels():
		if not w.use_as_steering:
			rear += w.position
			n += 1
	if n == 0:
		return 0.0
	rear /= n
	var com := _rover.to_global(_rover.center_of_mass)
	var point := _rover.to_global(rear)
	var v := _rover.linear_velocity + _rover.angular_velocity.cross(point - com)
	var forward := v.dot(-_rover.global_basis.z)
	var lateral := v.dot(_rover.global_basis.x)
	if Vector2(forward, lateral).length() < 0.3:
		return 0.0
	return rad_to_deg(absf(atan2(lateral, absf(forward))))


## How still it sits. With a driver the throttle is closed, so engine braking
## holds it; empty, nothing touches the brake at all, which is how the rover
## sits in the world before anyone climbs in.
##
## Also where the sag is read, against `Rover.static_sag()`'s claim that it is
## gravity over the summed stiffness. With the ground's top at y = 0, a wheel
## carrying no load holds its chassis at (hardpoint drop + radius): the wheel
## node sits where the wheel is at rest length, not the rest length above it.
## The first version added the rest length and read a constant 25 cm too much at
## both gravities - the gravity difference was right, which is how it showed.
func _parked() -> void:
	await _reset()
	var wheel := _wheels()[0]
	var touching := -wheel.position.y + wheel.wheel_radius
	var measured := touching - _rover.global_position.y
	_rows.append("sag    empty   measured %.1f cm, predicted %.1f cm (%.0f%% of travel); wheels down %d/%d" % [
		measured * 100.0, _rover.static_sag() * 100.0, _rover.sag_fraction() * 100.0,
		_rover.wheels_down(), _rover.wheel_count()])
	var worst := 0.0
	var start := _rover.global_position
	for i in 2 * _hz:
		await get_tree().physics_frame
		worst = maxf(worst, _rover.linear_velocity.length())
	_rows.append("parked driver  max speed %.3f m/s, drift %.3f m in 2 s" % [
		worst, _flat(_rover.global_position - start)])

	_rover.exit()
	await get_tree().physics_frame
	_rover.brake = 0.0
	worst = 0.0
	start = _rover.global_position
	for i in 2 * _hz:
		await get_tree().physics_frame
		worst = maxf(worst, _rover.linear_velocity.length())
	_rows.append("parked empty   max speed %.3f m/s, drift %.3f m in 2 s (brake released)" % [
		worst, _flat(_rover.global_position - start)])
	_rover.enter(_astronaut)
	await get_tree().physics_frame


# --- helpers ------------------------------------------------------------

func _reset() -> void:
	for action: String in ["drive_forward", "drive_back", "move_left", "move_right", "brake"]:
		Input.action_release(action)
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO
	_rover.steering = 0.0
	_rover.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0))
	for i in SETTLE:
		await get_tree().physics_frame


## Full throttle until the rover is doing `speed`, then off - or until it has
## stopped gaining. A governed rover settles just under its cap and never gets
## there exactly, and physics runs in real time even headless: the first
## version waited out a full minute per attempt and the run was killed.
func _reach(speed: float) -> void:
	var target := speed
	if _rover.top_speed > 0.0:
		target = minf(speed, _rover.top_speed - 0.1)
	Input.action_press("drive_forward")
	var best := -INF
	var stalled := 0
	for i in 60 * _hz:
		await get_tree().physics_frame
		var v := _rover.forward_speed()
		if v >= target:
			break
		if v > best + 0.01:
			best = v
			stalled = 0
		else:
			stalled += 1
			if stalled > 2 * _hz:
				break
	Input.action_release("drive_forward")


func _load_crates() -> void:
	for i in CRATES:
		var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
		add_child(crate)
		if _rover.cargo_rack().load_crate(crate):
			_crates.append(crate)
	_rover.refresh_load()
	_rows.append("loaded %d crates: %.0f kg, centre of mass %s" % [
		_crates.size(), _rover.mass, _rover.center_of_mass])


func _wheels() -> Array[VehicleWheel3D]:
	var out: Array[VehicleWheel3D] = []
	for child in _rover.get_children():
		if child is VehicleWheel3D:
			out.append(child)
	return out


func _driven() -> int:
	var n := 0
	for w in _wheels():
		if w.use_as_traction:
			n += 1
	return n


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
