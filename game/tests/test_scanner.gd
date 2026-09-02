extends Node3D
## Regression test for the scan pulse.
##
## The *look* cannot be tested here — a dot grid is a picture, and
## tests/scan_capture.tscn exists for that. What can be tested is everything
## around it, and these are the parts that would break quietly:
##
##   1. **The wave has to travel.** If the radius went straight to full, every
##      tag would appear at once and the pulse would be a light switch. Nothing
##      would error; it would just stop being a scan.
##
##   2. **Reach has to mean something.** Anything past it must never be tagged,
##      or the scanner is an all-seeing eye with a nice animation.
##
##   3. **The tag budget has to hold.** Nineteen labels in one pile is what the
##      first version drew, and it was unreadable. A cap that silently stopped
##      applying would look fine on an empty plain and fail exactly where the
##      scan matters most.
##
##   4. **A pulse has to end**, releasing its tags. A scanner that leaks a
##      Label3D per object per ping is a slow memory leak behind a key the
##      player will press constantly.
##
##   5. **The distance on a tag has to count down as you approach.** It is
##      measured from the viewer every frame, while the reveal stays anchored to
##      the ping - two positions that were the same number for as long as the
##      player stood still, which is exactly how long it takes to not notice.
##
## **Driven by the scanner's own state, not by frame counts.** The pulse
## advances on `_process` and the checks run on `_physics_process`, and headless
## does not interleave those two clocks anything like realtime — the first
## version asked for progress two physics frames after the ping and got exactly
## zero, and the second waited 150 frames for a wave that had already finished.
## Each stage now waits for the condition it is about to assert on, with a frame
## budget as the failure case.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_scanner.tscn

var _scanner: Scanner
var _near: Crate
var _far: Crate
var _frames := 0
var _stage := 0
var _failures: Array[String] = []
var _radius_early := 0.0
var _distance_before := ""


func _ready() -> void:
	# The scanner pings from the active camera, so there has to be one.
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.0, 0.0)
	add_child(camera)
	camera.current = true

	_scanner = Scanner.new()
	_scanner.reach = 60.0
	_scanner.wave_speed = 30.0
	# Generous, so there is a wide window in which the pulse is arrived-but-not-
	# yet-gone for the swept checks to run in.
	_scanner.hold = 2.0
	_scanner.fade = 2.0
	_scanner.max_tags = 3
	# Off, so the budget is what is under test rather than the screen-space
	# declutter, which would otherwise refuse tags this stage is counting.
	#
	# It was switched off originally on the belief that a projection means
	# nothing under --headless. That was a guess, and it was wrong:
	# `unproject_position()` is arithmetic on the camera and measures correctly
	# with the dummy renderer - see `probe_headless_unproject.gd`, and
	# `test_site_sign.gd`, which does test declutter headless.
	_scanner.tag_separation_px = 0.0
	add_child(_scanner)

	_near = _crate_at(Vector3(0.0, 0.0, -5.0), "Near crate")
	_far = _crate_at(Vector3(0.0, 0.0, -200.0), "Far crate")
	# Four more close in, so the cap of three has something to refuse.
	for i in 4:
		_crate_at(Vector3(2.0 + i, 0.0, -6.0), "Filler %d" % i)


func _crate_at(at: Vector3, label: String) -> Crate:
	var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
	crate.cargo_name = label
	crate.freeze = true
	add_child(crate)
	crate.global_position = at
	return crate


## Frames to wait for any one stage's condition before giving up on it.
const STAGE_BUDGET := 2000


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames > STAGE_BUDGET:
		_expect(false, "stage %d never met its condition in %d frames"
			% [_stage, STAGE_BUDGET])
		_finish()
		return

	match _stage:
		0:
			_check_idle()
			_start()
			_advance()
		1:
			# Wait for the wave to have left but not arrived.
			if _scanner.radius() <= 0.0:
				return
			_check_wave_is_travelling()
			_check_cooldown()
			_advance()
		2:
			if _scanner.radius() < _scanner.reach:
				return
			_check_swept()
			_advance()
		3:
			_move_the_viewer()
			_advance()
		4:
			# A whole physics frame later, so _process has redrawn the labels.
			_check_distance_is_live()
			_advance()
		5:
			if _scanner.is_running():
				return
			_check_finished()
			_advance()
		6:
			_finish()


func _advance() -> void:
	_stage += 1
	_frames = 0


func _check_idle() -> void:
	_expect(not _scanner.is_running(), "the scanner is running before anything pinged it")
	_expect(_scanner.radius() < 0.0,
		"idle radius is %.1f, not negative" % _scanner.radius())
	_expect(_scanner.tag_count() == 0, "there are tags before the first ping")


func _start() -> void:
	_expect(_scanner.ping(), "the first ping was refused")
	_expect(_scanner.is_running(), "the scanner is not running after a ping")


## A pulse that arrives everywhere at once is a light switch, not a scan.
func _check_wave_is_travelling() -> void:
	_radius_early = _scanner.radius()
	_expect(_radius_early > 0.0, "the wave has not left the origin")
	_expect(_radius_early < _scanner.reach,
		"the wave was at its full %.0f m the moment it left" % _scanner.reach)
	# Nothing 200 m away can be tagged whatever the wave is doing.
	_expect(not _tagged(_far), "the far crate was tagged before the wave got near it")


func _check_cooldown() -> void:
	_expect(not _scanner.ping(),
		"a second ping went out inside the %.1f s cooldown" % _scanner.cooldown)


func _check_swept() -> void:
	_expect(_scanner.radius() >= _scanner.reach,
		"the wave is still at %.1f m of %.0f" % [_scanner.radius(), _scanner.reach])
	# Asserted here rather than beside the cooldown check, which ran in the same
	# physics frame as the reading it was comparing against and so could only
	# ever see the wave standing still.
	_expect(_scanner.radius() > _radius_early,
		"the wave never moved past %.1f m" % _radius_early)
	_expect(_tagged(_near), "the near crate was never tagged")
	_expect(not _tagged(_far),
		"the crate 200 m away was tagged, and reach is %.0f" % _scanner.reach)
	_expect(_scanner.tag_count() <= _scanner.max_tags,
		"%d tags drawn against a cap of %d" % [_scanner.tag_count(), _scanner.max_tags])
	_expect(_scanner.tag_count() > 0, "nothing was tagged at all")
	print("swept %.0f m, %d tags against a cap of %d"
		% [_scanner.radius(), _scanner.tag_count(), _scanner.max_tags])


## Walk the viewer toward a tagged crate and its label must count down.
##
## The reveal distance and the shown distance were one number until 2026-08-31,
## so a tag read whatever it read at the moment the wave reached it and then sat
## there. Standing still, that is indistinguishable from correct.
func _move_the_viewer() -> void:
	_distance_before = _label_for(_near)
	_expect(_distance_before != "", "the near crate has no tag to read")
	# The test scene has no astronaut and no driven rover, so the viewer falls
	# back to the camera. Move it most of the way to the crate.
	var camera := get_viewport().get_camera_3d()
	camera.global_position = _near.global_position + Vector3(0.0, 2.0, 1.0)


## Split across two stages rather than awaiting inside one. An `await` here
## would hand control back mid-check, the driver would advance the stage, and
## the assertion could land after _finish() had already reported a pass.
func _check_distance_is_live() -> void:
	if _distance_before == "":
		return
	var after := _label_for(_near)
	_expect(after != _distance_before,
		"the tag still reads '%s' with the viewer moved in beside the crate"
		% _distance_before)
	print("tag went from '%s' to '%s' as the viewer moved in"
		% [_distance_before, after])


## A scanner that leaks a label per object per ping is a slow leak behind a key
## the player will press constantly.
func _check_finished() -> void:
	_expect(not _scanner.is_running(),
		"the pulse is still running well past hold + fade")
	_expect(_scanner.tag_count() == 0,
		"%d tags survived the pulse ending" % _scanner.tag_count())
	_expect(_scanner.ping(), "a new ping was refused long after the cooldown")


## The text of `crate`'s tag, or "" if it has none.
func _label_for(crate: Crate) -> String:
	for child in _scanner.get_children():
		for label in child.get_children():
			var text := label as Label3D
			if text != null and text.text.begins_with(crate.cargo_name):
				return text.text
	return ""


func _tagged(crate: Crate) -> bool:
	for child in _scanner.get_children():
		for label in child.get_children():
			var text := label as Label3D
			if text != null and text.text.begins_with(crate.cargo_name):
				return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the pulse travels, respects reach, caps its tags and ends.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
