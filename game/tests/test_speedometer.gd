extends Node3D
## Regression test for the rover speedometer. See [[Rover]].
##
## A gauge has two halves and only one of them is easy to get right. The
## arithmetic is three lines; whether anybody ever sees the result is the half
## this project keeps getting wrong — an `Area3D` that detected crates and let
## them fall through, a tunable system absent from the F1 panel, a survey that
## was correct and off screen. So most of what follows is about visibility.
##
##   1. **It is not up on foot.** A speed readout while walking is a dead gauge
##      reading zero, and it would mean the driving check is passing on
##      something other than driving.
##   2. **Boarding puts it on screen**, and it says something. Visible and blank
##      is the same as absent.
##   3. **The dead band reads a flat zero and drops the marker.** The direction
##      comes off the sign of `forward_speed()`, which flickers about zero on a
##      rover settling on its suspension — so without the band a parked vehicle
##      strobes REV at you.
##   4. **Falling is not speed.** `ground_speed()` is horizontal on purpose: a
##      speedometer that climbs as you drop off a ledge is reporting the wrong
##      quantity at exactly the moment somebody is looking at it.
##      `linear_velocity.length()` is the obvious wrong answer and it looks
##      right for as long as the rover stays on the ground.
##   5. **Reversing says so**, and says it in the marker rather than by putting
##      a minus sign in front of the figure.
##
## **Driven by what is on screen, not by frame counts.** The HUD draws in
## `_process` and these checks run in `_physics_process`, which headless does
## not interleave anything like realtime. The first version of stage 5 set a
## reverse velocity and read the panel on the next physics frame — the panel
## was still showing the number from before the change, and the stage passed on
## a REV marker left over from the rover rolling backwards while parked. Every
## stage now waits for the readout itself to catch up, with a frame budget as
## the failure case.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_speedometer.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const BUDGET := 900
const SETTLE := 60

## Metres the rover is lifted for the falling check. High enough that it is
## clearly moving before anything catches it.
const DROP_HEIGHT := 30.0
## Downward speed (m/s) the drop has to reach before the check means anything.
const FALLING_AT := 8.0
## Reverse speed (m/s) asked for, re-applied every frame against the drivetrain.
const REVERSE_AT := 3.0
## Figure (m/s) the panel has to reach before the reverse check is reading the
## velocity it was given rather than whatever was on screen beforehand.
const REVERSE_SHOWN := 2.0

var _astronaut: Astronaut
var _rover: Rover
var _hud: HUD
var _frames := 0
var _stage := 0
var _deadline := 0
var _failures: Array[String] = []
## The dead band as authored, put back after stage 2 borrows it.
var _deadband := 0.0


func _ready() -> void:
	add_child(WORLD.instantiate())


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE:
		return
	if _rover == null and not _find_the_pieces():
		if _frames > BUDGET:
			_expect(false, "never found the astronaut, rover and HUD in the world")
			_finish()
		return
	match _stage:
		0: _stage_nothing_on_foot()
		1: _stage_boarding_puts_it_up()
		2: _stage_the_dead_band_reads_zero()
		3: _stage_falling_is_not_speed()
		4: _stage_reversing_says_so()
		5: _finish()


func _find_the_pieces() -> bool:
	_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_rover = get_tree().get_first_node_in_group("rover") as Rover
	_hud = get_tree().get_first_node_in_group("hud") as HUD
	if _astronaut == null or _rover == null or _hud == null:
		return false
	_deadband = _hud.speedo_deadband
	return true


## 1. Nothing on screen while nobody is driving.
func _stage_nothing_on_foot() -> void:
	_expect(_rover.driver == null, "the rover started with a driver in it")
	_expect(_hud.speedo_readout() == "",
		"the speedometer was up with nobody driving: '%s'"
			% _hud.speedo_readout())
	_rover.enter(_astronaut)
	_advance(1)


## 2. Boarding puts it up, and it says something.
func _stage_boarding_puts_it_up() -> void:
	var line := _hud.speedo_readout()
	if line == "" and _frames < _deadline:
		return
	print("boarded: '%s %s', ground_speed %.3f m/s"
		% [line, _hud.speedo_unit(), _rover.ground_speed()])
	_expect(line != "", "boarding the rover left the speedometer off screen")
	_expect(_hud.speedo_unit().begins_with("m/s"),
		"the unit line read '%s'" % _hud.speedo_unit())
	# Borrowed rather than waiting for the rover to stop: it is parked on
	# authored ground and creeps, and a test that waits for a true zero would be
	# waiting on the terrain rather than on the gauge.
	_hud.speedo_deadband = absf(_rover.ground_speed()) + 1.0
	_advance(2)


## 3. Inside the dead band the figure is a flat zero and the marker is gone.
func _stage_the_dead_band_reads_zero() -> void:
	var line := _hud.speedo_readout()
	var unit := _hud.speedo_unit()
	if line != "0.0" and _frames < _deadline:
		return
	print("dead band %.2f m/s: '%s %s' at %.3f m/s"
		% [_hud.speedo_deadband, line, unit, _rover.ground_speed()])
	_expect(line == "0.0",
		"a rover inside a %.2f m/s dead band read '%s' rather than a flat zero"
			% [_hud.speedo_deadband, line])
	_expect(not unit.contains("REV"),
		"a rover inside the dead band reported itself reversing: '%s'" % unit)
	_hud.speedo_deadband = _deadband
	_lift_and_drop()
	_advance(3)


## 4. The gauge measures travel over the ground, not the drop.
func _stage_falling_is_not_speed() -> void:
	if _rover.linear_velocity.y > -FALLING_AT:
		if _frames < _deadline:
			return
		_expect(false, "the rover never fell: dropped from %.0f m and its "
			% DROP_HEIGHT
			+ "vertical speed only reached %.1f m/s" % -_rover.linear_velocity.y)
		_finish()
		return
	var through_the_air := _rover.linear_velocity.length()
	var over_the_ground := absf(_rover.ground_speed())
	print("falling: %.1f m/s through the air, %.1f m/s over the ground"
		% [through_the_air, over_the_ground])
	_expect(over_the_ground < through_the_air * 0.5,
		"a rover falling at %.1f m/s read %.1f m/s on the gauge — the "
			% [through_the_air, over_the_ground]
		+ "vertical component is being counted as speed")
	_advance(4)


## 5. Backwards reads backwards, in the marker and not in the figure.
##
## The velocity is re-applied every frame, because the drivetrain is braking
## against it — and the stage does not read the panel until the panel has caught
## up, or it would be asserting on whatever was drawn before the push.
func _stage_reversing_says_so() -> void:
	if _rover.linear_velocity.y < -1.0:
		if _frames < _deadline:
			return
		_expect(false, "the rover never came to rest after the drop")
		_finish()
		return
	# basis.z points backwards — the chassis faces -Z like every other node,
	# whatever the drivetrain does with engine_force.
	_rover.linear_velocity = _rover.global_transform.basis.z * REVERSE_AT
	var line := _hud.speedo_readout()
	var unit := _hud.speedo_unit()
	var shown := line.to_float()
	if shown < REVERSE_SHOWN and _frames < _deadline:
		return
	print("reversing: '%s %s', ground_speed %.2f m/s"
		% [line, unit, _rover.ground_speed()])
	_expect(shown >= REVERSE_SHOWN,
		"pushed backwards at %.1f m/s and the panel only ever reached '%s' — "
			% [REVERSE_AT, line]
		+ "it is not reading the rover's velocity")
	_expect(_rover.ground_speed() < 0.0,
		"a reversing rover reported %.2f m/s, which is not negative"
			% _rover.ground_speed())
	_expect(unit.contains("REV"),
		"a rover reversing at %.2f m/s did not say so: '%s'"
			% [_rover.ground_speed(), unit])
	_expect(not line.begins_with("-"),
		"the figure carried the sign as well as the marker: '%s'" % line)
	_advance(5)


# --- helpers ------------------------------------------------------------

## Put the rover in the air with nothing under it, so the next stage has a
## genuine fall to measure rather than a shove along the ground.
func _lift_and_drop() -> void:
	_rover.global_position += Vector3.UP * DROP_HEIGHT
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO


func _advance(stage: int) -> void:
	_stage = stage
	_deadline = _frames + BUDGET


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the speedometer shows only while driving, holds zero in "
			+ "the dead band, ignores the drop, and marks reverse.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
