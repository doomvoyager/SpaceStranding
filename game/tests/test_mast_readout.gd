extends Node3D
## Regression test for the *wiring* of the mast survey readout, in the real
## world scene. `test_mast_survey` covers the arithmetic; this covers whether
## anybody ever sees it.
##
## This is the failure this project keeps meeting: a system that is correct,
## registered, and exactly where it was told to be, and which reaches nobody.
## An Area3D that detected crates and let them fall through it. A whole tunable
## system absent from the F1 panel because `_discover()` is hand-written. Every
## headless assertion passed in both cases. So the assertions here are
## deliberately about visibility rather than about numbers:
##
##   1. **Carrying a mast puts the readout on screen.** If `deploys_as` does not
##      reach the HUD, the survey is a function nothing calls.
##   2. **Carrying ordinary freight does not.** A readout that is always up is
##      not a readout, it is furniture — and it would mean the deployable test
##      is passing on something other than deployability.
##   3. **It says something.** Visible and blank is the same as absent.
##
## Marks the crate deployable at runtime rather than depending on the world
## scene carrying the property, so this test still passes on a scene Mac has
## since edited.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_mast_readout.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
## The HUD refreshes the survey on a timer and draws in _process, which does not
## interleave with _physics_process under --headless — so this is a budget to
## fail against, not a schedule to assert on.
const BUDGET := 600
const SETTLE := 60

var _astronaut: Astronaut
var _hud: HUD
var _mast: Crate
var _plain: Crate
var _frames := 0
var _stage := 0
var _failures: Array[String] = []


func _ready() -> void:
	add_child(WORLD.instantiate())


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE:
		return
	if _astronaut == null and not _find_the_pieces():
		if _frames > BUDGET:
			_expect(false, "never found the astronaut, HUD and cargo in the world")
			_finish()
		return
	match _stage:
		0: _stage_empty_handed()
		1: _stage_carrying_plain_freight()
		2: _stage_carrying_the_mast()
		3: _finish()


func _find_the_pieces() -> bool:
	_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_hud = get_tree().get_first_node_in_group("hud") as HUD
	for node in get_tree().get_nodes_in_group("cargo"):
		var crate := node as Crate
		if crate == null:
			continue
		if crate.name == "Mast105":
			_mast = crate
		elif _plain == null:
			_plain = crate
	if _astronaut == null or _hud == null or _mast == null or _plain == null:
		return false
	# The world scene does not have to carry `deploys_as` for this test to mean
	# something — what is being tested is that the property reaches the HUD.
	_mast.deploys_as = load("res://scenes/world/relay.tscn")
	_expect(_mast.is_deployable(), "a crate with deploys_as set is not deployable")
	_expect(not _plain.is_deployable(), "ordinary freight reported deployable")
	return true


func _stage_empty_handed() -> void:
	_expect(_hud.survey_readout() == "",
		"the survey readout was up with nothing on the astronaut's back: '%s'"
			% _hud.survey_readout())
	_stage = 1


## 2. Ordinary cargo must not summon it.
func _stage_carrying_plain_freight() -> void:
	_astronaut.back_rack().load_crate(_plain)
	if _frames % 8 != 0:
		return
	_expect(_astronaut.carried_deployable() == null,
		"a plain crate on the back reported as a carried deployable")
	_expect(_hud.survey_readout() == "",
		"carrying ordinary freight put the survey readout on screen: '%s'"
			% _hud.survey_readout())
	_stage = 2


## 1 and 3. The mast must summon it, and it must say something.
func _stage_carrying_the_mast() -> void:
	if _astronaut.carried_deployable() == null:
		_astronaut.back_rack().load_crate(_mast)
		return
	var line := _hud.survey_readout()
	if line == "" and _frames < BUDGET:
		return
	print("readout while carrying the mast: '%s'" % line)
	_expect(line != "",
		"carrying the mast left the survey readout off screen")
	_expect(line != "no survey data",
		"the readout could not survey the world scene's own ground")
	_stage = 3


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the mast puts a survey on screen and ordinary freight does not.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
