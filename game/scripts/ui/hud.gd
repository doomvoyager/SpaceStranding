extends CanvasLayer
class_name HUD
## Traversal-slice HUD: a static controls card, two context prompts that say
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

@onready var _interact_label: Label = $Prompts/Interact
@onready var _cargo_label: Label = $Prompts/Cargo
@onready var _delivery_label: Label = $Prompts/Delivery
@onready var _load_label: Label = $Prompts/Load

var _astronaut: Astronaut
var _rover: Rover
var _pad: DeliveryPad


func _ready() -> void:
	_astronaut = get_node_or_null(astronaut_path) as Astronaut
	if _astronaut == null:
		_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_rover = get_node_or_null(rover_path) as Rover
	if _rover == null:
		_rover = get_tree().get_first_node_in_group("rover") as Rover
	_pad = _find_pad()


func _process(_delta: float) -> void:
	if _astronaut == null:
		return
	_show_prompt(_interact_label, "E / A", _astronaut.interact_prompt())
	_show_prompt(_cargo_label, "F / X", _astronaut.cargo_prompt())
	_load_label.text = _load_text()
	# Resolved lazily as well as on ready: pads are world content, and a
	# settlement that streams in after the HUD would otherwise never be seen.
	if _pad == null:
		_pad = _find_pad()
	var receipt := _pad.recent_delivery() if _pad != null else ""
	_delivery_label.visible = receipt != ""
	if _delivery_label.visible:
		_delivery_label.text = receipt


## TODO: there will be a pad per settlement. Then this has to become "the pad
## the player is standing at", not the first one in the group.
func _find_pad() -> DeliveryPad:
	var pad := get_node_or_null(pad_path) as DeliveryPad
	if pad != null:
		return pad
	return get_tree().get_first_node_in_group("delivery") as DeliveryPad


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
	if _pad != null and _pad.delivered_count > 0:
		parts.append("%d delivered · %.0f cr" % [_pad.delivered_count, _pad.total_paid])
	return "     ".join(parts)


## "Rover 3/6 · scuffed" — the condition shown is the *worst* crate aboard,
## because a load is only as good as the item that arrives broken.
func _rack_text(rack: CargoRack) -> String:
	var text := "%s %d/%d" % [rack.rack_name, rack.count(), rack.capacity()]
	if rack.is_empty():
		return text
	return "%s · %s" % [text, Crate.label_for(rack.worst_condition())]
