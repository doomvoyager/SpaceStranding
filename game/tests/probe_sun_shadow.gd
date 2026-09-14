extends Node3D
## Why does nothing cast a sun shadow onto the ground in test_world?
##
## Found 2026-09-14 by the view capture's controls: with the sun raised to 35
## degrees, neither the suit, the crates nor a facility box shadowed the
## regolith - nor a plain StandardMaterial3D swapped in for it - while the suit
## still shadowed itself. At a 5 degree sun the ground's look *is* its shadows,
## so this has to be found before any real lunar ground is judged by eye.
##
## The smallest scene that should show a shadow - a box on a plane under a
## DirectionalLight3D - then the world's settings added back one at a time,
## each alone on that baseline and finally all together. Every variant is
## captured with the box casting and with its `cast_shadow` off, and the share
## of pixels that moved is the shadow. A variant that reads near zero names
## the cause; if only "everything" does, it is an interaction and the next run
## adds them cumulatively.
##
## Windowed, like every capture - --headless renders nothing:
##   engine/Godot.app/Contents/MacOS/Godot --path game res://tests/probe_sun_shadow.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://sun_shadow"
## A pixel counts as changed when any channel moves by more than this, of 255.
const CHANGE := 16
const CAMERA_AT := Vector3(7.0, 4.5, 9.0)

var _sun: DirectionalLight3D
var _camera: Camera3D
var _caster: MeshInstance3D
var _ground: Node3D
var _env: WorldEnvironment
## What `_measure` toggles `cast_shadow` on: the box, or every mesh of the suit.
var _casters: Array[GeometryInstance3D] = []
## What "casting" means for this variant: ON, or SHADOWS_ONLY for the fix.
var _casting_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
var _real_sun_elevation := 0.0
var _lines: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_real_sun_elevation = World.sun_elevation_deg
	var variants := {
		"baseline": func(): pass,
		"world_sun_settings": _world_sun_settings,
		"sun_placed_at_400m": _sun_placed_at_400m,
		"world_environment": _world_environment,
		"camera_near_far_as_world": _camera_as_world,
		"sun_at_5_5_degrees": _low_sun,
		"terrain_patch_regolith": _terrain_patch_regolith,
		"terrain_patch_plain": _terrain_patch_plain,
		"terrain_2048m_as_world": _terrain_as_world,
		"everything": _everything,
		# Second pass, after the first named the 2048 m heightmap terrain:
		# size or source, and what brings the shadow back.
		"terrain_1024m_procedural": _terrain_1024_procedural,
		"terrain_2048m_procedural": _terrain_2048_procedural,
		"terrain_2048m_low_bias": _terrain_2048_low_bias,
		"terrain_2048m_not_casting": _terrain_2048_not_casting,
		"field_3x3_of_683m_as_world": _field_as_world,
		# Third pass. The second was confounded: the heightmap at the origin
		# puts the box on the 42 degree massif face, inside the massif's own
		# shadow, so its shadow had nothing left to darken. These stand in the
		# real world scene, on the playa the astronaut spawns on.
		"world_box_on_playa": _world_box_on_playa,
		"world_box_low_sun": _world_box_low_sun,
		"world_suit": _world_suit,
		"world_suit_custom_aabb": _world_suit_custom_aabb,
		# Fourth pass: the eye's arrangement, and the fix.
		"world_suit_culled_by_camera": _world_suit_culled_by_camera,
		"world_suit_shadows_only": _world_suit_shadows_only,
		"world_box_culled_by_camera": _world_box_culled_by_camera,
		"world_rover_eye_as_authored": _world_rover_eye_as_authored,
		"world_rover_eye_shadows_only": _world_rover_eye_shadows_only,
		# The rover's own shadow lies under and just beyond its nose; from an
		# eye 2 m up looking level it is below the frame. Pitched down it is not.
		"world_rover_eye_down_as_authored": _world_rover_eye_down_as_authored,
		"world_rover_eye_down_shadows_only": _world_rover_eye_down_shadows_only,
	}
	# `-- --only=a,b` runs a subset; the full set is twenty variants and minutes.
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	for name: String in variants:
		if not only.is_empty() and not only.has(name):
			continue
		_build_baseline()
		await variants[name].call()
		await _settle(8)
		await _measure(name)
		_teardown()
	print("")
	print("sun shadow bisect - share of pixels the box's shadow moves, per variant:")
	for line in _lines:
		print(line)
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


# --- The baseline -------------------------------------------------------

func _build_baseline() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	add_child(_sun)
	_aim_sun(35.0, Vector3.ZERO)

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = CAMERA_AT
	_camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	_camera.current = true

	_ground = _plane_ground()
	add_child(_ground)

	_caster = MeshInstance3D.new()
	_caster.name = "Box"
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	_caster.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.5, 0.3)
	_caster.material_override = mat
	add_child(_caster)
	_caster.position = Vector3(0.0, 1.0, 0.0)
	_casters = [_caster]


func _teardown() -> void:
	# Only what hangs off this node: a world variant's sun is the world's own
	# child and goes with it.
	for node in [_sun, _camera, _ground, _caster, _env]:
		if node != null and node.get_parent() == self:
			remove_child(node)
			node.free()
	_sun = null
	_env = null
	_casters.clear()
	_casting_mode = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	World.sun_elevation_deg = _real_sun_elevation


func _plane_ground() -> Node3D:
	var ground := MeshInstance3D.new()
	ground.name = "Plane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	ground.material_override = _grey()
	return ground


func _grey() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	mat.roughness = 1.0
	return mat


## Light travelling along the direction World.sun_direction() would give at
## this elevation, azimuth 0: toward -Z and down. Same construction as
## test_world's _align_sun().
func _aim_sun(elevation_deg: float, from: Vector3) -> void:
	var e := deg_to_rad(elevation_deg)
	var dir := Vector3(0.0, -sin(e), -cos(e))
	_sun.look_at_from_position(from, from + dir, Vector3.UP)


# --- The variants -------------------------------------------------------

func _world_sun_settings() -> void:
	_sun.light_energy = 0.46
	_sun.light_color = Color(1.0, 0.97, 0.92)
	_sun.light_angular_distance = 0.53
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.16
	_sun.directional_shadow_split_3 = 0.42
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_max_distance = 320.0
	_sun.directional_shadow_pancake_size = 40.0


func _sun_placed_at_400m() -> void:
	_aim_sun(35.0, Vector3(0.0, 400.0, 0.0))


func _world_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.45, 0.47)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	_env.environment = env
	add_child(_env)


func _camera_as_world() -> void:
	_camera.near = 0.05
	_camera.far = 6000.0
	_camera.fov = 72.0


func _low_sun() -> void:
	_aim_sun(5.5, Vector3.ZERO)


## The project's own terrain, procedural so no asset is needed, on the
## regolith material it ships with. Gently rolling, box set on the ground.
func _terrain_patch_regolith() -> void:
	await _swap_ground_for_terrain(512.0, 4.0, null)


func _terrain_patch_plain() -> void:
	await _swap_ground_for_terrain(512.0, 4.0, _grey())


## The world's actual ground: the authored heightmap at its scene size and
## spacing, 2 M triangles, on the regolith.
func _terrain_as_world() -> void:
	await _swap_ground_for_terrain(2048.0, 4.0, null, true)


func _everything() -> void:
	_world_sun_settings()
	_sun_placed_at_400m()
	_world_environment()
	_camera_as_world()
	await _swap_ground_for_terrain(2048.0, 4.0, null, true)


func _terrain_1024_procedural() -> void:
	await _swap_ground_for_terrain(1024.0, 4.0, null)


func _terrain_2048_procedural() -> void:
	await _swap_ground_for_terrain(2048.0, 4.0, null)


## The world's ground with the light's biases cut to a fifth. If the shadow
## comes back, the bias is what ate it - and it grows with the depth range the
## casters span, which a 2 km mesh makes enormous.
func _terrain_2048_low_bias() -> void:
	await _swap_ground_for_terrain(2048.0, 4.0, null, true)
	_sun.shadow_bias = 0.02
	_sun.shadow_normal_bias = 0.2


## The world's ground, itself not casting. A diagnosis, not a fix: rims have to
## cast. If this brings the box's shadow back, the terrain's own extent in the
## shadow map is what breaks it.
func _terrain_2048_not_casting() -> void:
	await _swap_ground_for_terrain(2048.0, 4.0, null, true)
	var mesh := _ground.get_node("TerrainMesh") as GeometryInstance3D
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The same 2 km of the same heightmap as nine tiles instead of one mesh -
## the shape the streaming plan takes anyway.
func _field_as_world() -> void:
	var field := TerrainField.new()
	field.name = "Field"
	field.tiles_across = 3
	field.tile_size = 683.0
	field.tile_resolution = 4.0
	field.height_source = ProceduralTerrain.HeightSource.HEIGHTMAP
	field.heightmap = load(ProceduralTerrain.DEFAULT_HEIGHTMAP)
	await _install_ground(field)


func _swap_ground_for_terrain(size: float, spacing: float, material: Material,
		heightmap := false) -> void:
	var terrain := ProceduralTerrain.new()
	terrain.name = "Terrain"
	terrain.size = size
	terrain.resolution = spacing
	if heightmap:
		terrain.height_source = ProceduralTerrain.HeightSource.HEIGHTMAP
		terrain.heightmap = load(ProceduralTerrain.DEFAULT_HEIGHTMAP)
	else:
		terrain.height_scale = 3.0
	if material != null:
		terrain.surface_material = material
	await _install_ground(terrain)


func _install_ground(ground: TerrainSource) -> void:
	remove_child(_ground)
	_ground.free()
	_ground = ground
	add_child(ground)
	await _settle(6)
	# The box on the ground, and the camera framing it, wherever that is.
	var ground_y := ground.world_height_at(0.0, 0.0)
	_caster.position = Vector3(0.0, ground_y + 1.0, 0.0)
	_camera.position = CAMERA_AT + Vector3(0.0, ground_y, 0.0)
	_camera.look_at(Vector3(0.0, ground_y + 0.8, 0.0), Vector3.UP)


# --- In the real world scene ---------------------------------------------

func _world_box_on_playa() -> void:
	await _install_world(35.0, false)


func _world_box_low_sun() -> void:
	await _install_world(5.5, false)


## The suit as the caster, its meshes toggled together. Animation frozen,
## head lamp off, camera off to the side so the figure does not stand in front
## of its own shadow, which is how the chase camera missed it on the 14th.
func _world_suit() -> void:
	await _install_world(35.0, true)


## The same, with a real bounding box on the skinned mesh. Its imported AABB
## is two centimetres - see the FBX entry in CLAUDE.md - and a caster culled
## by a wrong AABB is a caster that shadows nothing.
func _world_suit_custom_aabb() -> void:
	await _install_world(35.0, true)
	for caster in _casters:
		(caster as MeshInstance3D).custom_aabb = AABB(
			Vector3(-1.0, -0.2, -1.0), Vector3(2.0, 2.6, 2.0))
	await _settle(4)


## The suit on its own render layer and the probe camera's cull mask without
## that layer - the first-person eye's arrangement. If the shadow goes with
## the suit, a camera's cull mask culls shadow casters as well, and hiding a
## thing from the eye by layer hides its shadow from the eye.
func _world_suit_culled_by_camera() -> void:
	await _install_world(35.0, true)
	for caster in _casters:
		caster.layers = 2
	_camera.cull_mask = _camera.cull_mask & ~2
	await _settle(4)


## The suit invisible by SHADOW_CASTING_SETTING_SHADOWS_ONLY instead of by a
## layer, the camera seeing every layer. If the shadow stays, that is the fix.
func _world_suit_shadows_only() -> void:
	await _install_world(35.0, true)
	for caster in _casters:
		caster.layers = 1
	_camera.cull_mask = 0xFFFFF
	_casting_mode = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	await _settle(4)


## A static box on a layer the camera culls. The suit is skinned, and a rule
## read off one kind of mesh is a guess about the other.
func _world_box_culled_by_camera() -> void:
	await _install_world(35.0, false)
	_caster.layers = 2
	_camera.cull_mask = _camera.cull_mask & ~2
	await _settle(4)


## From the rover's own eye, as the scene authors it: the hull on layer 3 and
## the eye's mask without it. Mac saw no rover shadow from the cab.
func _world_rover_eye_as_authored() -> void:
	await _install_world(35.0, false, true)


## The same eye seeing every layer, the hull shadows-only.
func _world_rover_eye_shadows_only() -> void:
	await _install_world(35.0, false, true)
	var eye := get_viewport().get_camera_3d()
	eye.cull_mask = 0xFFFFF
	_casting_mode = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	await _settle(4)


func _world_rover_eye_down_as_authored() -> void:
	await _install_world(35.0, false, true)
	_pitch_rover_eye(-50.0)


func _world_rover_eye_down_shadows_only() -> void:
	await _install_world(35.0, false, true)
	_pitch_rover_eye(-50.0)
	get_viewport().get_camera_3d().cull_mask = 0xFFFFF
	_casting_mode = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	await _settle(4)


func _pitch_rover_eye(degrees: float) -> void:
	var rover := _ground.find_child("Rover", true, false) as Rover
	rover._look_yaw = 0.0
	rover.get_node("CamPivot/SpringArm3D").rotation.x = deg_to_rad(degrees)
	rover._aim_eye()


func _install_world(elevation_deg: float, suit: bool, rover_eye := false) -> void:
	# The probe's own sun, ground and box give way to the world's.
	for node in [_sun, _ground, _caster]:
		remove_child(node)
		node.free()
	_caster = null
	_casters.clear()
	var world := WORLD.instantiate()
	_ground = world
	add_child(world)
	for i in 90:
		await get_tree().physics_frame
	_sun = world.find_child("Sun", true, false) as DirectionalLight3D
	World.sun_elevation_deg = elevation_deg
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	var rover := world.find_child("Rover", true, false) as Rover
	var astronaut := world.find_child("Astronaut", true, false) as Astronaut
	var at := astronaut.global_position
	if rover_eye:
		# The rover's eye is the camera; its hull, on layer 3, is the caster.
		astronaut.get_parent().remove_child(astronaut)
		astronaut.free()
		for node in rover.find_children("*", "GeometryInstance3D", true, false):
			var g := node as GeometryInstance3D
			if (g.layers & 4) != 0:
				_casters.append(g)
		# Frozen, or the eye rides the suspension settling between the two
		# frames and every edge in the picture reads as a change.
		rover.freeze = true
		rover._look_yaw = deg_to_rad(-60.0)
		rover._aim_eye()
		rover.eye().make_current()
		await _settle(10)
		return
	if rover != null:
		rover.get_parent().remove_child(rover)
		rover.free()
	if suit:
		var rig := astronaut.get_node("Body/Rig") as AstronautRig
		rig.set_animating(false)
		(astronaut.get_node("Body/HeadLamp") as Light3D).visible = false
		for node in rig.find_children("*", "GeometryInstance3D", true, false):
			_casters.append(node as GeometryInstance3D)
		# Hand the screen to the probe camera without the rig arguing.
		astronaut.set_menu_open(true)
	else:
		astronaut.get_parent().remove_child(astronaut)
		astronaut.free()
		_caster = MeshInstance3D.new()
		_caster.name = "Box"
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 2.0, 2.0)
		_caster.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.5, 0.3)
		_caster.material_override = mat
		add_child(_caster)
		_caster.global_position = at + Vector3(0.0, 1.0, 0.0)
		_casters = [_caster]
	# From the side, so a shadow running away from the sun crosses the frame.
	_camera.global_position = at + Vector3(8.0, 3.0, 0.0)
	_camera.look_at(at + Vector3(0.0, 0.8, 0.0), Vector3.UP)
	_camera.make_current()
	await _settle(10)


# --- Measuring ----------------------------------------------------------

func _measure(name: String) -> void:
	_set_casting(true)
	var casting := await _shot("%s_casting" % name)
	_set_casting(false)
	var not_casting := await _shot("%s_no_shadow" % name)
	_diff_image(casting, not_casting).save_png("%s/%s_diff.png" % [OUT_DIR, name])
	var moved := _changed_fraction(casting, not_casting) * 100.0
	_lines.append("  %-28s %5.2f%% of pixels   luma %.3f -> %.3f   bias %.2f / %.2f   light along %s"
		% [name, moved, _luma(casting), _luma(not_casting), _sun.shadow_bias,
			_sun.shadow_normal_bias, (-_sun.global_basis.z).snapped(Vector3.ONE * 0.01)])


## "Not casting" for the shadows-only variants is *hidden outright*: with
## `cast_shadow` merely OFF the mesh would render, and the difference would be
## the hull appearing in the driver's face rather than its shadow going.
func _set_casting(on: bool) -> void:
	var shadows_only := _casting_mode == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for caster in _casters:
		if shadows_only:
			caster.visible = on
			caster.cast_shadow = _casting_mode
		else:
			caster.cast_shadow = (
				_casting_mode if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(shot_name: String) -> Image:
	for i in 6:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, shot_name])
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
