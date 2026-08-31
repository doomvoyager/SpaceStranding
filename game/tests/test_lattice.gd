extends Node3D
## Regression test for [[The-Lattice]]: line-of-sight linking, coverage, and
## transfers between linked facilities.
##
## What this exists to catch:
##
##   1. **A relay must actually be load-bearing.** Two facilities out of range
##      of each other are dark; one mast between them links them; taking that
##      mast away makes them dark again. If any of those three failed the
##      network would look like it worked while being a radius check, or a
##      constant, or nothing at all.
##
##   2. **Line of sight has to mean something.** A mast buried under the terrain
##      must not link, however close it is. Without this the whole system is a
##      distance check wearing a raycast's clothes, and *where* you put a relay
##      would not matter — which is the one thing it is supposed to be about.
##
##   3. **A transfer must take time and land on the right shelf.** Instant
##      arrival would make the Lattice a teleporter, which is the failure the
##      note has warned about since it was written.
##
##   4. **Dark facilities must be unreadable.** Not "readable but greyed out":
##      `facilities_reachable_from` is what the panel asks, and it must not
##      list a facility nothing can see.
##
## Runs as a scene rather than via --script so autoloads exist. Builds its own
## terrain so the ridge is known rather than inherited from the test world.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_lattice.tscn

const SETTLE_FRAMES := 6

## High enough that the terrain is never between two masts. The generated world
## tops out around 24 m in world space with the default height scale.
const AIR := 90.0

var _terrain: ProceduralTerrain
var _hearth: Facility
var _longshadow: Facility
var _relay: Relay
var _frames := 0
var _stage := 0
var _failures: Array[String] = []
var _seconds := 0.0


func _ready() -> void:
	# A real terrain, so the line-of-sight half is testing the thing the game
	# uses rather than an empty world where every line is clear.
	_terrain = ProceduralTerrain.new()
	add_child(_terrain)

	# 70 m apart, which the default 45 m range cannot span, with the relay
	# halfway: two 35 m legs, both inside it. Held well above the terrain so the
	# graph half is about range and topology and nothing else — the terrain gets
	# its own assertions in stage 2.
	_hearth = _spawn_facility("hearth", "Hearth", Vector3(0.0, AIR, 0.0))
	_longshadow = _spawn_facility("longshadow", "Longshadow", Vector3(70.0, AIR, 0.0))

	_relay = load("res://scenes/world/relay.tscn").instantiate() as Relay
	_relay.relay_id = "ridge"
	_relay.position = Vector3(35.0, AIR, 0.0)
	add_child(_relay)


func _spawn_facility(id: String, display: String, at: Vector3) -> Facility:
	var facility := load("res://scenes/world/facility.tscn").instantiate() as Facility
	facility.facility_id = id
	facility.display_name = display
	facility.position = at
	add_child(facility)
	return facility


func _physics_process(delta: float) -> void:
	_seconds += delta
	_frames += 1
	if _frames % SETTLE_FRAMES != 0:
		return
	_stage += 1
	match _stage:
		1: _check_relay_links_them()
		2: _check_line_of_sight_matters()
		3: _check_removing_the_relay_goes_dark()
		4: _start_a_transfer()
		# Stages 5-8 are the transfer in flight; nothing to do but let it run.
		9: _check_transfer_is_still_travelling()
		10: _finish_the_transfer()
		11: _check_it_landed()
		12: _finish()


## Two facilities too far apart to see each other, one mast between them.
func _check_relay_links_them() -> void:
	var span := Lattice.distance_between("hearth", "longshadow")
	_expect(span > Lattice.default_range,
		"the facilities are %.1f m apart, inside the %.1f m range - the relay is doing nothing"
		% [span, Lattice.default_range])
	_expect(Lattice.are_linked("hearth", "longshadow"),
		"the relay did not link them; %d link(s) in the network" % Lattice.link_count())
	_expect(Lattice.facilities_reachable_from("hearth") == ["longshadow"],
		"Hearth reaches %s" % str(Lattice.facilities_reachable_from("hearth")))
	_expect(Lattice.neighbours("hearth").has("ridge"),
		"Hearth does not link to the relay directly")
	print("%.0f m apart, range %.0f, %d link(s), Hearth reaches %s"
		% [span, Lattice.default_range, Lattice.link_count(),
			str(Lattice.facilities_reachable_from("hearth"))])


## Ground in the way means no link, however close.
##
## Without this the whole system is a distance check wearing a raycast's
## clothes, and *where* a relay goes would not matter - which is the one thing
## it is supposed to be about.
func _check_line_of_sight_matters() -> void:
	var ground := _terrain.world_height_at(0.0, 0.0)
	var far_ground := _terrain.world_height_at(60.0, 0.0)
	var buried := Vector3(0.0, ground - 5.0, 0.0)
	var aloft := Vector3(0.0, ground + 40.0, 0.0)
	var target := Vector3(60.0, far_ground + 40.0, 0.0)

	_expect(not Lattice.has_line_of_sight(buried, target),
		"a mast five metres underground can see out")
	_expect(Lattice.has_line_of_sight(aloft, target),
		"two masts forty metres up cannot see each other over open ground")
	print("ground at origin %.2f: buried mast blind, mast aloft clear" % ground)


func _check_removing_the_relay_goes_dark() -> void:
	_relay.get_parent().remove_child(_relay)
	Lattice.rebuild()
	var dark_links := Lattice.link_count()
	_expect(not Lattice.are_linked("hearth", "longshadow"),
		"they are still linked with the relay gone - the link is not the relay's doing")
	_expect(Lattice.facilities_reachable_from("hearth").is_empty(),
		"Hearth still reaches %s with no relay"
		% str(Lattice.facilities_reachable_from("hearth")))
	_expect(Orders.transfer_seconds("hearth", "longshadow") < 0.0,
		"a transfer was priced between two dark facilities")

	# Put it back for the transfer half. request_ready() is required: a node
	# re-entering the tree does not run _ready() again, so without it the relay
	# comes back as scenery and never re-registers as a site.
	_relay.request_ready()
	add_child(_relay)
	Lattice.rebuild()
	_expect(Lattice.are_linked("hearth", "longshadow"), "the relay did not come back")
	print("relay out: %d link(s). Relay back: %d link(s)."
		% [dark_links, Lattice.link_count()])


func _start_a_transfer() -> void:
	var item := StoredItem.new()
	item.cargo_name = "Spare cell"
	item.mass = 48.0
	item.condition = 0.72
	Orders.deposit("longshadow", item)

	var seconds := Orders.transfer_seconds("hearth", "longshadow")
	_expect(seconds > 5.0,
		"a transfer across 70 m takes %.1f s, which is not a journey" % seconds)
	_expect(Orders.request_transfer("longshadow", "hearth", 0),
		"the transfer was refused between linked facilities")
	_expect(Orders.stock_count("longshadow") == 0,
		"the item is still on Longshadow's shelf while in flight")
	_expect(Orders.stock_count("hearth") == 0,
		"the item arrived at Hearth instantly - the Lattice is a teleporter")
	_expect(Orders.inbound_to("hearth").size() == 1,
		"Hearth shows %d inbound" % Orders.inbound_to("hearth").size())
	print("transfer requested, %.0f s out" % seconds)


## Mid-flight: on neither shelf, and not yet arrived.
func _check_transfer_is_still_travelling() -> void:
	_expect(Orders.transfers_in_flight() == 1,
		"%d transfers in flight" % Orders.transfers_in_flight())
	_expect(Orders.stock_count("hearth") == 0, "it arrived early")


## Rather than idling for the full duration, hurry the clock. The property under
## test is that it takes time and lands correctly, not the wall-clock wait.
func _finish_the_transfer() -> void:
	var queue := Orders.inbound_to("hearth")
	if queue.is_empty():
		_expect(false, "nothing was in flight to finish")
		return
	var inbound = queue[0]
	_expect(inbound.remaining > 0.0,
		"the transfer had %.1f s left, so it was never really travelling"
		% inbound.remaining)
	_expect(inbound.fraction_done() > 0.0 and inbound.fraction_done() < 1.0,
		"progress reads %.2f mid-flight" % inbound.fraction_done())
	inbound.remaining = 0.001


func _check_it_landed() -> void:
	_expect(Orders.transfers_in_flight() == 0,
		"%d still in flight after arrival" % Orders.transfers_in_flight())
	_expect(Orders.stock_count("hearth") == 1,
		"Hearth holds %d after the transfer landed" % Orders.stock_count("hearth"))
	if Orders.stock_count("hearth") == 0:
		return
	var landed: StoredItem = Orders.stock_of("hearth")[0]
	_expect(landed.cargo_name == "Spare cell", "'%s' arrived" % landed.cargo_name)
	_expect(is_equal_approx(landed.condition, 0.72),
		"it arrived at %.2f condition, not the 0.72 it left at" % landed.condition)
	print("arrived at Hearth, condition %.2f" % landed.condition)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: relays link, line of sight matters, transfers take time.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
