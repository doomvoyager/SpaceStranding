---
status: built
verified: 2026-09-02
godot: res://scripts/world/scanner.gd
godot: res://scripts/world/site_sign.gd
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
capped and decluttered - see below. **The rover does not tag itself while you
are driving it**, which would be a label hanging in your own windscreen naming
the vehicle you are sitting in.

**A facility is not tagged at ground level either.** It is named by its own mast
sign instead, which is the same reveal moved up to the aerial and given four
times the reach - see below.

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

## The name at the mast

`site_sign.gd`, on the `Sign` node of `facility.tscn` and `relay.tscn`. Added
2026-09-02.

The sign used to be scenery: always up, and big enough to read from across the
Verge. That worked while there were two facilities on an empty plain, and
stopped working the moment the world had things in it - a name burning over
every site at all times is the map drawn on the world, and it flattens the thing
this game is about, which is not knowing what is over the ridge until you go and
look.

So the sign is dark until `Q`, and then it is **the site's scan tag**: same
envelope, same fade, same distance readout that counts down as you approach.
Two things about it are deliberately not the same as a tag:

- **`sign_range` is 200 m against the pulse's 70.** A facility is the one thing
  worth finding from further away than the wave itself travels. The pulse never
  physically reaches a sign at 200 m, so it lights when the front hits its own
  limit - which reads as the return coming back rather than as a switch.
- **It is anchored to the mast**, 8.4 m up on a facility and 13.4 on a relay,
  not to `tag_lift` above the ground.

**`Scanner.tag_groups` no longer lists `facility` or `relay`.** With both, a
site inside the pulse's reach was named twice - once here at the mast and once
seven metres below at ground level. The close-range parts of a facility -
terminal, dock, storage, delivery pad - are still tagged by the scanner, and are
the reading that matters once you have arrived.

**Size: 0.00018, down from 0.0004.** `probe_sign_size.tscn` renders the same
frame at five values; 0.0004 dwarfs the building it names, 0.00012 loses its
strokes to the outline against red terrain, and 0.00018 is legible at 200 m
without being the loudest thing in frame. It sits just below `tag_size`
(0.00022), which is right: the sign is further away than anything the scanner
tags.

### Two names in one place

A sign is a node in its own scene and knows nothing about the other signs, so
the first version wrote them straight through one another: three sites 60 m
apart, seen from 200 m, produced `LONGSHADOW - 58 M` and `RELAY - 23 M` sharing
the same 145 px of screen. The same failure the tag pile was, arrived at from
the opposite direction.

**The arbitration lives on the scanner, and the sign asks for it.**
`sign_has_room()` decides once a frame which names fit, nearest-to-the-ping
first, refusing anything within `sign_separation_px` of a name already placed.
200 px by default, which is the first value that separates the frame above; a
sign is a much wider label than a tag, which is why it is not
`tag_separation_px`.

Three things about the shape of it:

- **Ordered by distance from the ping, not from the player.** The origin does
  not move for the life of a pulse, so a name cannot swap places with its
  neighbour while you drive past.
- **The sign asks rather than being told.** A flag pushed from the scanner would
  be a frame stale by the time the sign drew, and the sign would spend that
  frame visible in a slot it had already lost.
- **A sign missing from a frame's answer forces a fresh one.** That is the
  correctness argument, not defensive coding: the signs run their own clocks in
  their own `_process`, in tree order, and one crosses from "the wave has not
  reached me" to "I want to draw" *during* that pass - so the sign that ran
  first can trigger the resolve while a later one still looks idle. Absent read
  as "no reason to refuse you". It cost exactly one frame of a name drawn in a
  slot it had lost, and the crowding test caught it.

New tags are also refused a spot on top of a sign - `sign_points()` seeds the
tag reveal's taken list. **A tag already placed is not moved**, though: tags are
sticky once created, and a site further off than something taggable beside it
lights its sign after that tag has claimed its spot. They end up on adjacent
lines rather than through each other, which is legible, so it stands.

`Facility.mast_point()` returns the sign's global position, so the sign is also
the facility's aerial for [[The-Lattice]]. Hiding a node does not move it, so
none of the above touches the graph - but *moving* the sign moves the aerial,
which is worth knowing before nudging it in the inspector.

## Obstacles get an outline

Rocks big enough to hit are drawn with a red silhouette while the scan is up.
Colour, strength and sharpness are on the F1 panel; strength 0 turns it off.

**"Sticking above the ground" is a distinction [[Scatter]] already makes.** A
rock at or above `collision_above` is exactly the set that gets a collision
shape, so the outline marks what you can actually *hit* rather than whatever
happens to be visible. Nothing new had to be measured or guessed.

It travels to the shader as **MultiMesh custom data** - red channel 1 on an
obstacle - and is drawn as a **rim term**. Both choices are about draw calls:
splitting big rocks into their own MultiMesh, or adding an inverted-hull pass,
each mean a second MultiMesh per cell per variant, and draw calls are the budget
the whole cell design exists to protect.

`use_custom_data` has to be set while `instance_count` is still 0, exactly like
`transform_format`. Set it after and the engine refuses, then every write is
silently dropped and no rock ever outlines. `test_rock_scatter.tscn` asserts the
flag is on; the per-instance *values* cannot be checked headless, for the same
measured reason instance transforms cannot.

The outline is gated by the same swept and edge terms as the grid, so it arrives
with the wave and thins out with it rather than snapping on across the map.

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

## What a pulse actually costs

Mac reported a large drop while scanning, worse with the map up. **The scanner
was not the cause.** Measured on the real world, 1600x900, with a three-stop
route planted:

| | before | after |
|---|---|---|
| idle | 1.11 ms — 899 fps | 1.10 ms — 906 fps |
| map open | 2.47 ms — 405 fps | 1.19 ms — 841 fps |
| scanning | 7.49 ms — 134 fps | 1.32 ms — 755 fps |
| scanning, map open | 8.67 ms — 115 fps | 1.38 ms — 725 fps |

Switching each suspect off in turn said where it went. The tags cost 0.09 ms
for nineteen of them. The dot grid in the terrain shader cost **nothing
measurable** — turning `scan_grid_enabled` off changed the frame not at all.
What a pulse actually does is switch on [[The-Map]]'s route reveal, which was
rebuilding its whole line every frame: 399 vertices, each a
`Route.ground_height()`.

And that call was 76% overhead. `Lattice._terrain()` checked the `terrain`
group first and then fell back to a recursive walk of the tree — but
**`terrain.gd` never joined the group**, so the fallback ran every time, over
9,524 nodes, at 10.5 us a call. It is a field read now, and the group is
actually populated:

| | before | after |
|---|---|---|
| `Lattice.terrain()` | 10.5 us | 0.49 us |
| `Route.ground_height()` | 13.8 us | 3.1 us |

Every height query in the project goes through that function — the Lattice's
own line-of-sight walks and the mast survey included — so the cache is worth
more than the frame it was found in.

`res://tests/probe_scan_cost.tscn`, windowed. Both halves of the fix are
described under [[The-Map]], since the route line is where they live.

## Interactions

[[Rover]] · [[Astronaut-Traversal]] · [[Terrain]] · [[Cargo]] · [[Orders]] ·
[[The-Lattice]] · [[The-Map]] · [[Visual-Direction]]

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

`res://tests/test_site_sign.tscn` covers the mast signs: that they are dark
with no pulse out, that they connect to the scanner lazily and actually receive
the ping, that `sign_range` gates, that the distance is measured from the player
rather than from the mast or from where the ping went out, and that they go dark
again with the pulse. It also asserts that `tag_groups` has stopped listing
`facility` and `relay`, which is the guard against the double label coming back.

Its last two stages move one sign onto another and assert that the nearer name
keeps the space and the further one goes dark, then switch `sign_separation_px`
to zero and assert both come back - so a pass cannot be a sign that was simply
broken. It builds its own camera rather than depending on which way the
astronaut faces at spawn, because a sign behind the camera is correctly refused
a slot and the test would fail for the wrong reason. `unproject_position()` is
arithmetic on the camera and works fine under `--headless`; that was measured by
`res://tests/probe_headless_unproject.tscn` rather than assumed, because the
neighbouring fact about synthesised mouse events never reaching the GUI makes it
exactly the kind of thing that would not.

`res://tests/scan_capture.tscn` is the look pass,
`res://tests/probe_scan_glow.tscn` the tuning one, and
`res://tests/probe_scan_cost.tscn` the cost one, and
`res://tests/probe_sign_size.tscn` the sign-size sweep. All four run
**windowed**.

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
