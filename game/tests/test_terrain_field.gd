extends Node3D
## Regression test for `TerrainField` — nine tiles behaving as one piece of
## ground. See [[Terrain]].
##
## What this exists to catch:
##
##   1. **The field answers the seam.** `extent()`, `sample_step()`,
##      `world_height_at()` and `world_surface_at()` are the whole contract the
##      rest of the project was narrowed onto. A field that gets any of them
##      wrong is not a drop-in for the single patch, and the failure would show
##      up as objects buried or floating rather than as an error.
##
##   2. **Seams are continuous.** This is the reason the placeholder mirrors
##      rather than repeats. A tile and its mirrored neighbour meet on the same
##      edge row of the master, so height either side of a boundary has to
##      agree — a cliff at every 4 km is not something to discover by driving
##      into one.
##
##   3. **Mirroring is actually on.** With it off, all nine tiles are identical
##      and the seams *are* cliffs. Asserted both ways, because "the heights
##      match" is only meaningful if the unmirrored case is shown to differ.
##
##   4. **The tile lookup is right at the edges.** `_tile_at` floors into a
##      grid, which is exactly the arithmetic that produces an off-by-one at a
##      boundary and answers from the wrong tile — plausibly, and therefore
##      invisibly.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_terrain_field.tscn

## Small tiles and coarse sampling: this is testing the layout arithmetic, not
## the heightmap, and nine 4096 m tiles at 4 m would be 18 M triangles.
const TILE := 256.0
const RES := 8.0
const ACROSS := 3
## Metres either side of a join. Small on purpose — see the note on
## `_check_seams_are_continuous`.
const STRADDLE := 0.05

var _field: TerrainField
var _failures: Array[String] = []


func _ready() -> void:
	_field = TerrainField.new()
	_field.tiles_across = ACROSS
	_field.tile_size = TILE
	_field.tile_resolution = RES
	# Procedural, so the test carries no dependency on the 15 MB bake — and so
	# it still means something on a machine where the art has not been pulled.
	_field.height_source = ProceduralTerrain.HeightSource.PROCEDURAL
	add_child(_field)

	_check_it_built()
	_check_the_seam()
	_check_tile_lookup()
	_check_seams_are_continuous()
	# Before the mirroring check, which adds a *second* field to the tree. Whose
	# arrival correctly makes it the answer to "where is the ground" — and would
	# make this check fail for a reason that is not a bug. `queue_free()` is
	# deferred, so it is still there for the rest of this frame either way.
	_check_the_lattice_finds_the_field()
	_check_the_heightmap_mirrors()
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)


func _check_it_built() -> void:
	if _field.tile_count() != ACROSS * ACROSS:
		_fail("built %d tiles, expected %d"
			% [_field.tile_count(), ACROSS * ACROSS])
	if not _field.is_built():
		_fail("the field reports it is not built")


## 1. The contract, against the numbers a single patch would have given.
func _check_the_seam() -> void:
	var box := _field.extent()
	var want := TILE * float(ACROSS)
	if not is_equal_approx(box.size.x, want) or not is_equal_approx(box.size.y, want):
		_fail("extent() is %s, expected %.0f square" % [box.size, want])
	# Centred on the field's own origin, so the middle tile straddles it — the
	# reason an odd grid was chosen over an even one.
	if not is_equal_approx(box.get_center().x, 0.0) \
			or not is_equal_approx(box.get_center().y, 0.0):
		_fail("extent() is not centred: %s" % box.get_center())
	if not is_equal_approx(_field.sample_step(), RES):
		_fail("sample_step() is %f, expected %f" % [_field.sample_step(), RES])

	var p := _field.world_surface_at(120.0, -300.0)
	if not is_equal_approx(p.x, 120.0) or not is_equal_approx(p.z, -300.0):
		_fail("world_surface_at moved the point it was asked about: %s" % p)
	if not is_equal_approx(p.y, _field.world_height_at(120.0, -300.0)):
		_fail("world_surface_at and world_height_at disagree at (120, -300)")


## 4. Every tile has to be reachable, and the point that lands on it has to be
## the one inside it. A lookup that is off by one still returns *a* height.
func _check_tile_lookup() -> void:
	var box := _field.extent()
	var seen := {}
	for iz in ACROSS:
		for ix in ACROSS:
			# Dead centre of each tile, which no rounding rule can get wrong.
			var x := box.position.x + (float(ix) + 0.5) * TILE
			var z := box.position.y + (float(iz) + 0.5) * TILE
			var tile: Node = _field._tile_at(x, z)
			if tile == null:
				_fail("no tile under the centre of cell (%d, %d)" % [ix, iz])
				continue
			seen[tile.name] = true
			var expected := "Tile_%d_%d" % [ix, iz]
			if tile.name != expected:
				_fail("the centre of cell (%d, %d) resolved to %s, expected %s"
					% [ix, iz, tile.name, expected])
	if seen.size() != ACROSS * ACROSS:
		_fail("only %d distinct tiles were reachable, expected %d"
			% [seen.size(), ACROSS * ACROSS])

	# Outside the field, the nearest tile answers rather than nothing.
	if _field._tile_at(box.position.x - 5000.0, 0.0) == null:
		_fail("a point off the west edge resolved to no tile at all")


## 2. Seams are continuous — measured by whether the step *scales*.
##
## **An absolute threshold is the wrong instrument here, and the first version
## of this test used one.** It asserted "no more than 0.25 m across a join" and
## failed at 18 m — on ground where the same 16 m straddle in *open terrain,
## nowhere near a seam*, stepped 9.9 m. Procedural noise at `height_scale` 48 is
## simply that rough, so the number was measuring the terrain, not the joins.
##
## What separates a cliff from a slope is what happens when you look closer: a
## slope's step shrinks in proportion to the straddle, a discontinuity does not.
## Measured across straddles of 16, 4, 1 and 0.1 m, the procedural seam gives
## 19.1 / 4.78 / 1.195 / 0.119 — exactly linear, so it is ground. So the test
## compares seam against open ground **at the same tiny straddle**, which
## calibrates itself against whatever the terrain is doing and needs no constant
## tied to `height_scale`.
func _check_seams_are_continuous() -> void:
	var pair := _seam_vs_open(_field, _field.extent(), STRADDLE)
	print("  procedural: seam %.4f m, open ground %.4f m, over %.2f m"
		% [pair[0], pair[1], STRADDLE * 2.0])
	_expect_continuous(pair, "procedural")


## The judgement both paths are held to. A seam that behaves like open ground is
## ground; the floor keeps a perfectly flat field from failing on a rounding bit.
func _expect_continuous(pair: Array[float], what: String) -> void:
	var limit := maxf(pair[1] * 3.0, 0.02)
	if pair[0] > limit:
		_fail("%s seams step %.4f m over a %.2f m straddle, against %.4f m in "
			% [what, pair[0], STRADDLE * 2.0, pair[1]]
			+ "open ground — that is a discontinuity, not a slope")


## 3. The heightmap path, where mirroring *is* the mechanism.
##
## Nine tiles share one master, so without mirroring every tile is the same
## picture and every join is a cliff. With it, a tile and its neighbour meet on
## the same edge row — and because the two sides are mirror images the step is
## not merely small but exactly **zero**. Asserted both ways round: "the heights
## match" means nothing unless the unmirrored case is shown to differ.
##
## Skipped loudly rather than weakened when the 15 MB bake is not on this
## machine — the art is gitignored and a fresh clone does not have it.
func _check_the_heightmap_mirrors() -> void:
	if not ResourceLoader.exists(ProceduralTerrain.DEFAULT_HEIGHTMAP):
		print("SKIP: no authored heightmap on this machine, so the mirrored")
		print("      seam claim is untested. Pull the terrain art to mean it.")
		return
	var field := TerrainField.new()
	field.tiles_across = ACROSS
	field.tile_size = TILE
	field.tile_resolution = RES
	field.height_source = ProceduralTerrain.HeightSource.HEIGHTMAP
	add_child(field)
	var box := field.extent()

	var mirrored := _seam_vs_open(field, box, STRADDLE)
	print("  heightmap mirrored: seam %.4f m, open ground %.4f m"
		% [mirrored[0], mirrored[1]])
	_expect_continuous(mirrored, "mirrored heightmap")

	# The setter defers its rebuild, so rebuild by hand: _ready() is not a
	# coroutine and there is no frame to wait for here.
	field.mirror_tiles = false
	field._build()
	var plain := _seam_vs_open(field, box, STRADDLE)
	print("  heightmap unmirrored: seam %.4f m (this one should be a cliff)"
		% plain[0])
	if plain[0] <= mirrored[0] * 10.0 + 0.5:
		_fail("turning mirroring off left the seams at %.4f m against %.4f m — "
			% [plain[0], mirrored[0]]
			+ "the mirroring assertion is not testing anything")
	field.queue_free()


## Worst height step straddling an interior seam, and the worst straddling
## ordinary ground a quarter-tile away from one, at the same distance.
##
## Returned together because neither number means anything alone: the whole
## instrument is the comparison.
func _seam_vs_open(field: TerrainField, box: Rect2, reach: float) -> Array[float]:
	var seam := 0.0
	var open := 0.0
	for edge in range(1, ACROSS):
		var seam_x := box.position.x + float(edge) * TILE
		var seam_z := box.position.y + float(edge) * TILE
		for i in 40:
			var t := (float(i) + 0.5) / 40.0
			var z := box.position.y + t * box.size.y
			var x := box.position.x + t * box.size.x
			# Vertical seam, straddled in X; horizontal seam, straddled in Z.
			seam = maxf(seam, absf(field.world_height_at(seam_x - reach, z)
				- field.world_height_at(seam_x + reach, z)))
			seam = maxf(seam, absf(field.world_height_at(x, seam_z - reach)
				- field.world_height_at(x, seam_z + reach)))
			# Control, well inside a tile.
			open = maxf(open, absf(field.world_height_at(x, seam_z + TILE * 0.25 - reach)
				- field.world_height_at(x, seam_z + TILE * 0.25 + reach)))
	return [seam, open]


## 5. The field has to be what `Lattice.terrain()` hands back.
##
## This is the whole point of `TerrainSource`: nine tiles standing where one
## patch stood, without retyping every caller. Two ways it can go wrong and both
## are silent:
##
##   * The cast fails and `terrain()` returns **null**, so every height query in
##     the project answers zero. That was the state before the base type existed,
##     which is why the field was kept out of the `terrain` group until now.
##   * A **tile** answers instead of the field. Tiles are `TerrainSource` too and
##     join the group in their own `_ready`, and the lookup keeps whichever
##     arrived last — always a tile. Queries would then be answered by one
##     4096 m corner of a 12 km world, correctly, for points nowhere near it.
##
## The second is the nastier one, and the assertion for it is not "did we get a
## field" but "does the thing we got span the whole world".
func _check_the_lattice_finds_the_field() -> void:
	var found := Lattice.terrain()
	if found == null:
		_fail("Lattice.terrain() returned null with a field in the tree — "
			+ "every height query in the project would answer zero")
		return
	if found != _field:
		_fail("Lattice.terrain() returned %s, not the field itself" % found.name)
	var box: Rect2 = found.extent()
	var want := TILE * float(ACROSS)
	if not is_equal_approx(box.size.x, want):
		_fail("Lattice.terrain() spans %.0f m, not the field's %.0f — a tile is "
			% [box.size.x, want]
			+ "answering for the whole world")
	# And the answer has to agree with the field's own, at a point deliberately
	# outside the middle tile.
	var far_x := box.position.x + TILE * 0.5
	if not is_equal_approx(found.world_height_at(far_x, 0.0),
			_field.world_height_at(far_x, 0.0)):
		_fail("Lattice.terrain() and the field disagree about the ground at x=%.0f"
			% far_x)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: nine tiles answer the seam, and their joins are continuous.")
		# quit() only schedules the exit, so this must return or the failure
		# path below runs anyway and overwrites the code with 1.
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
