---
status: reference
verified: 2026-08-30
godot: res://scripts/core/world_constants.gd
tags: [system, setting, reference]
---

# Vesper c

Everything numeric about the world lives in `world_constants.gd`, autoloaded as
`World`. **Never hardcode gravity, pressure or star direction anywhere else** -
retuning the planet has to stay a one-file change.

## The star: Vesper

An M3V red dwarf. Small, cool, red, and violent. Its habitable zone is close
enough that everything in it is tidally locked. It flares hard and often, which
is the whole basis of [[Flares]].

## The body

| Property | Value | Consequence for play |
|---|---|---|
| Radius | ~3,300 km (0.52 R⊕) | Tight horizon. High ground genuinely matters. |
| Surface gravity | **3.34 m/s² (0.34 g)** | Long jumps, floaty falls, slow rollovers, huge stopping distances. |
| Atmosphere | ~18 kPa, N₂ / CO₂ / Ar | Unbreathable - suit required. But: wind, dust, weather, and sound. |
| Rotation | Tidally locked, 19.7-day orbit | **The star never moves.** See [[Visual-Direction]]. |
| Surface temp | +90 °C substellar → −140 °C antistellar | The map has a thermal axis. |

Project gravity in `project.godot` is set to 3.34, so every rigid body and
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

- [ ] TODO: how big is the Verge, in kilometres of drivable band? Gates the
      streaming and floating-origin work. #question
- [ ] TODO: does the band wrap the planet, or is the playable stretch a segment
      of it with hard edges? #question
