---
tags: [decisions]
---

# Decision log

Settled arguments and rejected ideas. **Check here before re-proposing
anything.** Newest first.

---

## 2026-08-31 - Orders: a named crate, authored in a TSV, with no clock on it

Mac's inbox note specified order management. Three forks in it were real, and
all three are now called. See [[Orders]].

**An order is a named crate, not a requirement.** Accepting 217 spawns 217's
boxes; the alternative - *deliver 120 kg of ore, fill it from anything
qualifying* - needs Facility Storage to be deep before the first order is
interesting, and makes the crate anonymous exactly when [[Cargo]]'s damage model
wants a specific object with a history. Not rejected, deferred: it is what
Storage grows into if hauling ever feels thin.

**The terminal panel moves cargo Storage to Dock, and no further.** A menu that
assigned crates straight to the rover would delete the physical stow verb and
the derived centre of mass from 2026-08-30, which is one of the better things
built. The menu does the warehouse half; the world keeps the loading half. The
inventory panel Mac asked for is a **reader** - nothing moves cargo except `F`.

**Deadlines are parked, not rejected.** `payout = base_value * condition^1.5`
was built so arriving slowly is a strategy, and a clock says the opposite. The
conditions under which the two coexist are known and strict - timed orders a
minority, the window quoted against the estimated drive rather than in raw
minutes, and a missed window decaying the bonus rather than failing the order -
but they cost more than they are worth before there is a single route to drive.
The [[Flares]] interaction is the blocker if it comes back: sheltering from a
flare must not cost you the window, or the game punishes obedience to its own
safety rule. `deadline_s` stays in the schema at 0, because the TSV editor
deliberately cannot add columns.

Three smaller calls made at the same time:

- **Facility is the generic; a Settlement is a Facility with people.** Two words
  were already in use for one thing - [[Settlements-and-Cast]] listed exactly
  the jobs Mac's note gave Facility. The split buys unmanned depots, relays and
  drop sites for free.
- **Ownership is a separate axis from type.** "Materials" and "materials you
  cannot use" are the same contents with different owners. `owner` is
  `PLAYER` / `FACILITY:<id>` / `ORDER:<code>`, and "can I build with this?" is
  just "is it mine?".
- **The TSV is a catalogue, never a save.** Parsed once at load; runtime state
  is savegame data keyed by `code`. Mac's call, and the right one - the moment
  the table is written at runtime it stops being a file that can be edited.
  `tools/tsv-editor.html` ports from StarChef unchanged, because it is generic
  by design; only its bash launcher needs replacing on Windows.

**An abandoned order resets its row and not its boxes.** Mac's call that an
accepted order can be handed back, and returns to the board as if never taken.
The crates are the exception: they go back to the origin's Storage in whatever
condition they are in, still owned by the order. A clean reset would be a damage
launderer - accept, wreck, abandon, re-accept, collect a pristine crate - which
would quietly undo `condition^1.5` and break the rule that a crate is the same
node its whole life.

Abandonment is done at a terminal, so **the drive back is the penalty** and no
fee or standing hit has to be invented. Two cases then need no rules of their
own: putting a crate down is not abandoning the order, so a box left in the
field is the player's own lost cargo on the same terms as an orbital drop; and a
ruined crate is still deliverable at `base_value * 0^1.5`, so hauling a wreck
home for nothing clears the board entry without any dead-order detection.

Kept deliberately: **the three-digit code is diegetic.** Stencilled on the
crate, printed on the receipt, spoken over comms, so one number refers to one
object across the HUD, the pad and the script. It stays **opaque** - encoding
the origin Facility in the first digit is the obvious convenience and means
moving a Facility renumbers the world.

## 2026-08-31 - Rocks are cells of MultiMesh, and only the big ones are solid

Mac asked for rocks scattered on the terrain with distance culling. Two things
were decided; the rest is sliders.

**Cells, not one big MultiMesh.** This was measured before it was designed,
because the obvious implementation silently does not work.
`visibility_range_end` is measured against the *instance's* AABB, and a
MultiMesh is one instance holding every transform - so a whole-patch MultiMesh
has a whole-patch AABB, the camera is permanently inside it, and the range
never fires. A 120 m range on 8192 rocks in one MultiMesh dropped **exactly
zero** of its 1,376,256 primitives. The same rocks in 32 m cells drew 96,768.

Cells are therefore the unit of the whole system, not a tuning detail, and they
have a floor as well as a ceiling: 16 m cells with nothing culling them cost
more than doing nothing, because hundreds of small draw calls beat one big one.
The default landed at 48 m rather than the synthetic 32, because the real
scatter has a multiplier the probe did not - a MultiMesh holds exactly one
mesh, so every rock variant is its own instance in every cell.

**Big rocks collide, gravel does not.** Rocks at or above 1.4 m get a convex
hull; everything smaller is visual only. A shape per pebble is both expensive
and unpleasant to drive over, and "picking a line through rocks" in [[Rover]]
is about boulders, not grit. Collision is deliberately *not* distance-culled:
you cannot reach a rock the renderer has not already drawn, so there is no
invisible-wall case to solve.

Rejected on the way past: per-rock `StaticBody3D` nodes (hundreds of nodes for
no benefit over shapes under a per-cell body), and driving the culling from
GDScript (`visibility_range_*` is done by the render server, so the system runs
no per-frame code at all).

The rock meshes are procedural placeholders and say so. `rock_meshes` takes
authored meshes and the generator steps aside - that is the intended path once
Mac models a set. See [[Scatter]].

## 2026-08-31 - The post pass is on trial, and merged to one draw

Mac brought the film post stack they had already built for StarChef and wired
it in, explicitly to see what it does here. **This does not overturn "surface
treatment only, no post-process pass" from 2026-08-30** - Mac named that
decision as settled while asking, and the reasoning behind it is untouched.
Post cannot create the painterly look, only unify it. What is on trial is
whether it flatters the surface treatment or fights it, which is a judgement to
make while driving.

The one thing that *was* decided: **it runs as a single pass.** It arrived as
four ColorRects with a `BackBufferCopy` between each, and `film.gdshader` -
which came over in the same import - already existed to replace exactly that
shape. Merged, measured, and kept:

- 1.174 ms/frame to 0.965 at 1600x900. The post work alone drops from 0.30 ms
  to 0.10, about a third of the cost, because three full-screen copies and
  three mip-chain rebuilds per frame go away.
- The merged pass renders the same frame: mean per-channel difference of
  0.13/255, against 2.47/255 for the no-post control.
- All 19 settings preserved, none renamed, all still exposed - which was Mac's
  one condition. They are now on sliders in the F1 panel as well.

`film_material.tres` was carrying StarChef's tuning, which is a *different
look*; it now carries the values Space Stranding was actually running. The
StarChef numbers are in git at 253e9f4 if they are ever wanted.

Measured, not assumed: a `canvas_item` shader declaring `hint_screen_texture`
with `filter_linear_mipmap` already receives a full mip chain, so the merged
pass needs **no** `BackBufferCopy` in front of it. Adding one changes the image
not at all and costs 0.01 ms.

## 2026-08-31 - The tuning panel is generated by reflection

Mac asked for an F1 panel with sliders for every tunable. The shape of it was
the only real decision, and it went to reflection rather than a hand-written
list.

The panel reads `get_property_list()` and builds a control for anything marked
`PROPERTY_USAGE_SCRIPT_VARIABLE`, which is exactly a script's own `@export`
vars. `@export_group` headings and `@export_range` bounds come through with
them.

**A hand-written panel would have been wrong the first time either of us added
an export.** There are about fifty tunables across seven scripts today. The
generated one cannot drift: add an export, get a slider. It also puts pressure
in the right direction - when a guessed slider range feels wrong, the fix is to
write a real `@export_range` in the script, which improves the inspector too.

**The panel is explicitly not a second source of truth.** Nothing it does
writes to a scene or to `project.godot`, because the editor stays where values
are authored (hard rule 3). "Copy changes" reports only what differs from the
authored values, as a short list to read across into the inspector. A JSON
save/load in `user://` covers surviving a restart mid-iteration.

Costs accepted: only float, int, bool, Vector3 and Color are supported, so
strings and resources are skipped; targets are discovered when the panel opens;
and the six wheels' suspension and grip had to be named explicitly, because
they are built-in `VehicleWheel3D` properties rather than script variables.
That last one is worth the exception - they are the numbers [[Rover]] has been
carrying as tuned-by-reasoning-never-driven.

## 2026-08-31 - World's constants became variables

Forced by the panel, and worth recording because it reads against hard rule 4
at a glance.

**It is not a weakening of the one-place rule.** `world_constants.gd` is still
the only place a planetary number is written down; the values simply became
`@export var` so they can be moved while the game runs. Retuning the planet
went from a one-file change to a no-file change.

Two things it did cost. The names went to snake_case, because a SHOUTING name
that can be reassigned underneath you is worse than the churn of renaming seven
call sites. And anything *derived* from a tunable had to become a function
rather than a stored value - `gravity_ratio()`, `horizon_distance()`,
`star_direction()`, which also stopped being `static` - so nothing can go stale
when a value moves. Anything caching a derived value listens to
`World.changed`.

Gravity needed one more thing: `project.godot`'s `default_gravity` is read when
the physics space is created, so setting it at runtime does nothing at all.
`World` pushes each change to the space itself. Measured, not assumed - see
`tests/probe_runtime_gravity.tscn`.

## 2026-08-31 - Cargo damage comes from the carrier's jolt

Mac asked for crate fragility. The obvious implementation - crates take damage
from their own collisions - **cannot work for the case that matters**, and
finding that out first is what set the design.

A stowed crate is frozen with its collision switched off, so it can never
receive a contact event. All the damage that matters happens while cargo is on
a rack, which is exactly when the crate is blind. So the **rack** measures the
carrier and passes the jolt down to whatever it is holding.

That is not a workaround. Strapped-down cargo is not hurt by its own
collisions, it is hurt by the vehicle slamming into things - so the damage a
load takes is a direct read on how the [[Rover]] is being driven, which is the
mechanic we actually wanted. A loose crate is its own carrier and measures
itself, so there is one damage curve with two sources.

**Jolt is proper acceleration**, `|dv/dt - g|` - what an accelerometer bolted
to the crate would read. Free fall reads zero, which is correct: falling is
free and the landing is what costs. Damage is integrated over time rather than
fired on a threshold crossing, so there is no edge detection to get wrong, no
double-counting a landing that spans frames, and no frame-rate dependence.

**The thresholds were measured, not chosen.** `probe_carrier_jolt.tscn` drives
the loaded rover over real terrain: parked reads 3.96, ten seconds of full
throttle over broken ground peaks at 7.44, a 7 m drop runs 33 at p99. The floor
sits at 12 - clear of everything ordinary, with headroom for a shipping terrain
and a retuned engine. The first guess had been 8, which left 7% margin.

**Costs accepted:**

- Damage is invisible on the crate itself. Only the HUD word and the delivery
  receipt change. That is now the top `#now` in [[Cargo]] and it is Mac's call
  how far the art goes.
- The astronaut hits about twice as hard as the rover for a comparable fall,
  because `move_and_slide` stops dead where a sprung chassis does not. Kept
  deliberately - it makes the rover the safe way to move something delicate.
- The jolt is smoothed over 0.05 s, without which the same landing would cost
  four times as much at 120 Hz as at 30 Hz.

## 2026-08-31 - Delivery pays on condition, and cargo must be set down

The other half of the same decision: damage that is never scored is a hidden
number, and a hidden number changes nobody's driving.

`DeliveryPad` grades a crate on arrival and pays
`base_value * condition ^ 1.5`. The exponent is above 1 on purpose - a
half-condition crate pays 42 of 120, not 60 - so "arrive slowly" is a strategy
rather than a preference.

**Cargo has to come off the rack and be set down on the pad.** Nobody chose
that either: a stowed crate is on collision layer 0 so the camera spring arm
ignores the tower on the astronaut's back, which means an `Area3D` cannot see
it. Driving a loaded rover across the pad delivers nothing. The same accident
that fixed the camera gives us the depot, and unloading becomes a deliberate
act rather than a drive-through.

Condition is graded in words, never a percentage, from one static shared
function - so the HUD and the receipt cannot disagree about the same crate.

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
