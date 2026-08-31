extends Node3D
## Regression test for the order system: the catalogue, issuing, routing,
## delivery, prerequisites and handing an order back.
##
## Three of these would not be caught by anything else and are the reason the
## test exists:
##
##   1. **A crate delivered to the wrong facility must pay nothing.** The pad
##      accepts any crate that settles on it, so without an address check every
##      order becomes "drive to the nearest pad" and the destination column in
##      data/orders.tsv would mean nothing at all. Nothing would look broken.
##
##   2. **Handing an order back must take the cargo with it.** Leave the crates
##      behind and the order can be taken a second time while the first lot is
##      still lying on the dock — a crate duplicator, and a quiet one.
##
##   3. **Re-taking an order must issue pristine cargo.** That is the whole of
##      Mac's call on 2026-08-31: abandoning is a clean restart. If it ever
##      stopped being true, a player who backtracked would find the same
##      battered boxes and no way to tell why.
##
##   4. **Cargo on a dock must be liftable off it.** A docked crate is stowed in
##      a rack, so it is invisible to `nearest_loose_crate()` and `E` slides
##      straight past it. The first build of this shipped an order board that
##      issued cargo nothing could then pick up — every headless assertion
##      passed, because the crates existed and were on their slots.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_orders.tscn

## Area3D overlap lists only refresh on a physics step, so a crate placed on a
## pad cannot be seen by it until physics has run.
const SETTLE_FRAMES := 12

var _hearth: Facility
var _longshadow: Facility
var _astronaut: Astronaut
var _frames := 0
var _stage := 0
var _failures: Array[String] = []
## Crates from order 104, kept so the test can batter one and check it heals.
var _batch: Array[Crate] = []


func _ready() -> void:
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	col.shape = shape
	ground.add_child(col)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child(ground)

	_hearth = _spawn_facility("hearth", "Hearth", Vector3(0.0, 0.0, 0.0))
	_longshadow = _spawn_facility("longshadow", "Longshadow", Vector3(60.0, 0.0, 0.0))

	# Beside Hearth's dock, which sits at x = -3.6 in facility space. Well
	# inside the 3.5 m interact sphere, and nowhere near Longshadow.
	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	_astronaut.position = Vector3(-3.6, 1.0, 1.6)
	add_child(_astronaut)


func _spawn_facility(id: String, display: String, at: Vector3) -> Facility:
	var facility := load("res://scenes/world/facility.tscn").instantiate() as Facility
	facility.facility_id = id
	facility.display_name = display
	facility.position = at
	add_child(facility)
	return facility


func _physics_process(_delta: float) -> void:
	_frames += 1
	# One stage per settle window, so every pad check gets its physics step.
	if _frames % SETTLE_FRAMES != 0:
		return
	_stage += 1
	match _stage:
		1: _check_catalogue()
		2: _check_issue()
		3: _check_wrong_pad()
		4: _check_right_pad()
		5: _check_prerequisite()
		6: _check_abandon()
		7: _check_reissue_is_pristine()
		8: _check_dock_is_reachable()
		9: _finish()


# --- The catalogue ------------------------------------------------------

func _check_catalogue() -> void:
	_expect(Orders.problems.is_empty(),
		"data/orders.tsv has problems: %s" % ", ".join(Orders.problems))
	_expect(Orders.count() >= 6, "only %d orders loaded" % Orders.count())

	var order := Orders.get_order(104)
	_expect(order != null, "order 104 is missing")
	if order == null:
		return
	# The row is the authoring surface, so these are the numbers the crates
	# must come out carrying.
	_expect(order.crates == 3, "104 should be 3 crates, is %d" % order.crates)
	_expect(is_equal_approx(order.mass_kg, 55.0), "104 mass is %.1f" % order.mass_kg)
	_expect(order.destination == "longshadow", "104 goes to '%s'" % order.destination)

	# 103 requires 101, so it must not be on the board yet.
	_expect(Orders.state_of(103) == Orders.State.LOCKED,
		"103 requires 101 but is not locked")
	var board := Orders.board_for("hearth")
	for o in board:
		_expect(o.code != 103, "103 is on the board despite its prerequisite")
	_expect(not board.is_empty(), "nothing on Hearth's board")

	# Loose cargo is found, never offered.
	for o in Orders.board_for("longshadow"):
		_expect(o.code != 105, "loose order 105 is on a board")


# --- Issuing ------------------------------------------------------------

func _check_issue() -> void:
	_expect(Orders.accept(104), "could not accept 104")
	_batch.assign(_hearth.issue(Orders.get_order(104)))
	_expect(_batch.size() == 3, "issuing 104 made %d crates, expected 3" % _batch.size())
	_expect(_hearth.dock().count() == 3,
		"dock holds %d after issuing 104" % _hearth.dock().count())
	for crate in _batch:
		_expect(crate.order_code() == 104, "issued crate is not marked as 104's")
		_expect(crate.cargo_owner == Crate.Owner.ORDER, "issued crate is not order-owned")
		_expect(is_equal_approx(crate.mass, 55.0),
			"issued crate weighs %.1f, row says 55" % crate.mass)
		_expect(is_equal_approx(crate.value, 90.0),
			"issued crate is worth %.1f, row says 90" % crate.value)


## The one nothing else would catch: right cargo, wrong address.
func _check_wrong_pad() -> void:
	var pad := _hearth.pad()
	var crate := _batch[0]
	_expect(not pad.accepts(crate),
		"Hearth's pad would accept 104, which is addressed to Longshadow")
	_put_on_pad(crate, pad)


func _check_right_pad() -> void:
	var hearth_pad := _hearth.pad()
	_expect(hearth_pad.delivered_count == 0,
		"Hearth paid for %d crate(s) it should have refused" % hearth_pad.delivered_count)
	_expect(Orders.progress(104) == Vector2i(0, 3),
		"104 progressed to %s at the wrong facility" % Orders.progress(104))

	# Now the right one. Two of three: the order must stay open.
	_put_on_pad(_batch[0], _longshadow.pad())
	_put_on_pad(_batch[1], _longshadow.pad())


func _check_prerequisite() -> void:
	_expect(Orders.progress(104) == Vector2i(2, 3),
		"104 is at %s after two crates" % Orders.progress(104))
	_expect(not Orders.is_delivered(104), "104 closed on a partial delivery")

	_put_on_pad(_batch[2], _longshadow.pad())
	# Deliveries are swept on the physics step, so the third lands next stage.


func _check_abandon() -> void:
	_expect(Orders.is_delivered(104), "104 did not close after all three crates")
	_expect(Orders.paid_for(104) > 0.0, "104 paid nothing")

	# 101 unlocks 103 on delivery, so take and finish it the short way.
	_expect(Orders.accept(101), "could not accept 101")
	var parts := _hearth.issue(Orders.get_order(101))
	for crate in parts:
		Orders.deliver_crate(101, 100.0)
		crate.queue_free()
	_expect(Orders.is_delivered(101), "101 did not close")
	_expect(Orders.state_of(103) == Orders.State.OFFERED,
		"103 did not unlock when 101 was delivered")

	# Hand 106 back after damaging it, and check nothing is left behind.
	_expect(Orders.accept(106), "could not accept 106")
	var issued := _hearth.issue(Orders.get_order(106))
	_expect(issued.size() == 1, "106 issued %d crates" % issued.size())
	issued[0].take_damage(0.6)
	_expect(issued[0].condition < 0.5,
		"test did not manage to damage the crate: %.2f" % issued[0].condition)

	var recalled := _hearth.recall(106)
	Orders.abandon(106)
	_expect(recalled == 1, "recall took %d crates, expected 1" % recalled)
	_expect(Orders.state_of(106) == Orders.State.OFFERED,
		"106 is not back on the board")


func _check_reissue_is_pristine() -> void:
	# queue_free lands between stages, so the dock is only measurable now.
	_expect(_crates_for(106) == 0,
		"%d crate(s) of 106 survived the recall" % _crates_for(106))

	_expect(Orders.accept(106), "could not re-accept 106 after handing it back")
	var again := _hearth.issue(Orders.get_order(106))
	_expect(again.size() == 1, "re-issuing 106 made %d crates" % again.size())
	_expect(is_equal_approx(again[0].condition, 1.0),
		"re-issued cargo arrived at %.2f condition, not pristine" % again[0].condition)
	print("handed back and re-taken: condition %.2f" % again[0].condition)


## Cargo issued onto a dock has to be liftable off it. A docked crate is stowed,
## so `E` cannot see it — `F` has to treat the dock the way it treats the
## rover's rack, or an accepted order is cargo you can look at and not carry.
func _check_dock_is_reachable() -> void:
	var dock := _hearth.dock()
	_expect(_astronaut.nearby_dock() == dock,
		"the astronaut cannot reach Hearth's dock; test is invalid")
	_expect(dock.count() > 0, "nothing on the dock to lift")
	_expect(_astronaut.cargo_prompt() != "",
		"F offers nothing beside a loaded dock")

	var before := dock.count()
	_astronaut._move_cargo()
	_expect(_astronaut.back_rack().count() == 1,
		"F beside a loaded dock did not take a crate; back rack holds %d"
		% _astronaut.back_rack().count())
	_expect(dock.count() == before - 1,
		"dock still holds %d of %d" % [dock.count(), before])

	# And back the other way, so a crate can be staged rather than only taken.
	_astronaut._move_cargo()
	_expect(dock.count() == before,
		"F carrying a crate beside the dock did not set it down: %d of %d"
		% [dock.count(), before])
	_expect(_astronaut.back_rack().is_empty(), "back rack did not empty onto the dock")


# --- Helpers ------------------------------------------------------------

## Take a crate out of whatever holds it and set it down on `pad`, at rest.
func _put_on_pad(crate: Crate, pad: DeliveryPad) -> void:
	crate.release(self, Transform3D(Basis.IDENTITY, pad.global_position + Vector3.UP * 0.4))
	crate.linear_velocity = Vector3.ZERO
	crate.freeze = true


func _crates_for(code: int) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("cargo"):
		var crate := node as Crate
		if crate != null and is_instance_valid(crate) and crate.order_code() == code:
			n += 1
	return n


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: orders load, issue, route, close, unlock and hand back.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
