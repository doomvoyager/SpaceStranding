extends Node3D
## How hard the scan dots can emit before the hue stops surviving.
##
## The scene tonemaps with ACES, which clamps saturated colour hardest exactly
## where it is brightest - the same property the [[Decision-Log]] notes for the
## palette's reds. The first scan emitted at 1.5 and produced a grid of white
## dots: perfectly visible, carrying no slope information at all.
##
## Renders the same frame across a range and reports the mean saturation of the
## dots, so the answer is looked at and measured rather than argued about.
##
## Runs windowed on purpose.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_scan_glow.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://scan_glow"
const VALUES := [0.25, 0.4, 0.55, 0.8, 1.2, 1.8]

var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	var hud := world.find_child("HUD", true, false)
	hud._controls_card.visible = false
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var scanner := world.find_child("Scanner", true, false) as Scanner
	# Tags off: this is about the grid, and text would skew the pixel stats.
	scanner.max_tags = 0

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true
	var here := astronaut.global_position
	_cam.position = here + Vector3(6.0, 9.0, 16.0)
	_cam.look_at(here + Vector3(-6.0, 0.0, -18.0), Vector3.UP)

	print("%8s %14s %14s" % ["glow", "mean sat", "blown pixels"])
	for value: float in VALUES:
		scanner.glow = value
		scanner.ping()
		# Let the wave cross the frame and settle.
		for i in 40:
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/glow_%.2f.png" % [OUT_DIR, value])
		var stats := _measure(image)
		print("%8.2f %13.3f %13.1f%%" % [value, stats.x, stats.y * 100.0])

	print("")
	print("Mean saturation over the bright pixels, and how many of them are")
	print("clipped to near-white. Want the highest glow that keeps saturation")
	print("up: past the knee the dots are bright and colourless, which is worse")
	print("than dim and readable.")
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Mean HSV saturation of the lit dots, and the fraction of them blown to white.
func _measure(image: Image) -> Vector2:
	var total := 0.0
	var blown := 0
	var counted := 0
	for y in range(int(image.get_height() * 0.55), image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var c := image.get_pixel(x, y)
			# Only the dots: they are much brighter than the regolith around
			# them, which is what makes them dots.
			if c.v < 0.55:
				continue
			counted += 1
			total += c.s
			if c.s < 0.12:
				blown += 1
	if counted == 0:
		return Vector2.ZERO
	return Vector2(total / counted, float(blown) / counted)


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out
