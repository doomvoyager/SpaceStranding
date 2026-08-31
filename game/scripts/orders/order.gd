extends RefCounted
class_name Order
## One row of data/orders.tsv, parsed.
##
## An order is a **named crate**, not a requirement to be filled from stock:
## accepting 217 spawns 217's boxes and they carry the code for the rest of
## their lives. See docs/02-Systems/Orders.md.
##
## This is the authored half only. Whether an order is offered, accepted or
## delivered is runtime state and lives in OrderBook, keyed by `code` — nothing
## here is ever written to, because nothing in data/orders.tsv is ever written
## to.

## Cargo contents. Deliberately not "may the player use it" — that is
## ownership, which is a different axis and lives on the crate.
enum Kind { MATERIALS, UPGRADE, SAMPLE, PERSONAL }

## An origin of `world` means the crates are authored into the scene rather
## than spawned on a dock. The row still supplies everything else about them.
const WORLD := "world"

var code := 0
var title := ""
var origin := ""
var destination := ""
var kind := Kind.MATERIALS
var crates := 1
var mass_kg := 35.0
var fragility := 1.0
var value := 120.0
## Parked. Always 0 — see the preamble in data/orders.tsv.
var deadline_s := 0.0
## Code that must be delivered before this is offered, or 0.
var requires := 0
var issuer := ""
var blurb := ""


## Build one from a header-keyed row. Returns null and appends to `problems` if
## the row cannot be trusted — a bad row is dropped loudly rather than silently
## becoming an order with a zero code that shadows another.
static func from_row(row: Dictionary, problems: Array[String]) -> Order:
	var order := Order.new()
	order.code = int(row.get("code", "0"))
	if order.code < 100 or order.code > 999:
		problems.append("code '%s' is not in 100-999" % row.get("code", ""))
		return null

	order.title = String(row.get("title", "")).strip_edges()
	order.origin = String(row.get("origin", "")).strip_edges()
	order.destination = String(row.get("destination", "")).strip_edges()
	if order.origin == "":
		problems.append("%d has no origin" % order.code)
		return null
	if order.destination == "":
		problems.append("%d has no destination" % order.code)
		return null
	if order.origin == order.destination:
		problems.append("%d is addressed to its own origin (%s)" % [order.code, order.origin])
		return null

	var kind_text := String(row.get("type", "materials")).strip_edges().to_lower()
	if not KIND_NAMES.has(kind_text):
		problems.append("%d has unknown type '%s'" % [order.code, kind_text])
		return null
	order.kind = KIND_NAMES[kind_text]

	order.crates = maxi(int(row.get("crates", "1")), 1)
	order.mass_kg = maxf(float(row.get("mass_kg", "35")), 0.1)
	order.fragility = clampf(float(row.get("fragility", "1")), 0.0, 4.0)
	order.value = maxf(float(row.get("value", "0")), 0.0)
	order.deadline_s = maxf(float(row.get("deadline_s", "0")), 0.0)
	order.requires = int(row.get("requires", "0"))
	order.issuer = String(row.get("issuer", "")).strip_edges()
	order.blurb = String(row.get("blurb", "")).strip_edges()
	return order


const KIND_NAMES := {
	"materials": Kind.MATERIALS,
	"upgrade": Kind.UPGRADE,
	"sample": Kind.SAMPLE,
	"personal": Kind.PERSONAL,
}


## Cargo that is already in the world rather than spawned on a dock.
func is_loose() -> bool:
	return origin == WORLD


func kind_label() -> String:
	match kind:
		Kind.UPGRADE:
			return "upgrade"
		Kind.SAMPLE:
			return "sample"
		Kind.PERSONAL:
			return "personal"
		_:
			return "materials"


## What the whole order weighs, for the board's summary line.
func total_mass() -> float:
	return mass_kg * crates


func total_value() -> float:
	return value * crates


## The word the board shows for how delicate this is. Same job as
## Crate.label_for(): the player should be reading the cargo, not a number.
func fragility_label() -> String:
	if fragility <= 0.3:
		return "rugged"
	elif fragility <= 0.8:
		return "sturdy"
	elif fragility <= 1.3:
		return "standard"
	elif fragility <= 2.0:
		return "delicate"
	return "fragile"
