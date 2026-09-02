extends Node3D
## Regression test for righting a flipped rover.
##
## The claim being defended is Mac's: a recovery costs **time only**, and a full
## rack survives it intact. That is why the righting is a driven transform
## rather than an angular impulse, and it is the assertion at the end here -
## six crates on the roof, upside down, and every one of them still pristine
## when it is back on its wheels.
##
## Also covers the two ways this can be right and useless: an upside-down rover
## that still lets you climb into it, and a `disembark` that puts the driver
## inside the terrain - which is the only way to reach the verb at all.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_rollover_recovery.tscn

const SETTLE_FRAMES := 90
## Generous: the rover is dropped upside down and has to stop bouncing before
## it will accept a recovery.
const FLIP_FRAMES := 240
const LAND_FRAMES := 120
## Frames of the hold budget. The commit happens partway through this.
const HOLD_FRAMES := 180

var _rover: Rover
var _astronaut: Astronaut
var _crates: Array[Crate] = []
var _frames := 0
var _stage := 0
var _held := 0
var _commit_frame := -1
var _condition_before := 1.0
var _peak_jolt := 0.0
## Only true across the recovery itself. The flip that precedes it is a crash,
## and billing the crash to the recovery is how this test read its own setup as
## a failure the first time it ran.
var _measuring := false
## Condition lost while `_measuring`, reported by the crates themselves.
var _measured_loss := 0.0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var g_col := CollisionShape3D.new()
	var g_shape := BoxShape3D.new()
	g_shape.size = Vector3(400.0, 2.0, 400.0)
	g_col.shape = g_shape
	ground.add_child(g_col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(3.4, 0.2, 0.0)
	add_child(_astronaut)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.0, 0.0)
	add_child(_rover)

	for i in 6:
		var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
		crate.position = Vector3(20.0 + i, 1.0, 0.0)
		add_child(crate)
		_crates.append(crate)


func _physics_process(delta: float) -> void:
	_frames += 1
	if _measuring:
		_peak_jolt = maxf(_peak_jolt, _rover.cargo_rack().jolt())

	match _stage:
		0:
			if _frames < SETTLE_FRAMES:
				return
			_load_and_flip()
			_stage = 1
			_frames = 0
		1:
			if _frames < FLIP_FRAMES:
				return
			_check_rolled_over()
			_stage = 2
			_frames = 0
		2:
			_hold_interact()
		3:
			if _rover.is_righting():
				return
			_stage = 4
			_frames = 0
		4:
			if _frames < LAND_FRAMES:
				return
			_check_upright()
			_check_cargo_survived()
			_finish()


## Six on the roof, then turn the whole thing over.
func _load_and_flip() -> void:
	for crate in _crates:
		_rover.cargo_rack().load_crate(crate)
	_rover.refresh_load()

	# Set it on its roof from a small height rather than rolling it, so the
	# test is about the recovery and not about how it got there.
	_rover.global_transform = Transform3D(
		Basis(Vector3.FORWARD, PI) * Basis(), Vector3(0.0, 1.6, 0.0)
	)
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO
	_rover.cargo_rack().reset_jolt()


func _check_rolled_over() -> void:
	# The baseline is taken *here*, with the wreck settled - not before the
	# flip. Landing a loaded rover on its roof costs the load real condition,
	# and that is the crash being paid for, not the recovery.
	_condition_before = _rover.cargo_rack().worst_condition()
	_rover.cargo_rack().reset_jolt()
	for crate in _crates:
		crate.damaged.connect(_on_crate_damaged)
	_measuring = true

	print("flipped: upright_dot %+.2f, speed %.2f m/s, load at %.4f"
		% [_rover.upright_dot(), _rover.linear_velocity.length(), _condition_before])
	if not _rover.is_rolled_over():
		_failures.append(
			"the rover is on its roof and is_rolled_over() is false (upright_dot %+.2f)"
			% _rover.upright_dot()
		)
	if not _rover.can_right():
		_failures.append(
			"the rover has been settled for %d frames and still will not accept"
			% FLIP_FRAMES
			+ " a recovery (speed %.2f m/s)" % _rover.linear_velocity.length()
		)

	# Climbing out of a wreck is the only way to reach the verb, so the exit
	# point has to be somewhere a person can stand.
	var out := _rover.exit_position()
	print("exit point while inverted: %.2f, %.2f, %.2f" % [out.x, out.y, out.z])
	if out.y < 0.0:
		_failures.append(
			"exit_position() is %.2f m underground while the rover is inverted" % out.y
		)

	# And E must not offer to climb into it.
	_astronaut.aim_at(_rover.global_position)
	if _astronaut.recovery_target() != _rover:
		_failures.append("the astronaut cannot see a rolled rover to right")
	var prompt := _astronaut.interact_prompt()
	print("prompt: %s" % prompt)
	if prompt.contains("Board"):
		_failures.append("E offers to board a rover lying on its roof: '%s'" % prompt)


## Hold E, and check it does not fire early.
func _hold_interact() -> void:
	_astronaut.aim_at(_rover.global_position)
	Input.action_press("interact")
	_held += 1

	if _rover.is_righting():
		_commit_frame = _held
		Input.action_release("interact")
		var seconds := float(_held) * (1.0 / Engine.physics_ticks_per_second)
		print("committed after %.2f s of holding (threshold %.2f)"
			% [seconds, _astronaut.recovery_hold_time])
		if seconds < _astronaut.recovery_hold_time - 0.05:
			_failures.append(
				"the recovery committed after %.2f s, before the %.2f s hold"
				% [seconds, _astronaut.recovery_hold_time]
			)
		_stage = 3
		return

	if _held < HOLD_FRAMES:
		return
	Input.action_release("interact")
	_failures.append(
		"held E for %d frames facing a rolled rover and nothing happened" % HOLD_FRAMES
	)
	_stage = 4
	_frames = 0


## Every loss the crates report while the recovery window is open, with the
## jolt that caused it - so a failure names the moment rather than the total.
func _on_crate_damaged(amount: float) -> void:
	if not _measuring:
		return
	_measured_loss += amount
	print("  damage %.4f at jolt %.2f m/s^2 (stage %d)"
		% [amount, _rover.cargo_rack().jolt(), _stage])


func _check_upright() -> void:
	var dot := _rover.upright_dot()
	print("after recovery: upright_dot %+.2f, y %.2f, rolled=%s"
		% [dot, _rover.global_position.y, _rover.is_rolled_over()])
	if _rover.is_rolled_over():
		_failures.append("the rover is still rolled over after the recovery (dot %+.2f)" % dot)
	if dot < 0.9:
		_failures.append("the rover came to rest %.2f off upright" % dot)
	# It must be standing on the ground, not floating or buried. The ground
	# slab's top is at y = 0.
	if _rover.global_position.y < 0.2 or _rover.global_position.y > 2.5:
		_failures.append(
			"the rover was set down at y %.2f, which is not on the ground"
			% _rover.global_position.y
		)


## The whole reason the righting is driven rather than thrown.
func _check_cargo_survived() -> void:
	var now := _rover.cargo_rack().worst_condition()
	_measuring = false
	print("load: %d crates, worst condition %.4f -> %.4f, peak jolt %.2f m/s^2"
		% [_rover.cargo_rack().count(), _condition_before, now, _peak_jolt]
		+ " (floor %.1f), reported loss %.4f"
		% [_crates[0].jolt_floor, _measured_loss])
	if _rover.cargo_rack().count() != 6:
		_failures.append(
			"%d of 6 crates are still on the rack" % _rover.cargo_rack().count()
		)
	if now < _condition_before - 0.001:
		_failures.append(
			"righting the rover cost the load %.4f of its condition; a recovery"
			% (_condition_before - now)
			+ " is meant to cost time and nothing else"
		)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: a loaded rover rights itself and arrives intact.")
		# quit() only schedules the exit, so this must return.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
