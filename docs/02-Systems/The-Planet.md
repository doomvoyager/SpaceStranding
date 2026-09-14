---
status: reference
verified: 2026-09-14
godot: res://scripts/core/world_constants.gd
tags: [system, setting, reference]
---

# The Moon

The game is set at the **lunar south pole, on the crater rims** - realistic, and
50 to 80 years from now. It replaced the fictional Vesper c on 2026-09-13; the
decision log has why that site, and what is still Mac's to decide.

Everything numeric about the world lives in `world_constants.gd`, autoloaded as
`World`. **Never hardcode gravity or the sun's direction anywhere else** -
retuning the world has to stay a one-file change.

As of 2026-08-31 it is a **no-file** change: these are `@export var` rather than
`const`, and the F1 panel ([[Debug-Panel]]) drives them live. Two consequences
worth knowing. Anything *derived* from a tunable is a function rather than a
stored value - `gravity_ratio()`, `horizon_distance()`, `curvature_drop()`,
`sun_direction()` - so it cannot go stale. And gravity has to be pushed to the
physics server as well as stored here, because `project.godot`'s
`default_gravity` is only read when the space is created; `World` does that
itself on every change.

## The body

| Property | Value | Consequence for play |
|---|---|---|
| Radius | 1,737.4 km (`body_radius`, a tunable) | The horizon is 2.43 km from a standing eye, 2.95 km from 2.5 m up, 5.9 km from 10 m. High ground is range. |
| Surface gravity | **1.62 m/s^2 (0.165 g)** | Full mass, a sixth of the weight. Long stops, wide turns, three-second jumps. See [[Rover]]. |
| Atmosphere | None | No drag, no haze, no weather, no sound through the air. |
| Day | 29.5 Earth days | At the pole the sun does not rise and set - it circles the horizon at 0.51 degrees an hour. |
| Surface temperature | Sunlit rims well above freezing; shadowed crater floors near 40 K | Not modelled yet. Vesper c's thermal axis went with it, because nothing had read it. |

Project gravity in `project.godot` is 1.62, so every rigid body and character is
low-g by default rather than by per-script correction.

**Godot's default linear damping was air, and is now zero.** Every rigid body
got 0.1/s of it unless it said otherwise. At 5.39 that hardly showed; at 1.62 it
caps a falling body at 16 m/s, and by arithmetic a rover dropped 30 m lands at
7.97 m/s - just under the 8 m/s `test_speedometer` waits for, which is how it
showed up. With the damping at zero the test passes again. A vacuum has no drag, so
`physics/3d/default_linear_damp` is 0. Angular damping stays at the default
0.1, for the solver rather than for the fiction.

## The sun

Between 85 and 88 degrees south the sun never climbs far: over a lunar day it
swings through about +/-6.5 to 3.5 degrees, circling the horizon rather than
crossing the sky. **`sun_elevation_deg` is 5.5**, inside that band - and it is
where Vesper's red star sat, so the grazing-light facts carry straight over:
flat ground gets `N.L` of about 0.09, and `surface.gdshader`'s hand-rolled fill
is still what keeps the near ground from rendering black.

**White, not red.** There is no atmosphere between the sun and the ground to
redden it, even at five degrees. `sun_energy` is **0.8** since the regolith
went grey (2026-09-14): a dark powder under a black sky needs a strong sun to
read as bright ground, and the 0.46 that matched the red star's luminance left
it mud. The sun is drawn 0.53 degrees across, its real size, by the sky shader.

**It does not move yet.** `sun_azimuth_deg` is fixed; at the pole it really
travels once round the horizon a month. Whether it holds still within a session
and moves between them is open below.

**The sky is black and there is no fog.** `shaders/sky.gdshader` draws it:
black, the sun's disc at its real size with a small glare round it (the eye's,
not the sky's), and faint stars - a camera exposed for sunlit regolith records
none, and `star_intensity` is the honesty slider. Both fogs are off. The scene's
ambient, which only the StandardMaterial3D props see, is a warm grey at 0.15:
the light the sunlit ground throws back, not a sky.

## The ground, and how it is lit

Mac asked for a realistic regolith on 2026-09-14, and the ground went from
Vesper's pink bake under a blue fill to this - all of it in
`shaders/surface.gdshader` and `materials/regolith.tres`, all of it in the
inspector:

- **Grey.** `albedo_color` (0.57, 0.53, 0.48), a warm neutral, no macro map.
  Highland regolith is a dark grey with a slight red slope; the brightness is
  exposure, the hue is the point.
- **Lit as regolith, not as paint.** `lunar_brdf` on regolith and rock puts a
  Lommel-Seeliger term in `light()` - `cos_i / (cos_i + cos_e)` in place of
  `cos_i` - with a backscatter lobe and a narrow opposition surge. Under the
  5.5 degree sun this is what keeps the far ground bright where Lambert goes
  black, washes the down-sun view flat and shadowless, and leaves the up-sun
  view dark with every rise a silhouette. The fill term survives at 0.15, warm
  grey, and only keeps the shadows from being holes. Crates and hulls keep a
  plain Lambert from the same function.
- **Detail below the DEM.** A cellular noise normal map on the ground plane at
  8 m and 60 m, and brightness variation at 120 m: the 5 m data is a sheet up
  close, and a grazing sun needs something to rake across. A stand-in for the
  detail layer queued in [[Terrain]], not a replacement.

**Open, 2026-09-15: the lunar term limb-brightens.** With the cameras out to
30 km, a far crater wall seen edge-on reads as a flat white sheet with a
knife-edge terminator. `2 n_l / max(n_l + n_v, 0.02)` goes to 2 wherever
`n_v` is near zero and the sun catches the ground at all. Pure
Lommel-Seeliger does that; the real disc is flat because macroscopic
roughness takes the limb back. Proposed, not built: a `lunar_view_floor`
uniform on the material, `max(n_v, floor)` at about 0.25, or a blend toward
Lambert as the view grazes - both tunable on F1, judged from the rim with
`probe_far_sheet.tscn`. Frames in `previews/2026-09-15/far-sheet-*`.

The frames are `previews/2026-09-14/regolith-before-*` against `regolith-after-*`,
seven views each: down-sun, up-sun, cross-sun, the feet, the rim, from 150 m,
the sky. The sweep in between (`v1`..`v5`) is there too, with the salmon
frames that turned out to be the settlement's lights and not the material.

**What the lights do to it.** Every point light in the scene was tuned against
a dark pink ground: the head lamp at 8, the Hearth's orange mast at 4 over 34 m,
the relay's cyan beacon, the red site beacon. On grey regolith with a
reflectance model that surges toward a light near the eye, the head lamp
whited out the ground ahead and the Hearth painted the spawn orange -
`regolith-after-lights-*` and `regolith-lamp-8-vs-3`. The head lamp is 3 now;
the settlement's lights are Mac's, below.

## The map: the rims

The polar geography does the job the twilight band did on Vesper c:

- **Lit rims** - near-constant sunlight on the high ground. Where settlements
  and solar power live.
- **Permanently shadowed crater floors** - dark, around 40 K, and holding water
  ice. Needs lights and heating; it is where the Lander's fuel comes from, and
  `orders.tsv` already has "Ice cores from the deep shadow".
- **Earth, low on the horizon** - above it from slopes facing the near side,
  hidden from the rest. Talking to Earth needs a line to Earth; everywhere else
  needs [[The-Lattice]].

Vesper c's best tension was *the safest place from the sky is the most hostile
place on the ground*, because its night side shadowed the flares. **That does
not carry over as it stood.** A solar particle storm arrives from much of the
sky rather than from the sun's direction, so a crater floor is not a shelter by
virtue of being dark; mass is. [[Flares]] needs rewriting around that.

## The horizon

Arithmetic, measured against nothing yet - see [[Terrain]] for the probe that
will:

- The ground drops away d^2/2R below a flat plane: 0.29 m at 1 km, 1.7 m at the
  2.4 km horizon, 22 m at the corner of a 3x3 world.
- A 20 m rise stays in view from a standing eye out to about 11 km, and the
  terrain has 210 m of relief. **The horizon hides small things, not hills.**
- **Vacuum has no fog to hide the world's edge**, which the in-house terrain
  plan was counting on.
- Line of sight for relays becomes a curvature question at km range: two 3 m
  masts on flat ground see each other at 6.5 km, two 10 m masts at 11.8 km.

Nothing simulates curvature yet; `horizon_distance()` and `curvature_drop()` are
ready and have no callers.

## Moved from Vesper c

| | Vesper c | The Moon |
|---|---|---|
| Gravity | 5.39 m/s^2 | 1.62 |
| Radius | 3,300 km, a `const` | 1,737.4 km, a tunable |
| Atmosphere | 18 kPa, 0.31 kg/m^3 - read by nothing | removed |
| Thermal axis | +90 to -140 °C - read by nothing | removed |
| Key light | red star, 0.85, 1.2° across | white sun, 0.46, 0.53° across |
| Sky and fog | red horizon glow, depth and volumetric fog | black, no fog |
| Default linear damping | Godot's 0.1 | 0 |
| API | `star_direction()`, `star_color`, `star_energy`... | `sun_direction()`, `sun_color`, `sun_energy`... |

## Open

- [x] Migrate the code to the Moon: `World`, `project.godot`, the world scene's
      sky, sun and fog, and the rover. Done 2026-09-13. #now
- [ ] The fiction half: the [[01-Pillars]] pitch and lineage, [[Flares]] as
      solar particle events sheltered by mass, and [[Science]] once Mac has a
      replacement for the xenological mystery, which "realistic" rules out.
      #next
- [ ] TODO: at the pole the sun circles the horizon at 0.51 deg an hour. Does it
      hold still within a session and move between them, keeping the shadow
      compass and the performance budget? Mac's call. #question
- [x] ~~The terrain still reads purple.~~ Grey, and lit as regolith, since
      2026-09-14 - see "The ground, and how it is lit". Mac's to retune; every
      number is on the material.
- [ ] TODO: the settlement's lights - the Hearth and Longshadow masts (orange,
      4 over 34 m), the relay beacon (cyan, 2.6 over 22 m), the site beacon
      (red, 8 over 60 m) - were chosen against pink ground and now paint the
      grey. `regolith-after-lights-*`. Halving the masts is the obvious first
      move; whether a settlement should glow at all in permanent daylight is
      the real question. Mac's. #next
- [ ] TODO: rocks. The scatter puts 9,000 over 17 km², one per 44 m square, so
      the spawn has none in sight - and pebbles are what regolith looks like
      at arm's length. A visual-only small scatter, or a denser one. #next
- [ ] TODO: Earth is not in the sky. Low on the horizon, it is both a landmark
      and the reason relays exist. Mac's call whether and how. #question
- [ ] TODO: "no GPS" wants a reason. ESA and NASA are both building south-pole
      lunar navigation now. #question
- [x] ~~The sun casts no shadow onto the ground in `test_world`.~~ It does -
      `tests/probe_sun_shadow.tscn`, 2026-09-14: a box on the playa moves 0.80%
      of the frame when it stops casting, 0.15% under the real 5.5° sun, the
      suit 0.24% from a side camera, and the 2 km heightmap shadows itself.
      What the view capture had measured was three artefacts at once: the
      chase camera's figure standing in front of its own shadow, the head lamp
      filling it in, and - the real finding - **the first-person eye culling
      the suit's layer and with it the suit's shadow**. See the engine fact in
      `CLAUDE.md` and [[Astronaut-Traversal]]. The crates' "wrong-way"
      shadows were perspective: a shadow running away from the camera from a
      crate in the bottom corner runs up-left toward the vanishing point. #now
