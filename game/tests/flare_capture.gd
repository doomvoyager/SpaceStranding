extends Node3D
## Stills of the camera's glass: the sun's flare and the smudges it lights, the
## flare going when something covers the sun, and regolith dust building up on
## the lens - then the real thing, from the rover's chase camera driving
## sunward.
##
## Every still but the last two is shot twice, with the glass off and on, and
## prints the share of the frame the glass moved by more than 16/255, with a
## difference image beside it. "The flare goes when the rover covers the sun"
## is then a number. The grain's clock is stopped for the run, so two shots of
## the same view differ only by the glass.
##
## The sun sits on the +Z horizon at 5.5 degrees. Sun only, as the other look
## captures are - `-- --lights` keeps the settlement's lights, and
## `-- --tag=name` prefixes the files. `-- --set=flare_halo=0.3,dust_density=2`
## overrides film_material values for the run, in memory, for sweeps.
##
## Must run WINDOWED - --headless draws nothing:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/flare_capture.tscn -- --tag=after

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://flare"
## A pixel counts as moved past this much in any channel. A whole-frame mean
## cannot see a small change; see CLAUDE.md.
const CHANGE := 16.0 / 255.0
## The glass's own intensities, zeroed for the "off" shot.
const GLASS := ["flare_intensity", "dirt_intensity", "dust_glow"]
## Eyes where the terrain covers the sun, and where the disc sits just under a
## rim with its glare showing - found by tests/probe_sun_disc.tscn.
const BEHIND_RIM := Vector3(0.0, 0.0, -180.0)
const UNDER_RIM := Vector3(-240.0, 0.0, 0.0)

var _terrain: TerrainSource
var _lens: Lens
var _film: ShaderMaterial
var _glass_on := {}
var _cam: Camera3D
var _dust: LensDust
var _tag := ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("flare_capture must run windowed")
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=") + "-"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 60:
		await get_tree().physics_frame
	_terrain = world.find_child("Terrain", true, false) as TerrainSource
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if not "--lights" in args:
		for light in world.find_children("*", "Light3D", true, false):
			if light != sun:
				(light as Light3D).visible = false
	_lens = world.find_child("PostprocessingEffects", true, false) as Lens
	_film = (world.find_child("Film", true, false) as ColorRect).material as ShaderMaterial
	_film.set_shader_parameter("time_scale", 0.0)
	for arg in args:
		if not arg.begins_with("--set="):
			continue
		for pair in arg.trim_prefix("--set=").split(",", false):
			var kv := pair.split("=")
			if kv.size() == 2:
				_film.set_shader_parameter(kv[0], float(kv[1]))
				print("set %s = %s" % [kv[0], kv[1]])
	for key: String in GLASS:
		_glass_on[key] = _film.get_shader_parameter(key)

	for c in world.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 30000.0
	add_child(_cam)
	_cam.current = true
	# A lens with no spray to watch: it holds whatever coverage is set here.
	_dust = LensDust.new()
	_cam.add_child(_dust)

	var toward := -World.sun_direction()
	var flat := Vector3(toward.x, 0.0, toward.z).normalized()
	var across := flat.cross(Vector3.UP)
	var eye := _ground(Vector3(0.0, 0.0, -4.0), 1.7)
	print("--- the glass, %s ---" % get_viewport().get_visible_rect().size)

	await _pair("01_sun_centre", eye, eye + toward * 100.0)
	await _pair("02_sun_off_axis", eye, eye + _turn(toward, -16.0, -8.0) * 100.0)
	await _pair("03_sun_near_edge", eye, eye + _turn(toward, -47.0, 0.0) * 100.0)
	await _pair("04_sun_out_of_frame", eye, eye + _turn(toward, -56.0, 0.0) * 100.0)
	var rover := world.find_child("Rover", true, false) as Rover
	var behind := rover.global_position + World.sun_direction() * 6.0
	await _pair("05_behind_rover", behind, behind + toward * 100.0)
	var rim := _ground(BEHIND_RIM, 1.7)
	await _pair("06_behind_rim", rim, rim + toward * 100.0)
	var under := _ground(UNDER_RIM, 1.7)
	await _pair("07_under_rim", under, under + toward * 100.0)

	var side := eye + across * 40.0 + Vector3.DOWN * 4.0
	await _pair("08_dust_25", eye, side, 0.25)
	await _pair("09_dust_50", eye, side, 0.5)
	await _pair("10_dust_100", eye, side, 1.0)
	await _pair("11_dust_60_sun", eye, eye + _turn(toward, -16.0, -8.0) * 100.0, 0.6)

	await _chase(world, rover)
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


## The same view with the glass off and on, and what changed.
func _pair(shot: String, eye: Vector3, look: Vector3, coverage := 0.0) -> void:
	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
	# Let the streamed tiles catch up with a moved eye.
	for i in 60:
		await get_tree().process_frame
	var off := await _shoot(shot + "_off", false, 0.0)
	var on := await _shoot(shot, true, coverage)
	_save(_diff_image(off, on), shot + "_diff")
	print("  %-22s glass moved %6.2f%% of the frame  luma %.3f -> %.3f  sun %s%s" % [
		shot, _changed_fraction(off, on) * 100.0, _luma(off), _luma(on),
		_lens.sun_uv.snapped(Vector2.ONE * 0.001),
		"" if _lens.sun_ahead > 0.0 else " (behind)"])


func _shoot(shot: String, glass: bool, coverage: float) -> Image:
	for key: String in GLASS:
		_film.set_shader_parameter(key, _glass_on[key] if glass else 0.0)
	_dust.coverage = coverage
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_save(img, shot)
	return img


## The rover's own chase camera, driving at the sun: first with the dust the
## drive threw, then with a lens most of the way gone.
func _chase(world: Node, rover: Rover) -> void:
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	# Parked, so the transform write lands; face it at the sun.
	var toward := -World.sun_direction()
	var face := Vector3(toward.x, 0.0, toward.z).normalized()
	rover.global_basis = Basis.looking_at(face, Vector3.UP)
	for i in 30:
		await get_tree().physics_frame
	rover.first_person = false
	rover.enter(astronaut)
	var chase := rover.view_camera()
	var lens := chase.get_node("LensDust") as LensDust
	Input.action_press("drive_forward")
	for i in 360:
		await get_tree().physics_frame
	for i in 4:
		await RenderingServer.frame_post_draw
	print("  chase: %.1f m/s, lens coverage %.3f after 6 s" % [rover.forward_speed(), lens.coverage])
	_save(get_viewport().get_texture().get_image(), "12_chase_sunward")
	lens.coverage = 0.7
	for i in 4:
		await RenderingServer.frame_post_draw
	_save(get_viewport().get_texture().get_image(), "13_chase_dusty")
	Input.action_release("drive_forward")


func _turn(dir: Vector3, yaw_deg: float, pitch_deg: float) -> Vector3:
	var d := dir.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var right := d.cross(Vector3.UP).normalized()
	return d.rotated(right, deg_to_rad(pitch_deg))


func _ground(at: Vector3, clearance: float) -> Vector3:
	return Vector3(at.x, _terrain.world_height_at(at.x, at.z) + clearance, at.z)


func _save(img: Image, shot: String) -> void:
	img.save_png("%s/%s%s.png" % [OUT_DIR, _tag, shot])


func _luma(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return total / maxf(n, 1.0)


## Share of sampled pixels where some channel moved by more than CHANGE.
func _changed_fraction(a: Image, b: Image) -> float:
	var moved := 0
	var n := 0
	for y in range(0, mini(a.get_height(), b.get_height()), 2):
		for x in range(0, mini(a.get_width(), b.get_width()), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			n += 1
			if absf(p.r - q.r) > CHANGE or absf(p.g - q.g) > CHANGE or absf(p.b - q.b) > CHANGE:
				moved += 1
	return float(moved) / float(maxi(n, 1))


## Half-size, four times the difference, so a faint change can be seen.
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
