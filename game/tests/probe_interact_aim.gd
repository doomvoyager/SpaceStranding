extends Node3D
## How forgiving the aim actually is, measured rather than reasoned about.
##
## `aim_bias` was picked with arithmetic — a crate 1.5 m away at 60 degrees
## should lose to a rover 2.5 m away dead ahead — and arithmetic is not the same
## as playing it. This fixes the geometry to the case Mac actually hit, **a
## crate lying beside the rover**, sweeps the look direction all the way round,
## and reports which arc gives which.
##
## Read it as: how much of the horizon has to be swept to change your mind, and
## whether either answer is so narrow it would feel like a fight.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_interact_aim.tscn

const SETTLE_FRAMES := 30

## Rover position, crate position, and a name. The rover is always ahead at +X;
## the crate is nearer and off to one side by varying amounts.
const CASES := [
	[Vector3(2.6, 0.0, 0.0), Vector3(1.6, 0.0, 1.0), "crate beside the rover"],
	[Vector3(2.6, 0.0, 0.0), Vector3(1.4, 0.0, 0.5), "crate almost in the way"],
	[Vector3(2.6, 0.0, 0.0), Vector3(1.2, 0.0, 1.8), "crate well off to one side"],
	[Vector3(2.6, 0.0, 0.0), Vector3(-1.4, 0.0, 0.0), "crate on the far side"],
]

var _astronaut: Astronaut
var _rover: Rover
var _crate: Crate
var _frames := 0


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	add_child(_rover)
	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(0.0, 1.0, 0.0)
	add_child(_astronaut)
	_crate = load("res://scenes/cargo/crate.tscn").instantiate()
	add_child(_crate)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames != SETTLE_FRAMES:
		return

	print("half-angle %.0f deg, aim_bias %.1f. Astronaut at the origin."
		% [_astronaut.interact_half_angle, _astronaut.aim_bias])
	print("")
	print("%-28s %8s %8s   %6s %6s %6s"
		% ["case", "crate", "rover", "crate", "rover", "none"])
	print("%-28s %8s %8s   %6s %6s %6s"
		% ["", "at", "at", "arc", "arc", "arc"])

	for case in CASES:
		var rover_at: Vector3 = case[0]
		var crate_at: Vector3 = case[1]
		_rover.global_position = rover_at + Vector3.UP
		_rover.linear_velocity = Vector3.ZERO
		_crate.global_position = crate_at + Vector3.UP
		_crate.linear_velocity = Vector3.ZERO

		var tally := {Astronaut.KIND_CRATE: 0, Astronaut.KIND_ROVER: 0, -1: 0}
		for degrees in 360:
			var radians := deg_to_rad(float(degrees))
			_astronaut.aim_at(_astronaut.global_position
				+ Vector3(cos(radians), 0.0, sin(radians)) * 10.0)
			var target := _astronaut.interact_target()
			var kind := target.kind if target != null else -1
			tally[kind] = int(tally.get(kind, 0)) + 1

		print("%-28s %8.1f %8.1f   %5d° %5d° %5d°" % [
			case[2],
			crate_at.length(), rover_at.length(),
			tally[Astronaut.KIND_CRATE], tally[Astronaut.KIND_ROVER], tally[-1],
		])

	print("")
	print("Each arc is how many degrees of look direction give that answer.")
	print("The three sum to 360. A tiny arc for either would mean a fight.")
	get_tree().quit()
