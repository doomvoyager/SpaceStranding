extends Node3D
## What does the post pass see where the sun is?
##
## A lens flare has to know two things about the sun every frame: where it is
## on screen, and whether anything is in front of it. The first is
## `Camera3D.unproject_position`. The second could be physics rays - but the
## streamed ground only carries collision within `collision_radius`, a crater
## rim 5 km off has none, and the rover's wheels are raycasts with no shape at
## all. The alternative is to look at the picture: the sky draws the disc far
## past white, and anything in front of the sun is by construction seen from
## its unlit side. If the disc reads as pure white in the image the post pass
## samples, and whatever covers it does not, the picture *is* the occlusion
## test - exact with what is drawn, at any distance, for free.
##
## So, for a clear sun, a sun behind the rover and a sun behind terrain:
##
##   * where the projected sun lands, and whether the drawn disc is there;
##   * the min channel of the pixels round it, 0-255, with the post hidden -
##     which is the image the film pass reads;
##   * whether a canvas_item `vertex()` can sample `hint_screen_texture`, and
##     whether it reads what a `fragment()` tap reads. If it can, the
##     visibility test runs four times a frame instead of once per pixel.
##
## Frames go to user://sun_disc, with and without the post stack.
##
## Must run WINDOWED - --headless draws nothing and `frame_post_draw` never
## fires:
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##       res://tests/probe_sun_disc.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const OUT_DIR := "user://sun_disc"
## Half-width of the printed pixel block round the projected sun.
const BLOCK := 6
const TAP_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 probe_uv = vec2(0.5);
uniform bool in_vertex = true;
varying flat float seen;
void vertex() {
	seen = textureLod(screen_tex, probe_uv, 0.0).r;
}
void fragment() {
	float v = in_vertex ? seen : textureLod(screen_tex, probe_uv, 0.0).r;
	COLOR = vec4(vec3(v), 1.0);
}
"""

var _terrain: TerrainSource
var _cam: Camera3D
var _post: CanvasLayer
var _taps: Array[ColorRect] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("probe_sun_disc must run windowed")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var world := WORLD.instantiate()
	add_child(world)
	for i in 60:
		await get_tree().physics_frame
	_terrain = world.find_child("Terrain", true, false) as TerrainSource
	var hud := world.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	_post = world.find_child("PostprocessingEffects", true, false) as CanvasLayer
	for c in _find_cameras(world):
		c.current = false
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 30000.0
	add_child(_cam)
	_cam.current = true
	_make_taps()

	var sun_dir := World.sun_direction()
	var toward := -sun_dir
	var flat := Vector3(toward.x, 0.0, toward.z).normalized()
	print("vp %s  sun toward %s" % [get_viewport().get_visible_rect().size,
		toward.snapped(Vector3.ONE * 0.001)])

	# 1. Clear, dead centre.
	var eye := _ground(Vector3(0.0, 0.0, -4.0), 1.7)
	await _shot("01_clear_centre", eye, eye + toward * 100.0)
	# 2. Clear, the sun up and to the left of centre - is the projection
	# right off-axis, and which way is +y?
	var off := toward.rotated(Vector3.UP, deg_to_rad(-18.0))
	off = off.rotated(off.cross(Vector3.UP).normalized(), deg_to_rad(-10.0))
	await _shot("02_clear_off_axis", eye, eye + off * 100.0)
	# 3. Behind the rover: back along the light from its origin, so the ray
	# to the sun passes through the chassis.
	var rover := world.find_child("Rover", true, false) as Node3D
	var behind := rover.global_position + sun_dir * 6.0
	await _shot("03_behind_rover", behind, behind + toward * 100.0)
	# 4. Behind terrain, and 5. the disc on a rim - found by marching the
	# heightfield toward the sun from a grid of eyes.
	var picks := _find_horizons(flat)
	if picks.has("hidden"):
		var p: Vector3 = picks["hidden"]
		await _shot("04_behind_terrain", p, p + toward * 100.0)
	if picks.has("grazing"):
		var p: Vector3 = picks["grazing"]
		await _shot("05_grazing_rim", p, p + toward * 100.0)

	print("captured to: ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(name: String, eye: Vector3, look: Vector3) -> void:
	_cam.global_position = eye
	_cam.look_at(look, Vector3.UP)
	var sun_point := eye - World.sun_direction() * 1000.0
	var behind := _cam.is_position_behind(sun_point)
	var px := _cam.unproject_position(sun_point)
	var size := get_viewport().get_visible_rect().size
	var uv := px / size
	for tap in _taps:
		(tap.material as ShaderMaterial).set_shader_parameter("probe_uv", uv)
	# Let the streamed tiles catch up with a moved eye before judging.
	for i in 90:
		await get_tree().process_frame
	for pass_name: String in ["raw", "post"]:
		_post.visible = pass_name == "post"
		for i in 6:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [OUT_DIR, name, pass_name])
		if pass_name != "raw":
			continue
		print("")
		print("%s  eye %s  sun px %s  uv %s  behind %s" % [name,
			eye.snapped(Vector3.ONE * 0.1), px.snapped(Vector2.ONE * 0.1),
			uv.snapped(Vector2.ONE * 0.0001), behind])
		_print_block(img, px)
		_print_brightest(img, px)
		print("  tap read in vertex %.3f  in fragment %.3f  (raw min-channel at centre %.3f)" % [
			img.get_pixel(4, int(size.y) - 12).r,
			img.get_pixel(24 + 4, int(size.y) - 12).r,
			_min_channel(img, px)])


## Min channel, 0-255, in a (2 BLOCK + 1)^2 block round `px`.
func _print_block(img: Image, px: Vector2) -> void:
	var cx := int(round(px.x))
	var cy := int(round(px.y))
	for y in range(cy - BLOCK, cy + BLOCK + 1):
		var row := "   "
		for x in range(cx - BLOCK, cx + BLOCK + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				row += "   ."
				continue
			row += "%4d" % int(round(_min_channel(img, Vector2(x, y)) * 255.0))
		print(row)


## Where the near-white pixels are within 40 px, so a misaligned projection
## shows up as an offset rather than as "no disc".
func _print_brightest(img: Image, px: Vector2) -> void:
	var sum := Vector2.ZERO
	var n := 0
	for y in range(int(px.y) - 40, int(px.y) + 41):
		for x in range(int(px.x) - 40, int(px.x) + 41):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if _min_channel(img, Vector2(x, y)) >= 0.98:
				sum += Vector2(x, y)
				n += 1
	if n == 0:
		print("  no pixel >= 0.98 within 40 px")
	else:
		print("  %d px >= 0.98 within 40 px, centroid %s (offset %s)" % [n,
			(sum / n).snapped(Vector2.ONE * 0.1),
			(sum / n - px).snapped(Vector2.ONE * 0.1)])


func _min_channel(img: Image, at: Vector2) -> float:
	var x := clampi(int(round(at.x)), 0, img.get_width() - 1)
	var y := clampi(int(round(at.y)), 0, img.get_height() - 1)
	var c := img.get_pixel(x, y)
	return minf(c.r, minf(c.g, c.b))


## Two 8x8 swatches in the bottom-left corner, on a layer above the post:
## the first samples the screen in vertex(), the second in fragment().
func _make_taps() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var shader := Shader.new()
	shader.code = TAP_SHADER
	for i in 2:
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.position = Vector2(float(i) * 24.0, get_viewport().get_visible_rect().size.y - 16.0)
		rect.size = Vector2(8.0, 8.0)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("in_vertex", i == 0)
		rect.material = mat
		layer.add_child(rect)
		_taps.append(rect)


## A grid of eyes round the spawn, each marched 4 km toward the sun. The
## highest ground angle along the way is that eye's horizon toward the sun:
## above the sun's elevation it is in shadow, within the disc's half-width of
## it the disc sits on the rim.
func _find_horizons(flat: Vector3) -> Dictionary:
	var elev := World.sun_elevation_deg
	var out := {}
	var best_hidden := INF
	var best_graze := INF
	for gx in range(-10, 11):
		for gz in range(-10, 11):
			var base := Vector3(gx * 60.0, 0.0, gz * 60.0)
			var eye := _ground(base, 1.7)
			var horizon := -90.0
			for i in range(1, 161):
				var d := float(i) * 25.0
				var p := eye + flat * d
				var h := _terrain.world_height_at(p.x, p.z)
				horizon = maxf(horizon, rad_to_deg(atan2(h - eye.y, d)))
			var r := base.length()
			if horizon > elev + 3.0 and r < best_hidden:
				best_hidden = r
				out["hidden"] = eye
			if absf(horizon - elev) < 0.15 and r < best_graze:
				best_graze = r
				out["grazing"] = eye
	print("horizon search: hidden %s  grazing %s" % [out.get("hidden"), out.get("grazing")])
	return out


func _ground(at: Vector3, clearance: float) -> Vector3:
	return Vector3(at.x, _terrain.world_height_at(at.x, at.z) + clearance, at.z)


func _find_cameras(from: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if from is Camera3D:
		out.append(from)
	for child in from.get_children():
		out.append_array(_find_cameras(child))
	return out
