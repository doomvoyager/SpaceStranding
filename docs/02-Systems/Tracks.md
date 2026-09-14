---
status: built
verified: 2026-09-14
godot: res://scripts/world/track_map.gd
tags: [system, world, look]
---

# Tracks

Wheel tracks in the regolith, left behind the rover and read by the ground.
Mac asked for them shader-based on 2026-09-14, and they are: nothing is added
to the scene per stamp, no decals and no ribbon meshes. The wheels paint into
one texture, and `surface.gdshader` samples it.

## How it works

**`TrackMap`** (`scripts/world/track_map.gd`, a node in `test_world.tscn`
following `../Rover`) owns a `SubViewport` that is never cleared. Every physics
tick each wheel in contact stamps a small sprite at its contact point, once it
has moved a third of a stamp length since its last, so stamps always overlap.
The viewport's texture goes to every material as the global uniform
`track_map`, the way the scan pulse's globals do.

**The map is a window that follows the rover, addressed toroidally.** A world
point lands on texel `posmod(xz / texel_size, texels)` whatever the window's
position, so moving the window copies nothing: it changes which world range is
valid, and the strip of texels the window has rolled onto - still holding a
picture from a window ago - is wiped with the empty value. The shader
bound-checks against `track_origin` so a point outside the window never reads
its alias inside it. 4096 texels at 0.08 m is a 328 m window and 48 MB of
texture, and beyond 160 m a track is two pixels wide anyway.

**The window forgets; the trail remembers.** Mac drove out of range and asked
for persistence, "more important than precision". `TrackTrail`
(`scripts/world/track_trail.gd`) records every stamp - position, heading,
depth, length, sixteen bytes - bucketed into 8 m cells, and when the window
rolls onto a strip the map wipes it and then paints back every remembered
stamp inside it (`TrackMap.new_ground()` says which world rectangles those
are; `_replay()` does the painting). Drive back to ground you crossed an hour
ago and the tracks are there as the window arrives, drawn by the very stamps
that made them - so this gives precision too. Measured in `track_capture`:
the rover moved 600 m away, long enough to wipe everything, and back;
1,293 stamps were painted back and the from-above frame differs from the
original by 0.35% of pixels, which is the rover having rolled a little.

The trail is the storable curve: `save_trail()` and `load_trail()` on the
map, `to_bytes()` and `from_bytes()` underneath, a versioned dictionary of
packed arrays. A 25 km drive is about 10 MB. Nothing calls them yet - the
game has no save - and `remember` on the node switches the whole memory off.
**Rejected: ribbon meshes along the stored curve**, the decal-style version:
a second material on a split shader, and two strips fighting wherever a
track crosses itself, to gain visibility at a range where a track is under a
pixel.

**Three channels.** R is depth. G and B are the direction of travel as
`0.5 + 0.5 (cos 2t, sin 2t)`, doubled so a wheel going the other way writes the
same value and so the map filters cleanly at a bend. The stamp's depth is a U
across the tyre (`rut_profile`), which is what a rut is and which also tells
the shader how far from the centre line a point is, since the map does not
store that. Stamps blend with MIX, so overlapping stamps converge on a value
rather than piling up, and the empty map is `(0, 0.5, 0.5)`, not black, so a
soft edge does not pull the direction toward a corner.

**What a track does to the ground** is what compressed regolith does. In
`surface.gdshader`, behind the per-material `tracks_enabled`:

- darkens the albedo by `track_darkening` times depth;
- bends the normal into a rut from the depth gradient, three extra samples a
  texel apart, scaled by `track_rut_depth` in metres;
- draws chevron tread ridges across the track from the stored heading,
  spaced `track_tread_spacing`, swept back off the centre line by
  `track_chevron_reach`, and faded out once a ridge is under about two pixels
  because the map has no mip chain to do it;
- switches off the opposition surge in `light()` under the track and halves
  the backscatter, so a track reads darker down-sun than the ground beside it
  - the real reason a track is visible from the cab on the Moon.

**Skid** deepens a stamp: `get_skidinfo()` is 1 with grip and 0 sliding, and
`skid_depth` is added at full slide.

## Footprints

`Footprints` (`scripts/player/footprints.gd`, a child of the astronaut) puts
the boots into the same map through `stamp()`, which takes a length and a
width since a boot is not a tyre. **It reads the skeleton, not the
animation** - Mac has new animations coming and asked what they would cost
the prints: nothing. Every physics tick the two toe bones' world positions
are taken, a ray under each finds the ground, and a foot is *down* when the
toe is within `contact_height` of it and moving slower than `contact_speed`
across it. Up to down is a landing, and a landing stamps one boot, centred
under the foot and headed heel to toe, if the foot has moved `min_step` from
its last print. Whatever the clip does with the feet is where the prints go;
what a new rig has to keep is the four bone names, which are exports, and
its feet on the ground, which a slider forgives. Only ground in the
`terrain` group takes a print - a facility deck does not - and nothing
stamps while the astronaut is hidden aboard the rover.

Measured on the Mixamo walk: the toe bottoms 4-7 cm *below* the floor; the
planted foot slides at up to about 1 m/s under a body doing 3 m/s, which at a
0.8 m/s threshold double-stamped a foot every few strides, so the threshold
is 1.5 and the step 0.5 m. Dropped half a metre onto the floor, both feet
print, which is right. A boot at 0.33 by 0.17 m is four texels by two on the
8 cm map, so a print is a dash at range and a boot up close; finer texels
cost window.

## Where the numbers are

Everything opens in the inspector. On the `TrackMap` node: the window
(`texels`, `texel_size`, `advance_step`), the stamp (`track_width`,
`stamp_length`, `depth`, `skid_depth`, `edge_softness`, `rut_profile`). On
`regolith.tres`: the look (`track_darkening`, `track_rut_depth`, the three
tread values). The F1 panel lists the node under Driving as "Wheel tracks";
the material's uniforms are the shader-uniform gap noted in [[Debug-Panel]].

## Verified

- `tests/test_track_map.tscn` - the toroidal texel arithmetic, the heading
  encoding and its round trip, when the window advances and by whole texels,
  which strips a move wipes (one, two across the seam, both axes, the whole
  map on a jump), and that the node follows the rover and queues stamps and
  wipes. The trail: cells, rectangle queries across cell edges, the byte
  round trip, save and load, the world rectangles a move rolls onto, and the
  node painting a remembered stamp back when the window reaches it, after a
  jump, and from a loaded file. 81 checks. Global read-back is skipped
  headless: the dummy renderer returns null for every global, the scanner's
  included.
- `tests/test_footprints.tscn` - the landing rule and the print pose, then
  the real astronaut scene walked four seconds on a floor in the `terrain`
  group beside a map: it finds the skeleton and both feet, the drop onto the
  floor prints once per foot and standing prints nothing, walking leaves
  prints that alternate feet a stride apart with a boot's width and length
  in the trail, and standing still afterwards adds none. 18 checks.
- `tests/footprint_capture.tscn` - walks the astronaut four seconds and two
  sideways, then four frames off the actual print positions, down-sun.
  `previews/2026-09-14/footprints-after-*`.
- `tests/probe_track_viewport.tscn` - a never-cleared SubViewport keeps every
  draw, starts black, and lands two stamps queued into one redraw. Windowed
  only: headless, `frame_post_draw` never fires.
- `tests/track_capture.tscn` - drives the rover four seconds straight and
  three in a turn, then five frames of what it left; then puts it 600 m away
  and back and shoots two of them again, printing how many stamps came back
  and the pixels that differ. `previews/2026-09-14/tracks-after-*` and
  `tracks-mem-*`; `tracks-v1-*` is the first pass, with the chevrons keyed to
  the world origin and a moire at range, both fixed by hanging the tread off
  the depth profile and fading it by `fwidth`. The rover is moved with the
  driver out: driven, a transform write was undone by the next physics frame.

## Open

- [x] ~~Persistence beyond the window.~~ The trail, 2026-09-14: the window
      repaints from memory as it moves. On the Moon a track lasts a million
      years; now it lasts a session.
- [ ] **Across sessions.** `save_trail()` and `load_trail()` exist and
      nothing calls them; the game has no save yet. When it does, the trail
      is one file in it. #next
- [ ] The trail only grows. A route driven a hundred times is a hundred
      layers of stamps in the same cells, all replayed; a cap per cell, or
      thinning old samples under new ones, when it shows.
- [x] ~~Footprints.~~ `Footprints` on the astronaut, 2026-09-14, off the
      skeleton so new animations cost nothing.
- [ ] A boot is two texels wide on the 8 cm map. If prints matter up close,
      6 cm texels (246 m window) or a second, finer map for the boots.
- [ ] The tread is a first guess: a U-chevron at 10 cm, faint. The real hauler
      has no tyre yet, so the pattern is whatever its wheels turn out to be.
      Mac's.
- [ ] The rut edge is texel-sharp at 8 cm from a low eye; `edge_softness` at
      0.6 hides most of it. Finer texels cost window: 6 cm is 246 m.
- [ ] The map does not survive the rover leaving and re-entering the tree,
      and does not follow a second vehicle. One rover, for now.
