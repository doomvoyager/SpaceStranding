extends Node
## The facility ledger. Autoloaded as `Orders`.
##
## Two things live here, and they are the same kind of thing: **what is where,
## and who owns it.** The order board is what a facility *wants* moved; storage
## is what a facility is *holding*. Delivery turns one into the other, so
## splitting them across two autoloads would only mean two globals talking to
## each other about one fact.
##
## Storage lives here rather than on the Facility node for two reasons. The
## [[The-Lattice]] ladder is meant to let a linked facility's stock be read from
## somewhere else entirely, which cannot depend on that facility being loaded;
## and this is the shape the save file wants - one blob, keyed by id.
##
## Two halves that must never merge:
##
##   The **catalogue** is data/orders.tsv, parsed once here at startup and then
##   read-only for the rest of the session. It is the file Mac edits.
##
##   The **state** — offered, accepted, delivered — is runtime, keyed by code,
##   and belongs in the save. Nothing here ever writes to the TSV. The moment
##   it did, the table would stop being something a spreadsheet can open and
##   become a save file wearing a spreadsheet's clothes.
##
## Facilities register themselves by id so the board can answer "what is on
## offer here" without knowing anything about the scene tree.
##
## See docs/02-Systems/Orders.md.

## Any change to any order's state. The panel and the HUD redraw on this rather
## than polling, and it is one signal rather than three so nothing can listen
## for accepted and quietly miss abandoned.
signal changed

signal accepted(order: Order)
signal abandoned(order: Order)
signal completed(order: Order)

## A facility's storage gained or lost something.
signal stock_changed(facility_id: String)

## A transfer was requested, or arrived. `arrived` says which.
signal transfer_changed(arrived: bool)

enum State {
	## On the board at its origin, waiting to be taken.
	OFFERED,
	## Taken. Its crates exist somewhere in the world.
	ACCEPTED,
	## Every crate arrived. Closed for good.
	DELIVERED,
	## Its prerequisite has not been delivered yet, so it is not shown at all.
	LOCKED,
}

const CATALOGUE_PATH := "res://data/orders.tsv"

## code -> Order, the authored catalogue. Never mutated after _ready().
var _catalogue: Dictionary = {}
## code -> State.
var _state: Dictionary = {}
## code -> how many of its crates have been accepted at the destination pad.
var _delivered_crates: Dictionary = {}
## code -> running total paid out for it.
var _paid: Dictionary = {}
## facility id -> Facility node.
var _facilities: Dictionary = {}
## facility id -> Array[StoredItem]. Runtime state, like everything else below
## the catalogue - and unlike the catalogue, this is what the save is for.
var _stock: Dictionary = {}
## Stock in flight between facilities. Array[Transfer].
var _transfers: Array = []


## Stock the network is moving from one shelf to another.
##
## The item is **off both shelves while it travels**, which is the honest
## reading: it is neither where it was nor where it is going. It also means
## nothing can be requested twice or withdrawn out from under a transfer.
class Transfer:
	var item: StoredItem
	var from_id := ""
	var to_id := ""
	## Seconds remaining, and how many it started with — the second is only so
	## a progress readout has a denominator.
	var remaining := 0.0
	var total := 0.0

	func fraction_done() -> float:
		if total <= 0.0:
			return 1.0
		return clampf(1.0 - remaining / total, 0.0, 1.0)
## Rows the parser refused, kept so a test can assert the table is clean.
var problems: Array[String] = []


@export_group("Transfers")
## Seconds before a requested transfer starts moving at all. The network has to
## find somebody to put it on a vehicle.
@export_range(0.0, 300.0, 1.0) var transfer_dispatch_s := 20.0

## Metres per second the network moves stock at. Deliberately slower than the
## rover: asking the Lattice to bring something is the patient option, and if it
## ever beat driving there yourself the rover would be a worse vehicle than the
## menu.
@export_range(0.1, 40.0, 0.1) var transfer_speed := 2.5


func _ready() -> void:
	load_catalogue()


# --- The catalogue ------------------------------------------------------

## Parse data/orders.tsv. Public and idempotent so a test can reload a fixture
## without restarting the project.
func load_catalogue(path := CATALOGUE_PATH) -> void:
	_catalogue.clear()
	_state.clear()
	_delivered_crates.clear()
	_paid.clear()
	_stock.clear()
	_transfers.clear()
	problems.clear()

	var text := _read(path)
	if text == "":
		problems.append("could not read %s" % path)
		return

	var header: PackedStringArray = []
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		# Comments and blank lines are the table's documentation. The tool that
		# edits this file preserves them; the loader simply steps over them.
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var cells := line.split("\t")
		if header.is_empty():
			header = cells
			continue
		var row := {}
		for i in mini(header.size(), cells.size()):
			row[header[i]] = cells[i]
		var order := Order.from_row(row, problems)
		if order == null:
			continue
		if _catalogue.has(order.code):
			problems.append("code %d appears twice" % order.code)
			continue
		_catalogue[order.code] = order

	# Prerequisites resolve after the whole table is in, so a row may require
	# one that appears below it.
	for code in _catalogue:
		var order: Order = _catalogue[code]
		if order.requires != 0 and not _catalogue.has(order.requires):
			problems.append("%d requires %d, which does not exist" % [code, order.requires])
			order.requires = 0
		_state[code] = State.LOCKED if order.requires != 0 else State.OFFERED

	if not problems.is_empty():
		for p in problems:
			printerr("ORDERS: " + p)
	print("ORDERS: %d loaded from %s, %d problems"
		% [_catalogue.size(), path, problems.size()])


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func all() -> Array[Order]:
	var out: Array[Order] = []
	for code in _catalogue:
		out.append(_catalogue[code])
	out.sort_custom(func(a: Order, b: Order) -> bool: return a.code < b.code)
	return out


func get_order(code: int) -> Order:
	return _catalogue.get(code, null)


func count() -> int:
	return _catalogue.size()


# --- State --------------------------------------------------------------

func state_of(code: int) -> State:
	return _state.get(code, State.LOCKED)


func is_accepted(code: int) -> bool:
	return state_of(code) == State.ACCEPTED


func is_delivered(code: int) -> bool:
	return state_of(code) == State.DELIVERED


## Everything the player currently owes somebody, in code order.
func accepted_orders() -> Array[Order]:
	var out: Array[Order] = []
	for order in all():
		if is_accepted(order.code):
			out.append(order)
	return out


## What a terminal at `facility_id` should show: everything on offer there, plus
## everything already accepted from there so it can be handed back.
##
## Loose cargo is never on a board. It is found, not taken.
func board_for(facility_id: String) -> Array[Order]:
	var out: Array[Order] = []
	for order in all():
		if order.is_loose() or order.origin != facility_id:
			continue
		var state := state_of(order.code)
		if state == State.OFFERED or state == State.ACCEPTED:
			out.append(order)
	return out


## Take an order. The caller is responsible for the crates: a Facility spawns
## them on its dock, and loose cargo is already in the world.
func accept(code: int) -> bool:
	if state_of(code) != State.OFFERED:
		return false
	_state[code] = State.ACCEPTED
	_delivered_crates[code] = 0
	accepted.emit(_catalogue[code])
	changed.emit()
	return true


## Pick up loose cargo and its order takes itself.
##
## Found cargo obligates nobody: there is no board to take it from, no clock,
## and nothing to fail. Accepting it is only what makes the destination
## readable and the pad willing to take it in. It is also why a loose order can
## never be handed back — you were never given it.
func notice_found(code: int) -> bool:
	var order: Order = _catalogue.get(code, null)
	if order == null or not order.is_loose() or state_of(code) != State.OFFERED:
		return false
	_state[code] = State.ACCEPTED
	_delivered_crates[code] = 0
	accepted.emit(order)
	changed.emit()
	print("ORDER %d found: %s, wanted at %s"
		% [order.code, order.title, facility_name(order.destination)])
	return true


## Hand an order back. It returns to its board exactly as it was offered.
##
## **The caller recalls the cargo first** — see Facility.recall(). That is the
## part that was argued: handing an order back reconditions its crates, which
## looks like a damage launderer until you notice the recall returns them to the
## *origin*. Re-running the order costs the whole outbound leg again, so it is a
## repair priced at a round trip rather than a reset button. See the
## Decision-Log entry of 2026-08-31.
func abandon(code: int) -> bool:
	if state_of(code) != State.ACCEPTED:
		return false
	_state[code] = State.OFFERED
	_delivered_crates[code] = 0
	abandoned.emit(_catalogue[code])
	changed.emit()
	return true


## Book one crate of `code` as arrived. Returns true when that was the last one
## and the order is now closed.
func deliver_crate(code: int, payout: float) -> bool:
	var order: Order = _catalogue.get(code, null)
	if order == null or state_of(code) != State.ACCEPTED:
		return false
	_delivered_crates[code] = int(_delivered_crates.get(code, 0)) + 1
	_paid[code] = float(_paid.get(code, 0.0)) + payout
	if int(_delivered_crates[code]) < order.crates:
		changed.emit()
		return false
	_state[code] = State.DELIVERED
	_unlock_dependents(code)
	completed.emit(order)
	changed.emit()
	return true


## How many of this order's crates are in, and how many there are.
func progress(code: int) -> Vector2i:
	var order: Order = _catalogue.get(code, null)
	if order == null:
		return Vector2i.ZERO
	return Vector2i(int(_delivered_crates.get(code, 0)), order.crates)


func paid_for(code: int) -> float:
	return float(_paid.get(code, 0.0))


func total_paid() -> float:
	var sum := 0.0
	for code in _paid:
		sum += float(_paid[code])
	return sum


func delivered_count() -> int:
	var n := 0
	for code in _state:
		if _state[code] == State.DELIVERED:
			n += 1
	return n


func _unlock_dependents(code: int) -> void:
	for other in _catalogue:
		var order: Order = _catalogue[other]
		if order.requires == code and _state[other] == State.LOCKED:
			_state[other] = State.OFFERED


# --- Storage ------------------------------------------------------------
##
## Deliberately **uncapped**. Mac's call, 2026-08-31. The reason to consolidate
## stock in one place should be that you want it *here* rather than *there* -
## which is what the [[The-Lattice]] ladder is for - and not that a number ran
## out. A cap would turn a depot into inventory tetris and add a failure case
## with no good answer: where does an overflowing delivery go?

## What `facility_id` is holding, in the order it was put there. The array is
## live, so callers must not hold onto it across a deposit.
func stock_of(facility_id: String) -> Array[StoredItem]:
	if not _stock.has(facility_id):
		var fresh: Array[StoredItem] = []
		_stock[facility_id] = fresh
	return _stock[facility_id]


func stock_count(facility_id: String) -> int:
	return stock_of(facility_id).size()


func stock_mass(facility_id: String) -> float:
	var total := 0.0
	for item in stock_of(facility_id):
		total += item.mass
	return total


## Put something on the shelf.
func deposit(facility_id: String, item: StoredItem) -> void:
	if item == null:
		return
	stock_of(facility_id).append(item)
	stock_changed.emit(facility_id)


## Take item `index` off the shelf and hand it back, or null if there is no such
## item or it is not the player's to take.
func withdraw(facility_id: String, index: int) -> StoredItem:
	var shelf := stock_of(facility_id)
	if index < 0 or index >= shelf.size():
		return null
	var item: StoredItem = shelf[index]
	if not item.is_withdrawable():
		return null
	shelf.remove_at(index)
	stock_changed.emit(facility_id)
	return item


# --- Transfers ----------------------------------------------------------
##
## The Lattice's second rung. Coverage lets you *see* a linked facility's stock;
## this is asking for a piece of it, and waiting.
##
## It costs time and nothing else - Mac's call, 2026-08-31. Time is enough,
## because the duration scales with distance and is deliberately slower than
## driving: a transfer is the patient option, never the efficient one. If the
## network ever beat the rover, the rover would be a worse vehicle than a menu.

func _process(delta: float) -> void:
	if _transfers.is_empty():
		return
	var landed := false
	for i in range(_transfers.size() - 1, -1, -1):
		var transfer: Transfer = _transfers[i]
		transfer.remaining -= delta
		if transfer.remaining > 0.0:
			continue
		_transfers.remove_at(i)
		deposit(transfer.to_id, transfer.item)
		landed = true
		print("LATTICE: %s arrived at %s from %s"
			% [transfer.item.cargo_name, transfer.to_id, transfer.from_id])
	if landed:
		transfer_changed.emit(true)


## How long the network would take to move something `from_id` to `to_id`, or
## -1 if it could not.
func transfer_seconds(from_id: String, to_id: String) -> float:
	if from_id == to_id or not Lattice.are_linked(from_id, to_id):
		return -1.0
	var distance := Lattice.distance_between(from_id, to_id)
	if distance < 0.0:
		return -1.0
	return transfer_dispatch_s + distance / maxf(transfer_speed, 0.01)


## Ask the network to bring stock item `index` from `from_id` to `to_id`.
func request_transfer(from_id: String, to_id: String, index: int) -> bool:
	var seconds := transfer_seconds(from_id, to_id)
	if seconds < 0.0:
		return false
	var item := withdraw(from_id, index)
	if item == null:
		return false
	var transfer := Transfer.new()
	transfer.item = item
	transfer.from_id = from_id
	transfer.to_id = to_id
	transfer.remaining = seconds
	transfer.total = seconds
	_transfers.append(transfer)
	transfer_changed.emit(false)
	print("LATTICE: %s requested from %s to %s, %.0f s out"
		% [item.cargo_name, from_id, to_id, seconds])
	return true


## Everything in flight to `facility_id`, soonest first.
func inbound_to(facility_id: String) -> Array:
	var out: Array = []
	for transfer in _transfers:
		if transfer.to_id == facility_id:
			out.append(transfer)
	out.sort_custom(func(a, b) -> bool: return a.remaining < b.remaining)
	return out


func transfers_in_flight() -> int:
	return _transfers.size()


# --- Facilities ---------------------------------------------------------

## Facilities register on _ready() so the board can hand out crates and route
## deliveries without holding a NodePath to anything.
func register_facility(facility: Node) -> void:
	var id := String(facility.get("facility_id"))
	if id == "":
		printerr("ORDERS: a Facility registered with no facility_id")
		return
	if _facilities.has(id) and _facilities[id] != facility:
		printerr("ORDERS: two facilities both call themselves '%s'" % id)
	_facilities[id] = facility


func unregister_facility(facility: Node) -> void:
	var id := String(facility.get("facility_id"))
	if _facilities.get(id, null) == facility:
		_facilities.erase(id)


func facility(id: String) -> Node:
	return _facilities.get(id, null)


func facility_ids() -> Array:
	return _facilities.keys()


## Human-readable name for a facility id, falling back to the id itself so a
## board never shows a blank destination just because that end has not been
## built yet.
func facility_name(id: String) -> String:
	var node := facility(id)
	if node == null:
		return id
	var display := String(node.get("display_name"))
	return display if display != "" else id
