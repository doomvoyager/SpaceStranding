extends Node3D
## Where does everything actually sit after the terrain swap?
##
## The heightmap moved the ground out from under a world whose spawn points,
## prop placements and look-dev cameras were all written against a procedural
## patch centred on the origin. Nothing here asserts - it reports, so the
## numbers can be read once and the hard-coded ones fixed against them.
##
## Runs as a scene, windowed or headless. Headless is fine: this only asks the
## heightfield and the node transforms, never the renderer.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##       res://tests/probe_world_placement.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")


func _ready() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var terrain := world.find_child("Terrain", true, false) as ProceduralTerrain
	print("terrain origin   ", terrain.global_position)
	print("terrain size     %.0f m, scale %s" % [terrain.size, terrain.scale])

	var half := terrain.size * 0.5
	var c := terrain.global_position
	print("patch covers     x %.0f..%.0f   z %.0f..%.0f"
		% [c.x - half, c.x + half, c.z - half, c.z + half])

	print("\nground height at world points:")
	for p: Vector2 in [Vector2(0, 0), Vector2(0, 18), Vector2(-70, 40),
			Vector2(0, -60), Vector2(-120, -120), Vector2(20, 40)]:
		print("  (%7.1f, %7.1f)  y = %8.2f"
			% [p.x, p.y, terrain.world_height_at(p.x, p.y)])

	print("\nspawned nodes:")
	for name: String in ["Astronaut", "Rover", "Beacon", "Hearth",
			"Longshadow", "RidgeRelay"]:
		var n := world.find_child(name, true, false) as Node3D
		if n == null:
			print("  %-10s MISSING" % name)
			continue
		var g := terrain.world_height_at(n.global_position.x, n.global_position.z)
		print("  %-10s at %s   ground %.2f   clearance %+.2f"
			% [name, n.global_position, g, n.global_position.y - g])

	var crates := world.find_child("Crates", true, false)
	if crates != null:
		for ch in crates.get_children():
			var n := ch as Node3D
			var g := terrain.world_height_at(n.global_position.x, n.global_position.z)
			print("  %-10s at %s   ground %.2f   clearance %+.2f"
				% [n.name, n.global_position, g, n.global_position.y - g])

	get_tree().quit()
