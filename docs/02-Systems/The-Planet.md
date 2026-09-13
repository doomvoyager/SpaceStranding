---
status: reference
verified: 2026-09-13
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
redden it, even at five degrees. `sun_energy` 0.46 carries about the luminance
the red star did at 0.85, so the move changed the colour of the light and not
its level. The sun is drawn 0.53 degrees across, its real size.

**It does not move yet.** `sun_azimuth_deg` is fixed; at the pole it really
travels once round the horizon a month. Whether it holds still within a session
and moves between them is open below.

**The sky is black and there is no fog.** `test_world.tscn`'s procedural sky is
black top to horizon, both fogs are off, and the scene's ambient is a neutral
grey rather than the blue that was chosen to sit against a red star.

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
- [ ] The terrain still reads purple: the pink colour bake lit by the materials'
      blue fill, both chosen against a red star. Look work, and Mac's -
      `previews/2026-09-13/moon-after-*` against `moon-before-*`. #next
- [ ] TODO: Earth is not in the sky. Low on the horizon, it is both a landmark
      and the reason relays exist. Mac's call whether and how. #question
- [ ] TODO: "no GPS" wants a reason. ESA and NASA are both building south-pole
      lunar navigation now. #question
