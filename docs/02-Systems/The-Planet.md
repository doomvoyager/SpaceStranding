---
status: reference
verified: 2026-09-02
godot: res://scripts/core/world_constants.gd
tags: [system, setting, reference]
---

# Vesper c

> **Being replaced by the Moon.** On 2026-09-13 Mac moved the game to Earth's
> Moon, at the south polar rims, realistic and 50-80 years from now - see the
> decision log for why that site, and what is still open. Nothing below has
> been migrated yet: it describes the planet the code still runs.

Everything numeric about the world lives in `world_constants.gd`, autoloaded as
`World`. **Never hardcode gravity, pressure or star direction anywhere else** -
retuning the planet has to stay a one-file change.

As of 2026-08-31 it is a **no-file** change: these are `@export var` rather than
`const`, and the F1 panel ([[Debug-Panel]]) drives them live. Two consequences
worth knowing. Anything *derived* from a tunable is a function rather than a
stored value - `gravity_ratio()`, `horizon_distance()`, `star_direction()` -
so it cannot go stale. And gravity has to be pushed to the physics server as
well as stored here, because `project.godot`'s `default_gravity` is only read
when the space is created; `World` does that itself on every change.

## The star: Vesper

An M3V red dwarf. Small, cool, red, and violent. Its habitable zone is close
enough that everything in it is tidally locked. It flares hard and often, which
is the whole basis of [[Flares]].

## The body

| Property | Value | Consequence for play |
|---|---|---|
| Radius | ~3,300 km (0.52 R⊕) | Tight horizon. High ground genuinely matters. |
| Surface gravity | **5.39 m/s² (0.55 g)** | Still low-g — long jumps, floaty falls, huge stopping distances — but well above Mars, and a fall now costs cargo. |
| Atmosphere | ~18 kPa, N₂ / CO₂ / Ar | Unbreathable - suit required. But: wind, dust, weather, and sound. |
| Rotation | Tidally locked, 19.7-day orbit | **The star never moves.** See [[Visual-Direction]]. |
| Surface temp | +90 °C substellar → −140 °C antistellar | The map has a thermal axis. |

Radius and gravity together imply a bulk density around 5.8 g/cm³ - a dense,
iron-rich little world, close to Mercury's 5.43. Vesper c is small *and* heavy
for its size, which is why 0.52 R⊕ does not buy the floaty gravity it looks
like it should.

Project gravity in `project.godot` is set to 5.39, so every rigid body and
character is low-g by default rather than by per-script correction.

## The map: the Verge

The playable world is the twilight ribbon, and it has a built-in gradient:

- **Dayward** - hotter, brighter, dust storms, thermal load, meltwater channels,
  fully exposed to [[Flares]].
- **The Verge** - the liveable band. Settlements live here.
- **Nightward** - dark, cryogenic, ice. Needs lights and active heating, but is
  **flare-shadowed** by the planet's own bulk.

That last line is the map's best tension: *the safest place from the sky is the
most hostile place on the ground.*

## Open

- [ ] Migrate to the Moon. `World`: gravity 1.62 (mirrored in `project.godot`),
      radius 1,737.4 km as a tunable, atmosphere and the thermal axis retired;
      a black sky, a white sun, no depth or volumetric fog. Then this note, the
      [[01-Pillars]] pitch and lineage (vacuum carries no sound), [[Flares]] as
      solar particle events, and [[Science]] once Mac has a replacement for the
      xenological mystery. Scoped by the 2026-09-13 survey: nothing but the look
      reads the atmosphere today. Gravity breaks the rover's tuning silently, so
      it lands with the rover work in [[Rover]], not before it. #next
- [ ] TODO: at the pole the sun circles the horizon at 0.51 deg an hour. Does it
      hold still within a session and move between them, keeping the shadow
      compass and the performance budget? Mac's call. #question

- [ ] TODO: how big is the Verge, in kilometres of drivable band? Gates the
      streaming and floating-origin work. #question
- [ ] TODO: does the band wrap the planet, or is the playable stretch a segment
      of it with hard edges? #question
