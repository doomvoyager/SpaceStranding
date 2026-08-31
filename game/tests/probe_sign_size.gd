extends Node3D
## How big the facility sign has to be to work as a navigation aid.
##
## The sign is there so a facility can be found from across the Verge, so the
## question is not "does it render" but "can it be read from where you would be
## looking for the place". Renders the same distant frame at a few pixel_size
## values; pick the smallest one that is still readable.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##        res://tests/probe_sign_size.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://sign_size"
## With fixed_size on, pixel_size sets a constant *screen* size instead of a
## world size, which is what a navigation label wants: readable far away without
## filling the screen when you walk up to it.
const SIZES := [0.0004, 0.0007, 0.0012]
const DISTANCES := [62.0, 12.0]

var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	var hearth := world.find_child("Hearth", true, false) as Facility
	var sign_node := hearth.get_node("Sign") as Label3D
	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	var p := hearth.global_position
	sign_node.fixed_size = true

	# Typed explicitly: iterating an untyped const Array yields Variants, and a
	# Variant on the right of := makes the whole inference fail to compile.
	for distance: float in DISTANCES:
		_cam.position = p + Vector3(0.62, 0.26, 0.75).normalized() * distance
		_cam.look_at(p + Vector3(0.0, 6.0, 0.0), Vector3.UP)
		for size: float in SIZES:
			sign_node.pixel_size = size
			for i in 6:
				await RenderingServer.frame_post_draw
			var file := "%s/fixed_%.4f_at_%.0fm.png" % [OUT_DIR, size, distance]
			get_viewport().get_texture().get_image().save_png(file)
		print("captured %.0f m" % distance)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Screen pixels per world metre at `distance`, for this camera.
func _px_per_metre(distance: float) -> float:
	var height := get_viewport().get_visible_rect().size.y
	return height / (2.0 * distance * tan(deg_to_rad(_cam.fov) * 0.5))


func _find_cameras(n: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if n is Camera3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_cameras(c))
	return out
