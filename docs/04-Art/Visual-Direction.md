---
status: design
verified: 2026-08-30
godot: res://scenes/world/test_world.tscn
tags: [art]
---

# Visual direction

## The star does not move

**The single most important art decision in the project.** Vesper c is tidally
locked, so on the twilight band the star sits permanently ~5° above the horizon
and never rises or sets. Permanent golden hour. Kilometre-long shadows pointing
the same direction forever.

Three things fall out of it for free:

1. **It looks like nothing else.** Recognisable in a single screenshot.
2. **Shadow direction is a compass.** Players navigate by light, not by UI -
   which is what lets [[01-Pillars|no icon vomit]] survive contact with an open map.
3. **Lighting can be largely baked.** A static key light is a real performance
   win on an open map, and buys back the budget Godot's renderer costs us.

## Palette

Iron-rich dust under a red sun. Desaturated browns and rust, not orange cartoon.
The sky is dark and red at zenith, dusty red-orange at the horizon. Cool white
artificial light - head lamps, head lights, settlement interiors - is the only
thing on the planet that isn't red, which makes human presence read instantly.

## Materials

Machined, bolted, insulated, worn. Everything looks like it was built to be
repaired in gloves. No glowing holograms without a stated in-world reason.

## Known issues

- [ ] The design intent is a 4° star elevation; it is set to 5.5° because a
      grazing directional light makes shadow maps fall apart. Revisit if we move
      to baked lighting. `World.STAR_ELEVATION_DEG`.
