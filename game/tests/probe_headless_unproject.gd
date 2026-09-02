extends Node3D
## Does `Camera3D.unproject_position()` mean anything under --headless?
##
## It decides whether screen-space declutter can be regression-tested at all.
## `test_scanner.gd` switched the tag separation *off* rather than test it,
## noting it "needs a real projection to mean anything" — which was a guess, and
## the signs now need the same rule tested rather than assumed.
##
## The nearby precedent says be careful: a synthesised mouse event reaches
## `_unhandled_input` under headless and still never produces `gui_input`,
## because there is no window to hit-test against. So the question here is
## whether a projection is arithmetic on the camera (fine with a dummy renderer)
## or a query against a real surface (not).
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_headless_unproject.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3.ZERO
	cam.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	await get_tree().process_frame

	var rect := get_viewport().get_visible_rect().size
	print("display server: %s" % DisplayServer.get_name())
	print("viewport size: %s" % rect)

	# Dead ahead should land in the middle of the frame; off to one side should
	# land off to that side; behind should be reported as behind.
	var ahead := cam.unproject_position(Vector3(0.0, 0.0, -40.0))
	var right := cam.unproject_position(Vector3(8.0, 0.0, -40.0))
	var up := cam.unproject_position(Vector3(0.0, 8.0, -40.0))
	var behind := Vector3(0.0, 0.0, 40.0)
	print("ahead: %s" % ahead)
	print("8 m right: %s" % right)
	print("8 m up: %s" % up)
	print("is_position_behind(+Z): %s" % cam.is_position_behind(behind))

	var centred := ahead.distance_to(rect * 0.5) < 1.0
	var rightwards := right.x > ahead.x + 10.0
	var upwards := up.y < ahead.y - 10.0
	print("centred: %s  rightwards: %s  upwards: %s"
		% [centred, rightwards, upwards])
	print("VERDICT: %s" % ("usable" if centred and rightwards and upwards
		else "NOT usable"))
	get_tree().quit()
