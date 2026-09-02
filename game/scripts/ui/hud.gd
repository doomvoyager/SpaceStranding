extends CanvasLayer
class_name HUD
## Traversal-slice HUD: a controls card on `H`, two context prompts that say
## exactly what the two action keys would do right now, a load readout, and a
## delivery banner.
##
## The HUD asks the astronaut what it would do rather than working it out for
## itself. Interaction rules live in one place — astronaut.gd — and the HUD can
## never disagree with what the key actually does. Cargo condition works the
## same way: the words come from Crate.label_for(), so the HUD and the delivery
## receipt can never grade the same crate differently.

## Leave empty to find them by group ("player" / "rover" / "delivery").
@export var astronaut_path: NodePath
@export var rover_path: NodePath
@export var pad_path: NodePath

@export_group("Controls card")
## Whether the reference card starts visible. `H` (or the pad's Back button)
## toggles it either way.
##
## An export rather than a hardcoded default because it is a preference, and
## because the person most likely to want it off every time is the one with the
## inspector open. It is also on the F1 panel, so it can be flipped mid-session.
@export var show_controls_on_start := true

@export_group("Survey")
## Seconds between site surveys while carrying a mast.
##
## Deliberately coarse. A survey is a handful of line-of-sight walks over the
## heightfield, which is cheap enough to run every frame — but a readout that
## updates every frame stops reading as an instrument and starts reading as a
## compass needle pointing at the answer, and following a gradient is not the
## same activity as choosing a site. Four times a second is fast enough to feel
## live and slow enough to make you stand still and look.
@export_range(0.05, 2.0, 0.05) var survey_interval := 0.25

@onready var _interact_label: Label = $Prompts/Interact
@onready var _cargo_label: Label = $Prompts/Cargo
@onready var _delivery_label: Label = $Prompts/Delivery
@onready var _load_label: Label = $Prompts/Load
@onready var _manifest_label: Label = $Prompts/Manifest
@onready var _raise_label: Label = $Prompts/Raise
@onready var _survey_label: Label = $Prompts/Survey
@onready var _controls_card: Control = $Controls

var _astronaut: Astronaut
var _rover: Rover
## Last survey, and when it was taken. Held rather than recomputed per frame
## so the readout has something to show between refreshes.
var _survey: SiteSurvey
var _since_survey := 0.0


func _ready() -> void:
	add_to_group("hud")
	_astronaut = get_node_or_null(astronaut_path) as Astronaut
	if _astronaut == null:
		_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_rover = get_node_or_null(rover_path) as Rover
	if _rover == null:
		_rover = get_tree().get_first_node_in_group("rover") as Rover
	_controls_card.visible = show_controls_on_start


## Handled here rather than in the astronaut because the card is the HUD's, and
## because it should work while driving and while a panel is up — neither of
## which routes input through the astronaut.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_controls"):
		_controls_card.visible = not _controls_card.visible
		get_viewport().set_input_as_handled()


## The card's own state, for the F1 panel and for tests.
func controls_visible() -> bool:
	return _controls_card.visible


## The survey line as the player sees it, or "" when it is not on screen.
## For tests: a readout that is correct and never shown is the failure mode
## this project keeps meeting, and only the visibility half is easy to miss.
func survey_readout() -> String:
	return _survey_label.text if _survey_label.visible else ""


func _process(delta: float) -> void:
	if _astronaut == null:
		return
	# A panel owns the whole screen while it is up, and a controls card floating
	# over it would just be noise.
	_tick_survey(delta)
	var menu := _astronaut.is_menu_open()
	_hide_all() if menu else _draw()


## Only the context prompts go away behind a panel. The controls card is not a
## prompt — it does not describe the moment, it describes the game — so it keeps
## whatever state the player put it in.
func _hide_all() -> void:
	for label in [_interact_label, _cargo_label, _delivery_label, _load_label,
			_manifest_label, _survey_label, _raise_label]:
		label.visible = false


func _draw() -> void:
	_show_prompt(_interact_label, "E / A", _astronaut.interact_prompt())
	_show_prompt(_cargo_label, "F / X", _astronaut.cargo_prompt())
	_show_prompt(_raise_label, "R / Y", _astronaut.raise_prompt())
	_load_label.visible = true
	_load_label.text = _load_text()
	var manifest := _manifest_text()
	_manifest_label.visible = manifest != ""
	if _manifest_label.visible:
		_manifest_label.text = manifest
	_survey_label.visible = _survey != null and _astronaut.carried_deployable() != null
	if _survey_label.visible:
		_survey_label.text = _survey.summary()

	var receipt := _recent_receipt()
	_delivery_label.visible = receipt != ""
	if _delivery_label.visible:
		_delivery_label.text = receipt


## The receipt from whichever pad last took something, not the first pad in the
## tree — which is what this used to do and which showed Hearth's receipt for a
## crate set down at Longshadow. A receipt goes stale in a few seconds, so at
## most one is live and "the first live one" is the pad you are standing at.
##
## An explicit `pad_path` still wins, for a scene that wants to pin it.
func _recent_receipt() -> String:
	var pinned := get_node_or_null(pad_path) as DeliveryPad
	if pinned != null:
		return pinned.recent_delivery()
	for node in get_tree().get_nodes_in_group("delivery"):
		var pad := node as DeliveryPad
		if pad == null:
			continue
		var line := pad.recent_delivery()
		if line != "":
			return line
	return ""


## What is owed, and to whom. Keeps the order visible while driving, so nobody
## has to remember which pad a crate is addressed to.
func _manifest_text() -> String:
	var lines := PackedStringArray()
	for order in Orders.accepted_orders():
		var progress := Orders.progress(order.code)
		var line := "%d  %s → %s" % [
			order.code, order.title, Orders.facility_name(order.destination)
		]
		if progress.y > 1:
			line += "  (%d/%d)" % [progress.x, progress.y]
		lines.append(line)
	return "
".join(lines)


func _show_prompt(label: Label, keys: String, action: String) -> void:
	label.visible = action != ""
	if label.visible:
		label.text = "%s   %s" % [keys, action]


func _load_text() -> String:
	var parts := PackedStringArray()
	parts.append(_rack_text(_astronaut.back_rack()))
	if _rover != null:
		var rack := _rover.cargo_rack()
		parts.append(_rack_text(rack))
		var cargo := rack.load_mass()
		if cargo > 0.0:
			parts.append("%.0f kg" % cargo)
	# Earnings are the player's, not a pad's. Reading them off one pad meant the
	# total reset the moment you delivered somewhere else.
	if Orders.delivered_count() > 0:
		parts.append("%d orders · %.0f cr" % [Orders.delivered_count(), Orders.total_paid()])
	return "     ".join(parts)


## "Rover 3/6 · scuffed" — the condition shown is the *worst* crate aboard,
## because a load is only as good as the item that arrives broken.
func _rack_text(rack: CargoRack) -> String:
	var text := "%s %d/%d" % [rack.rack_name, rack.count(), rack.capacity()]
	if rack.is_empty():
		return text
	return "%s · %s" % [text, Crate.label_for(rack.worst_condition())]



## Re-survey the ground underfoot, at most every `survey_interval` seconds and
## only while there is a mast on the astronaut's back.
##
## The survey is of where the *player* stands, not where they are looking. A
## mast is raised at your feet, so answering for anywhere else would be telling
## you about a spot you cannot use.
func _tick_survey(delta: float) -> void:
	if _astronaut.carried_deployable() == null:
		_survey = null
		_since_survey = 0.0
		return
	_since_survey -= delta
	if _survey != null and _since_survey > 0.0:
		return
	_since_survey = survey_interval
	var at := _astronaut.global_position
	_survey = Lattice.survey_at(at.x, at.z)