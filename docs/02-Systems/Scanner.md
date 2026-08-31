---
status: built
verified: 2026-08-31
godot: res://scripts/world/scanner.gd
tags: [system, traversal, ui]
---

# Scanner

`Q` / `LB`. One ping goes out as an expanding ring; ground it has passed keeps a
dot grid coloured by **whether the [[Rover]] could drive it**, and anything
usable it sweeps over gets a tag.

The acknowledged parent is the Odradek. What is ours is the colour: it answers
*can I drive that*, against a number measured off the rover, rather than
painting steepness.

## Behaviour

A pulse travels out at `wave_speed` to `reach`, holds, and fades. Ground behind
the front keeps the grid; the front itself is a brighter ring, which is what
makes it read as a wave going out rather than a radius being resized.

Tags name what they are and how far off: `Water canister   12 m`. They are
capped and decluttered - see below.

**The grid thins out over the last `edge_fade` metres of `reach`**, rather than
ending on a circle. The wave front already softened as it travelled, but ground
it had passed stayed at full strength right up to the limit and then simply
stopped - a hard rim you could see from any height. The same term fades the
ring, so the front *dissolves* on its way out instead of arriving and switching
off. 22 m of a 70 m reach by default; `edge_fade` is clamped to 90% of `reach`
when pushed, so a fade wider than the range cannot dim the grid underfoot.

## Where the pulse lives

**Global shader uniforms.** One scanner drives every surface in the world with a
single write per frame, rather than holding a list of materials and keeping it
in step with the scene. Declared in `project.godot` under `[shader_globals]`.

A **local** `scan_grid_enabled` on each material decides who actually draws the
grid: `regolith_painterly` and `rock_painterly` yes, crates and hulls no, where a
slope-coloured dot grid would mean nothing. The pulse still reaches them; they
get tagged instead.

**The tunables are `@export`s on `scanner.gd`**, pushed into those globals from
their setters. A `ShaderMaterial`'s uniforms carry `PROPERTY_USAGE_EDITOR` but
*not* `PROPERTY_USAGE_SCRIPT_VARIABLE`, so the [[Debug-Panel]] cannot see them -
and a number nobody can move while driving is a number nobody will tune.

That was only half the story on the day it was built. Script exports *are*
reflected, but which objects the panel looks at is a hand-written list — so the
scanner shipped with every slider it needed and none of them on screen. Fixed
2026-08-31; see [[Debug-Panel]] for the seam.

## Two positions, not one

**The pulse goes out from the player; the labels measure from the player *now*.**

The origin cannot be the astronaut's node - boarding the rover hides it and
leaves it where it stood, so scanning from the driver's seat would ping a spot
in the sand behind you. It was the *camera* for a while, which fixed that and
introduced a quieter problem: the chase arm sits six metres back, so every
distance read long. `_viewer_position()` answers properly - the rover when
someone is driving it, the astronaut otherwise.

**A tag's distance is recomputed every frame against where you are**, so it
counts down as you walk toward the thing. Only the *reveal* geometry stays
anchored to the origin: what the wave has swept over is a fact about the ping,
and letting it chase the player would mean walking forward kept uncovering
things the pulse had already gone past.

Those were one number until 2026-08-31, which is indistinguishable from correct
for exactly as long as the player stands still.

## Green and red mean something

`max_slope_deg` is **26**, and it was measured. `probe_rover_climb.tscn` puts the
loaded rover on slopes of known angle at full throttle and reports how far it
gets up each in a fixed run, against the same run on the flat:

| slope | up-slope in 5 s | vs flat |
|---|---|---|
| 0° | 37.0 m | 100% |
| 8° | 31.8 m | 86% |
| 16° | 25.9 m | 70% |
| 24° | 19.6 m | 53% |
| 32° | 14.0 m | 38% |
| 40° | 8.9 m | 24% |
| 48° | 3.3 m | 9% |
| 56° | −5.6 m | slides backwards |

**The rover does not stall** anywhere useful - it slows, smoothly, until 56°
where it slides back down. So the threshold is where progress *halves*: 25.5°,
rounded to 26. Red then promises "this will cost you half your speed or worse",
which is the honest thing a slope colour can say. Anything else makes the scan a
picture of steepness.

Slope comes off the rendered normal in the fragment shader, so it accounts for
whatever scale the terrain node is carrying - which matters, because the terrain
in `test_world` is scaled 0.5 on Y. The player drives the terrain as drawn.

## Three things the look cost

None of these were visible from the code, and all three came out of
`scan_capture.tscn`.

**Additive emission came out white.** The scene tonemaps with ACES, which clamps
saturated colour hardest exactly where it is brightest - the same property
[[Visual-Direction]] already notes for the palette's reds. A grid emitting at 1.5
was perfectly visible and carried no information at all.

**Darkening the albedo and adding emission came out pale mint.** The fill term a
few lines above the scan block had already pushed ambient into `EMISSION` using
the *red* albedo, so the dot was a wash over that. A dot has to **own** both
channels: `ALBEDO` to black under it, `EMISSION` replaced rather than added.

**Nineteen tags in one pile is unreadable.** Six crates beside each other became
a single smear of overlapping text. Capped at the twelve nearest, *plus* a
screen-space separation test - the cap alone still stacks the nearest six on top
of one another.

`probe_scan_glow.tscn` measures mean saturation and blown-pixel fraction across
a range of emission strengths rather than arguing about them. 0.55 is the knee:
2.6% of dot pixels clipped, against 7.8% at 0.8 and 26% at 1.8.

## Interactions

[[Rover]] · [[Astronaut-Traversal]] · [[Terrain]] · [[Cargo]] · [[Orders]] ·
[[The-Lattice]] · [[Visual-Direction]]

## Verification

`res://tests/test_scanner.tscn` covers everything around the picture: that the
wave travels rather than arriving everywhere at once, that `reach` excludes
things beyond it, that the tag cap holds, and that a pulse ends and releases its
labels - a scanner leaking a `Label3D` per object per ping is a slow leak behind
a key the player will press constantly.

It is driven by the scanner's own state rather than by frame counts. The pulse
advances on `_process` and the checks run on `_physics_process`, and headless
does not interleave those two clocks anything like realtime: one version asked
for progress two physics frames after the ping and got exactly zero, the next
waited 150 frames for a wave that had already finished.

`res://tests/scan_capture.tscn` is the look pass, and
`res://tests/probe_scan_glow.tscn` the tuning one.

## Open

- [ ] TODO: the dot grid is world-locked at a fixed spacing, so it is dense far
      away and sparse up close. Death Stranding's thins with distance. Worth a
      look once there is terrain with real relief to judge it against.
      #playtest
- [ ] TODO: nothing distinguishes *why* something is tagged - a crate you own, a
      crate belonging to an order, and a facility all read as text in slightly
      different colours. Icons are the obvious answer and are Mac's call.
      #question
- [ ] TODO: the pulse ignores line of sight entirely: it tags things through
      hills. [[The-Lattice]] already has a terrain sight-line solve that could
      be reused, at the cost of a raycast per candidate. Whether the scanner
      *should* be occluded is a design question, not only a cost one. #question
- [ ] TODO: no sound. A scanner is half a sound effect. #next
