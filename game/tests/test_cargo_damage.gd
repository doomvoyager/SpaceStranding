extends Node3D
## Regression test for cargo condition, the carrier-jolt damage model, and
## delivery payout.
##
## Two halves, because the model has two very different failure modes.
##
## The deterministic half feeds a synthetic velocity profile straight through
## JoltMeter and Crate.apply_jolt, with no physics engine involved at all. That
## is the only way to test the property the whole design rests on: **the same
## physical event must cost the same damage at any tick rate.** A one-frame
## velocity change produces a raw jolt of dv/dt, which is four times larger at
## 120 Hz than at 30 Hz — so without the smoothing, cargo fragility would
## silently depend on the player's frame rate.
##
## The physics half drives the real rover and asserts the thing that would ruin
## the game if it broke: ordinary driving must cost nothing.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_cargo_damage.tscn

const SETTLE := 150
const PARKED := 90
const DRIVE := 180
const FREEFALL := 20
const FALL := 190
const OVERLAP := 12
## Half a crate: sets one on the ground rather than dropping it from a height.
const RESTING_HEIGHT := 0.3

## Rates the impulse test compares. 30 and 120 bracket anything plausible.
const RATES: Array[float] = [30.0, 60.0, 120.0]
## Spread allowed across those rates, as a fraction of the mean. Discretising a
## smoothed impulse is not exact; this is measured headroom, not a wish.
const RATE_TOLERANCE := 0.10

var _ground: StaticBody3D
var _rover: Rover
var _astronaut: Astronaut
var _pad: DeliveryPad
var _pristine: Crate
var _battered: Crate
var _midload: Crate

var _frames := 0
var _failures: Array[String] = []
var _drive_damage := 0.0
var _drop_damage := 0.0

@onready var F_PARKED := SETTLE + PARKED
@onready var F_MIDLOAD := F_PARKED + DRIVE / 2
@onready var F_DRIVE_END := F_PARKED + DRIVE
@onready var F_DROP := F_DRIVE_END + 1
@onready var F_DROP_RESET := F_DROP + FREEFALL
@onready var F_DROP_END := F_DROP_RESET + FALL
@onready var F_ROVER_ON_PAD := F_DROP_END + OVERLAP
@onready var F_STOWED_CHECK := F_ROVER_ON_PAD + OVERLAP
@onready var F_SET_DOWN := F_STOWED_CHECK + 1
@onready var F_DELIVERY_CHECK := F_SET_DOWN + OVERLAP
@onready var F_DONE := F_DELIVERY_CHECK + OVERLAP


func _ready() -> void:
	_test_below_floor_is_free()
	_test_tick_rate_independence()
	_test_fragility_scales()
	_test_condition_floor_and_labels()
	_test_payout_curve()
	_build_world()


# --- deterministic half -------------------------------------------------

## Feed one velocity impulse through the real meter and the real damage curve,
## at `rate` Hz, and report the condition lost. `crate` supplies the curve.
func _impulse_damage(crate: Crate, rate: float, speed := 6.0) -> float:
	var meter := JoltMeter.new()
	meter.gravity = Vector3(0.0, -World.SURFACE_GRAVITY, 0.0)
	var delta := 1.0 / rate
	var before := crate.condition

	# A second of steady fall: constant velocity is no acceleration at all, so
	# this must cost nothing and only exists to prime the meter.
	for i in int(rate):
		crate.apply_jolt(meter.sample(Vector3(0.0, -speed, 0.0), delta), delta)
	# The landing: stopped dead in a single frame, which is exactly what
	# move_and_slide does to the astronaut.
	for i in int(rate * 2.0):
		crate.apply_jolt(meter.sample(Vector3.ZERO, delta), delta)

	var lost := before - crate.condition
	crate.condition = before
	return lost


func _fresh_crate(fragility := 1.0) -> Crate:
	var crate := Crate.new()
	crate.fragility = fragility
	return crate


## A jolt under the floor must cost nothing, for as long as it goes on. This is
## what stops parked cargo rotting and a smooth road being a slow tax.
func _test_below_floor_is_free() -> void:
	var crate := _fresh_crate()
	var delta := 1.0 / 60.0
	# Ten seconds at a hair under the floor.
	for i in 600:
		crate.apply_jolt(crate.jolt_floor - 0.01, delta)
	_expect(crate.condition == 1.0,
		"ten seconds just under the jolt floor cost %.6f condition"
		% (1.0 - crate.condition))
	crate.free()


## THE property. Same event, three tick rates, same cost.
func _test_tick_rate_independence() -> void:
	var results: Array[float] = []
	for rate in RATES:
		var crate := _fresh_crate()
		results.append(_impulse_damage(crate, rate))
		crate.free()

	var total := 0.0
	for r in results:
		total += r
	var mean := total / results.size()
	var spread := 0.0
	for r in results:
		spread = maxf(spread, absf(r - mean))
	var deviation := spread / maxf(mean, 1e-9)

	print("impulse damage by tick rate: 30 Hz %.4f   60 Hz %.4f   120 Hz %.4f"
		% [results[0], results[1], results[2]])
	print("  mean %.4f, worst deviation %.1f%%" % [mean, 100.0 * deviation])

	_expect(mean > 0.02,
		"the test impulse barely damaged anything (%.4f); it is not exercising the curve"
		% mean)
	_expect(deviation < RATE_TOLERANCE,
		"damage varies %.1f%% across tick rates 30-120 Hz, over the %.0f%% budget"
		% [100.0 * deviation, 100.0 * RATE_TOLERANCE])


## Fragility is a plain multiplier on damage taken, so a crate twice as delicate
## loses twice as much from the same event.
func _test_fragility_scales() -> void:
	var tough := _fresh_crate(0.5)
	var normal := _fresh_crate(1.0)
	var delicate := _fresh_crate(2.0)
	var a := _impulse_damage(tough, 60.0)
	var b := _impulse_damage(normal, 60.0)
	var c := _impulse_damage(delicate, 60.0)
	print("fragility 0.5 / 1.0 / 2.0 lost %.4f / %.4f / %.4f" % [a, b, c])
	_expect(is_equal_approx(b / maxf(a, 1e-9), 2.0),
		"fragility 1.0 lost %.4f against the 0.5 crate %.4f; expected double" % [b, a])
	_expect(is_equal_approx(c / maxf(b, 1e-9), 2.0),
		"fragility 2.0 lost %.4f against the 1.0 crate %.4f; expected double" % [c, b])
	tough.free()
	normal.free()
	delicate.free()


## Condition cannot go negative, and the labels have to move in the right
## direction — the HUD and the delivery receipt both read them.
func _test_condition_floor_and_labels() -> void:
	var crate := _fresh_crate()
	crate.take_damage(5.0)
	_expect(crate.condition == 0.0,
		"a huge hit left condition at %.4f, expected a floor of 0" % crate.condition)
	_expect(crate.condition_label() == "ruined",
		"a destroyed crate reads %s" % crate.condition_label())
	crate.take_damage(1.0)
	_expect(crate.condition == 0.0,
		"damage past zero pushed condition to %.4f" % crate.condition)
	_expect(Crate.label_for(1.0) == "pristine",
		"an undamaged crate reads %s" % Crate.label_for(1.0))
	crate.free()


## Payout falls with condition, faster than linearly.
func _test_payout_curve() -> void:
	var pad := DeliveryPad.new()
	var crate := _fresh_crate()
	_expect(is_equal_approx(pad.payout_for(crate), pad.base_value),
		"a pristine crate pays %.1f, not the %.1f base"
		% [pad.payout_for(crate), pad.base_value])
	crate.condition = 0.5
	var half := pad.payout_for(crate)
	_expect(half < pad.base_value * 0.5,
		"a half-condition crate pays %.1f, which is not worse than linear" % half)
	crate.condition = 0.0
	_expect(is_zero_approx(pad.payout_for(crate)),
		"a ruined crate still pays %.1f" % pad.payout_for(crate))
	print("payout: pristine %.0f, half-condition %.0f, ruined 0" % [pad.base_value, half])
	pad.free()
	crate.free()


# --- physics half -------------------------------------------------------

func _build_world() -> void:
	_ground = StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 2.0, 600.0)
	col.shape = shape
	_ground.add_child(col)
	_ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(_ground)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.0, 0.0)
	add_child(_rover)

	# enter() hands the camera and input over to a real astronaut; passing null
	# aborts it half way and leaves the rover un-driven and silently parked.
	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(2.6, 1.0, 0.0)
	add_child(_astronaut)

	_pad = load("res://scenes/cargo/delivery_pad.tscn").instantiate()
	_pad.position = Vector3(0.0, 0.0, -40.0)
	add_child(_pad)

	# Two on the rack for the driving and drop tests.
	for i in 2:
		var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
		add_child(crate)
		_rover.cargo_rack().load_crate(crate)
	_rover.refresh_load()

	# Set down resting on the ground, not dropped onto it. A crate spawned a
	# metre up falls a metre, and the damage model correctly charges for it —
	# which would quietly pre-damage every crate in this test.
	_midload = _spawn_crate("Mid-load crate", Vector3(200.0, RESTING_HEIGHT, 200.0))
	_pristine = _spawn_crate("Pristine crate", Vector3(210.0, RESTING_HEIGHT, 200.0))
	_battered = _spawn_crate("Battered crate", Vector3(220.0, RESTING_HEIGHT, 200.0))


## Half the 0.6 m crate, so it starts in contact rather than in the air.
func _spawn_crate(crate_name: String, at: Vector3) -> Crate:
	var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
	crate.cargo_name = crate_name
	add_child(crate)
	crate.global_position = at
	return crate


func _physics_process(_delta: float) -> void:
	_frames += 1
	match _frames:
		F_PARKED:
			_check_parked()
			_rover.enter(_astronaut)
			Input.action_press("drive_forward")
		F_MIDLOAD:
			_load_while_moving()
		F_DRIVE_END:
			_check_driving()
			Input.action_release("drive_forward")
		F_DROP:
			_start_drop()
		F_DROP_RESET:
			_rover.cargo_rack().reset_jolt()
			_reset_rack_condition()
		F_DROP_END:
			_check_drop()
		F_ROVER_ON_PAD:
			_park_rover_on_pad()
		F_STOWED_CHECK:
			_check_stowed_not_delivered()
		F_SET_DOWN:
			_set_crates_on_pad()
		F_DELIVERY_CHECK:
			_check_delivery()
		F_DONE:
			_check_paid_once()
			_finish()


## A parked, loaded rover must not damage its own cargo just by existing.
func _check_parked() -> void:
	var worst := _rover.cargo_rack().worst_condition()
	print("parked %.1f s loaded: worst condition %.6f"
		% [float(PARKED) / Engine.physics_ticks_per_second, worst])
	_expect(worst == 1.0,
		"a parked loaded rover damaged its cargo by %.6f" % (1.0 - worst))


## Loading mid-drive must not read the carrier velocity as an impact.
func _load_while_moving() -> void:
	_expect(_rover.linear_velocity.length() > 1.0,
		"rover is only doing %.2f m/s; the mid-drive load test is not exercising anything"
		% _rover.linear_velocity.length())
	_rover.cargo_rack().load_crate(_midload)
	_rover.refresh_load()


func _check_driving() -> void:
	var speed := _rover.linear_velocity.length()
	_drive_damage = 1.0 - _rover.cargo_rack().worst_condition()
	print("drove %.1f s reaching %.1f m/s: cargo lost %.6f condition"
		% [float(DRIVE) / Engine.physics_ticks_per_second, speed, _drive_damage])
	_expect(speed > 3.0, "rover only reached %.2f m/s; not a real drive" % speed)
	_expect(_drive_damage == 0.0,
		"ordinary driving cost %.6f condition — the floor is too low" % _drive_damage)
	_expect(_midload.condition == 1.0,
		"a crate loaded onto a moving rover took %.6f damage on the way in"
		% (1.0 - _midload.condition))


func _start_drop() -> void:
	_rover.exit()
	_rover.global_position = Vector3(0.0, 8.0, 0.0)
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO


func _reset_rack_condition() -> void:
	for crate in _rover.cargo_rack().crates():
		crate.condition = 1.0


## The other side of the same coin: a real impact has to actually cost.
func _check_drop() -> void:
	_drop_damage = 1.0 - _rover.cargo_rack().worst_condition()
	print("dropped the loaded rover 7 m: cargo lost %.4f condition" % _drop_damage)
	_expect(_drop_damage > 0.005,
		"a 7 m drop cost only %.6f condition; impacts are not registering" % _drop_damage)
	_expect(_drop_damage < 1.0, "a single 7 m drop destroyed the cargo outright")


## A stowed crate is on collision layer 0, so the pad cannot see it. Driving a
## loaded rover onto the pad must deliver nothing.
func _park_rover_on_pad() -> void:
	_rover.global_position = _pad.global_position + Vector3(0.0, 1.2, 0.0)
	_rover.linear_velocity = Vector3.ZERO


func _check_stowed_not_delivered() -> void:
	_expect(_pad.delivered_count == 0,
		"parking a loaded rover on the pad delivered %d crate(s) still on the rack"
		% _pad.delivered_count)
	_rover.global_position = Vector3(0.0, 1.0, 60.0)


func _set_crates_on_pad() -> void:
	# Set explicitly: this checks the pad's arithmetic, not the haul that got
	# them here.
	_pristine.condition = 1.0
	_battered.condition = 0.5
	var at := Transform3D.IDENTITY
	at.origin = _pad.global_position + Vector3(-0.8, RESTING_HEIGHT + 0.01, 0.0)
	_pristine.release(self, at)
	at.origin = _pad.global_position + Vector3(0.8, RESTING_HEIGHT + 0.01, 0.0)
	_battered.release(self, at)


func _check_delivery() -> void:
	_expect(_pad.delivered_count == 2,
		"two crates set down on the pad, %d delivered" % _pad.delivered_count)
	var expected := _pad.base_value + _pad.base_value * pow(0.5, _pad.payout_exponent)
	print("delivered %d crates for %.1f cr (expected %.1f)"
		% [_pad.delivered_count, _pad.total_paid, expected])
	_expect(is_equal_approx(_pad.total_paid, expected),
		"pad paid %.2f, expected %.2f — a pristine crate plus a half-condition one"
		% [_pad.total_paid, expected])


## Cargo sitting on the pad must not be paid for again every physics frame.
func _check_paid_once() -> void:
	_expect(_pad.delivered_count == 2,
		"crates left lying on the pad were re-delivered: count is now %d"
		% _pad.delivered_count)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: cargo damage, tick-rate independence and delivery payout are correct.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
