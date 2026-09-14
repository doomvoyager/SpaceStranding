extends Node3D
## What is the pale sheet above the far crater wall?
##
## Mac raised every camera's far plane to 30 km and saw, looking toward the
## sun across Shackleton, a bright flat surface hanging above the dark far
## wall. A slope that faces the camera faces away from a sun in front of it
## and has to be dark, so a lit sheet up there is geometry that should not be
## facing the eye at all. Four frames of the same view take the suspects out
## one at a time:
##
##   01  as the game draws it
##   02  Lambert in place of the lunar term
##   03  every tile's skirt hidden
##   04  the ground unshaded flat grey - the silhouette alone
##   05  the detail normal map off
##
## from two eyes: the rim, 150 m over the pole, and the plain behind the
## rover at the spawn. The first run also reported the deepest skirts
## resident: 5.6 m, on a root tile - not the sheet.
##
## Must run WINDOWED - --headless is the dummy renderer and writes no image.
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/probe_far_sheet.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://far_sheet"

var _terrain: StreamedTerrain
var _cam: Camera3D



func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = world.find_child("Terrain", true, false) as StreamedTerrain
	var hud := world.find_child("HUD", true, false)
	if hud != null:
		hud.set("visible", false)

	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.far = 30000.0
	add_child(_cam)
	_cam.current = true
	# Two eyes, both looking across Shackleton toward the sun's side of the
	# sky: the light travels toward -Z, so the sun stands at +Z. The rim is
	# ~600 m from the spawn toward +x, +z; from 150 m over the pole the far
	# wall is in view. Three materials each: the game's, Lambert in place of
	# the lunar term, and unshaded flat grey.
	var pole := Vector3(-374.4, 0.0, 966.9)
	var eyes := {
		"rim": [pole + Vector3(0.0, 150.0, 0.0), pole + Vector3(-1500.0, -300.0, 5000.0)],
		"plain": [Vector3(0.0, 3.0, -9.0), Vector3(-1500.0, 200.0, 5000.0)],
	}
	var regolith := _terrain.surface_material as ShaderMaterial
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = Color(0.5, 0.5, 0.5)
	for key: String in eyes:
		var eye: Vector3 = eyes[key][0]
		if key == "plain":
			eye.y += _terrain.world_height_at(eye.x, eye.z)
		_cam.position = eye
		_cam.look_at(eyes[key][1], Vector3.UP)
		_terrain.refresh()
		for i in 900:
			if _terrain.is_settled():
				break
			await get_tree().process_frame
		print("%s: eye %s, %d tiles" % [key, eye, _terrain.resident_keys().size()])
		_terrain.surface_material = regolith
		await _shot("%s_01_as_drawn" % key)
		regolith.set_shader_parameter("lunar_brdf", false)
		await _shot("%s_02_lambert" % key)
		regolith.set_shader_parameter("lunar_brdf", true)
		_show_skirts(false)
		await _shot("%s_03_no_skirts" % key)
		_show_skirts(true)
		_terrain.surface_material = flat
		await _shot("%s_04_flat" % key)
		_terrain.surface_material = regolith
		regolith.set_shader_parameter("use_detail", false)
		await _shot("%s_05_no_detail" % key)
		regolith.set_shader_parameter("use_detail", true)
	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _skirts() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var tiles := _terrain.get_node_or_null("Tiles")
	if tiles == null:
		return out
	for tile in tiles.get_children():
		var skirt := tile.get_node_or_null("Skirt") as MeshInstance3D
		if skirt != null:
			out.append(skirt)
	return out


func _show_skirts(on: bool, material: Material = null) -> void:
	for skirt in _skirts():
		skirt.visible = on
		if material != null:
			skirt.material_override = material


func _report_skirts() -> void:
	var rows: Array = []
	var tiles := _terrain.get_node_or_null("Tiles")
	for tile in tiles.get_children():
		var skirt := tile.get_node_or_null("Skirt") as MeshInstance3D
		if skirt == null:
			continue
		var verts: PackedVector3Array = (skirt.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var n := verts.size() / 8
		var depth := verts[0].y - verts[4 * n].y
		rows.append([depth, String(tile.name), verts[0]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("deepest skirts (depth m, tile, a rim vertex in terrain-local metres):")
	for i in mini(8, rows.size()):
		print("  %8.1f  %-10s %s" % [rows[i][0], rows[i][1], rows[i][2]])


func _shot(name: String) -> void:
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  ", name)


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
