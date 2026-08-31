extends Node3D
## Sanity check on what rock_positions() actually contains.
##
## The scan capture framed itself on "the biggest rock" and pointed the camera
## at (-535, 824) on a 512 m map. Either the record is not what its docstring
## says, or the capture is reading it wrong, and guessing which would be the
## third wrong guess in a row.

const WORLD := preload("res://scenes/world/test_world.tscn")


func _ready() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	for i in 60:
		await get_tree().physics_frame

	var terrain := world.find_child("Terrain", true, false) as ProceduralTerrain
	var scatter := world.find_child("RockScatter", true, false) as RockScatter
	var positions := scatter.rock_positions()
	var sizes := scatter.rock_sizes()

	print("terrain size %.0f, so positions should sit inside +/- %.0f"
		% [terrain.size, terrain.size * 0.5])
	print("scatter node global origin %s" % scatter.global_position)
	print("%d positions, %d sizes" % [positions.size(), sizes.size()])

	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var biggest := 0.0
	var biggest_at := Vector3.ZERO
	var solid := 0
	for i in positions.size():
		var p := positions[i]
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		if sizes[i] > biggest:
			biggest = sizes[i]
			biggest_at = p
		if sizes[i] >= scatter.collision_above:
			solid += 1
	print("x %.1f..%.1f   y %.1f..%.1f   z %.1f..%.1f" % [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	print("biggest %.2f m at %s" % [biggest, biggest_at])
	print("%d of %d are at or above the %.2f m collision threshold"
		% [solid, sizes.size(), scatter.collision_above])
	get_tree().quit()
