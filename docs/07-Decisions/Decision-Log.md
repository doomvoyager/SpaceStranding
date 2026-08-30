---
tags: [decisions]
---

# Decision log

Settled arguments and rejected ideas. **Check here before re-proposing
anything.** Newest first.

---

## 2026-08-30 - Godot 4, not Unity or Unreal

Mac was openly willing to switch engines and asked which one Claude could
manipulate most directly. Decided on capability, not familiarity.

Godot's `.tscn` / `.tres` / `project.godot` are plain text, so Claude authors
scenes, resources and materials as directly as code and verifies headlessly.
Unity would force Claude to write scene-*generating* editor scripts instead of
scenes - its YAML is keyed by fileID + GUID across sidecar `.meta` files and is
too fragile to hand-edit - at 30-60 s per batchmode iteration. Unreal's binary
`.uasset` cannot be read or written at all, and Blueprints are fully opaque.

**The known costs were priced in and accepted:** weaker terrain tooling, no
Nanite or Lumen, and large-map float precision needing floating origin or a
double-precision build. Do not propose an engine switch as the fix for any of
them. If switching comes up again, the deciding question is whether Mac still
wants Claude authoring content directly.

## 2026-08-30 - Vesper c: tidally locked, red dwarf, 0.34 g

Chosen from four options (Europa-like ice moon, Titan, Mars, free-invention
exoplanet). Mac picked far-future exoplanet and left the specifics to Claude.

Tidal locking is doing real work, not flavour: it fixes the star on the horizon
(see [[Visual-Direction]]), gives the map a thermal axis, strings the
settlements into a natural chain, and makes the nightside flare-shadowed - so
the safest place from the sky is the most hostile on the ground.

Mars was rejected as well-trodden. Titan remains the strongest unused
alternative if the fixed-star look ever fails to land.

## 2026-08-30 - Flares replace timefall; the Lattice replaces the chiral network

Both are deliberate structural analogues of Death Stranding systems, kept
because they carry the same tension, and rewritten so they are ours. See
[[Flares]] and [[The-Lattice]].

**No supernatural threat.** There is no BT analogue. Pressure comes from the
environment and the pull comes from the [[Science]] mystery.

## 2026-08-30 - Godot's VehicleBody3D drives toward +Z

Not a design decision - an engine fact that cost a bug, recorded so it is not
rediscovered.

Positive `engine_force` pushes toward **+Z**, while the chassis faces −Z like
every other Godot node. The rover therefore drove backwards, which **also read
as inverted steering** because the vehicle was coming at the camera.

Mac reported both as flipped and asked for both to be inverted. Inverting both
would have left the steering genuinely wrong: measured on the corrected
throttle, positive `steering` yaws left, which is already what `A` produces.
**One sign fixed both.** Verified with
`res://tests/probe_vehicle_axes.gd` - re-run it rather than reasoning about it.
