extends Node3D
## Traversal-slice sandbox. Places the star, then drops the player and rover
## onto whatever the terrain generator produced.

@onready var _terrain: ProceduralTerrain = $Terrain
@onready var _astronaut: Astronaut = $Astronaut
@onready var _rover: Rover = $Rover
@onready var _star: DirectionalLight3D = $Star
@onready var _crates: Node3D = $Crates


func _ready() -> void:
	_align_star()
	_place_on_ground(_astronaut, Vector3(6.0, 0.0, 0.0), 1.2)
	_place_on_ground(_rover, Vector3(-6.0, 0.0, 0.0), 1.6)
	_place_on_ground($Beacon, Vector3(0.0, 0.0, -140.0), 0.0)
	_settle_crates()


## Crates are hand-placed in the editor on X/Z; only their height is solved
## here, against whatever the terrain generator happened to produce.
func _settle_crates() -> void:
	for child in _crates.get_children():
		var crate := child as Node3D
		if crate != null:
			_place_on_ground(crate, crate.global_position, 0.45)


## Point the key light along the fixed star direction from World.
func _align_star() -> void:
	_star.look_at_from_position(
		Vector3(0.0, 400.0, 0.0),
		Vector3(0.0, 400.0, 0.0) + World.star_direction(),
		Vector3.UP
	)
	_star.light_color = World.STAR_COLOR
	_star.light_energy = World.STAR_ENERGY


## Terrain nodes report local height, so convert through the terrain transform.
func _place_on_ground(node: Node3D, at: Vector3, clearance: float) -> void:
	var local := _terrain.to_local(at)
	var h := _terrain.height_at(local.x, local.z)
	node.global_position = Vector3(at.x, h + clearance, at.z)
