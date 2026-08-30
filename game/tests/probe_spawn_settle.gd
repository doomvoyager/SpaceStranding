extends Node3D
## Diagnostic: does anything in the world damage its own cargo just by starting?
##
## The delivery capture reported a crate at 0.88 condition that nobody had
## touched. Either placement drops crates onto the ground hard enough to
## register, or they are sliding down slopes and tumbling. Those want opposite
## fixes, so measure which.
##
## Runs as a scene. Prints, never fails.
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##     res://tests/probe_spawn_settle.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const SAMPLES := [30, 90, 180, 360]

var _crates: Array[Crate] = []
var _spawn: Array[Vector3] = []
var _frames := 0


func _ready() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().physics_frame

	var holder := world.find_child("Crates", true, false)
	for child in holder.get_children():
		var crate := child as Crate
		if crate != null:
			_crates.append(crate)
			_spawn.append(crate.global_position)
	print("--- spawn settle probe: %d crates ---" % _crates.size())


func _physics_process(_delta: float) -> void:
	_frames += 1
	if not SAMPLES.has(_frames):
		return
	print("")
	print("after %d frames (%.1f s)" % [_frames, float(_frames) / Engine.physics_ticks_per_second])
	for i in _crates.size():
		var crate := _crates[i]
		print("  crate %d  condition %.4f  moved %.3f m  speed %.3f m/s  jolt %.2f"
			% [i, crate.condition, crate.global_position.distance_to(_spawn[i]),
			   crate.linear_velocity.length(), crate.jolt()])
	if _frames == SAMPLES[-1]:
		get_tree().quit(0)
