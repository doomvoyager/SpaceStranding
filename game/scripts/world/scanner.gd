extends Node3D
class_name Scanner
## The survey pulse. `Q` / `LB`.
##
## One ping goes out as an expanding ring. Ground it has passed keeps a dot grid
## coloured by **whether the rover could drive it** — green flat, red steep —
## and anything usable it sweeps over gets a tag: cargo, terminals, docks,
## storage, pads, relays, the rover itself.
##
## Two decisions worth stating, because they are not obvious from the code:
##
## **The pulse goes out from the player, and the labels measure from the player
## *now*.** Two different positions, and both were wrong to begin with.
##
## The origin cannot be the astronaut's node, because boarding the rover hides
## it and leaves it where it stood - scanning from the driver's seat would ping
## a spot in the sand behind you. It was the camera for a while, which fixed
## that but sat six metres back on the chase arm, so every distance read long.
## `viewer_position()` answers properly: the rover when someone is driving it,
## the astronaut otherwise.
##
## And the distance on a tag is recomputed against where you are *this frame*,
## not against where the ping went out. Only the reveal geometry stays anchored
## to the origin - what the wave has swept over is a fact about the ping, and
## letting it chase the player would mean walking forward kept uncovering things
## the pulse had already passed.
##
## **The look lives here, not in the material.** Every tunable below is pushed
## into the shader's global uniforms on change. A ShaderMaterial's uniforms
## carry PROPERTY_USAGE_EDITOR but not PROPERTY_USAGE_SCRIPT_VARIABLE, so the F1
## panel cannot see them — and a number nobody can move while driving is a
## number nobody will tune. See docs/02-Systems/Scanner.md.

## A pulse went out from `origin`.
signal pinged(origin: Vector3)

@export_group("Pulse")
## How far the wave reaches, metres. Also the tag range.
@export_range(10.0, 300.0, 1.0) var reach := 70.0:
	set(v):
		reach = v
		_push()

## Metres of the outer edge over which the grid thins to nothing.
##
## Without it the scanned area ends on a hard circle - the wave front softens as
## it travels, but ground it has already passed stays at full strength right up
## to `reach` and then stops. Fading the ring by the same term is what makes the
## front *dissolve* on its way out rather than arrive and switch off.
##
## Clamped against `reach` when pushed, so a fade wider than the range cannot
## make the grid invisible everywhere.
@export_range(0.0, 120.0, 0.5) var edge_fade := 22.0:
	set(v):
		edge_fade = v
		_push()

## Metres per second the front travels. Slow enough to read as a wave going out
## rather than a light switch.
@export_range(10.0, 400.0, 1.0) var wave_speed := 95.0:
	set(v):
		wave_speed = v
		_push()

## Seconds the grid stays at full strength after the wave reaches its limit.
@export_range(0.0, 30.0, 0.1) var hold := 4.0

## Seconds the grid takes to fade out after the hold.
@export_range(0.1, 20.0, 0.1) var fade := 2.5

## Shortest gap between pings. Stops the whole world strobing on a held key.
@export_range(0.0, 10.0, 0.1) var cooldown := 0.7

@export_group("Grid")
## Metres between dots.
@export_range(0.2, 8.0, 0.05) var dot_spacing := 0.6134:
	set(v):
		dot_spacing = v
		_push()

## Dot radius as a fraction of the spacing.
@export_range(0.02, 0.5, 0.01) var dot_size := 0.06704:
	set(v):
		dot_size = v
		_push()

## How hard the dots emit.
##
## Not a free dial. The scene tonemaps with ACES, which clamps saturated colour
## hardest exactly where it is brightest — so the first version emitted at 1.5
## and produced a grid of *white* dots carrying no slope information whatever.
## Measured by `tests/probe_scan_glow.tscn`, which renders the same frame at a
## range of values so the point where green stops being green is visible rather
## than argued about.
@export_range(0.05, 3.0, 0.05) var glow := 1.94095:
	set(v):
		glow = v
		_push()

## Thickness of the bright leading ring, metres.
@export_range(0.2, 20.0, 0.1) var ring_width := 2.5:
	set(v):
		ring_width = v
		_push()

@export var easy_color := Color(0.32, 1.0, 0.55):
	set(v):
		easy_color = v
		_push()

@export var hard_color := Color(1.0, 0.29, 0.26):
	set(v):
		hard_color = v
		_push()

## Slope, in degrees, that reads as fully red.
##
## **Measured, not chosen.** `tests/probe_rover_climb.tscn` puts the loaded
## rover on slopes of known angle at full throttle and reports how far it gets
## up each in a fixed run, against the same run on the flat:
##
## | slope | up-slope in 5 s | vs flat |
## |---|---|---|
## | 0° | 37.0 m | 100% |
## | 8° | 31.8 m | 86% |
## | 16° | 25.9 m | 70% |
## | 24° | 19.6 m | 53% |
## | 32° | 14.0 m | 38% |
## | 40° | 8.9 m | 24% |
## | 48° | 3.3 m | 9% |
## | 56° | −5.6 m | slides back |
##
## The rover does not *stall* anywhere useful — it slows, smoothly, until 56°
## where it slides backwards. So the threshold is where progress **halves**:
## 25.5°, rounded to 26. Red then means "this will cost you half your speed or
## worse", which is the honest thing a slope colour can promise. Any other
## number makes the scan a picture of steepness rather than an answer to "can I
## drive that".
@export_range(5.0, 60.0, 0.5) var max_slope_deg := 26.0:
	set(v):
		max_slope_deg = v
		_push()

@export_group("Obstacle outline")
## Colour of the silhouette drawn on rocks big enough to hit.
@export var outline_color := Color(1.0, 0.22, 0.18):
	set(v):
		outline_color = v
		_push()

## How hard the outline burns. Zero switches it off.
@export_range(0.0, 6.0, 0.05) var outline_strength := 1.6:
	set(v):
		outline_strength = v
		_push()

## How tightly the outline hugs the silhouette. Higher is a thinner line.
@export_range(0.5, 12.0, 0.1) var outline_power := 2.2:
	set(v):
		outline_power = v
		_push()

@export_group("Tags")
## Groups a node must be in to be worth tagging. Every one of these already
## exists for other reasons, so nothing has to be marked up twice.
## **Not `facility` or `relay`.** A site is named by its own mast sign, which
## is the same reveal moved up to the aerial and given four times this reach —
## see `site_sign.gd`. Tagging it here as well would label a nearby facility
## twice, once at the mast and once seven metres below it. The close-range parts
## of a facility are still listed, and are the reading that matters once you
## have arrived.
@export var tag_groups: Array[String] = [
	"cargo", "rover", "delivery", "terminal", "dock_deck", "storage_intake",
]

## Metres above a tagged node its label floats.
@export_range(0.0, 8.0, 0.1) var tag_lift := 1.4

@export_range(0.00005, 0.002, 0.00001) var tag_size := 0.00022

## Most tags on screen at once, nearest first.
##
## A scan that labels everything labels nothing: the first pass tagged all
## nineteen things in reach and six crates in a pile became one unreadable
## smear of overlapping text.
@export_range(1, 60, 1) var max_tags := 12

## Screen pixels a new tag must keep from every tag already placed. This is what
## actually fixes the pile — a cap alone still stacks the nearest six on top of
## each other.
@export_range(0.0, 400.0, 5.0) var tag_separation_px := 110.0

## Screen pixels a mast sign keeps from every other sign, and from every tag.
##
## Its own number rather than `tag_separation_px` because a sign is a much wider
## label — a site name plus a distance, where a tag is usually one short word —
## and because the two are looked at from different ranges. Measured off
## `previews/2026-09-02/signsize-0.00018_at_200m.png`, where LONGSHADOW and
## RELAY sat 145 px apart and overlapped outright: 200 is the first value that
## separates that frame.
##
## Zero switches the arbitration off, which is what the look-dev captures used
## to get by default.
@export_range(0.0, 500.0, 5.0) var sign_separation_px := 200.0

var _elapsed := -1.0
var _since_ping := 999.0
var _origin := Vector3.ZERO
## Live tags, one per tagged node. node -> Label3D.
var _tags: Dictionary = {}
## This frame's answer to "which mast signs have room on screen". SiteSign ->
## bool, rebuilt once a frame and then read by every sign that asks.
var _sign_slots: Dictionary = {}
## The process frame `_sign_slots` was built on, or -1.
var _sign_frame := -1
@onready var _tag_root := Node3D.new()


func _ready() -> void:
	add_to_group("scanner")
	add_child(_tag_root)
	_push()
	_set_pulse(-1.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	# Not from behind a full-screen panel. Q with the map open was firing a pulse
	# into a world nobody could see — harmless, and it burned the cooldown, so
	# the scan you wanted after closing the map did nothing.
	var player := get_tree().get_first_node_in_group("player") as Astronaut
	if player != null and player.is_menu_open():
		return
	if event.is_action_pressed("scan"):
		ping()
		get_viewport().set_input_as_handled()


## Where the player actually is: the rover when they are driving it, the
## astronaut when they are not, and the camera as a last resort so a test scene
## with neither still works.
##
## Public because it is the one answer to that question and other things need
## it — `site_sign.gd` measures a facility's distance from here rather than
## keeping a second copy of the rover-or-foot rule.
func viewer_position() -> Vector3:
	# Astronaut.vantage() answers the rover-or-foot question now, so this is not
	# a second copy of that rule. The camera fallback stays, for a test scene
	# with no player in it at all.
	var player := get_tree().get_first_node_in_group("player") as Astronaut
	if player != null:
		return player.vantage()
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else global_position


## Send a pulse from where the player is standing.
func ping() -> bool:
	if _since_ping < cooldown:
		return false
	if get_viewport().get_camera_3d() == null:
		return false
	_origin = viewer_position()
	_elapsed = 0.0
	_since_ping = 0.0
	_clear_tags()
	pinged.emit(_origin)
	return true


func is_running() -> bool:
	return _elapsed >= 0.0


## How far the wave front has travelled, or -1 when idle.
func radius() -> float:
	return -1.0 if _elapsed < 0.0 else minf(_elapsed * wave_speed, reach)


func _process(delta: float) -> void:
	_since_ping += delta
	if _elapsed < 0.0:
		return
	_elapsed += delta

	var travel := radius()
	var arrival := reach / maxf(wave_speed, 0.01)
	var strength := 1.0
	if _elapsed > arrival + hold:
		strength = 1.0 - (_elapsed - arrival - hold) / maxf(fade, 0.01)
	if strength <= 0.0:
		_elapsed = -1.0
		_set_pulse(-1.0, 0.0)
		_clear_tags()
		return

	_set_pulse(travel, strength)
	_reveal_tags(travel, strength)


func _set_pulse(travel: float, strength: float) -> void:
	RenderingServer.global_shader_parameter_set("scan_origin", _origin)
	RenderingServer.global_shader_parameter_set("scan_radius", travel)
	RenderingServer.global_shader_parameter_set("scan_strength", strength)


## Push the look. Called from every setter, so moving a slider on the F1 panel
## shows up on the next frame rather than the next ping.
func _push() -> void:
	if not is_inside_tree():
		return
	RenderingServer.global_shader_parameter_set("scan_ring_width", ring_width)
	RenderingServer.global_shader_parameter_set("scan_dot_spacing", dot_spacing)
	RenderingServer.global_shader_parameter_set("scan_dot_size", dot_size)
	RenderingServer.global_shader_parameter_set("scan_easy_color", easy_color)
	RenderingServer.global_shader_parameter_set("scan_hard_color", hard_color)
	RenderingServer.global_shader_parameter_set("scan_max_slope", max_slope_deg)
	RenderingServer.global_shader_parameter_set("scan_glow", glow)
	RenderingServer.global_shader_parameter_set("scan_reach", reach)
	# A fade wider than the reach would start below zero metres and dim the grid
	# everywhere, including underfoot.
	RenderingServer.global_shader_parameter_set(
		"scan_edge_fade", minf(edge_fade, reach * 0.9))
	RenderingServer.global_shader_parameter_set("scan_outline_color", outline_color)
	RenderingServer.global_shader_parameter_set(
		"scan_outline_strength", outline_strength)
	RenderingServer.global_shader_parameter_set("scan_outline_power", outline_power)


# --- Tags ---------------------------------------------------------------

## Everything worth tagging within reach, nearest first.
func taggable() -> Array[Node3D]:
	var seen := {}
	var out: Array[Node3D] = []
	for group in tag_groups:
		for node in get_tree().get_nodes_in_group(group):
			var spatial := node as Node3D
			if spatial == null or seen.has(spatial):
				continue
			# A stowed crate is inside something already tagged, and a tower of
			# labels on the rover's roof helps nobody.
			var crate := spatial as Crate
			if crate != null and crate.is_stowed():
				continue
			# Nor does a label on the vehicle you are sitting in, hanging in the
			# middle of your own windscreen.
			var rover := spatial as Rover
			if rover != null and rover.driver != null:
				continue
			seen[spatial] = true
			out.append(spatial)
	return out


func _reveal_tags(travel: float, strength: float) -> void:
	var camera := get_viewport().get_camera_3d()
	# Where the player is *now*, which is what a tag's distance should read.
	var viewer := viewer_position()
	# Nearest first, so when the budget runs out it is the far things that lose
	# their tag rather than whatever the group order happened to put first.
	var candidates := taggable()
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _origin.distance_squared_to(a.global_position) \
			< _origin.distance_squared_to(b.global_position))

	# Where every tag already sits on screen, so a new one can be refused a spot
	# that is already taken. Seeded with the mast signs, which are decided first
	# and outrank a tag: a site name is the thing you are scanning to find, and
	# `Dock  16 m` written through the middle of it helps nobody.
	var taken: Array[Vector2] = sign_points()
	for node in _tags:
		if is_instance_valid(node) and camera != null:
			taken.append(camera.unproject_position(_anchor(node)))

	for node in candidates:
		if not is_instance_valid(node):
			continue
		# Anchored to the ping, not to the player: what the wave has swept over
		# is a fact about where it was sent from.
		var swept := _origin.distance_to(node.global_position)
		if swept > reach or swept > travel:
			continue

		var label: Label3D = _tags.get(node, null)
		if label == null:
			if _tags.size() >= max_tags:
				continue
			var anchor := _anchor(node)
			if camera != null and camera.is_position_behind(anchor):
				continue
			if camera != null and not _has_room(
					camera.unproject_position(anchor), taken, tag_separation_px):
				continue
			label = _make_tag(node)
			_tags[node] = label
			if camera != null:
				taken.append(camera.unproject_position(anchor))

		label.global_position = _anchor(node)
		# `distance` above is from the origin and gates the sweep; what the
		# label says is measured from the viewer, every frame, so the number
		# counts down as you walk toward the thing.
		var away := viewer.distance_to(node.global_position)
		label.text = "%s   %d m" % [_describe(node), int(round(away))]
		label.modulate.a = strength


func _anchor(node: Node3D) -> Vector3:
	return node.global_position + Vector3.UP * tag_lift


func _has_room(at: Vector2, taken: Array[Vector2], separation: float) -> bool:
	for other in taken:
		if at.distance_to(other) < separation:
			return false
	return true


func _make_tag(node: Node3D) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = tag_size
	label.font_size = 128
	label.outline_size = 26
	label.modulate = _tint(node)
	label.outline_modulate = Color(0.03, 0.05, 0.06, 0.85)
	_tag_root.add_child(label)
	return label


## What to call the thing. Asks the node what it is rather than keeping a table
## of names here, so renaming a facility or a crate renames its tag.
func _describe(node: Node3D) -> String:
	var crate := node as Crate
	if crate != null:
		var code := crate.order_code()
		if code != 0:
			return "%s · %d" % [crate.cargo_name, code]
		return crate.cargo_name
	var facility := node as Facility
	if facility != null:
		return facility.display_name
	if node is Relay:
		return "Relay"
	if node is Rover:
		return "Rover"
	if node is DeliveryPad:
		return "Delivery pad"
	if node is FacilityTerminal:
		return "Terminal"
	if node.is_in_group("storage_intake"):
		return "Storage"
	if node.is_in_group("dock_deck"):
		return "Dock"
	return node.name


func _tint(node: Node3D) -> Color:
	if node is Crate:
		return Color(1.0, 0.78, 0.38, 1.0)
	if node is Facility or node is Relay:
		return Color(0.42, 0.88, 0.96, 1.0)
	if node is Rover:
		return Color(0.92, 0.94, 0.96, 1.0)
	return Color(0.62, 0.9, 0.78, 1.0)


# --- Mast signs ---------------------------------------------------------
#
# The signs are nodes in their own scenes and run their own reveal - see
# `site_sign.gd`. What they cannot do on their own is stand out of each other's
# way, because each one knows nothing about the others: three sites 60 m apart,
# seen from 200 m, wrote their names straight through one another.
#
# So the arbitration lives here, with the tags', and for the same reason. A sign
# *asks* rather than being told, which is what keeps it out of frame ordering:
# a flag pushed from here would be a frame stale by the time the sign drew, and
# the sign would spend that frame visible in a slot it had already lost.

## Whether `sign_node` has room to draw this frame. Called by the sign itself
## from its own `_process`, so the answer is current at the moment it is used.
##
## **A sign missing from this frame's answer forces a fresh one**, and that is
## not defensive coding — it is the whole correctness argument. The signs run
## their own clocks in their own `_process`, in tree order, and a sign crosses
## the threshold from "the wave has not reached me" to "I want to draw" during
## that pass. So the sign that ran first can have triggered the resolve while a
## later one still looked idle, leaving it absent from the answer it is about to
## consult. Absent read as "no reason to refuse you", so it drew — for exactly
## one frame, in a slot it had already lost, which is the flicker the arbitration
## exists to prevent. Recomputing with the asker present costs at most a couple
## of extra passes on the frame a name arrives.
func sign_has_room(sign_node: SiteSign) -> bool:
	_resolve_signs()
	if not _sign_slots.has(sign_node) and sign_node.is_revealing():
		_sign_frame = -1
		_resolve_signs()
	return bool(_sign_slots.get(sign_node, true))


## Screen positions of the signs that got a slot this frame.
func sign_points() -> Array[Vector2]:
	_resolve_signs()
	var camera := get_viewport().get_camera_3d()
	var out: Array[Vector2] = []
	if camera == null:
		return out
	for node in _sign_slots:
		var sign_node := node as SiteSign
		if sign_node != null and _sign_slots[node] and is_instance_valid(sign_node):
			out.append(camera.unproject_position(sign_node.global_position))
	return out


## Decide which signs get a slot. Once a frame, however many ask.
##
## **Ordered by distance from the ping, not from the player.** The origin does
## not move for the life of a pulse, so a name cannot swap places with its
## neighbour while you drive past — which is the whole point of arbitrating at
## all. It is the same anchor the tag reveal uses, for the same reason.
func _resolve_signs() -> void:
	var frame := Engine.get_process_frames()
	if frame == _sign_frame:
		return
	_sign_frame = frame
	_sign_slots.clear()
	var lit: Array[SiteSign] = []
	for node in get_tree().get_nodes_in_group("site_sign"):
		var sign_node := node as SiteSign
		if sign_node != null and sign_node.is_revealing():
			lit.append(sign_node)
	# Everyone in, and recorded as such. Bailing out with an empty dictionary
	# would work - a missing entry reads as "has room" - but it would leave
	# `sign_slot_count()` reporting nought of nought while two names were on
	# screen, which is a diagnostic that lies exactly when it is consulted.
	var camera := get_viewport().get_camera_3d()
	if camera == null or sign_separation_px <= 0.0:
		for sign_node in lit:
			_sign_slots[sign_node] = true
		return
	lit.sort_custom(func(a: SiteSign, b: SiteSign) -> bool:
		return _origin.distance_squared_to(a.global_position) 			< _origin.distance_squared_to(b.global_position))
	var taken: Array[Vector2] = []
	for sign_node in lit:
		if camera.is_position_behind(sign_node.global_position):
			_sign_slots[sign_node] = false
			continue
		var at := camera.unproject_position(sign_node.global_position)
		var room := _has_room(at, taken, sign_separation_px)
		_sign_slots[sign_node] = room
		if room:
			taken.append(at)


## How many signs are drawing this frame, and how many wanted to. Diagnostics
## and tests.
func sign_slot_count() -> Vector2i:
	_resolve_signs()
	var shown := 0
	for node in _sign_slots:
		if _sign_slots[node]:
			shown += 1
	return Vector2i(shown, _sign_slots.size())


func _clear_tags() -> void:
	for node in _tags:
		var label: Label3D = _tags[node]
		if is_instance_valid(label):
			label.queue_free()
	_tags.clear()


## Live tag count. Diagnostics and tests.
func tag_count() -> int:
	return _tags.size()
