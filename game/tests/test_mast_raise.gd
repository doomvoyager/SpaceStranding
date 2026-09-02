extends Node3D
## Regression test for raising and lowering a relay mast — step two of the
## haulable mast. See [[The-Lattice]] and [[Cargo]].
##
## What this exists to catch:
##
##   1. **A raised mast must be load-bearing, not scenery.** Two facilities that
##      cannot see each other, a mast raised between them, and they link. This
##      is the same claim test_lattice makes about an authored relay, re-made
##      about one the player stood up — they are different code paths, and only
##      one of them registers itself from inside a crate.
##
##   2. **It must stand where the survey said it would.** The readout and the
##      verb both go through `survey_at`; if they ever drift apart the player is
##      told about one piece of ground and plants a mast on another.
##
##   3. **Lowering must give back the same crate.** Not an equivalent one — the
##      same node, carrying whatever damage it had accumulated. Crates are never
##      destroyed and respawned anywhere else in the game, and a mast is the
##      first thing that could have broken that.
##
##   4. **Lowering must take the site out of the graph.** A mast that is gone
##      from the world but still linking two facilities would be the worst kind
##      of bug: coverage that cannot be explained by anything visible.
##
##   5. **A dark site must still be allowed.** The survey is an instrument, not
##      a gate. If raising quietly refused where there was no link, the readout
##      would have become a rule and dark ground would stop being a real place.
##
##   6. **An authored relay must not be lowerable.** There is no crate inside it
##      to hand back, and inventing one would be cargo the player never carried.
##
##   7. **Two masts must not share a name.** relay.tscn carries an authored id,
##      so anything that only names a mast when the id is blank gives every
##      raised mast the same one — and the second quietly replaces the first in
##      the graph, leaving a mast standing in the world that coverage cannot
##      see. Caught by raising two, which is why one is not enough.
##
## Runs as a scene rather than via --script so autoloads exist. Builds its own
## terrain and facilities so the geometry is known.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_mast_raise.tscn

const BUILD_BUDGET := 240
## Area3D overlap lists only refresh on a physics step, so aiming at the mast
## and then asking what is in reach needs frames in between.
const OVERLAP_FRAMES := 10
## Far enough from both facilities that nothing is in reach of a mast there.
const DARK := Vector3(400.0, 0.0, 400.0)

var _terrain: ProceduralTerrain
var _astronaut: Astronaut
var _crate: Crate
var _second: Crate
var _relay: Relay
var _raised_at := Vector3.ZERO
var _condition_before := 0.0
var _frames := 0
var _stage := 0
var _waited := 0
var _failures: Array[String] = []


func _ready() -> void:
	_terrain = ProceduralTerrain.new()
	add_child(_terrain)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _terrain == null or not _terrain.is_built():
		if _frames > BUILD_BUDGET:
			_expect(false, "terrain never built in %d frames" % BUILD_BUDGET)
			_finish()
		return
	if _astronaut == null:
		_build_the_world()
		return
	match _stage:
		0: _stage_dark_to_begin_with()
		1: _stage_raise_it()
		2: _stage_it_links_them()
		3: _stage_lower_it()
		4: _stage_it_went_dark_again()
		5: _stage_a_dark_site_is_allowed()
		6: _stage_two_masts_do_not_share_a_name()
		7: _stage_authored_relays_do_not_come_down()
		8: _finish()


func _build_the_world() -> void:
	# 70 m apart, which the default 45 m reach cannot span. Both are stood at
	# mast height above their own ground, so the link that matters is the one
	# through a mast at the midpoint and not a fluke of the facilities' heights.
	var h := Lattice.survey_mast_height
	_spawn_facility("hearth", Vector3(-35.0,
		_terrain.world_height_at(-35.0, 0.0) + h, 0.0))
	_spawn_facility("longshadow", Vector3(35.0,
		_terrain.world_height_at(35.0, 0.0) + h, 0.0))

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate() as Astronaut
	_astronaut.position = Vector3(0.0, _terrain.world_height_at(0.0, 0.0) + 2.0, 0.0)
	add_child(_astronaut)

	_crate = load("res://scenes/cargo/crate.tscn").instantiate() as Crate
	_crate.cargo_name = "Recovered mast"
	_crate.deploys_as = load("res://scenes/world/relay.tscn")
	add_child(_crate)

	_second = load("res://scenes/cargo/crate.tscn").instantiate() as Crate
	_second.cargo_name = "Spare mast"
	_second.deploys_as = load("res://scenes/world/relay.tscn")
	add_child(_second)
	Lattice.rebuild()


func _stage_dark_to_begin_with() -> void:
	_expect(not Lattice.are_linked("hearth", "longshadow"),
		"the two facilities could already see each other before any mast existed")
	_astronaut.back_rack().load_crate(_crate)
	_expect(_astronaut.carried_deployable() == _crate,
		"the mast did not register as carried after loading it")
	_condition_before = _crate.condition
	_stage = 1


func _stage_raise_it() -> void:
	var survey := Lattice.survey_at(_astronaut.global_position.x,
		_astronaut.global_position.z)
	_raised_at = survey.ground_point
	_astronaut._raise_or_lower()
	_relay = _first_raised_relay()
	if _relay == null:
		_expect(false, "raising the mast produced no relay")
		_finish()
		return
	_expect(_astronaut.carried_deployable() == null,
		"the mast was still on the astronaut's back after being raised")
	_expect(_crate.is_stowed(),
		"a crate riding inside a raised mast reported itself loose")
	_expect(not _crate.visible, "the crate is still drawn inside the mast")

	# 2. The verb and the readout must agree about the ground.
	_expect(_relay.global_position.distance_to(_raised_at) < 0.01,
		"the mast stands at %s, but the survey said %s"
			% [_relay.global_position, _raised_at])

	# It has to be in the graph, not merely in the scene.
	_expect(_relay.relay_id != "", "the raised mast has no id")
	_expect(Lattice.site(_relay.relay_id) == _relay,
		"the raised mast '%s' never registered with the Lattice" % _relay.relay_id)
	_stage = 2


## 1. The payoff. Deferred a frame because the rebuild is.
func _stage_it_links_them() -> void:
	_expect(Lattice.are_linked("hearth", "longshadow"),
		"a mast raised between two dark facilities did not link them")
	print("raised '%s' at %s — hearth and longshadow linked: %s"
		% [_relay.relay_id, _raised_at, Lattice.are_linked("hearth", "longshadow")])
	_stage = 3


func _stage_lower_it() -> void:
	# Every verb goes through aim, and overlaps need a physics step to refresh.
	_astronaut.global_position = _relay.global_position + Vector3(0.0, 2.0, 1.5)
	_astronaut.aim_at(_relay.global_position)
	_waited += 1
	if _waited < OVERLAP_FRAMES:
		return
	var target := _astronaut.mast_target()
	if target == null:
		if _waited < OVERLAP_FRAMES * 6:
			return
		_expect(false, "a raised mast at arm's length was not a lowering target")
		_finish()
		return
	_expect(_astronaut.interact_target() == null
			or _astronaut.interact_target().kind != Astronaut.KIND_MAST,
		"a mast turned up as an `interact` target and would steal E")
	_astronaut._raise_or_lower()
	_stage = 4


func _stage_it_went_dark_again() -> void:
	# 3. The same crate, not an equivalent one.
	_expect(is_instance_valid(_crate), "the crate did not survive being lowered")
	if not is_instance_valid(_crate):
		_finish()
		return
	_expect(not _crate.is_stowed(), "the lowered crate is still riding in something")
	_expect(_crate.visible, "the lowered crate came back invisible")
	_expect(is_equal_approx(_crate.condition, _condition_before),
		"the crate came back at %.4f condition, not the %.4f it went in with"
			% [_crate.condition, _condition_before])

	# 4. And the site must be gone from the graph, not just from the scene.
	_expect(_first_raised_relay() == null, "the lowered mast is still in the scene")
	_expect(not Lattice.are_linked("hearth", "longshadow"),
		"the facilities are still linked by a mast that no longer exists")
	_stage = 5
	_waited = 0


## 5. Dark ground is a real place. Raising there must work and simply not link.
func _stage_a_dark_site_is_allowed() -> void:
	_astronaut.global_position = DARK + Vector3(0.0,
		_terrain.world_height_at(DARK.x, DARK.z) + 2.0, 0.0)
	_astronaut.back_rack().load_crate(_crate)
	if _astronaut.carried_deployable() == null:
		_waited += 1
		if _waited < OVERLAP_FRAMES:
			return
		_expect(false, "could not put the recovered mast back on the astronaut")
		_finish()
		return
	var survey := Lattice.survey_at(_astronaut.global_position.x,
		_astronaut.global_position.z)
	_expect(not survey.linked,
		"the spot chosen to be dark reported a link to '%s'" % survey.best_id)
	_astronaut._raise_or_lower()
	var dark_mast := _first_raised_relay()
	_expect(dark_mast != null, "raising on dark ground was silently refused")
	if dark_mast != null:
		_expect(Lattice.site(dark_mast.relay_id) == dark_mast,
			"a mast raised on dark ground did not register")
		_expect(Lattice.neighbours(dark_mast.relay_id).is_empty(),
			"a mast 400 m from everything linked to something")
		print("dark mast '%s' raised and registered, linking to nothing"
			% dark_mast.relay_id)
	_stage = 6
	_waited = 0


## 7. A second mast, raised while the first still stands, must get its own name
## and its own entry in the graph.
func _stage_two_masts_do_not_share_a_name() -> void:
	var first := _first_raised_relay()
	if first == null:
		_expect(false, "the dark mast vanished before a second could be raised")
		_finish()
		return
	var first_id := first.relay_id
	_astronaut.global_position = Vector3(DARK.x + 20.0,
		_terrain.world_height_at(DARK.x + 20.0, DARK.z) + 2.0, DARK.z)
	_astronaut.back_rack().load_crate(_second)
	if _astronaut.carried_deployable() == null:
		_waited += 1
		if _waited < OVERLAP_FRAMES:
			return
		_expect(false, "could not put the spare mast on the astronaut")
		_finish()
		return
	_astronaut._raise_or_lower()
	var second_relay := _relay_holding(_second)
	if second_relay == null:
		_expect(false, "the second mast produced no relay")
		_stage = 7
		return
	_expect(second_relay.relay_id != first_id,
		"two raised masts both call themselves '%s'" % first_id)
	_expect(Lattice.site(first_id) == first,
		"raising a second mast displaced the first from the graph")
	_expect(Lattice.site(second_relay.relay_id) == second_relay,
		"the second mast never registered")
	print("two masts standing: '%s' and '%s'" % [first_id, second_relay.relay_id])
	_stage = 7


func _relay_holding(crate: Crate) -> Relay:
	for node in get_tree().get_nodes_in_group("relay"):
		var relay := node as Relay
		if relay != null and not relay.is_queued_for_deletion() 				and relay.raised_from == crate:
			return relay
	return null


## 6. An authored relay has no crate to give back.
func _stage_authored_relays_do_not_come_down() -> void:
	var authored := load("res://scenes/world/relay.tscn").instantiate() as Relay
	authored.relay_id = "authored"
	authored.position = Vector3(0.0, 200.0, 0.0)
	add_child(authored)
	_expect(not authored.can_lower(),
		"an authored relay offered to be lowered into a crate nobody carried")
	_expect(authored.lower() == null,
		"lowering an authored relay produced a crate out of nothing")
	_stage = 8


func _first_raised_relay() -> Relay:
	for node in get_tree().get_nodes_in_group("relay"):
		var relay := node as Relay
		# queue_free() does not take effect until the frame ends, and group
		# membership outlives the call — so a mast lowered this frame is still
		# in the list and would read as "still standing".
		if relay != null and not relay.is_queued_for_deletion() and relay.can_lower():
			return relay
	return null


func _spawn_facility(id: String, at: Vector3) -> Facility:
	var facility := load("res://scenes/world/facility.tscn").instantiate() as Facility
	facility.facility_id = id
	facility.display_name = id.capitalize()
	facility.position = at
	add_child(facility)
	return facility


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: a raised mast links, stands where surveyed, and comes back a crate.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
