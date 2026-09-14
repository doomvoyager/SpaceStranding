extends Node3D
## Drive the rover and photograph the dust while it flies.
##
## The headless test proves the emitters throw when the wheels turn and
## aim behind them; whether a spray of grains reads as lunar dust - sharp
## arcs, sunlit specks over the rover's shadow, nothing lingering - is a
## render, and one taken mid-drive, since the grains are up for a couple of
## seconds and down for good. So: the astronaut boards, the rover drives
## cross-sun, and the camera shoots it from behind and from the side while
## it is still moving; then it brakes hard and is shot again on the skid.
## Sun only, HUD hidden, as `regolith_capture` does.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game res://tests/dust_capture.tscn -- --tag=after

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://dust"

var _terrain: TerrainSource
var _rover: Rover
var _cam: Camera3D
var _tag := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=") + "-"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 60:
		await get_tree().physics_frame
	_terrain = world.find_child("Terrain", true, false) as TerrainSource
	_rover = world.find_child("Rover", true, false) as Rover
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var dust := _rover.find_child("WheelDust", true, false) as WheelDust
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	for light in _find_lights(world):
		light.visible = light == sun

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 6000.0
	add_child(_cam)
	_cam.current = true

	_rover.enter(astronaut)
	# Boarding makes the rover's chase camera current; take it back, or every
	# frame is the chase view from inside the trailing spray.
	for c in _find_cameras(world):
		c.current = false
	_cam.current = true
	for i in 30:
		await get_tree().physics_frame
	Input.action_press("drive_forward")
	for i in 200:
		await get_tree().physics_frame
	_report(dust, "driving")
	await _shot("01_chase", Vector3(0.0, 2.2, 7.0), Vector3(0.0, 0.5, -4.0))
	await _shot("02_side_low", Vector3(6.0, 0.9, 1.5), Vector3(0.0, 0.4, 1.5))
	await _shot("03_rear_wheel", Vector3(2.4, 0.7, 4.0), Vector3(0.8, 0.2, 1.2))
	Input.action_release("drive_forward")
	Input.action_press("drive_back")
	for i in 12:
		await get_tree().physics_frame
	_report(dust, "braking")
	await _shot("04_braking_side", Vector3(6.0, 1.2, 0.5), Vector3(0.0, 0.3, 0.5))
	Input.action_release("drive_back")
	for i in 150:
		await get_tree().physics_frame
	_report(dust, "stopped")
	await _shot("05_stopped", Vector3(6.0, 1.2, 0.5), Vector3(0.0, 0.3, 0.5))

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Offsets are in the rover's frame: +Z behind it, +X to its right.
func _shot(name: String, offset: Vector3, look_offset: Vector3) -> void:
	var b := _rover.global_basis
	var yaw := Basis(Vector3.UP, atan2(b.z.x, b.z.z))
	var eye := _rover.global_position + yaw * offset
	var look := _rover.global_position + yaw * look_offset
	eye.y = maxf(eye.y, _terrain.world_height_at(eye.x, eye.z) + 0.4)
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s%s.png" % [OUT_DIR, _tag, name])
	print("  %s%s  %.1f m/s" % [_tag, name, _rover.forward_speed()])


func _report(dust: WheelDust, when: String) -> void:
	if dust == null:
		return
	var ratios := PackedFloat32Array()
	for e in dust.emitters():
		ratios.append(snappedf(e.amount_ratio, 0.01))
	print("%s at %.1f m/s: amount ratios %s" % [when, _rover.forward_speed(), ratios])


func _find_lights(from: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	if from is Light3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_lights(child))
	return out


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
