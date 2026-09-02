extends Node3D
## How big the facility sign has to be to work as a navigation aid.
##
## The sign is there so a facility can be found from across the Verge, so the
## question is not "does it render" but "can it be read from where you would be
## looking for the place". Renders the same distant frame at a few pixel_size
## values; pick the smallest one that is still readable.
##
## **Re-run 2026-09-02, on a sign that is now a scan result** rather than
## permanent scenery — see `site_sign.gd`. Two things changed the answer: the
## sign only shows during a pulse, so it no longer has to survive being stared
## at for a whole drive, which is what the old size was defending against; and
## it carries a distance now, so there is more of it on screen at any size. The
## sweep therefore runs *downward* from the old 0.0004.
##
## `reveal()` lights the signs by hand — there is no player here to press Q, and
## the reveal fades on the scanner's envelope, so they are re-lit per shot.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##        res://tests/probe_sign_size.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://sign_size"
## With fixed_size on, pixel_size sets a constant *screen* size instead of a
## world size, which is what a navigation label wants: readable far away without
## filling the screen when you walk up to it.
##
## 0.00022 is what `Scanner.tag_size` draws its own tags at, and is the size the
## sign should be judged against — the two belong to the same instrument now.
## 0.0004 is what the sign used to be, kept in the sweep so "a lot smaller" has
## something to be smaller *than*.
const SIZES := [0.00012, 0.00016, 0.00018, 0.00022, 0.0004]
## The far one is what the 200 m range exists for. The near one is the walk-up
## check: a fixed-size label does not shrink as you approach, so this is where an
## oversized sign starts covering the building it names.
const DISTANCES := [200.0, 30.0]

var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	var hearth := world.find_child("Hearth", true, false) as Facility
	var sign_node := hearth.get_node("Sign") as SiteSign
	# The reference card would sit over the top-left of every frame.
	var hud := world.find_child("HUD", true, false)
	hud._controls_card.visible = false
	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.current = true

	# Every sign in the scene, not only Hearth's: a 200 m frame has the other
	# sites in it, and how a field of signs reads together is the question.
	var signs: Array[SiteSign] = []
	for node in get_tree().get_nodes_in_group("site_sign"):
		var s := node as SiteSign
		if s != null:
			signs.append(s)
	print("signs in the scene: %d" % signs.size())

	var p := hearth.global_position

	# Typed explicitly: iterating an untyped const Array yields Variants, and a
	# Variant on the right of := makes the whole inference fail to compile.
	for distance: float in DISTANCES:
		_cam.position = p + Vector3(0.62, 0.26, 0.75).normalized() * distance
		_cam.look_at(p + Vector3(0.0, 6.0, 0.0), Vector3.UP)
		for size: float in SIZES:
			for s in signs:
				s.pixel_size = size
				s.reveal()
			# Long enough for the fade-in to finish, or each frame in the sweep
			# is a picture of a different alpha rather than of a different size.
			for i in 40:
				await RenderingServer.frame_post_draw
			var file := "%s/sign_%.5f_at_%.0fm.png" % [OUT_DIR, size, distance]
			get_viewport().get_texture().get_image().save_png(file)
			print("  %.5f -> '%s'" % [size, sign_node.text])
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
