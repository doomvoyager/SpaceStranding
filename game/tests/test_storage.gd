extends Node3D
## Regression test for facility storage: a real place, per facility, that keeps
## what it is given.
##
## What this exists to catch:
##
##   1. **Condition must survive the shelf.** Storage holds records rather than
##      nodes, so a stored crate is destroyed and a new one built when it comes
##      out. If that round trip lost `condition`, every warehouse would be a
##      free repair shop — the exact thing the abandonment rules were argued
##      over — and nothing would look broken.
##
##   2. **Storage is per facility.** Putting something in at Hearth must not
##      make it appear at Longshadow. That is the whole premise of the
##      [[The-Lattice]] ladder, and a single shared dictionary key would quietly
##      undo it.
##
##   3. **Handing an order back must sweep the shelf too.** An order's cargo can
##      reach storage two ways — overflow past a full dock, or the player
##      putting it there — and cargo left behind would let the order be taken a
##      second time while the first lot was still in the warehouse. A crate
##      duplicator with an extra step.
##
##   4. **A facility's own stock is not the player's to take.** Delivered and
##      house stock shows on the shelf; withdrawing it must be refused.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_storage.tscn

const SETTLE_FRAMES := 12

var _hearth: Facility
var _longshadow: Facility
var _astronaut: Astronaut
var _crate: Crate
var _frames := 0
var _stage := 0
var _failures: Array[String] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_hearth = _spawn_facility("hearth", "Hearth", Vector3.ZERO)
	_longshadow = _spawn_facility("longshadow", "Longshadow", Vector3(80.0, 0.0, 0.0))

	# Beside Hearth's intake, which sits at x = -6.2 in facility space.
	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(-6.2, 1.0, 2.0)
	add_child(_astronaut)

	# Spawned here rather than in the stage that uses it: Area3D overlap lists
	# only refresh on a physics step, so a crate created and reached for in the
	# same frame is invisible to the interact zone. Placed on the far side of
	# the astronaut from the intake, so aiming at one is aiming away from the
	# other.
	_crate = load("res://scenes/cargo/crate.tscn").instantiate()
	_crate.cargo_name = "Water canister"
	_crate.mass = 55.0
	_crate.position = Vector3(-6.2, 1.0, 2.8)
	add_child(_crate)


func _spawn_facility(id: String, display: String, at: Vector3) -> Facility:
	var facility := load("res://scenes/world/facility.tscn").instantiate() as Facility
	facility.facility_id = id
	facility.display_name = display
	facility.position = at
	add_child(facility)
	return facility


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames % SETTLE_FRAMES != 0:
		return
	_stage += 1
	match _stage:
		1: _check_empty_and_signed()
		2: _check_deposit_is_physical()
		3: _check_condition_survives()
		4: _check_per_facility()
		5: _check_overflow_goes_to_the_shelf()
		6: _check_recall_sweeps_the_shelf()
		7: _check_house_stock_is_not_yours()
		8: _finish()


func _check_empty_and_signed() -> void:
	_expect(Orders.stock_count("hearth") == 0,
		"Hearth starts with %d in storage" % Orders.stock_count("hearth"))
	# The sign is driven from display_name, so renaming a facility renames it.
	var sign_node := _hearth.get_node_or_null("Sign") as Label3D
	_expect(sign_node != null, "the facility has no Sign")
	if sign_node != null:
		_expect(sign_node.text == "Hearth",
			"the sign says '%s', not the display name" % sign_node.text)


## F while carrying, facing the intake, puts it in. There is no menu for this.
func _check_deposit_is_physical() -> void:
	_crate.take_damage(0.35)
	_expect(_crate.condition < 0.7,
		"test failed to damage the crate: %.2f" % _crate.condition)

	# Pick it up, then face the intake and hand it over.
	_astronaut.aim_at(_crate.global_position)
	_astronaut._interact()
	_expect(_astronaut.back_rack().count() == 1, "did not pick the crate up")

	var intake: Facility = _astronaut.nearby_storage()
	_expect(intake == _hearth, "the astronaut cannot reach Hearth's intake")
	_astronaut.aim_at(_hearth.get_node("Intake").global_position)
	_expect(_astronaut.cargo_prompt().begins_with("Put it in"),
		"F facing the intake offers '%s'" % _astronaut.cargo_prompt())
	_astronaut._move_cargo()


func _check_condition_survives() -> void:
	_expect(_astronaut.back_rack().is_empty(), "the crate did not leave the back rack")
	_expect(Orders.stock_count("hearth") == 1,
		"Hearth holds %d after a deposit" % Orders.stock_count("hearth"))
	if Orders.stock_count("hearth") == 0:
		return
	var item: StoredItem = Orders.stock_of("hearth")[0]
	_expect(item.cargo_name == "Water canister",
		"stored item is called '%s'" % item.cargo_name)
	_expect(item.condition < 0.7,
		"condition came out of the deposit at %.2f; damage was lost" % item.condition)
	print("stored at %.2f condition, %.0f kg" % [item.condition, item.mass])

	# Out again onto the dock, and it must be the same thing.
	var back := _hearth.withdraw_to_dock(0)
	_expect(back != null, "withdrawing to the dock returned nothing")
	if back == null:
		return
	_expect(back.is_stowed(), "the withdrawn crate is not on the dock")
	_expect(back.condition < 0.7,
		"the crate came off the shelf at %.2f condition — the shelf is a repair shop"
		% back.condition)
	_expect(is_equal_approx(back.mass, 55.0),
		"the crate came off the shelf weighing %.1f" % back.mass)
	_expect(Orders.stock_count("hearth") == 0,
		"withdrawing left %d behind" % Orders.stock_count("hearth"))
	print("withdrawn at %.2f condition" % back.condition)


## Two facilities, two shelves. The Lattice ladder rests entirely on this.
func _check_per_facility() -> void:
	var item := StoredItem.new()
	item.cargo_name = "Spare cell"
	Orders.deposit("hearth", item)
	_expect(Orders.stock_count("hearth") == 1,
		"Hearth holds %d" % Orders.stock_count("hearth"))
	_expect(Orders.stock_count("longshadow") == 0,
		"a deposit at Hearth put %d on Longshadow's shelf"
		% Orders.stock_count("longshadow"))
	Orders.withdraw("hearth", 0)


## A dock has eight slots. The ninth crate used to be dumped on the sand.
func _check_overflow_goes_to_the_shelf() -> void:
	var dock := _hearth.dock()
	var capacity := dock.capacity()
	_expect(Orders.accept(104), "could not accept 104")
	# 104 is three crates and the dock holds eight, so three issues is nine —
	# exactly one past the end, which is the case worth asserting.
	var order := Orders.get_order(104)
	var issues := int(ceil(float(capacity + 1) / float(order.crates)))
	for i in issues:
		_hearth.issue(order)
	_expect(dock.is_full(), "the dock did not fill: %d of %d" % [dock.count(), capacity])
	_expect(Orders.stock_count("hearth") > 0,
		"the dock overflowed to nowhere; storage holds %d"
		% Orders.stock_count("hearth"))
	var loose := 0
	for node in get_tree().get_nodes_in_group("cargo"):
		var crate := node as Crate
		if crate != null and not crate.is_stowed():
			loose += 1
	_expect(loose == 0, "%d crate(s) were dumped on the ground instead" % loose)
	print("dock %d/%d, %d overflowed onto the shelf"
		% [dock.count(), capacity, Orders.stock_count("hearth")])


func _check_recall_sweeps_the_shelf() -> void:
	_hearth.recall(104)
	Orders.abandon(104)
	_expect(Orders.stock_count("hearth") == 0,
		"handing 104 back left %d of its crates in storage"
		% Orders.stock_count("hearth"))
	# Not "the dock is empty": the water canister withdrawn earlier is the
	# player's and is still sitting there, which is correct. Recall takes 104's
	# cargo and nothing else.
	var left := 0
	for crate in _hearth.dock().crates():
		if crate.order_code() == 104:
			left += 1
	_expect(left == 0, "handing 104 back left %d of its crates on the dock" % left)
	_expect(_hearth.dock().count() == 1,
		"recall took %d crates off the dock that were not 104's"
		% (1 - _hearth.dock().count()))
	_expect(Orders.state_of(104) == Orders.State.OFFERED, "104 is not back on the board")


func _check_house_stock_is_not_yours() -> void:
	var house := StoredItem.new()
	house.cargo_name = "Reactor coolant"
	house.cargo_owner = Crate.Owner.FACILITY
	house.owner_id = "hearth"
	Orders.deposit("hearth", house)
	_expect(not house.is_withdrawable(), "facility stock reports as withdrawable")
	_expect(Orders.withdraw("hearth", 0) == null,
		"the player was handed the facility's own stock")
	_expect(Orders.stock_count("hearth") == 1,
		"the refused withdrawal removed it anyway")
	_expect(_hearth.withdraw_to_dock(0) == null,
		"the panel moved the facility's own stock onto the dock")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: storage keeps what it is given, per facility, condition and all.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
