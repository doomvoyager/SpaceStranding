---
status: partial
verified: 2026-08-30
godot: res://shaders/painterly.gdshader
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

## Stylized painterly, not PBR

Decided 2026-08-30 from Mac's own space paintings. See [[Decision-Log]].

The surface response is **banded, unlit-looking and specular-free**, carried by
`res://shaders/painterly.gdshader`. Five traits, taken from the reference:

1. **Flat, banded values.** Three steps per surface. Quantised, not a falloff.
2. **Rectangular brush stamps.** Hard-edged, axis-ish colour patches over
   otherwise flat surfaces. This is the signature, and it is what makes the
   look ours rather than generic "painterly".
3. **No specular anywhere.** There is not one highlight in any of the
   reference paintings. Metal reads through value shapes and rim light.
4. **Shadows shift hue, they do not just darken.** Cool blue against the red
   star. This is what puts teal in red dirt.
5. **No contact AO, no micro-detail.** Texture is painted macro-noise.

Scope is **surface treatment only** - no post-process pass, no canvas grain.
Geometry and silhouettes stay grounded and machined. The frame reads as a
stylized simulation, not as a moving painting. Revisit only if the surface
layer alone turns out not to carry it.

### What this means for modelling

- **Silhouette over greebles.** Readable at 100 m beats panel detail.
- **Normal maps are mostly dead weight.** Banded lighting turns their detail
  into noise at the band boundaries. Large forms only, or skip them.
- **Roughness and metallic maps are dead weight**, with specular off.
- **Albedo painted in flat blocks.** No photo texture, no grunge overlays.
- **Poly budget goes down.** Spend the saving on shape.

"Machined, bolted, insulated, worn" is unchanged - it is now carried by modelled
geometry and painted blocks rather than by texture maps.

## Palette

**Saturated, not muted.** Superseded the original "desaturated browns and rust"
on 2026-08-30 - the reference paintings are ferociously red and the saturation
is doing real work.

Iron-rich dust under a red sun, pushed hard. **Teal and turquoise are the
complementary accent**, scattered through the dust and sitting in the shadows,
never as a light source. The sky is dark and red at zenith, dusty red-orange at
the horizon. Cool white artificial light - head lamps, head lights, settlement
interiors - is the only thing on the planet that isn't red or its complement,
which makes human presence read instantly.

The nightside is the other half of the reference: cool blue ambient, warm
practical lights, stars. Same shader, different fill and star energy.

## Materials

Machined, bolted, insulated, worn. Everything looks like it was built to be
repaired in gloves. No glowing holograms without a stated in-world reason.

`res://materials/` holds the tuned presets - `regolith_painterly.tres` for
ground (slope tint on) and `hull_painterly.tres` for props (slope tint off,
stronger rim). Fork a `.tres`, never the shader.

## Known issues

- [ ] The design intent is a 4° star elevation; it is set to 5.5° because a
      grazing directional light makes shadow maps fall apart. Revisit if we move
      to baked lighting. `World.STAR_ELEVATION_DEG`.
- [ ] **The environment still uses ACES tonemapping** (`tonemap_mode = 3` in
      `test_world.tscn`), which clamps exactly the saturated reds the palette
      now calls for. Needs a pass with Filmic or Linear plus manual grading.
      Mac's scene, Mac's call. #next
- [ ] **The painterly shader ignores WorldEnvironment ambient** - it sets
      `render_mode ambient_light_disabled` and takes fill from the material's
      `fill_*` uniforms instead, because engine ambient erases the banding.
      Means fill is tuned per-material, not per-scene. Fine for now; a problem
      once there are day/night or interior/exterior zones. #question
- [ ] Brush stamps are a procedural hash, not a painted texture. Replacing
      `stamp_plane()` with a tiling stamp sheet Mac paints is what will make it
      read as Mac's hand rather than as a filter. No uniform for it yet - the
      shader only carries `albedo_texture`, which is a different job. #now

## Open

- [ ] **Judge it in motion.** Stills hold up; the whole direction lives or dies
      on whether the stamps swim while driving. The distance ladder should
      prevent it, but nobody has driven it yet. Run
      `res://tests/look_dev_capture.tscn` for stills, then actually drive.
      #now #playtest
