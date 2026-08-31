extends Area3D
class_name DeliveryPad
## Where a haul stops being cargo and starts being income.
##
## The pad exists so that [[Cargo]] condition has somewhere to be *read out*.
## Damage that is never scored is a hidden number, and a hidden number changes
## nobody's driving — so the pad is not decoration on the damage model, it is
## the half that makes the other half matter.
##
## **Cargo has to be taken off the rack and set down here.** That is not a rule
## written anywhere: a stowed crate sits on collision layer 0 so the camera
## spring arm ignores the tower on the astronaut's back, which means an Area3D
## cannot see it either. Driving a loaded rover across the pad delivers nothing,
## and unloading is a deliberate act. The same accident that fixed the camera
## gives us the depot.

## Emitted once per crate, the moment it is accepted.
signal delivered(crate: Crate, payout: float)

## What a pristine crate is worth when it carries no price of its own. Order
## cargo is priced by data/orders.tsv and ignores this; a crate found lying in
## the world falls back to it. Placeholder units — the economy has no name yet,
## so the HUD just says "cr".
@export var base_value := 120.0

## How hard damage bites the payout. 1.0 is linear; above that, a scuffed crate
## loses more than its condition suggests, which is what makes "arrive slowly"
## a real strategy rather than a stylistic preference.
@export_range(0.5, 4.0) var payout_exponent := 1.5

## A crate still moving faster than this has not been *delivered*, it is passing
## through. Stops a crate bouncing across the pad from counting.
@export var settle_speed := 1.5

var total_paid := 0.0
var delivered_count := 0
## The Facility this pad belongs to, or null for a standalone pad. Resolved on
## ready by walking up, so a pad dropped into a scene on its own still works —
## it just accepts anything, having no address to check against.
var _facility: Node = null
## Crates already accepted, so a delivered crate lying on the pad is not paid
## for every physics frame for the rest of the session.
var _accepted: Dictionary = {}
## The most recent delivery, for the HUD to display. Empty until the first one.
var _last_line := ""
var _last_at := 0.0


func _ready() -> void:
	add_to_group("delivery")
	monitoring = true
	_facility = _find_facility()


func _find_facility() -> Node:
	var node := get_parent()
	while node != null:
		if node is Facility:
			return node
		node = node.get_parent()
	return null


## The id this pad delivers to, or "" if it is not part of a facility.
func facility_id() -> String:
	return String(_facility.get("facility_id")) if _facility != null else ""


func _physics_process(_delta: float) -> void:
	# Swept rather than driven by body_entered, so a crate that is unstowed
	# while already standing on the pad, or dropped in before the pad was
	# ready, is still seen. Area3D overlap lists only refresh on a physics
	# step, which is exactly the rate this runs at.
	for body in get_overlapping_bodies():
		var crate := body as Crate
		if crate == null or _accepted.has(crate.get_instance_id()):
			continue
		if crate.is_stowed():
			continue
		if crate.linear_velocity.length() > settle_speed:
			continue
		if not accepts(crate):
			continue
		_accept(crate)


## Whether this pad will take `crate`.
##
## Order cargo is only cargo *here* if this is where it was addressed. Setting a
## crate down at the wrong facility has to do nothing at all, or the destination
## column in data/orders.tsv means nothing and every order is a delivery to the
## nearest pad.
func accepts(crate: Crate) -> bool:
	var code := crate.order_code()
	if code == 0:
		return true
	var order := Orders.get_order(code)
	if order == null:
		return true
	if not Orders.is_accepted(code):
		return false
	var here := facility_id()
	return here == "" or order.destination == here


func _accept(crate: Crate) -> void:
	var payout := payout_for(crate)
	_accepted[crate.get_instance_id()] = true
	total_paid += payout
	delivered_count += 1
	var code := crate.order_code()
	var closed := Orders.deliver_crate(code, payout) if code != 0 else false
	_last_line = "%s delivered — %s — %.0f cr" % [
		crate.cargo_name, crate.condition_label(), payout
	]
	if code != 0:
		var progress := Orders.progress(code)
		_last_line = "Order %d · %s" % [code, _last_line]
		if not closed:
			_last_line += "   (%d of %d)" % [progress.x, progress.y]
	_last_at = Time.get_ticks_msec() / 1000.0
	print("DELIVERY: %s (condition %.2f) pays %.0f cr; %d delivered, %.0f cr total"
		% [crate.cargo_name, crate.condition, payout, delivered_count, total_paid])
	if closed:
		print("ORDER %d complete." % code)
	delivered.emit(crate, payout)


## What this crate would pay right now. Public so the HUD can warn the player
## what a damaged crate is about to cost them *before* they set it down.
##
## The crate's own value wins when it has one — order cargo is priced by the
## row that created it, so the same pad pays differently for different jobs.
func payout_for(crate: Crate) -> float:
	var full := crate.value if crate.value > 0.0 else base_value
	return full * pow(clampf(crate.condition, 0.0, 1.0), payout_exponent)


## The last delivery line, for `seconds` after it happened. Empty once stale.
func recent_delivery(seconds := 6.0) -> String:
	if _last_line == "":
		return ""
	if Time.get_ticks_msec() / 1000.0 - _last_at > seconds:
		return ""
	return _last_line
