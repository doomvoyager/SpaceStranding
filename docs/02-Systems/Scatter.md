---
status: built
verified: 2026-08-31
godot: res://scripts/world/rock_scatter.gd
tags: [system, world, performance]
---

# Scatter

Boulders across the terrain patch, drawn as MultiMesh instances in
distance-culled cells. `RockScatter` is a `@tool` Node3D that sits **beside**
[[Terrain]], never under it.

## Cells are the design, not an optimisation

A MultiMesh is *one* instance holding thousands of transforms. Put the whole
field in one and its AABB is the size of the patch - the camera is always
inside it, so it can never be frustum-culled and `visibility_range_end` never
fires.

Measured in `tests/probe_scatter_cull.gd`, 8192 rocks over 512 m:

| | prims | draws | ms over empty |
|---|---|---|---|
| One MultiMesh, whole patch | 1,376,256 | 1 | +0.39 |
| Same + `visibility_range_end = 120` | **1,376,256** | 1 | +0.30 |
| 32 m cells, no range | 505,344 | 94 | +0.12 |
| **32 m cells + range 120** | **96,768** | 18 | **+0.05** |
| 16 m cells, no range | 467,712 | 348 | +0.48 |

A distance range on the whole-patch MultiMesh dropped **exactly zero**
primitives. Splitting into cells is what makes any of it work. The bottom row is
the other edge: 16 m cells with nothing culling them measured *worse* than
doing nothing at all, because 348 draw calls of tiny batches beat one big one.
Cells only pay while culling is eating them.

## Why the default cell is 48 m and not 32

The synthetic probe above says 32. The real scatter says 48, because it has a
multiplier the synthetic test did not: **a MultiMesh holds exactly one mesh, so
every rock variant is a separate instance in every cell.** Six variants across
two detail tiers is up to twelve multimeshes per cell.

`tests/probe_scatter_cost.gd`, 3297 rocks on the real 512 m patch at eye height:

| | prims | draws | ms |
|---|---|---|---|
| 6 variants, 32 m cells | 47,120 | 149 | 0.706 |
| **6 variants, 48 m cells** | **42,640** | **97** | **0.551** |
| 6 variants, 64 m cells | 71,360 | 81 | 0.608 |
| 48 m cells, culling off | 379,840 | 263 | 0.769 |

48 m draws fewer primitives than 32 m *and* a third fewer calls. Culling
removes **89%** of the primitives.

Draw distance costs roughly the square of itself, which is the row to read
before pushing `cull_distance` out:

| draw distance | prims | draws |
|---|---|---|
| 120 m | 24,400 | 50 |
| **170 m** (default) | 42,640 | 97 |
| 250 m | 74,080 | 184 |
| 350 m | 100,080 | 267 |

On a 4080 all of these are inside the noise floor - the scatter costs about
0.1 ms at defaults. **Primitives and draw calls are the reliable signal**; the
wall clock only starts ranking them on weaker hardware.

## Nothing runs per frame

Culling is `visibility_range_begin/end` on each cell, which the render server
does on its own. `fade_margin` dithers a cell out rather than popping it. The
near tier draws a 320-triangle rock, the far tier the same rock at 80.

The only GDScript that runs at all is a rebuild, and that happens on a property
change - the F1 panel commits scatter sliders on release, like [[Terrain]].

## Placement

Positions are rolled from a seed, then filtered three ways: a low-frequency
noise mask so rocks gather into fields instead of sprinkling like wallpaper, a
slope limit, and a size roll biased toward the small end. About a third of
candidates survive at the defaults.

**Slope is measured in world space.** The Terrain node carries a Y scale that
flattens the map, so a local gradient is not the one you see - the same trap
that had everything in `test_world` spawning in mid-air. Heights come through
`to_local`/`to_global` round trips, never from `height_at()` directly.

Each rock sinks into the ground by a fraction of its **half-height**, read off
the mesh's own AABB. It was originally a fraction of the diameter, which buried
about 70% of every rock, because boulders are squashed on Y and a half-height
is barely a third of a diameter. The field read as flat plates lying on sand
until a render showed it.

## Collision is for big rocks only

Rocks at or above `collision_above` (1.4 m) get a convex hull under a per-cell
`StaticBody3D`; everything smaller is visual. A shape per pebble is both
expensive and horrible to drive over. Hulls are shared per variant and carried
by each instance's own **uniform** scale - Jolt rejects non-uniform.

Collision is not distance-culled. You cannot reach a rock without the renderer
having drawn it first, so there is no invisible-wall case.

## The rocks are placeholder art

`RockMesh` builds noise-displaced icospheres, flat shaded. The reason is now
historical - `painterly.gdshader` was deleted 2026-09-03 and `surface.gdshader`
does not band - but the facets still read better than a smooth boulder, so this
stands until the art style is settled. Originally: the
painterly shader quantised light into three bands, and a smooth boulder turned
those bands into concentric contour rings, where facets take one band each and
read as brushed planes. An icosphere rather than `SphereMesh`, whose poles
pinch into slivers that displacement makes obvious.

`rock_meshes` takes authored meshes and the generator steps aside. That is the
intended path once Mac models a set.

## Where the code is

| | |
|---|---|
| The scatter | `res://scripts/world/rock_scatter.gd` |
| Placeholder boulders | `res://scripts/world/rock_mesh.gd` |
| Material | `res://materials/rock.tres` |
| Regression test | `res://tests/test_rock_scatter.tscn` |
| Culling mechanism | `res://tests/probe_scatter_cull.tscn` |
| Real-config cost | `res://tests/probe_scatter_cost.tscn` |
| Stills | `res://tests/scatter_capture.tscn` |

## Every instance carries whether it is an obstacle

`use_custom_data` is on, and each instance's red channel is 1 when its size is
at or above `collision_above` - the same threshold that decides whether it gets
a collision shape. [[Scanner]] reads it to outline rocks you can actually hit.

Custom data rather than a second MultiMesh on purpose: splitting the big rocks
out would double the instance count per cell per variant, which is precisely the
draw-call cost the cell design exists to avoid.

**It has to be enabled while `instance_count` is still 0**, exactly like
`transform_format`. Set it afterwards and the engine refuses the change, and
every subsequent write is dropped - silently, unlike the transform-format case,
which at least complains.

## Interactions

- [[Terrain]] - sampled for height and slope, and emits `rebuilt` so the rocks
  follow when the ground is retuned.
- [[Debug-Panel]] - every knob is a slider, committed on release.
- [[Rover]] - big rocks are the obstacles "picking a line through rocks"
  assumes.

## Known issues

- [ ] The scatter covers one 512 m patch and rebuilds all of it at once. Fine
      here, will not survive a streamed map - cells are already the right unit
      to stream, but nothing streams them.
- [ ] `rock_positions()` exists partly because a MultiMesh cannot be asked
      where its instances are from outside the renderer. Nothing but the test
      reads it yet.
- [ ] Authored meshes get no low-poly tier - both tiers draw the same mesh, so
      only the far cull helps. Imported LODs would fix it.

## Open

- [ ] TODO: decide whether rocks should nudge cargo spawn points, so a crate
      never settles inside a boulder. `rock_positions()` is already the query.
      #next
- [ ] TODO: drive through it and set `cull_distance` by eye. 170 m is a
      measured-cost default, not a looked-at one, and rocks stopping mid-view
      is visible from high ground. #playtest
