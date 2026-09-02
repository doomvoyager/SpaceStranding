extends Label3D
class_name SiteSign
## The name floating over a facility or a relay, and what a scan pulse does
## with it. See [[Scanner]].
##
## **It is a scan result, not scenery.** The sign used to hang there
## permanently, big enough to read from across the Verge — which worked while
## there were two facilities on an empty plain and stopped working the moment
## the world had things in it. A name burning over every site at all times is
## the map drawn on the world, and it flattens exactly the thing this game is
## about: not knowing what is over the ridge until you go and look.
##
## So it is dark until `Q`, and then it is the *site's* scan tag — the same
## reveal the crates and terminals get, moved up to the mast and given four
## times the range, because a facility is the one thing worth finding from
## further away than the pulse itself travels.
##
## **This replaces the scanner's own facility tag.** `Scanner.tag_groups` no
## longer lists `facility` or `relay`; if it did, a site inside the pulse's
## reach would be named twice — once here at the mast and once seven metres
## below at ground level. The close-range parts of a facility (terminal, dock,
## storage, pad) are still tagged by the scanner, which is the reading that
## matters once you have arrived.
##
## **The mast point is this node.** `Facility.mast_point()` returns the sign's
## global position, because the sign is already the highest authored thing on a
## facility and moves with it. Hiding a node does not move it, so the lattice is
## unaffected by any of the above — but *moving* the sign moves the aerial, and
## that is worth knowing before nudging it in the inspector.

## Metres a ping will light this sign from. Deliberately well past
## `Scanner.reach`: the wave is a survey of the ground you are about to drive
## over, and this is the answer to "where am I going", which is a longer
## question. The pulse never physically reaches a sign at 200 m — it lights when
## the front hits its own limit, which reads as the return coming back.
@export_range(10.0, 1000.0, 5.0) var sign_range := 200.0

## Whether the sign carries how far off the site is, recomputed every frame
## against where the player is *now*. Same rule as a scan tag: the reveal is
## anchored to the ping, the number is not, so it counts down as you approach.
@export var show_distance := true

## Seconds the sign takes to come up once the wave reaches it. Short, but not
## zero — an instant switch reads as a bug in the pulse rather than as part of
## it.
@export_range(0.0, 2.0, 0.05) var fade_in := 0.3

## What the sign says, before any distance is appended.
##
## A facility writes its `display_name` here in `_ready()`, so renaming a
## facility renames its sign and the two cannot disagree. A relay authors it in
## the scene. Setting `text` directly still works and is what the inspector
## shows, but it will be overwritten on the next frame the sign is lit.
@export var site_name := "":
	set(v):
		site_name = v
		if not _lit:
			text = v

## Fallbacks for the pulse envelope, used only when there is no scanner in the
## scene to read the real ones off. Matched to `scanner.gd`'s own defaults.
const FALLBACK_HOLD := 4.0
const FALLBACK_FADE := 2.5
const FALLBACK_ARRIVAL := 70.0 / 95.0

var _scanner: Node
## The alpha the sign was authored with. The reveal scales this rather than
## replacing it, so a sign deliberately set to sit back at 0.85 does not come
## up at full strength the moment it is driven by code.
var _base_alpha := 1.0
## Seconds since the ping that lit this sign, or -1 when it is dark.
var _since_ping := -1.0
## Whether the last ping was close enough to light this sign at all.
var _lit := false
## Seconds after the ping before the wave front reaches us.
var _delay := 0.0
## How far up the reveal envelope the sign is, 0 to 1. Held separately from
## `modulate.a`, which carries the authored alpha folded in and so is not the
## question anything wants to ask.
var _strength_now := 0.0


func _ready() -> void:
	add_to_group("site_sign")
	_base_alpha = modulate.a
	# The authored text is the name unless something sets one. Captured rather
	# than assumed, so a sign dropped into a scene with its text typed in still
	# says the right thing.
	if site_name == "":
		site_name = text
	_darken()


func _process(delta: float) -> void:
	_find_scanner()
	if not _lit:
		return
	_since_ping += delta
	# **Not yet arrived is not the same as over**, and both read as zero
	# strength. Collapsing the two darkened the sign on the first frame after
	# every ping - the wave had not reached it, so it was dim, so the reveal
	# was declared spent, so it never came up at all. Nothing errored; a 200 m
	# sign simply behaved like a 0 m one.
	if _since_ping < _delay:
		return
	var envelope := _envelope()
	if envelope <= 0.0:
		_darken()
		return
	var strength := envelope
	if fade_in > 0.0:
		strength = clampf(minf(envelope, (_since_ping - _delay) / fade_in),
			0.0, 1.0)
	if strength <= 0.0:
		return
	visible = true
	_strength_now = strength
	modulate.a = strength * _base_alpha
	text = _readout()


## Light the sign as though a pulse had just swept over it. For capture scenes
## and tests, which need it up without a scanner and a player to fire one.
func reveal() -> void:
	_lit = true
	_since_ping = 0.0
	_delay = 0.0
	visible = true
	modulate.a = 0.0
	text = _readout()


## Whether the sign is currently showing. `visible` alone is the honest answer
## because nothing else hides it — but this is what tests should ask, so the
## question stays the same if that ever stops being true.
func is_lit() -> bool:
	return _lit and visible


## How far up the reveal envelope the sign is, 0 to 1. Diagnostics and tests.
## Not `modulate.a`, which has the authored alpha folded into it.
func strength() -> float:
	return _strength_now if _lit and visible else 0.0


# --- The pulse ----------------------------------------------------------

## Connected lazily: the scanner is a sibling somewhere in the scene and neither
## node can count on the other existing when it readies. Same shape as
## `route_marks.gd`, for the same reason.
func _find_scanner() -> Node:
	if _scanner == null or not is_instance_valid(_scanner):
		_scanner = get_tree().get_first_node_in_group("scanner")
		if _scanner != null and _scanner.has_signal("pinged") \
				and not _scanner.is_connected("pinged", _on_ping):
			_scanner.connect("pinged", _on_ping)
	return _scanner


## Measured from the site, not from the sign. The sign is eight metres up a
## mast, and a facility you are standing next to should not read as further off
## than one you are not.
func _site_position() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.global_position if parent != null else global_position


func _on_ping(origin: Vector3) -> void:
	var away := origin.distance_to(_site_position())
	if away > sign_range:
		# Not "leave the old reveal running": a ping you fired somewhere else
		# should take down what the last one put up.
		_darken()
		return
	_lit = true
	_since_ping = 0.0
	# The front sweeps out at wave_speed and stops at reach. A sign past that
	# lights when the wave hits its limit rather than never, which is what makes
	# 200 m of range possible on a 70 m pulse.
	var reach := 70.0
	var speed := 95.0
	var scanner := _find_scanner()
	if scanner != null:
		reach = float(scanner.get("reach"))
		speed = maxf(float(scanner.get("wave_speed")), 0.01)
	_delay = minf(away, reach) / speed
	visible = false
	modulate.a = 0.0


## How much life the pulse has left, 0 to 1, before this sign's own fade-in is
## folded in.
##
## Matched to the scanner's own envelope rather than given its own timing, so
## every sign goes out with the pulse and with the tags, on the same frame.
## Read off the scanner's exports because it does not publish a strength.
##
## Measured from the ping and not from `_delay`, which is what keeps a sign at
## 200 m and one at 10 m going dark together rather than trailing each other.
func _envelope() -> float:
	if _since_ping < 0.0:
		return 0.0
	var arrival := FALLBACK_ARRIVAL
	var hold := FALLBACK_HOLD
	var fade := FALLBACK_FADE
	var scanner := _find_scanner()
	if scanner != null:
		arrival = float(scanner.get("reach")) \
			/ maxf(float(scanner.get("wave_speed")), 0.01)
		hold = float(scanner.get("hold"))
		fade = maxf(float(scanner.get("fade")), 0.01)
	if _since_ping <= arrival + hold:
		return 1.0
	return clampf(1.0 - (_since_ping - arrival - hold) / fade, 0.0, 1.0)


## The name, and how far off the site is from where the player is standing now.
func _readout() -> String:
	if not show_distance:
		return site_name
	var away := _viewer_position().distance_to(_site_position())
	return "%s · %d m" % [site_name, int(round(away))]


## Where the player actually is — the rover when they are driving it, the
## astronaut when they are not. Asked of the scanner rather than worked out
## again here: a second copy of that rule is exactly the bug `Astronaut
## .vantage()` exists to have only once.
##
## Duck-typed, like `route_marks.gd` and `lattice.gd` before it. Naming the
## `Scanner` type here would close a `class_name` cycle — the scanner already
## refers to `Facility`, and the facility now refers to this script.
##
## The camera fallback is for a capture scene lit by `reveal()` with no scanner
## in it. There is no third case: without a scanner nothing can fire a ping.
func _viewer_position() -> Vector3:
	var scanner := _find_scanner()
	if scanner != null:
		return scanner.call("viewer_position")
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else global_position


func _darken() -> void:
	_lit = false
	_since_ping = -1.0
	_strength_now = 0.0
	visible = false
	modulate.a = 0.0
	text = site_name
