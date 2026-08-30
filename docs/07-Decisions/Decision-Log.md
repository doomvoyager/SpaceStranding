---
tags: [decisions]
---

# Decision log

Settled arguments and rejected ideas. **Check here before re-proposing
anything.** Newest first.

---

## 2026-08-30 - Triggers drive the rover; the stick only steers

Mac's call, immediately after the first gamepad pass bound throttle to the left
stick's Y axis like the keyboard's `W`/`S`. **`RT` accelerates, `LT`
decelerates, and the stick steers only.**

The implementation constraint worth remembering: `move_forward` /
`move_back` are shared between the astronaut on foot and the rover, so the stick
could not simply be unbound - that would have killed on-foot walking. The rover
got its own `drive_forward` / `drive_back` actions instead (`W`/`S`, `RT`/`LT`,
no stick binding). Two actions rather than one is what lets the same stick mean
different things in the two contexts without either script inspecting where the
input came from.

**`LT` brakes before it reverses**, above 0.6 m/s forward. Read literally,
"decelerate" could have been brake-only - but with throttle off the stick that
would leave a gamepad with no reverse at all. Brake-then-reverse is the
universal driving convention and satisfies both readings. `S` behaves the same
way, which is a change to the keyboard, and a deliberate one: the two should not
diverge. `Space` / `B` remain the separate full brake.

## 2026-08-30 - Cargo is a slot grid, not a physics placement puzzle

Answers the `#blocking` question that had been sitting in [[Cargo]] since the
note was written: *is loading a physics placement puzzle on the rack, or a slot
grid with derived centre of mass?* Mac chose the slot grid, with the load
feeding back into the rover's mass and centre of mass.

The note itself said physics was "the better fantasy and the worse UX". What
tips it is that the slot grid keeps most of the fantasy: mass and *placement*
still change how the rover drives, because the centre of mass is derived from
which slots are occupied. What is given up is the fiddling, not the consequence.

**Six slots on the rover in a 2×3 roof grid, two on the astronaut's back.** The
slots are Node3D children of a `CargoRack`, so capacity and layout are authored
by dragging markers in the editor and no slot count exists in code. One script
serves both racks.

Costs accepted: crates are one size, so *volume* is not yet a real axis - every
item occupies exactly one slot. Multi-slot items would be the way back toward
the puzzle if the load ever feels too frictionless.

## 2026-08-30 - Two cargo verbs, not one priority-ordered interact

`E` already boarded the rover, and cargo needed pick up, stow and unload. The
tempting shape is a single context-sensitive `E` that tries the nearest thing
first.

Rejected because it makes the common case worst: walk up to a **loaded** rover
intending to drive it and a priority-ordered `E` hands you a crate. Instead:

- **`E` / `A` - deal with the world.** Loose crate in range, or board the rover.
- **`F` / `X` - move cargo.** Carrying: stow on the rack or put it down.
  Empty-handed beside a loaded rover: take one off.

Boarding never competes with unloading, and unloading needs no third binding.
The HUD asks the astronaut what each key *would* do rather than describing the
rules itself, so a prompt cannot drift from the behaviour it describes.

Gamepad was wired at the same time on Mac's request - deliberately early, while
there is little enough input code that parity is cheap.

## 2026-08-30 - Stylized painterly, saturated, surface treatment only

Mac brought their own space paintings and asked for that look. Nothing in this
log had settled render style, so it was open.

**Three calls, all Mac's:**

- **Painterly, yes.** The specific version is cheap to shade: the stamps in the
  reference are *rectangular and hard-edged*, not organic brushwork. Organic
  strokes need a flow field and swim under camera motion; blocky patches hold
  still. This is why the look is achievable at all.
- **Saturated, not the muted palette.** This **supersedes** "desaturated browns
  and rust, not orange cartoon" in [[Visual-Direction]]. The paintings are
  ferociously red with teal accents and the saturation carries the appeal.
- **Surface treatment only.** Banded lighting, no specular, brush stamps in
  albedo. **No post-process pass** - deliberately rejected for now. Post alone
  cannot create the look, only unify it, and leading with it is the standard
  way to end up with a realistic game wearing a filter. Geometry stays grounded.

Costs accepted: normal, roughness and metallic maps stop earning their keep, so
Mac's Blender workflow moves toward silhouette and flat painted albedo. The
poly budget goes *down*.

The direction is not proven until it has been judged **in motion** - stills
cannot show swimming, which is the one failure mode that would sink it.

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
