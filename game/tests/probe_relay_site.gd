extends Node3D
## Where a relay would actually work.
##
## Hearth and Longshadow are about 69 m apart and the default link range is 45,
## so neither can see the other and one mast between them has to close the gap.
## Where that mast goes is a line-of-sight question, not a midpoint question -
## which is the whole reason the Lattice checks terrain rather than radius.
##
## Scans candidate ground for sites within range of both and with clear sight to
## both, and reports them worst-clearance-first so the choice is the sturdy one
## rather than the one that only just works.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_relay_site.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
## Height of the relay's antenna above the ground it stands on.
const MAST_HEIGHT := 11.0


func _ready() -> void:
	var world := WORLD.instantiate()
	add_child(world)
	for i in 40:
		await get_tree().physics_frame

	var terrain := world.find_child("Terrain", true, false) as ProceduralTerrain
	var hearth := world.find_child("Hearth", true, false) as Facility
	var longshadow := world.find_child("Longshadow", true, false) as Facility
	var a: Vector3 = hearth.mast_point()
	var b: Vector3 = longshadow.mast_point()
	var reach := Lattice.default_range

	print("Hearth mast %s" % a)
	print("Longshadow mast %s" % b)
	print("%.1f m apart, link range %.1f - %s"
		% [a.distance_to(b), reach,
			"already linked" if a.distance_to(b) <= reach else "needs a relay"])
	print("")

	var found: Array = []
	for x: int in range(-60, 25, 2):
		for z: int in range(-30, 45, 2):
			var ground := terrain.world_height_at(float(x), float(z))
			var mast := Vector3(float(x), ground + MAST_HEIGHT, float(z))
			if mast.distance_to(a) > reach or mast.distance_to(b) > reach:
				continue
			if not Lattice.has_line_of_sight(mast, a):
				continue
			if not Lattice.has_line_of_sight(mast, b):
				continue
			# A site is only as good as its weakest reason to work, so score the
			# worst of two margins: how much sight-line clearance it has, and
			# how many metres of range are left over. Ranking on clearance
			# alone picks sites sitting at 44.0 m of a 45 m reach, which stop
			# working the moment anything in the scene moves.
			var clearance := minf(_clearance(terrain, mast, a),
				_clearance(terrain, mast, b))
			var spare := reach - maxf(mast.distance_to(a), mast.distance_to(b))
			found.append([minf(clearance, spare), float(x), float(z), ground,
				clearance, spare])

	if found.is_empty():
		print("no site sees both. Either the range is too short or the ridge is too high.")
		get_tree().quit()
		return

	found.sort_custom(func(p, q) -> bool: return p[0] > q[0])
	print("%d sites see both. Best by weakest margin:" % found.size())
	print("  %-18s %8s %10s %8s" % ["site", "ground", "clearance", "spare"])
	for i in mini(8, found.size()):
		var e: Array = found[i]
		print("  (%6.1f, %6.1f) %8.2f %9.2f m %6.2f m"
			% [e[1], e[2], e[3], e[4], e[5]])
	get_tree().quit()


## Smallest gap between the line and the terrain beneath it.
func _clearance(terrain: ProceduralTerrain, from: Vector3, to: Vector3) -> float:
	var worst := INF
	var steps := 40
	for i in range(1, steps):
		var point := from.lerp(to, float(i) / float(steps))
		worst = minf(worst, point.y - terrain.world_height_at(point.x, point.z))
	return worst
