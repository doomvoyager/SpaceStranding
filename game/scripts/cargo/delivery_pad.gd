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

## What a pristine crate of this kind is worth. Placeholder units — the economy
## has no name yet, so the HUD just says "cr".
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
## Crates already accepted, so a delivered crate lying on the pad is not paid
## for every physics frame for the rest of the session.
var _accepted: Dictionary = {}
## The most recent delivery, for the HUD to display. Empty until the first one.
var _last_line := ""
var _last_at := 0.0


func _ready() -> void:
	add_to_group("delivery")
	monitoring = true


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
		_accept(crate)


func _accept(crate: Crate) -> void:
	var payout := payout_for(crate)
	_accepted[crate.get_instance_id()] = true
	total_paid += payout
	delivered_count += 1
	_last_line = "%s delivered — %s — %.0f cr" % [
		crate.cargo_name, crate.condition_label(), payout
	]
	_last_at = Time.get_ticks_msec() / 1000.0
	print("DELIVERY: %s (condition %.2f) pays %.0f cr; %d delivered, %.0f cr total"
		% [crate.cargo_name, crate.condition, payout, delivered_count, total_paid])
	delivered.emit(crate, payout)


## What this crate would pay right now. Public so the HUD can warn the player
## what a damaged crate is about to cost them *before* they set it down.
func payout_for(crate: Crate) -> float:
	return base_value * pow(clampf(crate.condition, 0.0, 1.0), payout_exponent)


## The last delivery line, for `seconds` after it happened. Empty once stale.
func recent_delivery(seconds := 6.0) -> String:
	if _last_line == "":
		return ""
	if Time.get_ticks_msec() / 1000.0 - _last_at > seconds:
		return ""
	return _last_line
