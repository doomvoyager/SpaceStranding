extends Node3D
## The authored astronaut, in the world, doing each of the things it can do.
##
## The headless test proves the state machine reaches every state and that the
## blend lands on the right clip. What it cannot see is whether the figure is
## facing the way it walks, whether the feet skate, whether the crate on its
## back is anywhere near its back - and, the one this project has a verified
## fact about, whether a 5-degree star leaves it a black silhouette.
##
## Walks it with real input rather than by writing velocity, so the shots go
## through the controller the player uses. Prints the state machine's own name
## for each frame, so a picture that looks wrong can be told from a picture of
## the wrong clip.
##
## Must run as a scene, windowed. --headless is the dummy renderer and writes
## no image:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/astronaut_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://astronaut_look"

var _cam: Camera3D
var _astronaut: Astronaut
var _rig: AstronautRig


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	_astronaut = world.find_child("Astronaut", true, false) as Astronaut
	_rig = _astronaut.find_child("Rig", true, false) as AstronautRig

	for c in _cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 4000.0
	add_child(_cam)
	_cam.current = true

	var hud := world.find_child("HUD", true, false)
	if hud != null:
		hud.visible = false

	await _shot("10_idle", Vector3(2.6, 1.2, 3.2))
	await _shot("11_idle_wide", Vector3(7.0, 3.0, 9.0))

	# Walking, then running, both on held input rather than written velocity.
	Input.action_press("move_forward")
	await _settle(45)
	await _shot("12_walk", Vector3(3.0, 1.3, 3.0))
	await _shot("13_walk_behind", Vector3(0.4, 1.7, 4.2))

	Input.action_press("sprint")
	await _settle(45)
	await _shot("14_run", Vector3(3.0, 1.3, 3.0))
	await _shot("15_run_behind", Vector3(0.4, 1.7, 4.2))

	# The jump, sampled on the way up and on the way down. Low gravity gives
	# about two seconds of hang, against a 0.43 s launch clip - so the second
	# of these is the shot that says whether holding the apex pose reads as
	# floating or as a freeze.
	Input.action_release("sprint")
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	await _settle(18)
	await _shot("16_jump_rising", Vector3(3.4, 2.0, 3.4))
	await _wait_until_falling()
	await _shot("17_jump_falling", Vector3(3.4, 2.0, 3.4))
	await _wait_until_grounded()
	await _shot("18_land", Vector3(3.0, 1.3, 3.0))

	Input.action_release("move_forward")
	await _settle(120)

	# And carrying, which is what the game is actually about. The placeholder
	# had a box mesh standing in for a backpack; this says whether the rack is
	# still in the right place now that the figure under it is a real one.
	var crate := _astronaut.nearest_loose_crate()
	if crate == null:
		for c in get_tree().get_nodes_in_group("cargo"):
			var loose := c as Crate
			if loose != null and not loose.is_stowed():
				crate = loose
				break
	if crate != null:
		_astronaut.back_rack().load_crate(crate)
		await _settle(30)
		await _shot("19_carrying", Vector3(2.8, 1.4, 3.4))
		await _shot("20_carrying_side", Vector3(4.0, 1.4, 0.0))

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _wait_until_falling() -> void:
	for i in 400:
		await get_tree().physics_frame
		if _astronaut.velocity.y < -0.5:
			return


func _wait_until_grounded() -> void:
	for i in 400:
		await get_tree().physics_frame
		if _astronaut.is_on_floor():
			return


func _cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_cameras(c))
	return out


## Frame the astronaut from an offset in its own body space, so a shot taken
## while it is walking away still has it in it.
func _shot(shot_name: String, offset: Vector3) -> void:
	var body := _astronaut.get_node("Body") as Node3D
	var at := _astronaut.global_position
	_cam.position = at + body.global_transform.basis * offset
	_cam.look_at(at + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	for i in 6:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	# Mean luma, because "is the astronaut readable under a 5-degree star" is a
	# question with a number behind it, and a note that says "looked dark" is
	# worth less beside the frame than one that says how dark.
	var sum := 0.0
	var step := 4
	var count := 0
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var c := image.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			count += 1
	print("%-18s state=%-7s speed=%.2f m/s  mean luma %.4f"
		% [shot_name, _rig.current_state(), Vector2(_astronaut.velocity.x,
			_astronaut.velocity.z).length(), sum / float(count)])
