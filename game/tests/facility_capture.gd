extends Node3D
## Look-dev capture for the Facility and the order panel. Boots the real world
## scene and writes PNGs to user://facility_look/.
##
## What a headless test cannot judge, and what this exists for:
##
##   - whether the terminal, dock and pad read as *one place* rather than three
##     props that happen to be near each other
##   - whether the dock is at a height you would actually lift a crate onto
##   - whether the panel is legible over the terrain, and whether 940x540 of
##     board is the right amount of screen
##   - whether an issued order looks like cargo waiting for you
##
## Must run as a scene, not --script. Runs windowed on purpose: --headless uses
## the dummy renderer and produces no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/facility_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://facility_look"

var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)

	for i in 90:
		await get_tree().physics_frame

	var hearth := world.find_child("Hearth", true, false) as Facility
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var panel := world.find_child("OrderPanel", true, false) as OrderPanel

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	var p := hearth.global_position
	# From a distance first: the sign is a navigation aid, so the question is
	# whether it can be read from where you would be looking for the place.
	await _shot("00_from_afar", p + Vector3(38.0, 16.0, 46.0), p + Vector3(0.0, 6.0, 0.0))
	await _shot("01_facility", p + Vector3(9.0, 5.0, 11.0), p + Vector3(-1.0, 1.0, 0.0))
	await _shot("02_terminal", p + Vector3(1.4, 2.0, 4.2), p + Vector3(0.0, 1.3, 0.0))

	# An order on the dock: what the player walks out to after accepting.
	Orders.accept(104)
	hearth.issue(Orders.get_order(104))
	for i in 30:
		await get_tree().physics_frame
	var dock := hearth.dock().global_position
	await _shot("03_dock_loaded", dock + Vector3(2.2, 2.4, 4.6), dock + Vector3(0.0, 0.4, 0.0))

	# The board itself. Stand the astronaut at the terminal first so the frame
	# behind the panel is the one a player would actually see through it.
	astronaut.global_position = p + Vector3(0.0, 1.2, 3.0)
	astronaut.velocity = Vector3.ZERO
	for i in 20:
		await get_tree().physics_frame
	var a := astronaut.global_position
	_cam.position = a + Vector3(0.0, 1.6, 3.4)
	_cam.look_at(p + Vector3(0.0, 1.2, 0.0), Vector3.UP)
	panel.open(hearth)
	for i in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/04_board.png" % OUT_DIR)

	# The storage tab, with something on the shelf to look at. Deposited through
	# the facility rather than assembled by hand, so the capture exercises the
	# same path the player does.
	for spec in [["Water canister", 55.0, 0.62], ["Core samples", 22.0, 0.97],
			["Pipe stock", 55.0, 0.31], ["Spare cell", 48.0, 1.0]]:
		var item := StoredItem.new()
		item.cargo_name = spec[0]
		item.mass = spec[1]
		item.condition = spec[2]
		item.value = 140.0
		Orders.deposit(hearth.facility_id, item)
	var house := StoredItem.new()
	house.cargo_name = "Reactor coolant"
	house.mass = 90.0
	house.cargo_owner = Crate.Owner.FACILITY
	house.owner_id = hearth.facility_id
	Orders.deposit(hearth.facility_id, house)

	panel.get_node("Root/Frame/Margin/Rows/Tabs").current_tab = 1
	for i in 8:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/05_storage.png" % OUT_DIR)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out


func _shot(shot_name: String, eye: Vector3, look: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(look, Vector3.UP)
	for i in 6:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
