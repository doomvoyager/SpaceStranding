---
status: built
verified: 2026-09-15
godot: res://scripts/world/streamed_terrain.gd
tags: [system, world, scaffolding]
---

# Terrain

The world's ground is **streamed** as of 2026-09-14: one resident heightfield
of the real south pole, 24.6 km across, and a quadtree of mesh tiles built
around whoever is looking - "Streamed tiles", below. Everything above that
section is the history of the single patch it replaced, kept because the
patch (`res://scripts/world/terrain.gd`) and the mirrored field are still in
the project for the tests that build their own ground, and because most of
what was learned on them - the seam, the winding, the trimesh, `is_built()` -
carried straight over.

> Gameplay code must not depend on anything in here beyond the seam:
> `world_height_at`, `world_surface_at`, `extent()`, `sample_step()`,
> `is_built()` and `rebuilt`, on `TerrainSource`.

## The masters, and why they are not in the repo

`game/assets/terrain/_source/` holds two 8193x8193 Gaea exports, 420 MB
together. Both are **gitignored**, on the same rule as the asset zips: the repo
holds what the game uses, not what it was delivered in. Mac keeps the masters.

| Master | Format | Notes |
|---|---|---|
| `world_01_height.exr` | 8193², one FLOAT channel, ZIP | Normalised **0.0819-0.9233**. No absolute vertical scale survives the export, so the metres are ours to choose. |
| `world_01_color.tif` | 8193², uncompressed 8-bit RGB | Mean RGB (157, 126, 106) - warmer and more saturated than [[Visual-Direction]] asks for. |

They are aligned: correlation of height against colour luminance is 0.42 at zero
offset and plateaus at 0.436 across a ±768 px search, so there is no
registration error to correct.

Neither can be used as delivered:

- **Godot cannot import TIFF at all.** Not a settings problem - the format is
  unsupported, so the colour master must be re-encoded whatever else happens.
- **Godot expands the height master to 805 MB.** A one-channel ZIP EXR imports
  as three-channel uncompressed float. Measured, not guessed.

`_source/` carries a `.gdignore` - committed, while its contents are not - so a
filesystem scan never reaches either file.

## The bake

`tools/bake-terrain.py` runs once per re-export from Gaea and writes the two
files the game actually loads. Needs numpy, Pillow and tifffile; the EXR read
and write are implemented in the script rather than pulled from OpenEXR, which
is a heavy build dependency for what is zlib plus a byte shuffle.

```bash
python tools/bake-terrain.py
```

| Bake | Size | Why |
|---|---|---|
| `world_01_height_2049.exr` | 15.4 MB | 2049² supports 2 m mesh spacing over the 4096 m patch, with headroom below the 4 m we use. |
| `world_01_color_4096.webp` | 3.3 MB | 1 m/texel. The master is only 0.5 m/texel at this footprint, and neither is sharp underfoot - see the open item. |

**8193 is 8192+1, and that is the whole reason the height bake is free.** Every
power-of-two stride lands exactly on source texels, so decimation is a pure
subsample - verified zero error at strides 4, 8 and 16. The script refuses any
`--height-size` that does not divide the master evenly, and round-trips its own
output before shipping it, because a heightfield wrong by a little is a terrain
that looks fine and puts every placed object at the wrong altitude.

The colour bake *is* resampled, and drops the duplicated +1 edge first: 8192 is
what tiles, and keeping the odd column skews every texel by half its width.

## Import settings are set by hand, on purpose

Both `.import` files carry `detect_3d/compress_to=0`. Left at the default, Godot
re-imports a texture to a **lossy VRAM format the first time it is used in a 3D
material** - which for the heightfield would silently destroy the float heights
and change the shape of the world, with nothing logged. The albedo is explicitly
`compress/mode=2` with `high_quality=true` (BPTC) and **mipmaps on**: a 4096 map
stretched over 4096 m with no mipmaps aliases hard at distance and crawls
whenever the camera moves.

The importer preserves full float - worst pixel error 4.7e-9 against ground
truth read outside the engine, and a 4.2 M-float bulk readback in under 10 ms.
`tests/probe_heightmap_import.gd` measures both.

## The two sources

`height_source` picks between them. `height_at()`, `world_height_at()` and the
`rebuilt` signal behave identically either way, so [[Scatter]], [[The-Lattice]]
and the facilities never learn which is in use.

**Heightmap.** Samples the bake across the whole patch. `height_span` is
**metres of relief between the map's lowest and highest sample** - relief, not
scale, so it stays meaningful when the map is re-exported with a different
range. `height_floor` is the local height of the lowest sample.

**Procedural.** The original three-octave FastNoiseLite stack. It is the script
*default*, so a bare `ProceduralTerrain.new()` in a test still costs nothing;
the world scene sets Heightmap explicitly. A missing or relief-free map falls
back to it and warns, rather than falling back to flat ground - a plane reads as
"the map has not loaded yet" and gets ignored.

The class name predates all this and is now half a lie. Renaming it touches
sixteen test files, so it is a deliberate TODO rather than drift.

## The world's numbers

As of 2026-09-14, the streamed ground:

| | |
|---|---|
| Footprint | 24,576 m tiled, of a 24,580 m window - 3 x 3 root tiles of 8192 m |
| Data | LOLA 5 m/px, 4917² float32, 97 MB resident, Gaussian-smoothed at sigma 2.5 samples |
| Mesh spacing | 4 m nearest, doubling per ring to 128 m; 1.85 M triangles at the spawn |
| Relief | 4830 m after smoothing (4,830 raw) |
| Grade | median 14.5°, p90 31.3°, p99 34.2°; 75.0% at or under the rover's 25° (14.7 / 31.5 / 36.1 / 75% raw) |
| Terrain offset | (-374.4, -1246.9, +966.9) - the pole at the map's centre, the flat spot at the origin |

The single patch these replaced, for the record: 4096 m at 4 m, 210 m of
relief, median 3°, offset (-470, 0, +1242).

**The offset is not decoration.** The map's peak sits at its centre, so at zero
offset the world origin - where the astronaut, the rover and every crate spawn -
landed on a **42° face at 204 m**. The offset puts a 0.19° playa under the origin
at 19 m, with the massif 1.3 km away and prominent on the horizon. It is one
number on the Terrain node and Mac can move it.

The 0.5 Y scale the node used to carry is **gone**. It existed to flatten
procedural noise that was too aggressive; with `height_span` in real metres it
is redundant, and it had already caused one shipped bug by making local heights
read as half of world heights.

## Things that bit, and are guarded now

**Winding.** Godot treats *clockwise* triangles as front faces. Wound the other
way the whole terrain is backface-culled and you fall through an invisible
world. The index loop is commented accordingly.

**Collision is a trimesh, not `HeightMapShape3D`.** The height shape samples on
a fixed 1-unit grid, which would force a non-uniform scale on the
`CollisionShape3D` - and **Jolt rejects non-uniformly scaled height shapes.**

**No `owner` on the generated nodes**, or every save bakes a six-figure-triangle
mesh into the `.tscn`.

**`height_at()` reports LOCAL height.** Use `world_height_at()`, which converts
through the node transform. This is now load-bearing in a way it was not before,
because the terrain is translated rather than sitting on the origin.

**`is_built()` before trusting a height.** An unbuilt terrain answers **zero**
for every point rather than failing, and zero is a perfectly plausible height -
so anything solving positions against one quietly stacks the whole scene onto
this node's own origin. The editor ground snap in [[Placement]] refuses to write
until this is true; it is the only guard between a not-yet-built patch and a
destructive edit that looks exactly like a correct one.

**UV2 spans the patch 0..1; UV1 tiles.** The macro albedo is sampled through
UV2. UV1 is world metres over 16 and repeats hundreds of times across the patch,
so it can carry detail and never the macro map. Deriving one from the other
would hard-code the patch size into the material and break the next time `size`
moves - the terrain writes a real UV2 instead.

**Hand-placed structures do not survive a terrain swap.** The Hearth, Longshadow
and the ridge relay all carried Y values tuned against the procedural patch;
the heightmap left the Hearth **13.6 m underground**. `test_world.gd` now settles
everything in the `facility` and `relay` groups onto the ground, exactly as it
already did for crates - X/Z stay hand-placed in the editor, only height is
solved. Both scenes put their origin at the ground contact point, so they settle
flush.

The editor now solves the same height *while you drag* - see [[Placement]] - so
the Y in the scene file is no longer a number nobody has checked since the last
terrain it was tuned against. When that landed the Hearth's stored Y was still
7 m out and the recovered mast 6 m, neither visible without pressing play.

**It is in the `terrain` group now, and was not before.** Nothing had ever
called `add_to_group("terrain")`, so every lookup that checked the group first —
`Lattice._terrain()`, which is the project's one answer to "where is the ground"
— missed and fell through to a recursive walk of all 9,524 nodes in the scene.
Ten microseconds on a function the route line calls four hundred times a frame.
Nothing errored, nothing looked wrong, and the group had been sitting in the
code as a documented fast path the entire time. See [[Scanner]].

**The scatter assumed the terrain was at the origin.** `rock_scatter.gd` drew
positions from `-half..+half` in world space, which was the same thing only
while the patch was centred on nothing in particular. It now scatters around
`_terrain.global_position`; without that, rocks land off the patch edge where
`height_at()` clamps and leaves them hanging.

## Tests

```bash
engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_heightmap_terrain.tscn
```

Checks the sampled heights against ground truth read out of the `.exr` by the
bake tool, **outside the engine** - at 4096 m / 4 m the grid steps exactly two
texels through the 2049 map, so the expected values are exact rather than
approximate and a one-texel drift moves them by metres. Also checks the range
mapping, that UV2 spans the patch, that a relief-free map falls back to noise
rather than to a plane, and that procedural still works.

Stills, which must run **windowed** - `--headless` is the dummy renderer and
writes no image:

```bash
engine/Godot_v4.7.1-stable_win64_console.exe --path game res://tests/terrain_capture.tscn
```

```bash
engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/probe_world_placement.tscn
```

`probe_world_placement` reports where every spawned thing sits relative to the
ground. It is the fastest way to catch a terrain change having buried something.

## Nine tiles, before the art exists

**Built 2026-09-03.** `TerrainField` (`res://scripts/world/terrain_field.gd`)
lays out an N x N grid of `ProceduralTerrain` tiles and answers the seam on
their behalf, so nothing downstream knows it is not one patch.

Mac has one 8193² master, which covers 8192 m at native resolution - two tiles
of the nine. Until the rest are authored, every tile samples the same master,
**mirrored on alternate rows and columns**.

**Mirrored, not stretched**, for two reasons that both outrank how it looks:

- **Grades survive.** Stretching one 210 m master over 12,288 m keeps the relief
  and triples the run, so every slope divides by three: the measured median 3
  deg becomes 1 and the p99 17 becomes 6. A pancake - and it would invalidate
  the drivability tuning the rover was re-seated against two days earlier.
  Mirroring changes no slope anywhere.
- **It keeps tile bugs loud.** Nine tiles sampling one *contiguous* stretched
  map means a wrong tile index still produces plausible ground and the bug
  hides. Nine discrete tiles means a wrong index is a visible discontinuity.

Measured at a 0.1 m straddle: the mirrored heightmap seam steps **0.0000 m**
against 0.1804 m in open ground - not merely continuous but exactly symmetric,
since the two sides are mirror images. Unmirrored the same seam steps **27.75
m**, which is what makes the assertion worth having.

**The procedural path needed a separate fix and does not use mirroring at all.**
It sampled noise at `x * resolution`, so every patch started at noise coordinate
zero and nine tiles were nine copies of one hill with a cliff at every join.
Offsetting by the node's own position makes adjacent tiles contiguous in the
noise domain and the field seamless by construction. A patch at the origin is
unaffected, which is every existing test.

**Wired in through `TerrainSource`.** The seam started as a convention; it is a
type now — `res://scripts/world/terrain_source.gd`, which both
`ProceduralTerrain` and `TerrainField` extend and which `Lattice.terrain()`
returns. Nine tiles stand where one patch stood and no caller was retyped except
to name the base. `world_surface_at` lives there, since both implementations had
the same one-line copy; everything else is a stub that **errors** rather than
answering, because the alternative is a plausible zero and this project has
already had "the ground is at height 0" pass every test.

**A field is shadowed by its own tiles unless you stop it.** Tiles are
`TerrainSource` too, they join the `terrain` group in their own `_ready`, and
the lookup keeps whichever arrived last — which is always a tile. Every height
query would then be answered by one 4096 m corner of a 12 km world, *correctly*,
for points nowhere near it. `Lattice._is_tile()` walks the parent chain and
skips anything under another terrain. Proved by removing it: `Lattice.terrain()`
returns `Tile_2_2`, spanning 256 m of a 768 m field.

## float32 does not stand in the way of 12 km

**Measured 2026-09-03**, before any tiling, because a failure here would have
meant a floating origin and that touches every system in the project.

| from origin | float step | rest jitter | round trip | render |
|---|---|---|---|---|
| 0 m | 0.00000012 m | 0 | exact | mean luma 0.2005 |
| 8,700 m *(centred 3x3 corner)* | 0.00048828 m | 0 | exact | 0.1983 |
| 40,000 m | 0.00195313 m | 0 | exact | 0.1985 |

The render row is the whole world translated and shot with the same framing -
terrain, lights, props and camera together, so it stays a precision test rather
than a test of a scene pulled apart. The frames are indistinguishable: no shadow
acne, no depth fighting, no vertex swim. `previews/2026-09-03/farrender-*.png`.

**So 3x3 needs no floating origin.** Worth stating plainly because the
arithmetic bound on its own predicts trouble that Jolt and the renderer do not
actually have.

Two false starts, both worth keeping. The first version dropped its test body on
procedural relief and measured **1.8 m** of jitter at the origin - a box sliding
downhill. The second flattened the ground and got exactly `0.0` everywhere
including 40 km, which is not a clean result but Jolt **sleeping** the body and
zeroing its velocity. Rest jitter is only measurable on a body that is awake and
on ground with no slope to slide down.

## The world-space seam

**Added 2026-09-03**, before any tiling work, because nine tiles break the
contract five systems were quietly relying on.

| Ask | Answer |
|---|---|
| `world_height_at(x, z)` | ground height, world space |
| `world_surface_at(x, z)` | the whole point, X and Z carried through |
| `extent() -> Rect2` | where the ground *is*, world X/Z |
| `sample_step()` | world metres between samples |

Nothing outside `terrain.gd` reads `size`, `resolution`, `height_at()` or
`height_at_index()` any more. Those are local-space and index-space, and both
only mean anything while there is exactly one patch centred on its own node.

**Five systems had baked that in.** `map_terrain.gd` and `coverage_map.gd`
walked the local grid and pushed every sample through `to_global`;
`rock_scatter.gd` took `size * 0.5` around `global_position`; `rock_scatter.gd`
and `test_world.gd` each carried their own hand-written `to_local` /
`height_at` / `to_global` round trip, with their own copy of the warning about
the node's Y scale. That warning existed because the trap had already been
sprung once - and the "assumes the terrain is at the origin" bug that left the
Hearth 13.6 m underground is the same shape, fixed locally rather than as a
contract. `world_surface_at()` is now the one answer.

The seam is asserted in `test_heightmap_terrain.gd` on a terrain that has been
**moved 1.3 km and scaled 2x**, not on one sitting at the origin - where every
implementation is right by accident. Proved load-bearing by reverting `extent()`
to the naive `Rect2(-half, -half, size, size)`: three assertions fire.

Still open, and deliberately not done here: the coverage mask reaches the
shader through **UV2**, which spans one patch 0..1. Nine tiles have nine UV2s,
so the mask has to be sampled by world position instead. That is rendering
coupling rather than the height contract, and it belongs with the chunking.

## Where it is going, as of 2026-09-14

Mac's call, in the [[Decision-Log]]: **the real south pole, composed per tile,
about 25 km across, the Gaea master retired.** The plan; 1 and 5 are built,
below, and the rest is not:

1. **Base: LOLA.** NASA's south-pole DEM - 20 m/px for 80-90°S, 5 m/px inside
   87°S, public domain, GeoTIFF. A window of it, fetched and baked by
   `tools/lola-window.py`. **Built.**
2. **Detail below the DEM.** A deterministic layer for what 5-20 m/px cannot
   hold and the rover sees: craters on the lunar size-frequency law (∝ D⁻²),
   fresh to soft, regolith undulation at 0.1-0.5 m, boulders seeded from the
   fresh craters through [[Scatter]]. Amplitudes and densities on F1.
3. **Authored sections as stamps.** A `TerrainStamp` node: a heightmap, placed
   with the [[Placement]] gizmos, size, rotation, a blend margin, and its
   height solved from the base along its rim - the placement rule for a whole
   patch. Replace for pads, cuts and landing fields; add for hills.
4. **Composed on the CPU into each tile's buffer**, so render, physics, the
   map, the [[The-Lattice|Lattice]] and placement read one set of numbers and
   the seam contract below holds. A new `height_source`, not a new terrain.
5. **Built around the player.** Rings of tiles at 4, 16 and 64 m with skirts,
   built off the main thread, collision for the near ring only. **Built**,
   as a quadtree rather than rings - "Streamed tiles". Past the horizon the
   curvature drop in the shared surface shader - the natural cutoff
   [[The-Planet]] describes, in place of the fog the 09-03 plan assumed - is
   still to do.

Two things go before any of it is judged by eye: the sun-shadow probe in
[[The-Planet]] - at a 5° sun the ground's look *is* its shadows and none render
today - and the real-ground probe below.

## The real ground, measured

**2026-09-14.** `tools/lola-window.py` reads a window of NASA's LOLA south-pole
DEM over HTTP - the products are tiled BigTIFFs and the server takes byte
ranges, so 25.6 km at 20 m is 16 MB and a 4.1 km patch at 5 m is 9 MB, no
download - decodes the tiles itself (deflate plus the TIFF floating-point
predictor, which tifffile refuses without a 30 MB codec wheel), reports
slopes against the rover's 25°, writes hillshade and drivability previews, and
bakes an EXR in raw metres through `bake-terrain.py`'s writer.

| | 25.6 km at 20 m, around the pole | 4.1 km at 5 m, on the pole | 4.1 km at 5 m, the plateau toward de Gerlache |
|---|---|---|---|
| Relief | 4,821 m - Shackleton is in frame | 1,709 m - half the patch is its inner wall | 1,729 m |
| Slope, median / p90 / p99 | 17 / 32 / 34.5° | 22 / 32 / 37° | 21 / 26 / 30° |
| At or under the rover's 25° | 66% | 63% | 85% |
| Under 15° | 43% | 27% | 16% |

**The real pole is rugged.** The crater walls are the red ring in
`lola-overview-25km-slope.png`; the plateau between the craters reads green at
20 m and is 15-25° at 5 m. Nowhere inside a 1 km margin of the plateau patch
has a calm 100 m; the pole patch has one - 3°, 90% drivable for a kilometre
around it, median 14° - and that is where the world origin now sits, 1.3 km
from the pole with Shackleton's rim ~600 m off. `lola-pole-hill.png` and
`lola-pole-slope.png` are the patch; the rim crest runs diagonally across it
and the dark half is the wall.

**In the scene, for the rest of that day:** the Terrain node's map was
`lola_pole_4100.exr`, 1025² over 4100 m (4 m, the 5 m data resampled),
`height_span` 1708.6, offset (-374.4, -1477.6, 966.9) so the flat spot was
the origin at y ≈ 0. Everything placed settled onto it correctly
(`probe_world_placement`); the facilities kept their old X/Z. Later the same
day the material went grey, with the bake off for good and a noise normal map
standing in for the detail layer - see [[The-Planet]], "The ground, and how
it is lit" - and that evening the patch gave way to the streamed ground
below. The 4.1 km bake stays in the repo until nothing references it.

**What the frames say.** The macro is right: a plain, a crest, a wall dropping
into shadow, small craters from the overview. Up close the ground is a smooth
sheet - 5 m data under a 4 m mesh has nothing between the samples - which is
the case for the detail layer, not against the data. The 20 m product's "green"
is 15-25° at 5 m; the metre scale will be rougher still, and boulders.

## Streamed tiles

**Built 2026-09-14**, the evening of the day the ground was decided. The
Terrain node in `test_world.tscn` is a `StreamedTerrain`
(`res://scripts/world/streamed_terrain.gd`) now.

**The heights are resident; only the meshes stream.** The Lattice traces
sight lines to relays kilometres off, the route planner samples across the
map and the map panel draws all of it, so `world_height_at` has to answer
anywhere at any time. The whole 24.6 km window lives in memory as a
[Heightfield] (`res://scripts/world/heightfield.gd`) - 4917² float32 at 5 m,
97 MB, read in 50-70 ms - and every seam question is a Catmull-Rom read on
it, exact on every sample and smooth between them (bilinear drew the data
grid at grazing light; see the known issues). `is_built()` means the file
loaded. Tiles are a view of the data, and every
vertex of every tile at every level is an exact sample of the same function
the seam answers, so a crate placed on `world_height_at` rests on the mesh
exactly as it did on the patch.

**Not a texture.** Godot's EXR importer expands one float channel to three,
so the same window as a `CompressedTexture2D` would be 290 MB and carry the
`detect_3d` trap. `tools/lola-window.py --raw` writes `lola_pole_24k.hf`: a
32-byte header - magic, width, height, spacing, lowest, highest - then
little-endian float32 rows, north up, in metres. Godot leaves an unknown
extension alone, so it never meets an importer; `Heightfield.load_file`
reads it with one `FileAccess` call. It is the largest file in the repo by a
factor of six, and Mac chose to commit it over having each machine fetch it.

**A quadtree of 65 x 65 tiles.** Six levels: 4 m spacing over 256 m at the
finest, doubling to 128 m over 8192 m at the root, and 3 x 3 roots cover
24,576 m of the 24,580 m window. A tile splits into its four children while
the viewer is within `split_ratio` tile-widths of it, which makes the rings
of the plan without hollowing coarse tiles around fine ones. Counted at the
spawn on the real ground, `select_tiles` alone:

| samples | ratio | tiles | triangles | 4 m ground out to |
|---|---|---|---|---|
| 65 | 1.0 | 139 | 1.21 M | 1.07 km |
| 65 | **1.5** | **212** | **1.85 M** | **1.30 km** |
| 65 | 2.0 | 310 | 2.70 M | 1.60 km |
| 129 | 1.0 | 115 | 3.89 M | 2.0 km |
| 129 | 1.5 | 170 | 5.74 M | 2.5 km |

The first capture ran 129-sample tiles at 1.5 and cost 5.7 M; the old patch
was 2 M, and that is the budget, so 65 at 1.5 is the default. Everything is
on F1 under "Terrain".

**Skirts hide what is between the shared points.** A coarse tile's edge
passes through the same samples its finer neighbour's does, and between them
the finer edge wanders off the coarse straight line. Each tile hangs a wall
below every edge, as deep as the data dips under that edge - measured along
it while the tile is built - plus half a metre. The first skirts were a
whole spacing deep, which at a 5.5° sun is a 64 m wall throwing a 660 m
shadow; they are their own mesh under the tile now, with shadow casting off,
and nothing collides with them.

**Built on worker threads, added on the main thread.** About 6 ms a tile at
65 samples; `probe_tile_threads` measured 22 ms at 129 and eight at once in
48 ms wall. Nearest first, `builds_per_frame` a frame. A tile is only retired
once whatever covers its ground - its children, or its parent - is resident,
so a swap never shows a hole; retired tiles wait hidden in a cache of
`cache_tiles` so turning round costs nothing. Collision is a trimesh on every
tile within `collision_radius` (1 km, 62 tiles at the spawn), and the tiles
inside it at ready are built synchronously, so the rover has a floor before
the first physics tick.

**Two engine facts came out of it**, in `CLAUDE.md`:
`Mesh.create_trimesh_shape()` deadlocks on a worker, and a worker holding a
bound method outlives the node it was bound to.

**What did not have to change.** UV2 on every tile spans the whole tiled
extent 0..1 rather than the tile, so the coverage mask - built over
`extent()` by `CoverageMap`, sampled through UV2 by the surface shader -
works unchanged; it is capped at 4096 texels a side now, 6 m on this ground.
Nothing that reads the seam was touched: the Lattice, the map, the route
line, placement, the footprints and the tracks all run on the streamed ground
as they did on the patch. Fourteen tests and captures that named
`ProceduralTerrain` now name `TerrainSource`, which is what they meant. The
rock scatter throws its `count` over a 4.1 km square around the origin
instead of the whole extent, which keeps the spawn as dense as it was;
scattering around the player is [[Scatter]]'s item.

**The frames** - `previews/2026-09-14/terrain-streamed-v2-*`, six views:
the spawn plain as it was; the rim; over the crest into the crater, with the
rim's own shadow across the far wall; a 1500 m overview; the horizon from the
crest; and the whole world from 8 km up, Shackleton entire. No seam shows at
any range. Beside them, `terrain-patch-*` are the same first four shots from
the single patch, which stop dead at its 4.1 km edge - the far walls were
never drawn before. On those far walls, on the shadowed side, there are fine
diagonal striations the near ground does not have; see the open item.

Tests: `test_streamed_terrain.tscn` - the seam on a moved node, the
selection tiling the ground exactly once, every vertex on `world_height_at`
at two levels, the winding, the skirts, the hole-free swap frame by frame,
collision following the viewer with a raycast to prove it, the Lattice
finding the terrain and not a tile, and the real file's header.

## Known issues

- [x] ~~**Striations past every crest, and a pale sheet on the far walls.**~~
      Both dealt with 2026-09-15 on Mac's go, the sheet outright and the
      lines by three-quarters. The material has `lunar_view_floor` at 0.25
      (the sweep, `far-sheet-floor-sweep.jpg`). The bake is smoothed
      (`lola-window.py --smooth 2.5`, a Gaussian of 12 m: sigma 1 took the
      speckle from 0.54 to 0.29 m and left most of the lines, 2.5 takes
      most of the lines and the steepest faces with them - p99 slope 36.1
      to 34.2°, the steepest 62 to 41°, the drivable share 75% either way;
      `far-sheet-crest-three.jpg` has raw, 1 and 2.5 side by side) and the
      sampler is **Catmull-Rom** rather than bilinear - `Heightfield.height_at`
      - because bilinear's slope jumps at every data row and a 4 m mesh over
      a 5 m field puts a vertex either side of every jump, so the data's own
      grid came out as lines wherever the sun grazed a face. What is left
      (`far-sheet-crest-before-after.jpg`, `far-sheet-final-*`) is the
      smoothed noise itself, blobs of 10-15 m and 0.3 m, each lighting its
      sun side on the terminator; the high-pass of the rim
      (`lola-24k-rim-highpass-x3.png`) shows the blobs and no stripes. A
      heavier blur trades 5 m detail for it, and the detail layer will bury
      it under real roughness either way. The diagnosis, kept:
      two things, found with `probe_far_sheet.tscn` (2026-09-15, windowed,
      from the rim and from the plain; frames `previews/2026-09-15/far-sheet-*`).
      **The striations are the data's noise, lit at grazing incidence.** They
      survive Lambert in place of the lunar term, the skirts hidden, and the
      detail normal map off, and they sit on the face just past a crest -
      the terminator, where the sun rays run along the ground. The 5 m
      product carries 0.54 m of per-sample speckle (the high-pass,
      `2026-09-14/lola-24k-wall-highpass.png`), which is a 6° tilt per
      sample: invisible on ground the sun hits squarely, and at the
      terminator each bump's sun side lights up while the rest stays dark,
      in the DEM's own rows and columns, which perspective draws as lines
      converging on the horizon. The fix belongs at the bake - a small
      Gaussian in `lola-window.py` - or in the detail layer, which will have
      to smooth before it adds; not in the renderer.
      **The pale sheet is the lunar term at grazing view.** Lommel-Seeliger
      as written, `2 n_l / max(n_l + n_v, 0.02)`, goes to 2 - twice Lambert
      at normal incidence - wherever the eye sees the ground edge-on and the
      sun catches it at all, and steps to 0 at the terminator, so a far
      wall reads as a flat white sheet with a knife edge against the dark.
      Under Lambert the same wall is dark grey. Pure Lommel-Seeliger
      limb-brightens; the real Moon's disc does not, because roughness
      takes it back. A floor on `n_v`, or a blend toward Lambert as the
      view grazes, is the proposal in [[The-Planet]]. Mac saw both from the
      rover the moment the far plane went out to 30 km.
- [ ] The detail layer below the DEM, and stamps: the composition slot is
      `Heightfield`, and nothing composes yet. 5 m data under a 4 m mesh is
      still a sheet underfoot.
- [ ] No curvature drop past the horizon; `World.curvature_drop()` still has
      no callers.
- [ ] A slider on the Terrain rebuilds every tile; the near ring comes back
      synchronously, the rest over a few frames.
- [x] ~~The albedo is 1 m/texel and visibly soft underfoot.~~ The bake is
      off the material since 2026-09-14; the ground's colour is a flat albedo
      with noise-driven variation, and the sharpness underfoot is the detail
      layer's job.

## Open

- [x] ~~Colour grading pass on the macro albedo.~~ Moot: the bake is off
      the material (2026-09-14), and a DEM has no colour to grade.
- [ ] The spawn playa is the flattest ground on the map, which makes the
      immediate area bland. Moving the terrain offset trades that against
      spawning somewhere with more character. #next
- [x] ~~Pick the real terrain solution.~~ Ours, not Terrain3D (09-03), and
      now composed from the real south pole (09-14) - see "Where it is going".
- [x] **Real-ground probe.** Done 2026-09-14 - see "The real ground, measured"
      above. The pole patch is the scene's ground; the frames are in
      `previews/2026-09-14/lola-*`. #now
- [ ] **The detail layer**, next: the 5 m data at 4 m spacing is a smooth
      sheet up close, and it is what the streaming plan needs anyway. Craters
      on the size-frequency law below 50 m, regolith undulation, boulders from
      the fresh ones - composed into the tile buffer, on F1. #next
- [ ] The scene's facilities, relay and crates keep their old X/Z and land
      wherever the real ground puts them. Fine for a probe; a settlement is a
      placement pass on the real map, and Mac's. #next
- [ ] The masters are retired but the baked `world_01_*` files stay in the
      repo until the LOLA bake replaces them; `_source/` is Mac's to delete.
      The colour master goes with it: a DEM has no colour, so the ground's
      colour becomes the mask-driven material queued on 09-03. #next
- [ ] On the Moon, the horizon as the far cutoff. Measure before building: a
      probe on the real heightmap reporting how much ground curvature hides from
      ordinary positions. Arithmetic says it hides small things and not relief -
      a 20 m rise stays visible to ~11 km from a standing eye - and vacuum has no
      fog, so the world's edge shows from any high ground. Nothing simulates
      curvature yet; `World.horizon_distance()` has no callers. Proposed
      2026-09-13. #next
