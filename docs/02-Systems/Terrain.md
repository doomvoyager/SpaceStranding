---
status: built
verified: 2026-09-01
godot: res://scripts/world/terrain.gd
tags: [system, world, scaffolding]
---

# Terrain

The world runs on an **authored heightmap** as of 2026-09-01. The procedural
noise it replaced is still in the same script, one enum away, because the tests
that build their own patch want ground with no 15 MB dependency attached.

> Still a **single patch**: no streaming, no LOD, one `ArrayMesh` and one
> trimesh collider. The shipping terrain will be a streamed, chunked setup
> (Terrain3D or equivalent). Gameplay code must not depend on anything in here.

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

| | |
|---|---|
| Footprint | 4096 m |
| Mesh spacing | 4 m - a 1025² grid, ~2 M triangles, the same cost as the old 2048 m patch |
| Relief | 210 m |
| Grade | median 3°, p90 9°, p99 17°, steepest faces past 60° |
| Terrain offset | (-470, 0, +1242) |

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

## Known issues

- [ ] Single patch, no streaming, no LOD. 2 M triangles resident at all times.
- [ ] Rebuilds the whole mesh on any slider. ~150 ms of that is the map's range
      scan, cached after the first read.
- [ ] The albedo is 1 m/texel and visibly soft underfoot. The master only has
      0.5 m/texel to give at this footprint, so sharpening it means a detail
      layer, not a bigger bake.

## Open

- [ ] Colour grading pass on the macro albedo. The master is pinker and more
      saturated than [[Visual-Direction]] calls for; `macro_tint` and
      `macro_saturation` on the material pull it back without a re-bake, and
      nobody has judged where they should sit. Mac's call. #next
- [ ] The spawn playa is the flattest ground on the map, which makes the
      immediate area bland. Moving the terrain offset trades that against
      spawning somewhere with more character. #next
- [ ] TODO: pick the real terrain solution. Terrain3D is still the obvious
      candidate, and the map size question this was gated on now has an answer:
      4096 m. #next
