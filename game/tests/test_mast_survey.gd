extends Node3D
## Regression test for the mast site survey — `Lattice.survey_at()` and the
## HUD readout that hangs off it. See [[The-Lattice]] and [[Placement]].
##
## The survey is the half of the haulable mast that makes siting a *decision*.
## If it is wrong, the player is told a spot works and finds out it does not
## after carrying a mast there, which is the worst possible place to learn it.
##
## What this exists to catch:
##
##   1. **The mast height must not be a lie.** `survey_mast_height` is a second
##      copy of relay.tscn's Antenna height, kept because a survey has to answer
##      for a mast that is not a node yet. If the scene's antenna moves and the
##      constant does not, every survey answers for a mast of the wrong height —
##      silently, and in the direction that matters most, since height is most
##      of what a relay is for.
##
##   2. **"No link" and "cannot say" must be different answers.** An unbuilt
##      terrain answers zero for every height, and zero is a plausible height.
##      A survey that reported "no link" there would be indistinguishable from
##      a real answer about real ground.
##
##   3. **Line of sight has to survive into the survey.** A site in range but
##      with the ground in the way must not count. This is the same claim
##      test_lattice makes about the graph, re-made about the prospective
##      version — they are separate code paths and only one of them was tested.
##
##   4. **The margin must be the weakest reason, not the best one.** Ranking on
##      clearance alone picks sites sitting at 44.0 m of a 45 m reach. The whole
##      point of the score is that it is a minimum.
##
##   5. **Ground out of everything's reach must report honestly.** If distance
##      stopped mattering the readout would say yes everywhere.
##
## Runs as a scene rather than via --script so autoloads exist, and builds its
## own terrain so the geometry is known rather than inherited from the world.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_mast_survey.tscn

## Frames to wait for the terrain before giving up. A budget, not a schedule —
## the test drives off `is_built()`, because _process and _physics_process do
## not interleave anything like realtime under --headless.
const BUILD_BUDGET := 240

var _terrain: ProceduralTerrain
var _frames := 0
var _failures: Array[String] = []
var _done := false


func _ready() -> void:
	# 2. Asked before there is any terrain at all, the survey must say it
	#    cannot say — not "no link". Checked first because adding the terrain
	#    below is what makes it answerable, and there is no way back.
	var blind := Lattice.survey_at(0.0, 0.0)
	_expect(blind.unknown, "a survey with no terrain claimed to know something")
	_expect(not blind.linked, "a survey with no terrain reported a link")

	_check_mast_height_matches_the_scene()

	_terrain = ProceduralTerrain.new()
	add_child(_terrain)


## 1. The drift guard. `survey_mast_height` exists because instancing the relay
## a few times a second to measure it would be absurd; this is the price of
## that, paid once, here.
func _check_mast_height_matches_the_scene() -> void:
	var scene := load("res://scenes/world/relay.tscn") as PackedScene
	var relay := scene.instantiate() as Node3D
	var antenna := relay.get_node_or_null("Antenna") as Node3D
	if antenna == null:
		_expect(false, "relay.tscn has no Antenna node to measure")
	else:
		var authored := antenna.position.y
		_expect(is_equal_approx(authored, Lattice.survey_mast_height),
			"relay.tscn's antenna stands at %.2f m but Lattice.survey_mast_height is %.2f"
				% [authored, Lattice.survey_mast_height])
	# A node built with .new()/instantiate() and never parented is never freed,
	# and the leak reports at exit as engine internals rather than as this test.
	relay.free()


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if not _terrain.is_built():
		if _frames > BUILD_BUDGET:
			_expect(false, "terrain never built in %d frames" % BUILD_BUDGET)
			_finish()
		return
	_done = true
	_run()


func _run() -> void:
	var ground := _terrain.world_height_at(0.0, 0.0)

	# A clear site, one mast-height off the ground 25 m away: comfortably inside
	# the 45 m reach, and high enough at both ends that the gentle procedural
	# terrain between them is not in the way.
	var clear_at := Vector3(25.0, _terrain.world_height_at(25.0, 0.0)
		+ Lattice.survey_mast_height, 0.0)
	_spawn_facility("clear", "Clear", clear_at)

	# A nearer site, buried. In range from the surveyor by some margin, and
	# therefore the one a distance check would pick.
	var buried_at := Vector3(12.0, _terrain.world_height_at(12.0, 12.0) - 6.0, 12.0)
	_spawn_facility("buried", "Buried", buried_at)
	Lattice.rebuild()

	var here := Lattice.survey_at(0.0, 0.0)
	print("survey at origin: %s" % here.summary())
	print("  mast %s  range_spare %.2f  clearance %.2f  margin %.2f"
		% [here.mast_point, here.range_spare, here.clearance, here.margin])

	_expect(not here.unknown, "a survey over built terrain still reported unknown")
	_expect(here.linked, "the clear site 25 m away did not register as a link")

	# 3. The buried site is nearer. If it wins, line of sight is not reaching
	#    the survey and the readout is a radius check wearing a raycast's coat.
	_expect(here.best_id != "buried",
		"the survey linked to a site 6 m underground")
	_expect(here.best_id == "clear",
		"the survey linked to '%s', not the clear site" % here.best_id)

	# 4. The score is a minimum of the two reasons, never the kinder one.
	_expect(is_equal_approx(here.margin, minf(here.range_spare, here.clearance)),
		"margin %.2f is not the weakest of range_spare %.2f and clearance %.2f"
			% [here.margin, here.range_spare, here.clearance])

	# The mast is stood on the ground, not at the player's feet.
	_expect(is_equal_approx(here.mast_point.y, ground + Lattice.survey_mast_height),
		"the surveyed mast stands at %.2f, not %.2f above ground"
			% [here.mast_point.y - ground, Lattice.survey_mast_height])

	# 5. Far enough out that nothing is in reach.
	var away := Lattice.survey_at(400.0, 400.0)
	print("survey 400 m out: %s" % away.summary())
	_expect(not away.unknown, "a survey over built terrain reported unknown")
	_expect(not away.linked,
		"ground 400 m from every site reported a link to '%s'" % away.best_id)

	_finish()


func _spawn_facility(id: String, display: String, at: Vector3) -> Facility:
	var facility := load("res://scenes/world/facility.tscn").instantiate() as Facility
	facility.facility_id = id
	facility.display_name = display
	facility.position = at
	add_child(facility)
	return facility


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the survey stands a real mast on real ground and needs to see out.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
