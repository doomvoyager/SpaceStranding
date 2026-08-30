extends CanvasLayer
class_name HUD
## Traversal-slice HUD: a static controls card, and two context prompts that
## say exactly what the two action keys would do right now.
##
## The HUD asks the astronaut what it would do rather than working it out for
## itself. Interaction rules live in one place — astronaut.gd — and the HUD can
## never disagree with what the key actually does.

## Leave empty to find them by group ("player" / "rover").
@export var astronaut_path: NodePath
@export var rover_path: NodePath

@onready var _interact_label: Label = $Prompts/Interact
@onready var _cargo_label: Label = $Prompts/Cargo
@onready var _load_label: Label = $Prompts/Load

var _astronaut: Astronaut
var _rover: Rover


func _ready() -> void:
	_astronaut = get_node_or_null(astronaut_path) as Astronaut
	if _astronaut == null:
		_astronaut = get_tree().get_first_node_in_group("player") as Astronaut
	_rover = get_node_or_null(rover_path) as Rover
	if _rover == null:
		_rover = get_tree().get_first_node_in_group("rover") as Rover


func _process(_delta: float) -> void:
	if _astronaut == null:
		return
	_show_prompt(_interact_label, "E / A", _astronaut.interact_prompt())
	_show_prompt(_cargo_label, "F / X", _astronaut.cargo_prompt())
	_load_label.text = _load_text()


func _show_prompt(label: Label, keys: String, action: String) -> void:
	label.visible = action != ""
	if label.visible:
		label.text = "%s   %s" % [keys, action]


func _load_text() -> String:
	var parts := PackedStringArray()
	var back := _astronaut.back_rack()
	parts.append("%s %d/%d" % [back.rack_name, back.count(), back.capacity()])
	if _rover != null:
		var rack := _rover.cargo_rack()
		parts.append("%s %d/%d" % [rack.rack_name, rack.count(), rack.capacity()])
		var cargo := rack.load_mass()
		if cargo > 0.0:
			parts.append("%.0f kg" % cargo)
	return "     ".join(parts)
