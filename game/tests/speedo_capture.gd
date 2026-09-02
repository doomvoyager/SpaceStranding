extends Node3D
## Look-dev capture for the rover speedometer. Writes PNGs to user://speedo/.
##
## `test_speedometer.tscn` proves the number is right and that it is on screen.
## What it cannot judge is the only question left:
##
##   - is a mono readout in the bottom-right corner legible against terrain that
##     is this red, at this contrast, without a card behind it that shouts
##   - does it sit far enough from the load line to read as an instrument rather
##     than as another prompt
##   - do the digits hold still, or does the figure jitter left and right as the
##     number changes — the reason the panel is set in JetBrains Mono, which is
##     otherwise unused in this project
##   - does REV read at a glance
##
## Boards the rover and drives it by writing `linear_velocity` directly rather
## than by synthesising input: this is a picture of the panel, not a test of the
## drivetrain, and a scripted throttle would spend the capture climbing.
##
## Runs windowed on purpose: --headless is the dummy renderer and writes no
## image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/speedo_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://speedo"

var _rover: Rover


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	# The reference card covers the top left of every frame, and H is the toggle
	# a player would use.
	var hud := world.find_child("HUD", true, false)
	hud._controls_card.visible = false
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	_rover = get_tree().get_first_node_in_group("rover") as Rover

	# On foot first, which is the frame that shows the panel is *not* there.
	await _shot("01_on_foot", 20)

	_rover.enter(astronaut)
	await _shot("02_parked", 60)
	await _drive(1.4, 90)
	await _shot("03_walking_pace", 0)
	await _drive(5.2, 90)
	await _shot("04_at_speed", 0)
	await _drive(-2.6, 90)
	await _shot("05_reverse", 0)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Hold the rover at `speed` m/s along its own forward axis for `frames`.
##
## Re-applied every frame because the drivetrain is braking against it — with no
## throttle input the rover is coasting, and one shove would be gone before the
## HUD had drawn it.
func _drive(speed: float, frames: int) -> void:
	for i in frames:
		var forward := -_rover.global_transform.basis.z
		_rover.linear_velocity = Vector3(
			forward.x * speed, _rover.linear_velocity.y, forward.z * speed)
		await RenderingServer.frame_post_draw


func _shot(name: String, settle: int) -> void:
	for i in settle:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("  %s  %.2f m/s" % [name, _rover.ground_speed() if _rover != null else 0.0])
