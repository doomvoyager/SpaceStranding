extends Node3D
## Regression test for the full cargo round trip: ground -> back -> rover rack
## -> back -> ground, plus the load's effect on the rover's mass and centre of
## mass.
##
## The failure this exists to catch is a crate that looks attached but is not.
## A stowed crate is frozen with its collision off, so nothing in the physics
## world will complain if it silently stops tracking its slot - it will simply
## hang in the air where it was loaded. So the test drives the rover away and
## then asserts the crate is still exactly on its slot.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_cargo_flow.tscn

## Area3D overlap lists only refresh on a physics step, so every teleport in
## this test has to be followed by a few frames before the astronaut can see
## what is next to them.
const SETTLE_FRAMES := 45
const DRIVE_FRAMES := 150
const OVERLAP_FRAMES := 8

const F_LOAD := SETTLE_FRAMES
const F_PARK := F_LOAD + DRIVE_FRAMES
const F_UNLOAD := F_PARK + OVERLAP_FRAMES
const F_MOVE_AWAY := F_UNLOAD + 1
const F_DROP := F_MOVE_AWAY + OVERLAP_FRAMES
## A stowed crate must sit on its slot to within a millimetre.
const SLOT_TOLERANCE := 0.001

var _astronaut: Astronaut
var _rover: Rover
var _crate: Crate
var _empty_mass := 0.0
var _empty_com := Vector3.ZERO
var _frames := 0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var g_col := CollisionShape3D.new()
	var g_shape := BoxShape3D.new()
	g_shape.size = Vector3(600.0, 2.0, 600.0)
	g_col.shape = g_shape
	ground.add_child(g_col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	_rover.position = Vector3(0.0, 1.0, 0.0)
	add_child(_rover)

	# Inside the astronaut's interact zone, so the rover is always "nearby".
	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(2.6, 1.0, 0.0)
	add_child(_astronaut)

	_crate = load("res://scenes/cargo/crate.tscn").instantiate()
	_crate.mass = 55.0
	_crate.position = Vector3(3.2, 1.0, 0.0)
	add_child(_crate)


func _physics_process(_delta: float) -> void:
	_frames += 1

	match _frames:
		F_LOAD:
			_empty_mass = _rover.mass
			_empty_com = _rover.center_of_mass
			_run_transfers()
			_rover.enter(_astronaut)
			Input.action_press("drive_forward")

		F_PARK:
			Input.action_release("drive_forward")
			_check_still_attached()
			_rover.exit()
			_stand_at(_rover.global_position + _rover.global_transform.basis.x * 2.6)

		F_UNLOAD:
			_check_unload()

		F_MOVE_AWAY:
			_stand_at(Vector3(0.0, 1.0, 60.0))

		F_DROP:
			_check_drop()
			_finish()


func _stand_at(where: Vector3) -> void:
	_astronaut.global_position = where
	_astronaut.velocity = Vector3.ZERO


## Ground -> back -> rover rack, checking each hop and its side effects.
func _run_transfers() -> void:
	var back := _astronaut.back_rack()
	var rack := _rover.cargo_rack()

	_expect(back.capacity() == 2, "back rack should have 2 slots, has %d" % back.capacity())
	_expect(rack.capacity() == 6, "rover rack should have 6 slots, has %d" % rack.capacity())

	_astronaut._interact()
	_expect(_crate.is_stowed(), "E next to a loose crate did not pick it up")
	_expect(back.count() == 1, "back rack holds %d after pickup, expected 1" % back.count())
	_expect(_slot_error(_crate) < SLOT_TOLERANCE,
		"carried crate is %.4f m off its back slot" % _slot_error(_crate))

	_astronaut._move_cargo()
	_expect(rack.count() == 1, "rover rack holds %d after stow, expected 1" % rack.count())
	_expect(back.is_empty(), "back rack still holds %d after stow" % back.count())

	# 55 kg on the roof: heavier, and the mass has climbed toward the rack.
	_expect(is_equal_approx(_rover.mass, _empty_mass + 55.0),
		"rover mass %.1f after loading 55 kg onto %.1f" % [_rover.mass, _empty_mass])
	_expect(_rover.center_of_mass.y > _empty_com.y,
		"centre of mass did not rise: %.4f -> %.4f" % [_empty_com.y, _rover.center_of_mass.y])
	_expect(_rover.center_of_mass.x < _empty_com.x,
		"one crate on the left slot did not shift the centre of mass left: %.4f -> %.4f"
		% [_empty_com.x, _rover.center_of_mass.x])
	print("loaded: mass %.0f -> %.0f kg, CoM %s -> %s"
		% [_empty_mass, _rover.mass, _empty_com, _rover.center_of_mass])


## The one that matters: after the rover has actually driven, is the crate
## still on its slot rather than hanging where it was loaded?
func _check_still_attached() -> void:
	var travelled := _rover.global_position.length()
	_expect(travelled > 2.0, "rover only moved %.2f m; test is not exercising anything" % travelled)
	var err := _slot_error(_crate)
	print("after %.1f m of driving, crate is %.4f m off its slot" % [travelled, err])
	_expect(err < SLOT_TOLERANCE, "crate drifted %.4f m off its slot while driving" % err)


func _check_unload() -> void:
	_expect(_astronaut.nearby_rover() != null,
		"astronaut is not standing within reach of the rover; test is invalid")
	_astronaut._move_cargo()
	_expect(_astronaut.back_rack().count() == 1,
		"F empty-handed beside a loaded rover did not take a crate off")
	_expect(_rover.cargo_rack().is_empty(), "rover rack did not empty")
	_expect(is_equal_approx(_rover.mass, _empty_mass),
		"rover mass %.1f did not return to %.1f after unloading" % [_rover.mass, _empty_mass])
	_expect(_rover.center_of_mass.is_equal_approx(_empty_com),
		"centre of mass did not return to %s, is %s" % [_empty_com, _rover.center_of_mass])


## Nothing in range but ground: F must put the crate down, live again.
func _check_drop() -> void:
	_expect(_astronaut.nearby_rover() == null,
		"astronaut is still within reach of the rover; test is invalid")
	_astronaut._move_cargo()
	_expect(not _crate.is_stowed(), "F away from the rover did not drop the crate")
	_expect(not _crate.freeze, "dropped crate is still frozen")
	_expect(_crate.collision_layer != 0, "dropped crate still has its collision off")
	_expect(_astronaut.back_rack().is_empty(), "back rack did not empty on drop")


## How far a stowed crate is from the slot it should be sitting on.
func _slot_error(crate: Crate) -> float:
	var slot := crate.get_parent() as Node3D
	if slot == null:
		return INF
	return crate.global_position.distance_to(slot.global_position)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: cargo round trip and rover load are correct.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
