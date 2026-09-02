extends Node3D
## Regression test for the coverage mask — the boundary drawn on the ground.
## See [[The-Lattice]].
##
## What this exists to catch:
##
##   1. **Coverage must not be a circle.** This is the whole claim of the
##      system: a radius check makes the network a question of distance, which
##      the map cannot argue with. If the mask ever comes out as a clean disc,
##      the picture on the ground is quietly contradicting the mechanic it is
##      supposed to be teaching — and it would look perfectly fine while doing
##      it. Asserted by area: a covered region strictly smaller than the disc it
##      sits in is a region with terrain bitten out of it.
##
##   2. **Only sites that chain back to the anchor may paint.** A mast raised
##      out of reach of everything must light nothing, or the boundary stops
##      meaning "connected" and starts meaning "there is a mast here", which is
##      the one thing it must not mean.
##
##   3. **Extending the network must extend the ground.** Coverage growing when
##      a relay links a second facility is the entire loop this feature exists
##      to show.
##
##   4. **The gameplay query and the picture must be the same numbers.**
##      `Lattice.is_covered()` reads the mask rather than recomputing, so a
##      flare warning and the line on the ground can never disagree about where
##      the edge is.
##
## Runs as a scene rather than via --script so autoloads exist. Builds its own
## terrain so the occlusion is real rather than inherited.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_coverage_map.tscn

const BUILD_BUDGET := 300
## Where a relay would bridge to the far facility.
const BRIDGE := Vector3(35.0, 0.0, 0.0)

var _terrain: ProceduralTerrain
var _map: CoverageMap
var _anchor: Facility
var _far: Facility
var _stray: Relay
var _frames := 0
var _stage := 0
var _rebuilds := 0
var _covered_before := 0
var _failures: Array[String] = []


func _ready() -> void:
	_terrain = ProceduralTerrain.new()
	add_child(_terrain)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if not _terrain.is_built():
		if _frames > BUILD_BUDGET:
			_expect(false, "terrain never built")
			_finish()
		return
	if _map == null:
		_build()
		return
	if _rebuilds == 0:
		if _frames > BUILD_BUDGET:
			_expect(false, "the coverage mask never rebuilt")
			_finish()
		return
	match _stage:
		0: _stage_the_anchor_covers_its_own_ground()
		1: _stage_it_is_not_a_circle()
		2: _stage_a_stray_mast_lights_nothing()
		3: _stage_bridging_extends_the_ground()
		4: _finish()


func _build() -> void:
	# Sat on the ground rather than up in the air, so its sight lines graze the
	# terrain and the ridges actually take bites out of its coverage. A mast on
	# a pole would see over everything and the shape would be a disc.
	_anchor = _spawn_facility("hearth", Vector3(0.0,
		_terrain.world_height_at(0.0, 0.0), 0.0))
	# 70 m out: beyond the 45 m reach, so it is dark until something bridges.
	_far = _spawn_facility("longshadow", Vector3(70.0,
		_terrain.world_height_at(70.0, 0.0), 0.0))
	# 400 m away and connected to nothing.
	_stray = load("res://scenes/world/relay.tscn").instantiate() as Relay
	_stray.relay_id = "stray"
	_stray.position = Vector3(400.0, _terrain.world_height_at(400.0, 400.0), 400.0)
	add_child(_stray)

	_map = CoverageMap.new()
	add_child(_map)
	_map.rebuilt.connect(func() -> void: _rebuilds += 1)
	Lattice.rebuild()


func _stage_the_anchor_covers_its_own_ground() -> void:
	var here := _map.coverage_at(_anchor.global_position.x, _anchor.global_position.z)
	_expect(here > 0.5,
		"the anchor does not cover the ground it is standing on (%.2f)" % here)
	# 4. The query and the picture are the same numbers.
	_expect(Lattice.is_covered(_anchor.global_position.x, _anchor.global_position.z),
		"Lattice.is_covered disagreed with the mask under the anchor")
	_expect(not Lattice.is_covered(_far.global_position.x, _far.global_position.z),
		"the far facility was covered before anything bridged to it")
	_stage = 1


## 1. The assertion the whole feature rests on.
func _stage_it_is_not_a_circle() -> void:
	var reach := Lattice.default_range
	var covered := 0
	var in_disc := 0
	var step := 1.0
	var at := _anchor.global_position
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			if Vector2(x, z).length() <= reach:
				in_disc += 1
				if _map.coverage_at(at.x + x, at.z + z) > 0.0:
					covered += 1
			z += step
		x += step
	_covered_before = covered
	var ratio := float(covered) / maxf(float(in_disc), 1.0)
	print("coverage fills %.1f%% of the disc it sits in (%d of %d samples)"
		% [ratio * 100.0, covered, in_disc])
	_expect(covered > 0, "the anchor covered nothing at all")
	_expect(ratio < 0.98,
		"coverage fills %.1f%% of its disc — it is a radius check, not a sight line"
			% [ratio * 100.0])
	_stage = 2


## 2. Connected, or it does not count.
func _stage_a_stray_mast_lights_nothing() -> void:
	_expect(Lattice.site("stray") == _stray, "the stray mast never registered")
	_expect(not Lattice.are_linked("hearth", "stray"),
		"the stray mast 400 m out is somehow linked to the anchor")
	var under := _map.coverage_at(_stray.global_position.x, _stray.global_position.z)
	_expect(is_zero_approx(under),
		"a mast connected to nothing painted %.2f coverage under itself" % under)
	var ids := PackedStringArray()
	for site in Lattice.covering_sites():
		ids.append(String(site.call("lattice_id")))
	_expect(not ids.has("stray"),
		"the stray mast is in covering_sites(): %s" % ", ".join(ids))
	_stage = 3


## 3. The loop: bridge the gap and the ground answers.
func _stage_bridging_extends_the_ground() -> void:
	if Lattice.site("bridge") == null:
		var bridge := load("res://scenes/world/relay.tscn").instantiate() as Relay
		bridge.relay_id = "bridge"
		bridge.position = Vector3(BRIDGE.x,
			_terrain.world_height_at(BRIDGE.x, BRIDGE.z), BRIDGE.z)
		add_child(bridge)
		_rebuilds = 0
		return
	if _rebuilds == 0:
		return
	_expect(Lattice.are_linked("hearth", "longshadow"),
		"the bridging relay did not link the two facilities")
	var there := _map.coverage_at(_far.global_position.x, _far.global_position.z)
	_expect(there > 0.5,
		"the far facility is linked but its own ground reads %.2f coverage" % there)
	print("after bridging, the far facility's ground reads %.2f" % there)
	_stage = 4


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
		print("PASS: coverage follows sight lines, needs the anchor, and grows when you bridge.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
