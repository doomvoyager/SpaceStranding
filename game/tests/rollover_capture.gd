extends Node3D
## Look-dev capture for the rollover recovery. Boots the real world scene, puts
## the loaded rover on its roof, and writes a frame every so often through the
## righting to user://rollover_look/.
##
## The half no headless test can judge. `test_rollover_recovery.tscn` proves the
## rover ends upright with its load intact; it says nothing about whether the
## two and a half seconds in between read as a heave or as a cheat.
##
## Must run as a scene, not --script. Runs windowed on purpose: --headless uses
## the dummy renderer and produces no image.
##   engine/Godot.app/Contents/MacOS/Godot --path game res://tests/rollover_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://rollover_look"
## Frames through the righting to capture, as fractions of its duration.
const SAMPLES: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

var _cam: Camera3D
var _rover: Rover


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	_rover = world.find_child("Rover", true, false) as Rover
	for c in _find_cameras(world):
		c.current = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		(hud as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.fov = 52.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	var crates := world.find_child("Crates", true, false)
	if crates != null:
		for child in crates.get_children():
			var crate := child as Crate
			if crate != null:
				_rover.cargo_rack().load_crate(crate)
		_rover.refresh_load()

	# On its roof, from just above the ground it is standing on.
	var here := _rover.global_position
	_rover.global_transform = Transform3D(
		Basis(Vector3.FORWARD, PI), here + Vector3.UP * 0.6
	)
	_rover.linear_velocity = Vector3.ZERO
	_rover.angular_velocity = Vector3.ZERO
	for i in 180:
		await get_tree().physics_frame
	_rover.cargo_rack().reset_jolt()

	var eye := _rover.global_position + Vector3(6.4, 2.4, 5.4)
	await _shot("01_flipped", eye)

	print("rolled over: %s, will right: %s, load %d crates"
		% [_rover.is_rolled_over(), _rover.can_right(), _rover.cargo_rack().count()])
	_rover.begin_righting()

	# Driven off elapsed time rather than a frame count: _process and
	# _physics_process do not interleave anything like realtime here.
	var started := Time.get_ticks_msec()
	for i in SAMPLES.size():
		var want := SAMPLES[i] * _rover.righting_duration * 1000.0
		while Time.get_ticks_msec() - started < want:
			await get_tree().physics_frame
		await _shot("%02d_righting_%02d" % [i + 2, int(SAMPLES[i] * 100.0)], eye)

	for i in 120:
		await get_tree().physics_frame
	await _shot("09_settled", eye)
	print("settled: upright_dot %+.2f, worst condition %.4f"
		% [_rover.upright_dot(), _rover.cargo_rack().worst_condition()])
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out


func _shot(shot_name: String, eye: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(_rover.global_position, Vector3.UP)
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"%s/%s.png" % [OUT_DIR, shot_name]
	)
