extends Node3D
## Regression test for the authored-heightmap terrain source.
##
## The failure mode this guards against is not a crash. A heightfield that is
## subtly wrong - off by a texel, quantised to half float, silently fallen back
## to noise - produces a terrain that looks entirely plausible and puts every
## placed object, every Lattice sight line and every facility pad at the wrong
## altitude. So the numbers are checked against ground truth read out of the
## `.exr` by `tools/bake-terrain.py`, outside the engine, rather than against
## whatever the engine happens to return today.
##
##   1. **Exact texel hits.** At 4096 m / 4 m the 1025 grid steps exactly 2
##      texels through the 2049 map, so the bilinear blend collapses to a plain
##      read and the expected values below are exact, not approximate. If the
##      sampler ever drifts by a texel these move by metres.
##   2. **The range mapping.** `height_span` is metres of relief between the
##      map's lowest and highest sample, and the stride-2 grid happens to hit
##      both, so the built grid should span exactly `height_floor` to
##      `height_floor + height_span`.
##   3. **The fallback is not silent ground.** With the source set to Heightmap
##      and no usable map, the terrain falls back to *noise*, not to a plane -
##      a flat world reads as "the map has not loaded yet" and gets ignored.
##   4. **Procedural still works.** It is kept deliberately, for the tests that
##      build their own patch and for probes that want arbitrary relief.
##   5. **UV2 spans the patch.** The macro albedo is sampled through it. UV1
##      tiles hundreds of times, so getting these two confused gives a
##      kaleidoscope rather than a terrain, and nothing headless would notice.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_heightmap_terrain.tscn

const PATCH := 4096.0
const RES := 4.0
const SPAN := 210.0
const FLOOR := 12.5

## Ground truth from the bake tool's own EXR reader, at height_floor = 0.
## grid (x, z) -> metres above the map's lowest sample.
const EXPECTED := [
	[0, 0, 22.8041],
	[512, 512, 204.5856],
	[1024, 1024, 28.2243],
	[256, 768, 25.1133],
]

var _failures: Array[String] = []


func _ready() -> void:
	var terrain := ProceduralTerrain.new()
	terrain.name = "Terrain"
	terrain.height_source = ProceduralTerrain.HeightSource.HEIGHTMAP
	terrain.size = PATCH
	terrain.resolution = RES
	terrain.height_span = SPAN
	terrain.height_floor = FLOOR
	add_child(terrain)

	_check_samples(terrain)
	_check_range(terrain)
	_check_uv2(terrain)
	_check_world_height(terrain)
	_check_procedural_still_works()
	_check_fallback_is_not_flat()

	for f in _failures:
		print("FAIL: ", f)
	if _failures.is_empty():
		print("PASS: heightmap terrain (%d samples/side)" % (int(PATCH / RES) + 1))
		get_tree().quit(0)
		return
	get_tree().quit(1)
	return


func _fail(msg: String) -> void:
	_failures.append(msg)


## The map is read at exact texels here, so a millimetre of tolerance is
## generous. Anything looser would not catch a one-texel offset.
func _check_samples(terrain: ProceduralTerrain) -> void:
	for e: Array in EXPECTED:
		var got := terrain.height_at_index(e[0], e[1])
		var want: float = float(e[2]) + FLOOR
		if absf(got - want) > 0.001:
			_fail("height_at_index(%d, %d) = %f, expected %f"
				% [e[0], e[1], got, want])


func _check_range(terrain: ProceduralTerrain) -> void:
	var n := int(PATCH / RES) + 1
	var lo := INF
	var hi := -INF
	for z in n:
		for x in n:
			var h := terrain.height_at_index(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if absf(lo - FLOOR) > 0.01:
		_fail("grid floor is %f, expected height_floor %f" % [lo, FLOOR])
	if absf(hi - (FLOOR + SPAN)) > 0.01:
		_fail("grid ceiling is %f, expected floor+span %f" % [hi, FLOOR + SPAN])


func _check_uv2(terrain: ProceduralTerrain) -> void:
	var mi := terrain.get_node_or_null("TerrainMesh") as MeshInstance3D
	if mi == null or mi.mesh == null:
		_fail("no TerrainMesh to check UV2 on")
		return
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	if uv2.is_empty():
		_fail("mesh has no UV2; the macro albedo has nothing to sample through")
		return
	# Corners of the grid, which are the first and last vertices.
	if not uv2[0].is_equal_approx(Vector2.ZERO):
		_fail("UV2 does not start at (0, 0): %s" % uv2[0])
	if not uv2[uv2.size() - 1].is_equal_approx(Vector2.ONE):
		_fail("UV2 does not end at (1, 1): %s" % uv2[uv2.size() - 1])


## The trap documented in Terrain.md: local heights are not world heights when
## the node is scaled. Kept here because the world scene no longer carries a Y
## scale, so nothing else would catch it regressing.
func _check_world_height(terrain: ProceduralTerrain) -> void:
	terrain.scale = Vector3(1.0, 0.5, 1.0)
	var local := terrain.height_at(0.0, 0.0)
	var world := terrain.world_height_at(0.0, 0.0)
	if absf(world - local * 0.5) > 0.01:
		_fail("world_height_at ignored the node scale: local %f, world %f"
			% [local, world])
	terrain.scale = Vector3.ONE


func _check_procedural_still_works() -> void:
	var t := ProceduralTerrain.new()
	t.height_source = ProceduralTerrain.HeightSource.PROCEDURAL
	t.size = 256.0
	t.resolution = 4.0
	add_child(t)
	var lo := INF
	var hi := -INF
	for z in 65:
		for x in 65:
			var h := t.height_at_index(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if hi - lo < 1.0:
		_fail("procedural source produced flat ground (%f..%f)" % [lo, hi])
	t.queue_free()


## A missing map must not quietly become a plane.
func _check_fallback_is_not_flat() -> void:
	var t := ProceduralTerrain.new()
	t.height_source = ProceduralTerrain.HeightSource.HEIGHTMAP
	t.size = 256.0
	t.resolution = 4.0
	# An all-black 4x4 map has no relief, which is the "unusable" case.
	var img := Image.create(4, 4, false, Image.FORMAT_RF)
	img.fill(Color(0.5, 0.0, 0.0))
	t.heightmap = ImageTexture.create_from_image(img)
	add_child(t)
	var lo := INF
	var hi := -INF
	for z in 65:
		for x in 65:
			var h := t.height_at_index(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if hi - lo < 1.0:
		_fail("a relief-free map flattened the terrain instead of falling back "
			+ "to noise (%f..%f)" % [lo, hi])
	t.queue_free()
