---
status: built
verified: 2026-09-16
godot: res://scripts/ui/lens.gd
tags: [system, look]
---

# Lens

The camera's own glass: the sun's flare, the smudges the sun lights up, and
regolith dust that builds up on the chase camera's lens while you drive. Mac
asked for all three on 2026-09-16, with two textures and a flare shader
from godotshaders.com; what was built is below, and the calls made on the
proposal are in the [[Decision-Log]].

## Behaviour

- **The flare** appears when the sun is in the frame and nothing is in front
  of it, and goes the moment something is - the rover, a crater rim, a
  mast. It fades out over the last `sun_edge_margin` of the frame.
- **The flare dirt** (`dirt_flare_1.jpg`) is invisible until the sun is in
  view, then lights up: most strongly near the sun, `dirt_floor` of it
  everywhere on the lens.
- **The dust** (`lens_dirt_2.png`) is on the rover's chase camera only. It
  builds while the wheels throw regolith toward the camera, specks landing
  one by one in a random order; it fades once nothing has reached the lens
  for `fade_delay` seconds, over about half a minute; climbing out of the
  rover wipes it. In shade a speck reads as a faint grey - lit by the frame
  it sits in - and in the sun it glows.
- The cab eye and the astronaut's cameras have no dust; all four cameras get
  the flare and the dirt. The post layer draws under the HUD, so none of it
  lands on the interface.

## How it works

Four pieces:

- **`film.gdshader`** draws all of it, in the post stack's one pass - three
  sections between the halation and the grain. One pass is a settled call
  (2026-08-31): a second screen-reading pass would cost a second full-screen
  copy and mip chain, which is what an Apple GPU minds most.
- **`Lens`** (`scripts/ui/lens.gd`, the script on
  `scenes/postprocessing_effects.tscn`) works out, every frame and after
  every camera rig has moved, where the sun is on screen, how big its disc
  is there, and how dusty the current camera's lens is, and pushes them as
  shader globals: `lens_sun_uv`, `lens_sun_radius`, `lens_sun_ahead`,
  `lens_sun_color`, `lens_dust` (declared in `project.godot`). Globals so the
  F1 panel, which lists the material's uniforms, never offers them as
  sliders.
- **`LensDust`** (`scripts/vehicle/lens_dust.gd`) is a child of the camera it
  dirties - `rover.tscn`, under the chase camera - and keeps a `coverage`
  from 0 to 1. It changes only while its camera is on screen, so a spell in
  the cab leaves the chase lens as it was.
- **`WheelDust.exposure_at()`** says how much of the spray is flying at a
  point: per wheel, its rate over the full rate, times how squarely the point
  sits behind its throw, falling off past `reach`. `LensDust` finds the
  WheelDust on the vehicle it rides by itself, so the rebuilt rover needs no
  path.

### Is the sun visible? The picture says

The flare needs to know whether anything is in front of the sun, and
physics cannot tell it: the streamed ground has collision only within
`collision_radius`, so every far rim is invisible to a ray, and the rover's
wheels are raycasts with no shape. So the shader looks at the picture.
`tests/probe_sun_disc.tscn` measured what the post pass reads:

| where | min channel, 0-255 |
|---|---|
| the sun's disc, 32-40 px at 1600x900 | 255 |
| its glare ring | 130-150 |
| the rover in front of the sun | 24-26 |
| terrain in front of it | 30-32 |
| a rim with the disc just under it | 22-25 |

Anything in front of the sun is seen from its unlit side, so this holds by
construction, not by luck. `vertex()` takes nine taps inside the disc - a
canvas_item `vertex()` can read the screen texture and reads exactly what
`fragment()` does - and the fraction that are white is how much sun the lens
gets. Four corners, 36 fetches a frame. The same corner pass reads the frame's
mean colour off the top mip, which is what lights the dust in shade.

The known hole: a white HUD label over a hidden sun would read as the sun.
That is one of the two reasons the post layer went under the HUD.

### The flare

mu6k's `lensflare()` from Shadertoy 4sX3Rs, by way of malhotraprateek's
Godot port (godotshaders.com, MIT). The Shadertoy page was behind a bot check
on 2026-09-16; search results quote its author as saying it is free to use,
credit appreciated, and the shader's comment credits both. The ghost
positions and falloffs are theirs. Fixed on
the way in: `SCREEN_TEXTURE` does not exist in Godot 4; `cc()` and the dither
graded the whole frame, sun or no sun, and the `- length(uvd) * .05` term
darkened every frame's corners; the noise texture fed only those. Added: the
two kinds of ghost weighted apart (`flare_halo`, `flare_ghosts`), because
the port's broad halo sits on the sun when you look straight at it and
washed the frame orange - which on the Moon reads as air.

## Where the numbers are

On `shaders/post/film_material.tres`, in the inspector and in F1 under
"Post (Film)": the Sun, Flare, Dirt and Dust groups. The dust's timing is on
the `LensDust` node, in F1 under Driving as "Lens dust".

| | value | why |
|---|---|---|
| `sun_threshold` | 0.95 | between the disc's 1.0 and the glare's 0.6 |
| `flare_intensity`, `flare_halo`, `flare_ghosts` | 1.0, 0.35, 2.0 | the halo at the port's weight doubled the frame's brightness looking at the sun |
| `flare_tint` | (1, 0.9, 0.8) | cooler than the port's (1, 0.857, 0.714) |
| `dirt_intensity`, `dirt_floor`, `dirt_spread` | 0.4, 0.1, 0.4 | a floor of 0.25 veiled the whole lens |
| `dust_density`, `dust_ambient`, `dust_glow` | 2.5, 3.0, 0.6 | at 1.5 and 2.0 full coverage moved 2% of a shaded frame; at 1.0 lit dust read as snow |
| `LensDust.build_rate` | 0.04 | the chase camera measures an exposure of 0.51 at 3.9 m/s, so a clean lens is full in about 50 s |
| `LensDust.fade_rate`, `fade_delay` | 0.033, 2 s | Mac's "fades slowly": full to clean in 30 s |

All of it is Claude's first pass on stills, and Mac's to retune by eye.

## The textures

`lens_dirt_2.png` arrived at 6016x4016 and 55 MB. The master is in
`game/assets/textures/_source/` - gitignored, `.gdignore`d, the terrain
masters' rule - and `tools/bake-textures.py` writes the 3008x2008 copy the
game uses (2.7 MB, Mac's colours kept). Both textures import VRAM-compressed
(BPTC) with mipmaps, set by hand in their `.import`: 8.1 MB and 2.8 MB, where
lossless would be 32 MB for the dust alone. The dust texture's RGB is taken as
the dust's hue only; its brightness comes from what lights it.

Both are drawn cover-fit - scaled to fill the frame and cropped, never
stretched - so a speck keeps the shape it was painted.

## What it costs

`tests/probe_post_cost.tscn`, the same view of the sun with the glass at its
worst (sun centred, lens fully dusted) and with it skipped: **0.019 ms of GPU
time** at 1600x900 on an RTX 4080, 0.658 against 0.677, five alternating
rounds each within 0.003 of its median. Wall clock cannot see it at all - its
rounds spread 0.3 ms. Not yet measured on the MacBook.

## What the stills showed

`previews/2026-09-16/flare-*` (four sets: v1, v2, v3, after), `sun-disc-*`,
`post-cost-*`:

- **Covered is covered.** Behind the rover, behind a rim, with only the glare
  over a rim, and just out of frame, the glass moved 0.00% of the frame.
  Sunward from the chase camera the cab covers the sun, and there is no flare:
  that is right, and it will be the common view driving at the sun.
- **Dark dust vanishes against a black sky.** The first pass painted specks
  in the texture's own brown and full coverage moved 0.8% of a shaded frame.
  Lit by the frame's mean instead, and denser, it moves 4.4%.
- **Specks land in order.** 25, 50 and 100% coverage moved 3,921, 7,593 and
  15,196 pixels: linear, as the stretched noise intended.
- **A broken shader draws the frame white.** The name clash below turned
  every shot to luma 1.000 and the run carried on - the capture's numbers are
  what caught it.

## Verified

- `tests/test_lens_flare.tscn` - the post layer carries `Lens` and finds the
  scene's sun; the sun's position against a projection worked out by hand at
  four headings; the disc's radius in pixels; behind the camera; the dust of
  the camera on screen, of one without a lens, and of no camera; the post
  layer under the HUD, the order and map panels, and F1. 22 checks.
- `tests/test_lens_dust.tscn` - one wheel's share (behind, in front, to the
  side, off-axis, far, half rate, quiet, on top); a lens building, holding,
  fading, clearing; then the rover: the chase camera carries a LensDust that
  finds the WheelDust, the eye has none, a parked rover throws nothing, the
  lens dusts over driving and the post layer sees it, holds while the cab eye
  is up, gets nothing while reversing, fades stopped, and is wiped on exit.
  35 checks.
- `tests/flare_capture.tscn` - windowed; each still off and on, with the share
  of the frame moved.

## Open

- [ ] Mac's pass on the look, driving: how strong, how warm, how fast the
      dust builds. #playtest #question
- [ ] The cost on the MacBook's GPU; the probe prints GPU time now.
- [ ] Offered, not built: a starburst on the sun - Apollo frames with the sun
      in them have one.
- [ ] Offered, not built: an electrodynamic dust shield that clears the lens
      in a visible sweep, in place of the slow fade.
- [ ] Dust on the cab's windscreen, and off the boots onto the on-foot lens -
      the node is generic, the sources are not built. See [[Wheel-Dust]].
- [ ] "For now" on the post layer under the HUD: the HUD lost the grain and
      the colour fringe it had. Mac's to revisit.
