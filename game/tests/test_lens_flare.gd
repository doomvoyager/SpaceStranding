extends Node3D
## The lens, headless: where the Lens script says the sun is, and the post
## layer's place under the interface.
##
## `unproject_position` works headless (see CLAUDE.md), so the sun's position,
## its disc size and the behind-the-camera cut are all checkable here, against
## a projection worked out from the camera's own basis and field of view. What
## the shader does with them - whether the disc is found, the flare and the
## dust - is `flare_capture`, windowed.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_lens_flare.tscn

const POST := preload("res://scenes/postprocessing_effects.tscn")
const UI_SCENES := [
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/order_panel.tscn",
	"res://scenes/ui/map_panel.tscn",
]

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _sun()
	_layers()
	print("%d checks, %d failed" % [_checks, _fails])
	if _fails == 0:
		print("PASS")
		get_tree().quit(0)
		return
	print("FAIL")
	get_tree().quit(1)


func _sun() -> void:
	# A sun twice the real size, so finding the light is visible in the radius.
	var light := DirectionalLight3D.new()
	light.light_angular_distance = 1.06
	add_child(light)
	var lens := POST.instantiate() as Lens
	add_child(lens)
	_expect("the post layer carries the Lens script", lens != null)
	if lens == null:
		return
	_expect("it found the scene's sun", lens.sun_light() == light)
	_expect_near("and reads its size: %.5f rad" % lens.angular_radius(),
		lens.angular_radius(), deg_to_rad(0.53), 1e-6)
	_expect("it runs after the camera rigs", lens.process_priority > 0)

	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.make_current()
	var toward := -World.sun_direction()

	# Dead on.
	camera.look_at_from_position(Vector3(3.0, 2.0, -7.0), Vector3(3.0, 2.0, -7.0) + toward, Vector3.UP)
	lens.refresh()
	_expect("looking at the sun, it is ahead", lens.sun_ahead == 1.0)
	_expect_v2("and in the middle", lens.sun_uv, Vector2(0.5, 0.5), 1e-3)
	var size := get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	var want_r := tan(lens.angular_radius()) / tan_half * 0.5
	_expect_near("the disc's radius is %.2f px" % (lens.sun_radius.y * size.y),
		lens.sun_radius.y, want_r, want_r * 0.02)
	_expect_near("the same radius in x, in x's units",
		lens.sun_radius.x * size.x, lens.sun_radius.y * size.y, 0.05)

	# Off to one side and below: checked against the projection worked out by
	# hand from where the sun sits in the camera's own frame.
	for turn: Vector2 in [Vector2(20.0, 0.0), Vector2(-25.0, -8.0), Vector2(10.0, 12.0)]:
		var look := toward.rotated(Vector3.UP, deg_to_rad(turn.x))
		var right := look.cross(Vector3.UP).normalized()
		look = look.rotated(right, deg_to_rad(turn.y))
		camera.look_at_from_position(Vector3.ZERO, look, Vector3.UP)
		lens.refresh()
		var local := camera.global_basis.inverse() * toward
		var aspect := size.x / size.y
		var want := Vector2(
			0.5 + (local.x / -local.z) / (tan_half * aspect) * 0.5,
			0.5 - (local.y / -local.z) / tan_half * 0.5)
		_expect_v2("turned %s, the sun is where the projection says" % turn,
			lens.sun_uv, want, 1e-3)
		_expect("and still ahead", lens.sun_ahead == 1.0)

	# Behind.
	camera.look_at_from_position(Vector3.ZERO, -toward, Vector3.UP)
	lens.refresh()
	_expect("with the sun behind, it is not ahead", lens.sun_ahead == 0.0)

	# Dust follows the camera on screen.
	var dusty := LensDust.new()
	camera.add_child(dusty)
	dusty.coverage = 0.4
	lens.refresh()
	_expect_near("the lens reports the current camera's dust", lens.dust, 0.4, 1e-6)
	var other := Camera3D.new()
	add_child(other)
	other.make_current()
	lens.refresh()
	_expect("a camera with no LensDust is clean", lens.dust == 0.0)
	_expect("and no camera at all is safe", _no_camera_safe(lens, other))

	lens.queue_free()
	camera.queue_free()
	other.queue_free()
	light.queue_free()
	await get_tree().process_frame


func _no_camera_safe(lens: Lens, current: Camera3D) -> bool:
	current.clear_current(false)
	lens.refresh()
	return lens.sun_ahead == 0.0 and lens.dust == 0.0


## The post layer has to sit under every interface layer, or dust lands on the
## HUD and a white label over a hidden sun reads as the sun.
func _layers() -> void:
	var post := POST.instantiate() as CanvasLayer
	for path: String in UI_SCENES:
		var ui := (load(path) as PackedScene).instantiate() as CanvasLayer
		_expect("post (%d) draws under %s (%d)" % [post.layer, path.get_file(), ui.layer],
			post.layer < ui.layer)
		ui.free()
	_expect("and under the F1 panel", post.layer < Debug.layer)
	post.free()


func _expect(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL: %s" % label)


func _expect_near(label: String, got: float, want: float, tol: float) -> void:
	_checks += 1
	if absf(got - want) > tol:
		_fails += 1
		print("  FAIL: %s - got %s, wanted %s" % [label, got, want])


func _expect_v2(label: String, got: Vector2, want: Vector2, tol: float) -> void:
	_checks += 1
	if got.distance_to(want) > tol:
		_fails += 1
		print("  FAIL: %s - got %s, wanted %s" % [label, got, want])
