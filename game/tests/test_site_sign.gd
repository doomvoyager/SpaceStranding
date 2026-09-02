extends Node3D
## Regression test for the facility sign as a scan result. See [[Scanner]].
##
## The sign used to be scenery: always up, always readable, and therefore never
## worth firing a pulse for. It is now the site's scan tag, moved up to the mast
## and given four times the pulse's own reach. Four things about that will break
## quietly rather than loudly:
##
##   1. **A dark sign has to actually be dark.** If it comes up on its own, the
##      whole change is undone and nothing errors — the world just goes back to
##      having every name painted on it.
##   2. **The lazy connect has to happen.** The sign finds the scanner in
##      `_process` because neither can count on the other existing at ready. A
##      sign that never connects is a sign that never lights, and it looks
##      exactly like the intended dark state.
##   3. **`sign_range` has to mean something.** A range that stopped gating
##      would be an all-seeing eye with a nice fade, which is the same failure
##      `Scanner.reach` is tested against.
##   4. **The pulse has to end and take the signs with it.** A sign that leaks
##      past its own fade is scenery again, and only somebody watching the
##      screen for seven seconds would notice.
##   5. **Two names must not write through each other.** Each sign is a node
##      that knows nothing about the others, so the arbitration lives on the
##      scanner and the sign asks for it. If that ask were ever dropped, the
##      signs would still all be correct, all be lit, and be unreadable — which
##      is the same failure the tag pile was.
##
## And one guard against the change being reverted by accident: the scanner must
## not tag facilities itself any more, or a nearby site gets named twice.
##
## **Driven by the signs' own state, not by frame counts.** The reveal advances
## in `_process` and these checks run in `_physics_process`, which headless does
## not interleave anything like realtime. Each stage waits for the condition it
## is about to assert on, with a frame budget as the failure case.
##
## **The crowding stages need a camera pointed at the signs**, so this scene
## makes its own rather than depending on which way the astronaut happens to be
## facing at spawn. `unproject_position()` is arithmetic on the camera and works
## perfectly well under `--headless` — measured by
## `tests/probe_headless_unproject.tscn`, because the nearby fact about
## synthesised mouse events not reaching the GUI makes that worth checking
## rather than assuming.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_site_sign.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const BUDGET := 900
const SETTLE := 60

## The pulse is squeezed hard so the whole envelope fits in a fast test. The
## signs read `hold` and `fade` off the scanner live, so shortening it here is
## also a check that they are reading it rather than keeping their own copy.
const TEST_HOLD := 0.3
const TEST_FADE := 0.3
const TEST_WAVE_SPEED := 400.0

var _scanner: Scanner
var _signs: Array[SiteSign] = []
## The sign that must light: range turned up past anything in the scene.
var _near: SiteSign
## The sign that must not: range turned down to a metre.
var _far: SiteSign
var _frames := 0
var _stage := 0
var _deadline := 0
var _failures: Array[String] = []
var _lit_text := ""
var _camera: Camera3D
## Whether the current stage has run its one-off setup. Reset by `_advance()`,
## so a stage can arrange the world on its first frame and then wait for it.
var _armed := false


func _ready() -> void:
	add_child(WORLD.instantiate())


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE:
		return
	if _scanner == null and not _find_the_pieces():
		if _frames > BUDGET:
			_expect(false, "never found a scanner and two site signs in the world")
			_finish()
		return
	match _stage:
		0: _stage_dark_at_rest()
		1: _stage_the_pulse_lights_it()
		2: _stage_it_says_how_far()
		3: _stage_it_goes_out_again()
		4: _stage_two_names_in_one_place()
		5: _stage_the_separation_is_what_does_it()
		6: _finish()


func _find_the_pieces() -> bool:
	_scanner = get_tree().get_first_node_in_group("scanner") as Scanner
	_signs.clear()
	for node in get_tree().get_nodes_in_group("site_sign"):
		var sign_node := node as SiteSign
		if sign_node != null:
			_signs.append(sign_node)
	if _scanner == null or _signs.size() < 2:
		return false
	_scanner.hold = TEST_HOLD
	_scanner.fade = TEST_FADE
	_scanner.wave_speed = TEST_WAVE_SPEED
	_near = _signs[0]
	_near.sign_range = 5000.0
	_near.fade_in = 0.05
	_far = _signs[1]
	# Every other sign is put out of range, so the crowding stages below are a
	# two-horse race rather than a count that changes with the world scene.
	for i in range(1, _signs.size()):
		_signs[i].sign_range = 1.0
	# The scanner pings once per stage, and the default cooldown is longer than
	# the squeezed pulse.
	_scanner.cooldown = 0.0
	_look_at_the_near_sign()
	print("signs found: %d, near '%s', far '%s'"
		% [_signs.size(), _near.site_name, _far.site_name])
	return true


## A camera of our own, back from the near sign and looking at it.
##
## Without one, every assertion below is at the mercy of which way the astronaut
## was facing when the scene loaded: a sign behind the camera is refused a slot,
## correctly, and the test would fail for a reason that has nothing to do with
## what it is testing.
func _look_at_the_near_sign() -> void:
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 2000.0
	add_child(_camera)
	var at := _near.global_position
	_camera.global_position = at + Vector3(24.0, 6.0, 32.0)
	_camera.look_at(at, Vector3.UP)
	_camera.current = true


## 1, and the guard. Nothing is lit before a pulse, and the scanner has stopped
## tagging sites itself.
func _stage_dark_at_rest() -> void:
	for sign_node in _signs:
		_expect(not sign_node.is_lit(),
			"'%s' was lit with no pulse out" % sign_node.site_name)
		_expect(not sign_node.visible,
			"'%s' was visible with no pulse out" % sign_node.site_name)
	_expect(not _scanner.tag_groups.has("facility"),
		"the scanner still tags 'facility' — a nearby site is named twice, "
		+ "once at the mast and once at ground level")
	_expect(not _scanner.tag_groups.has("relay"),
		"the scanner still tags 'relay' — same double label as 'facility'")

	# 2. The connect is lazy, so give it frames to happen and then say so
	# plainly rather than firing into a scanner nothing is listening to.
	var wired := _signs_connected()
	if wired < _signs.size() and _frames < BUDGET:
		return
	_expect(wired == _signs.size(),
		"only %d of %d signs connected to the scanner's pinged signal"
			% [wired, _signs.size()])
	_expect(_scanner.ping(), "the scanner refused to ping")
	_stage = 1
	_deadline = _frames + BUDGET


## 1 and 3. The near sign comes up; the far one, gated by range, does not.
func _stage_the_pulse_lights_it() -> void:
	if not _near.is_lit():
		if _frames < _deadline:
			return
		_expect(false, "a pulse never lit '%s', whose range is 5 km"
			% _near.site_name)
		_finish()
		return
	_lit_text = _near.text
	print("lit: '%s' at strength %.2f" % [_lit_text, _near.strength()])
	_expect(_far.sign_range < _viewer_distance(_far),
		"the far sign is inside its own 1 m range, so this scene cannot "
		+ "test the range gate")
	_expect(not _far.is_lit(),
		"'%s' lit from %.0f m away with a range of %.0f m"
			% [_far.site_name, _viewer_distance(_far), _far.sign_range])
	_stage = 2


## The number on the sign is the distance to the site from where the player is
## standing, not to the sign eight metres above it and not to where the ping
## went out.
##
## Compared with a metre of slack rather than exactly. The text is written in
## `_process` and read here in `_physics_process`, which headless does not
## interleave anything like realtime — and an astronaut still settling onto a
## slope between the two moves the last digit. A metre is far tighter than any
## of the three wrong answers this is guarding against: the sign's own position
## is eight metres up, and the ping origin is wherever the player *was*.
func _stage_it_says_how_far() -> void:
	var expected := _viewer_distance(_near)
	var prefix := "%s · " % _near.site_name
	print("readout: '%s', site is %.1f m off" % [_lit_text, expected])
	_expect(_lit_text.begins_with(prefix),
		"the sign read '%s', which does not start with the site's name"
			% _lit_text)
	_expect(_lit_text.ends_with(" m"),
		"the sign read '%s', with no distance on it" % _lit_text)
	var shown := _lit_text.trim_prefix(prefix).trim_suffix(" m")
	_expect(shown.is_valid_int(),
		"the sign's distance did not parse as a number: '%s'" % shown)
	if shown.is_valid_int():
		_expect(absf(float(shown.to_int()) - expected) <= 1.0,
			"the sign read %s m when the site is %.1f m off — measured from "
				% [shown, expected]
			+ "the mast or from the ping rather than from the player")
	_stage = 3
	_deadline = _frames + BUDGET


## 5. Two names in the same place: the nearer keeps it, the further goes dark.
##
## The far sign is moved to a metre beyond the near one along the line out from
## the ping, which puts them within a few pixels of each other on screen and
## leaves the priority order unambiguous.
func _stage_two_names_in_one_place() -> void:
	if not _armed:
		_armed = true
		_crowd_them()
		_expect(_scanner.ping(), "the scanner refused the crowding ping")
		return
	# Both, not just the near one. They arrive at different times - the delay is
	# each sign's own distance over the wave speed - and reading the arbitration
	# while only one contender has turned up is how the first version of this
	# stage reported "1 of 1 signs drawing" and called the declutter proven.
	if not (_near.is_revealing() and _far.is_revealing()):
		if _frames < _deadline:
			return
		_expect(false, "the two signs were never inside their pulse at the "
			+ "same time: near %s, far %s"
				% [_near.is_revealing(), _far.is_revealing()])
		_finish()
		return
	var slots := _scanner.sign_slot_count()
	print("crowded at %.0f px separation: %d of %d signs drawing"
		% [_scanner.sign_separation_px, slots.x, slots.y])
	_expect(_near.is_revealing() and _far.is_revealing(),
		"only one of the two signs is inside its pulse, so there is nothing "
		+ "to arbitrate: near %s, far %s"
			% [_near.is_revealing(), _far.is_revealing()])
	_expect(slots.y >= 2,
		"the scanner saw %d signs wanting to draw, not two" % slots.y)
	_expect(_near.is_lit(),
		"'%s' is the nearer name and lost its slot anyway" % _near.site_name)
	_expect(not _far.is_lit(),
		"'%s' drew straight through '%s' — two names in one place"
			% [_far.site_name, _near.site_name])
	_expect(slots.x == 1,
		"%d signs drew in one spot at a %.0f px separation"
			% [slots.x, _scanner.sign_separation_px])
	_advance(5)


## And the separation is what does it, rather than the far sign being broken.
## At zero the arbitration is off and both names come back.
func _stage_the_separation_is_what_does_it() -> void:
	if not _armed:
		_armed = true
		_scanner.sign_separation_px = 0.0
		# A fresh pulse: the one the last stage fired has faded by now, and a
		# stage that waits for a reveal nobody started waits forever.
		_expect(_scanner.ping(), "the scanner refused the second crowding ping")
		return
	if not (_near.is_lit() and _far.is_lit()):
		if _frames < _deadline:
			return
		_expect(false, "with the separation off, only %s drew"
			% ("the near sign" if _near.is_lit() else
				"the far sign" if _far.is_lit() else "neither sign"))
		_finish()
		return
	var slots := _scanner.sign_slot_count()
	print("separation off: %d of %d signs drawing" % [slots.x, slots.y])
	_expect(_far.is_lit(),
		"'%s' stayed dark with the separation switched off, so it was not "
			% _far.site_name
		+ "crowding that hid it")
	_expect(_near.is_lit(), "'%s' went dark with the separation switched off"
		% _near.site_name)
	_expect(slots.x == 2 and slots.y == 2,
		"with the arbitration off the scanner reported %d of %d signs drawing, "
			% [slots.x, slots.y]
		+ "when both are on screen")
	_advance(6)


## Put the far sign a metre past the near one, on the line out from the ping.
## Same pixel, unambiguous order.
func _crowd_them() -> void:
	_far.sign_range = 5000.0
	_far.fade_in = 0.05
	var origin := _scanner.viewer_position()
	var out := (_near.global_position - origin).normalized()
	_far.global_position = _near.global_position + out
	print("crowded '%s' onto '%s', %.2f m apart"
		% [_far.site_name, _near.site_name,
			_far.global_position.distance_to(_near.global_position)])


## 4. The pulse ends and the sign goes with it.
func _stage_it_goes_out_again() -> void:
	if _near.is_lit():
		if _frames < _deadline:
			return
		_expect(false, "'%s' was still lit long after the pulse should have "
			% _near.site_name
			+ "faded (hold %.1f s, fade %.1f s)" % [TEST_HOLD, TEST_FADE])
		_finish()
		return
	_expect(not _near.visible, "the sign went unlit but stayed visible")
	_expect(_near.text == _near.site_name,
		"a dark sign kept its distance readout: '%s'" % _near.text)
	_advance(4)


# --- helpers ------------------------------------------------------------

## How many of the signs have found the scanner and hooked themselves up. The
## connection list is the only public way to ask, and asking is the point.
##
## Compared node by node rather than with `Array.has()`: the list also carries
## `route_marks.gd`, which listens to the same signal and is not a `SiteSign` -
## and a typed array refuses `has()` on anything outside its type, loudly, in
## the middle of an otherwise passing test.
func _signs_connected() -> int:
	var count := 0
	for entry in _scanner.get_signal_connection_list("pinged"):
		var callable: Callable = entry["callable"]
		for sign_node in _signs:
			if callable.get_object() == sign_node:
				count += 1
				break
	return count


## The site a sign belongs to — its parent, which is what the sign measures
## from rather than its own position up the mast.
func _site_of(sign_node: SiteSign) -> Node3D:
	return sign_node.get_parent() as Node3D


## Metres from the player to a sign's site.
func _viewer_distance(sign_node: SiteSign) -> float:
	return _scanner.viewer_position().distance_to(
		_site_of(sign_node).global_position)


func _advance(stage: int) -> void:
	_stage = stage
	_armed = false
	_deadline = _frames + BUDGET


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: site signs are dark until a pulse, gated by range, "
			+ "decluttered against each other, and go out with it.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
