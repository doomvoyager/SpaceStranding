extends Node3D
## Where the ground actually is. Reports terrain height at candidate facility
## sites, and the local slope, so a facility can be placed on flat ground
## rather than half-buried or cantilevered off a ridge.

const WORLD := preload("res://scenes/world/test_world.tscn")

func _ready() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	for i in 30:
		await get_tree().physics_frame
	var terrain := world.find_child("Terrain", true, false)

	# A facility is about 10 m wide - dock at -3.6, pad at +4.4 - so levelness
	# has to be measured across that, not across a 4 m patch.
	var best: Array = []
	for x in range(-60, 61, 4):
		for z in range(-70, 31, 4):
			var h: float = terrain.height_at(float(x), float(z))
			var spread := 0.0
			for dx in [-5.0, -2.5, 0.0, 2.5, 5.0]:
				for dz in [-2.0, 0.0, 2.0]:
					spread = maxf(spread,
						absf(terrain.height_at(x + dx, z + dz) - h))
			best.append([spread, float(x), float(z), h])
	best.sort_custom(func(a, b): return a[0] < b[0])

	print("flattest sites, 10 x 4 m footprint:")
	for i in 12:
		var e: Array = best[i]
		print("  (%6.1f, %6.1f)  height %6.2f   spread %5.2f"
			% [e[1], e[2], e[3], e[0]])

	for site in [Vector2(-18.0, 10.0), Vector2(-14.0, 6.0), Vector2(-22.0, 14.0),
			Vector2(-30.0, 18.0), Vector2(-8.0, 2.0)]:
		print("loose site (%6.1f, %6.1f): height %6.2f"
			% [site.x, site.y, terrain.height_at(site.x, site.y)])
	get_tree().quit()
