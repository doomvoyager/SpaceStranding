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
texture: tracks persist to about 160 m behind the rover and are forgotten
beyond it.

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
  wipes. Global read-back is skipped headless: the dummy renderer returns
  null for every global, the scanner's included.
- `tests/probe_track_viewport.tscn` - a never-cleared SubViewport keeps every
  draw, starts black, and lands two stamps queued into one redraw. Windowed
  only: headless, `frame_post_draw` never fires.
- `tests/track_capture.tscn` - drives the rover four seconds straight and
  three in a turn, then five frames of what it left. `previews/2026-09-14/
  tracks-after-*`; `tracks-v1-*` is the first pass, with the chevrons keyed to
  the world origin and a moire at range, both fixed by hanging the tread off
  the depth profile and fading it by `fwidth`.

## Open

- [ ] **Persistence beyond the window.** On the Moon a track lasts a million
      years, and your own tracks from the last trip would be a landmark and a
      way home. A second, patch-wide map at 1 m per texel holding only the
      darkening, no tread, written from the same stamps. Mac's call whether
      it is wanted. #next
- [ ] **Footprints.** `TrackMap.stamp()` is public; a boot stamp from the
      astronaut on each step is the same system. Mac's call. #next
- [ ] The tread is a first guess: a U-chevron at 10 cm, faint. The real hauler
      has no tyre yet, so the pattern is whatever its wheels turn out to be.
      Mac's.
- [ ] The rut edge is texel-sharp at 8 cm from a low eye; `edge_softness` at
      0.6 hides most of it. Finer texels cost window: 6 cm is 246 m.
- [ ] The map does not survive the rover leaving and re-entering the tree,
      and does not follow a second vehicle. One rover, for now.
