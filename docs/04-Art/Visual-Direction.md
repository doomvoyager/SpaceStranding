---
status: partial
verified: 2026-08-31
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

Scope was **surface treatment only** - no post-process pass, no canvas grain.

**That is now under trial rather than settled.** Mac had a film post stack
already built for StarChef and brought it across on 2026-08-31 to see what it
does here. The rejection stands as the *default* - see [[Decision-Log]] - and
what it was protecting against is unchanged: post cannot create this look, only
unify it, and leading with it is the standard way to end up with a realistic
game wearing a filter. The question the trial answers is whether it flatters
the painterly surface or fights it, and that is a judgement to make while
driving, not from a still.
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

## The post stack (on trial)

`res://scenes/postprocessing_effects.tscn`, a `CanvasLayer` at layer 10 holding
one full-screen `ColorRect` with `res://shaders/post/film_material.tres`.

Four effects in one pass, in the order film actually applies them:

| | What it is |
|---|---|
| Lens | Chromatic aberration and softness, both worsening toward the corners off one shared falloff |
| Glow | Broad neutral spill on highlights - lens scatter |
| Halation | The warm fringe. Channels spread at *different* radii, red widest, so the colour emerges from the spread rather than from a flat tint |
| Grain | Soft-light blended, weighted to the shadows, coloured. Last, always - grain sits in the emulsion, so run it earlier and the glow blooms the noise instead of the image |

**It arrived as four ColorRects with a `BackBufferCopy` between each** and was
merged into the single pass `film.gdshader` was written for. That is three
fewer full-screen copies and three fewer mip-chain rebuilds every frame:

| | ms/frame at 1600x900 |
|---|---|
| No post at all | 0.870 |
| Four ColorRects + 3 BackBufferCopy | 1.174 |
| One ColorRect | 0.965 |

The post work itself went from 0.30 ms to 0.10 - **a third of the cost** - and
the merged pass renders the same frame, measured at a mean per-channel
difference of 0.13/255 against a no-post control of 2.47/255.

**No `BackBufferCopy` is needed at all.** Adding one changes nothing and costs
0.01 ms: a `canvas_item` shader declaring `hint_screen_texture` with
`filter_linear_mipmap` already gets a full mip chain. Glow and halation read at
LOD 3-6, so if that were not true they would silently collapse to a plain copy
and vanish - which is exactly what the probe was written to catch.

Every one of the 19 settings survived the merge, and they are also live on
sliders in the F1 panel - see [[Debug-Panel]]. Tuning a look is a thing to do
while driving.

Measured by `res://tests/probe_post_cost.tscn`, which freezes the scene and the
grain's clock so two renders of the same frame are byte-comparable. Now that
the scene *is* the single pass, its first two rows should agree; if the first
climbs again, something has put the chain back.

## Known issues

- [ ] The design intent is a 4° star elevation; it is set to 5.5° because a
      grazing directional light makes shadow maps fall apart. Revisit if we move
      to baked lighting. `World.star_elevation_deg`, and now live on a
      slider in the F1 panel - see [[Debug-Panel]].
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
      shader only carries `albedo_texture`, which is a different job.
      **Parked 2026-08-31** - the procedural stamps read well enough in motion
      that this stopped being urgent.

## Open

- [x] **Judge it in motion.** Driven 2026-08-31. The stamps do not swim - the
      distance ladder holds - and Mac's call is that the camera and the look
      are good as they stand. The one failure mode that could have sunk the
      direction did not happen, so the direction is settled rather than
      provisional.
