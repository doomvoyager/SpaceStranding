extends Node3D
## The two views, on foot and in the rover, as the player sees them - plus the
## frames that justify the layer work.
##
## The headless test proves which camera is on screen and which layers it
## skips. What it cannot see is what the eye actually gets: whether the suit's
## shadow is still on the ground once the suit is hidden from the camera, and
## what the driver's eye would be staring at if the hull were not culled. So
## two sets of controls:
##
##   - **The shadow.** Under the real 5.5 degree sun a figure's shadow is a
##     nine-percent darkening nobody can see, so the sun is raised to 35 for
##     these frames, and the animation is frozen so nothing but the setting
##     changes between shots. The third-person frame is captured with the suit
##     on its own layer, on layer 1, and with `cast_shadow` off: the first two
##     should be identical and the third should not, or the instrument could
##     not see a shadow go and the identical pair proves nothing.
##   - **The hull.** The rover's eye is captured with its cull mask restored,
##     which is the blockout wedge it would otherwise be looking at.
##
## Must run as a scene, windowed. --headless is the dummy renderer and writes
## no image:
##   engine/Godot.app/Contents/MacOS/Godot --path game res://tests/view_capture.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://view_look"
## Sun elevation for the shadow controls, degrees. High enough that a standing
## figure's shadow is a plain dark shape rather than a streak to the horizon.
const CONTROL_SUN := 35.0
## A pixel counts as changed when any channel moves by more than this, out of
## 255. Well above dither and antialiasing, well below a shadow.
const CHANGE := 16

var _astronaut: Astronaut
var _rover: Rover


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 90:
		await get_tree().physics_frame

	_astronaut = world.find_child("Astronaut", true, false) as Astronaut
	_rover = world.find_child("Rover", true, false) as Rover
	# A CanvasLayer, not a CanvasItem - `visible` exists on both, the cast to
	# the wrong one came back null and the first run kept the controls card.
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false

	# Look along the sunlight, so your own shadow lies on the ground ahead. Read
	# off the light itself rather than off `World.sun_direction()`: the first
	# run aimed by the constant and the shadows in frame ran the other way.
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	var along := -sun.global_basis.z if sun != null else World.sun_direction()
	print("light travels along %s; World.sun_direction() says %s"
		% [(-sun.global_basis.z).snapped(Vector3.ONE * 0.01) if sun != null else "n/a",
			World.sun_direction().snapped(Vector3.ONE * 0.01)])
	along.y = 0.0
	_astronaut.aim_at(_astronaut.global_position + along.normalized() * 50.0)
	_astronaut._pitch_by(deg_to_rad(-12.0))

	_astronaut.first_person = false
	await _shot("01_foot_third")
	_astronaut.first_person = true
	await _shot("02_foot_first")
	# The suit back on layer 1, seen by every camera: the eye is inside the helmet.
	_set_suit_layers(1)
	await _shot("03_foot_first_suit_visible")
	_set_suit_layers(_astronaut.suit_layers)

	await _shadow_controls()

	_rover.enter(_astronaut)
	await _settle(30)
	_rover.first_person = false
	await _shot("12_rover_third")
	_rover.first_person = true
	await _shot("13_rover_first")

	# Control: the eye allowed to see the hull.
	var mask := _rover.eye().cull_mask
	_rover.eye().cull_mask = 0xFFFFF
	await _shot("14_rover_first_hull_visible")
	_rover.eye().cull_mask = mask

	# On a side slope, frozen so the pose holds: the eye rolls with the cab,
	# the chase camera stops at its limit.
	_rover.freeze = true
	_rover.tilt_smoothing = 0.0
	var xform := _rover.global_transform
	xform.basis = _rover.global_basis.rotated(-_rover.global_basis.z.normalized(), deg_to_rad(30.0))
	_rover.global_transform = xform
	await _settle(10)
	await _shot("15_rover_first_rolled_30")
	_rover.first_person = false
	await _shot("16_rover_third_rolled_30")

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## Third-person frames that differ only in the suit's render settings, plus
## the eye's view of the same shadow. Sun raised, animation frozen, head lamp
## off - the lamp is far brighter than the sun where the figure's shadow falls
## and fills it in, which is what the first run of this measured.
##
## A same-settings pair goes first: that is the noise floor, and a difference
## that does not clear it is not a difference. The figure reported is the share
## of pixels that moved by more than `CHANGE`, because a shadow is a region
## that changes a lot and noise is the whole frame changing a little, and a
## whole-frame mean cannot tell those apart. The two difference images are
## written beside the frames so the shape of what changed can be looked at.
func _shadow_controls() -> void:
	var rig := _astronaut.get_node("Body/Rig") as AstronautRig
	var lamp := _astronaut.get_node("Body/HeadLamp") as Light3D
	var real_sun: float = World.sun_elevation_deg
	# The setter emits World.changed, and the world scene re-aims the sun on it.
	World.sun_elevation_deg = CONTROL_SUN
	rig.set_animating(false)
	lamp.visible = false
	# Steeper than the game shots, so the ground the shadow falls on is in frame.
	_astronaut._pitch_by(deg_to_rad(-16.0))
	await _settle(10)

	_astronaut.first_person = false
	var on_suit_layer := await _shot("04_shadow_third_suit_layer")
	var again := await _shot("05_shadow_third_suit_layer_again")
	_set_suit_layers(1)
	var on_layer_1 := await _shot("06_shadow_third_layer_1")
	_set_suit_layers(_astronaut.suit_layers)
	_set_suit_shadows(false)
	var no_shadow := await _shot("07_shadow_third_no_shadow")
	_set_suit_shadows(true)

	# And from the eye, which cannot see the suit: its shadow should still be
	# on the ground, and go when casting is turned off.
	_astronaut.first_person = true
	var eye_casting := await _shot("08_shadow_first")
	_set_suit_shadows(false)
	var eye_no_shadow := await _shot("09_shadow_first_no_shadow")
	_set_suit_shadows(true)

	# The same two frames over a plain StandardMaterial3D ground. The second
	# run of this found no shadow on the regolith from anything - not the suit,
	# not the crates, not the facility - so this separates "the layer" from
	# "the terrain shader" before either gets blamed.
	var plain := StandardMaterial3D.new()
	# Mid grey. White saturated under the scene's ambient before the sun had a
	# say, and a saturated frame shows no shadow whatever the light does.
	plain.albedo_color = Color(0.25, 0.25, 0.25)
	plain.roughness = 1.0
	var regolith := _swap_ground(plain)
	await _settle(5)
	var plain_casting := await _shot("10_shadow_first_plain_ground")
	_set_suit_shadows(false)
	var plain_no_shadow := await _shot("11_shadow_first_plain_ground_no_shadow")
	_set_suit_shadows(true)
	_swap_ground(regolith)

	print("shadow control at a %.0f deg sun, lamp off - pixels moved by more than %d/255:"
		% [CONTROL_SUN, CHANGE])
	_report("same settings twice (noise floor)", on_suit_layer, again, "")
	_report("suit on layer %d vs layer 1" % _astronaut.suit_layers, on_suit_layer, on_layer_1, "diff_layer")
	_report("suit casting a shadow vs not", on_suit_layer, no_shadow, "diff_no_shadow")
	_report("from the eye, casting vs not", eye_casting, eye_no_shadow, "diff_first_no_shadow")
	_report("plain ground, casting vs not", plain_casting, plain_no_shadow, "diff_plain_ground_no_shadow")

	_astronaut._pitch_by(deg_to_rad(16.0))
	lamp.visible = true
	rig.set_animating(true)
	World.sun_elevation_deg = real_sun
	await _settle(10)


## Put `material` on every terrain node that has a `surface_material`, and
## return what the first one had so it can be put back.
func _swap_ground(material: Material) -> Material:
	var previous: Material = null
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if not ("surface_material" in node):
			continue
		if previous == null:
			previous = node.surface_material
		node.surface_material = material
	return previous


func _report(label: String, a: Image, b: Image, diff_name: String) -> void:
	print("  %-36s %5.2f%% of pixels, mean %.3f / 255"
		% [label, _changed_fraction(a, b) * 100.0, _difference(a, b) * 255.0])
	if diff_name != "":
		_diff_image(a, b).save_png("%s/%s.png" % [OUT_DIR, diff_name])


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _suit_meshes() -> Array[Node]:
	return _astronaut.get_node("Body/Rig").find_children("*", "GeometryInstance3D", true, false)


func _set_suit_layers(layers: int) -> void:
	for node in _suit_meshes():
		(node as GeometryInstance3D).layers = layers


func _set_suit_shadows(cast: bool) -> void:
	for node in _suit_meshes():
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)


func _shot(shot_name: String) -> Image:
	for i in 6:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	var camera := get_viewport().get_camera_3d()
	var through := "no camera"
	if camera != null:
		through = "%s/%s" % [camera.get_parent().name, camera.name]
	print("%-30s through %-22s mean luma %.4f" % [shot_name, through, _luma(image)])
	return image


func _luma(image: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var c := image.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			count += 1
	return sum / float(maxi(count, 1))


## Mean absolute per-channel difference between two frames, 0 to 1.
func _difference(a: Image, b: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(0, mini(a.get_height(), b.get_height()), 4):
		for x in range(0, mini(a.get_width(), b.get_width()), 4):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			sum += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			count += 3
	return sum / float(maxi(count, 1))


## Share of sampled pixels where some channel moved by more than CHANGE.
func _changed_fraction(a: Image, b: Image) -> float:
	var limit := float(CHANGE) / 255.0
	var changed := 0
	var count := 0
	for y in range(0, mini(a.get_height(), b.get_height()), 2):
		for x in range(0, mini(a.get_width(), b.get_width()), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > limit or absf(p.g - q.g) > limit or absf(p.b - q.b) > limit:
				changed += 1
			count += 1
	return float(changed) / float(maxi(count, 1))


## Where two frames differ, at half size, brightened four times so a shadow's
## worth of change reads as a shape.
func _diff_image(a: Image, b: Image) -> Image:
	var w := mini(a.get_width(), b.get_width()) / 2
	var h := mini(a.get_height(), b.get_height()) / 2
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var p := a.get_pixel(x * 2, y * 2)
			var q := b.get_pixel(x * 2, y * 2)
			out.set_pixel(x, y, Color(
				minf(absf(p.r - q.r) * 4.0, 1.0),
				minf(absf(p.g - q.g) * 4.0, 1.0),
				minf(absf(p.b - q.b) * 4.0, 1.0)))
	return out
