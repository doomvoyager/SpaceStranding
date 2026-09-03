---
status: built
verified: 2026-09-03
godot: res://scripts/player/astronaut.gd
tags: [system, traversal, core-loop]
---

# Astronaut traversal

On-foot movement in 0.55 g. Complete for the traversal slice.

## Behaviour

`CharacterBody3D`, third-person, camera-relative movement with the body turning
to face travel. Jump height is specified in metres and solved against actual
gravity (`v = √(2gh)`), so retuning [[The-Planet]] does not silently break the
jump.

**Walking is analog.** `Input.get_vector()` returns a vector whose *length* is
how far the stick was pushed, so the magnitude is kept separately and the
normalised direction is only used for heading. Normalising the wish direction
and discarding the throw - which is what the first version did - makes half a
stick walk at full speed. The keyboard produces exactly 1, so it is unaffected.

**The low-gravity feel is mostly one number.** Air acceleration is 1.2 against
9.0 on the ground - roughly a seventh. A jump is a commitment, not a steering
input, and that single ratio does more for the feel than the hang time does.
Ground acceleration is deliberately low too: the suit has mass and the regolith
has no grip.

Also built: coyote time (0.15 s), sprint, head lamp, `Esc` to release the mouse,
a two-slot back rack, and the interaction verbs for [[Cargo]].

**Full gamepad parity.** Left stick moves, right stick looks, `A` interacts, `X`
moves cargo, `B` jumps (and full-brakes in the [[Rover]], exactly as `Space`
already did for both), `L3` sprints. Mouse look is an event; stick look is a
held position, so it is polled in `_process` via the shared `StickLook` helper
that both camera rigs use.

The left stick's `move_forward` / `move_back` are **on-foot only**. The
[[Rover]] drives on its own `drive_forward` / `drive_back` (`W`/`S`, `RT`/`LT`)
so that the stick steers and nothing else once you are behind the wheel. Two
actions rather than one is what lets the same stick mean different things in the
two contexts without either script inspecting the input's source.

## Interaction

Three verbs in reach, and they never compete for the same press:

- **`E` / `A`** - deal with the world: a loose crate, a facility terminal, or
  the [[Rover]].
- **`F` / `X`** - move cargo: carrying, onto a rack with room, into a facility's
  storage intake, else on the ground; empty-handed, off a rack that has
  something. Racks are the rover's and a facility dock's - see [[Orders]].

  An intake **takes and never gives**. Handing something in needs no choosing;
  taking one of forty things out is what the terminal's list is for.

- **`R` / `Y`** - raise the mast on your back where you stand, or lower one you
  raised earlier and are looking at. Its own key rather than an overload of
  `E`, because "the nearest thing" is the ambiguity that verb has already had a
  bug in, and raising a mast when you meant to board the rover is not worth one
  saved binding. A mast is excluded from the other two verbs, so `E` and `F`
  behave exactly as they did. See [[The-Lattice]].

Boarding therefore never competes with unloading. The alternative - one key,
priority-ordered - hands you a crate when you walk up to a loaded rover meaning
to drive it.

**`M` / `Start`** opens [[The-Map]]. Not a verb at all - it acts on nothing in
the world - but it takes the screen through `set_menu_open()`, which is public
for exactly this: the map is on its own key and works while driving, so it
cannot go through a verb.

**`Q` / `LB`** is the third verb and competes with neither: it acts on the
world at a distance rather than on anything in reach. See [[Scanner]].

### Reach is a sphere; the target is chosen by aim

**Which of several things in reach either verb acts on is decided by where the
camera is looking.** The 3.5 m `InteractZone` sphere is only the broad phase -
*what is nearby*. Everything it finds is then scored, and the lowest score wins:

```
score = distance * (1 + aim_bias * (1 - dot(look, direction_to_thing)))
```

Anything more than `interact_half_angle` off the look direction is not a
candidate at all, so nothing behind you is reachable. Both values are `@export`,
so they are on the F1 panel; `aim_bias` at 0 is *exactly* the old
nearest-wins behaviour, which makes it easy to feel what the aim is buying.

There is no priority order any more. There used to be one - crate, then
terminal, then rover - and it meant a crate lying beside the rover was picked up
whatever the player wanted, which is the failure the two-verb split was supposed
to prevent, surviving inside `E`. Measured arcs and the one case that stays
awkward are in the [[Decision-Log]], 2026-08-31.

Two details are load-bearing. **Camera forward, not body forward**: the body only
turns while you are moving, so aiming off it would mean turning the camera while
standing still changed nothing. **Horizontal only**: a crate at your feet sits
far below the camera's forward ray, and a full 3D dot product would rule it out
for being on the ground.

### The prompt and the verb are one call

`interact_prompt()` runs `interact_target()`, which is the same function
`_interact()` acts on; `cargo_prompt()` and `_move_cargo()` share
`cargo_target()` the same way. The HUD only renders those strings. A prompt
cannot name something the key would not do, because there is no second copy of
the rule to drift.

`aim_at()` points the look direction at a world position. The player does this
with the mouse or the right stick; it is public so a test can aim before
pressing a key, which is now part of what a key press means.

### The one hold

`E` is a press everywhere except at a rolled-over [[Rover]], where it is held
for `recovery_hold_time` (1.2 s) to heave the wreck back onto its wheels.

That is not the "nearest thing" ambiguity [[Decision-Log]] gave the mast its
own key to avoid. That was ambiguity between two *different objects*; this is
one object in two states, and an upside-down rover cannot be boarded - so `E`
facing one has exactly one possible meaning, and the aim scoring already picks
the rover out of whatever else is lying beside it. The press path is guarded so
it cannot climb into a wreck.

`_tick_recovery()` checks the key *before* resolving a target, because
`recovery_target()` walks the interact zone and the HUD is already paying for
one of those every frame. The hold resets on release, on looking away and on
walking off: it is a heave, not a tally.

The prompt fills in as it goes - `Righting the rover ||||||....` - because this
is the only hold in the game and a verb that ignores a tap in silence looks
broken.

## Input handover

**`vantage()` is where the player actually is** — the [[Rover]] while driving
it, this node otherwise. Boarding hides the astronaut and stops its physics,
and nothing moves it again until `disembark`, so `global_position` is wherever
you got in. Anything asking where the player is has to go through here; the
scanner had its own copy of that rule and the HUD's route bearing had a second
one that was quietly wrong.

Boarding sets a `_driving` flag that suppresses the astronaut's own look and
interact handling, and both sides call `set_input_as_handled()` on the boarding
press. Without that, a single `E` reaches both nodes in the same frame and you
enter and immediately exit. Node order between the two is not guaranteed, so
both sides guard.

## The figure

An authored suited astronaut on a 41-bone Mixamo skeleton, replacing the capsule
and sphere it stood in as until 2026-09-03. `res://scenes/player/astronaut_rig.tscn`,
driven by `res://scripts/player/astronaut_rig.gd`.

Six files arrived. **`Idle_with_skin.fbx` is the one everything hangs off** - it
is the only one carrying both a skin and a rig. The four skinless clips share a
*byte-identical* skeleton in identical order, so their tracks already resolve
against it and nothing is retargeted or remapped. `astronaut_01_noBackpack.fbx`
is the same 37,235-vertex mesh with no rig; it is kept as the clean master and
referenced by nothing.

Each clip file imports as an **`AnimationLibrary`**, not a scene, and the slices
in its `.import` are what give the clips their names. Nothing is copied into an
authored resource, which is the point: a re-export changes the clip and there is
no second copy left saying otherwise. The rig file imports with
`animation/import=false` for the same reason - one place where animations live.

### What the controller says, and what it does not

`_animate()` reports three things once a physics frame: ground speed, whether we
are on the floor, and vertical velocity. **It never names a clip.** Which
animation that becomes is the state machine's business, so there is no second
opinion about what the astronaut is doing.

It is read *after* `move_and_slide()`, where velocity has stopped being what we
asked for and become what actually happened - walking into a rock looks like
standing against it rather than like walking.

`vertical_speed` is passed rather than derived because stepping off a ledge and
pushing off one are the same "airborne" to anything that only checks the floor.

### The blend space is in the clips' own units

The animations are **in-place** - the hips translate 0.000 m across every one of
them - so nothing in the files says how fast the figure is meant to be moving.
That number still exists as the stride the legs describe, and
`tests/probe_astronaut_clips.gd` measures it: two steps to a cycle, widest toe
separation over the cycle length. The walk travels at **2.06 m/s**, the run at
**4.36 m/s**.

The game's `walk_speed` is 3.2 and `sprint_speed` 6.4, which are 1.55x and 1.47x
those - near enough the same multiple that **one number covers both**. The blend
space is fed `speed / stride_scale` and played back at `stride_scale` (1.5), so
the legs cover the ground the body actually crosses. Raise it and the feet drag;
lower it and they skate. All three are `@export`, so they are on the F1 panel and
the blend points are re-applied every frame from them.

### The jump is three clips, and holds rather than loops

`Jump.fbx` is one 2.167 s take covering crouch, launch, flight and recovery. The
frames dividing those are a property of the animation, and were measured off the
feet rather than eyeballed: takeoff f25, apex f31, touchdown f37 of 65 at 30 fps.

**Low gravity is what decides the shape of the state machine here.** A 1.9 m jump
at 3.34 m/s^2 hangs for about 2.1 s against an airborne phase of 0.4 s, so
looping the air clip would cycle the legs five times and read as flailing. The
slices are therefore **non-looping**: a finished `AnimationNodeAnimation` holds
its last frame, so `jump` settles into the apex tuck and stays there for as long
as the hang lasts. That reads as floating, which is what it should be.

The crouch before f18 is dropped on purpose - the controller sets jump velocity
on the key press, so the figure is already rising and a wind-up would play after
the fact.

States are `Ground` (a blend tree: the 1D locomotion blend into a time scale),
`Jump`, `Fall` and `Land`, with `Land` releasing to `Ground` automatically at the
end of its clip.

### The model faces the wrong way, and that is handled once

The mesh faces **+Z**; `_face_travel_direction` yaws the body so that **-Z** is
forward. The rig node carries a 180 degree correction to meet it.

Measured off the rig's own ankle-to-toe vector, (0.18, 0, 0.98), rather than
eyeballed - and asserted in `tests/test_astronaut_rig.gd`, because getting it
wrong makes the astronaut moonwalk, which reads as inverted *movement*. The
tempting fix - flipping the controller's `atan2` - would leave camera-relative
movement genuinely backwards. Exactly the shape of the [[Rover]]'s
`ENGINE_FORCE_SIGN` trap.

## Interactions

[[Rover]] · [[Cargo]] · [[Flares]] · [[Orders]] · [[Scanner]]

## Open

- [ ] TODO: balance and stumble under load, the way Death Stranding handles
      it. The two back slots now exist and carry real mass; nothing on foot
      reads it yet. #next
- [ ] TODO: suit systems - O₂, thermal, dose - are a separate survival system
      and are not written. #next
- [ ] TODO: the back rack sits at z = 0.78 m, tuned against a placeholder box
      that no longer exists. The authored torso's back surface is around
      z = 0.3, so a carried crate rides roughly 0.25 m clear of it - visible in
      `previews/2026-09-03/astronaut-20_carrying_side.png`. Mac's call, since
      it is a placement judgement rather than a bug. #next
- [ ] TODO: the suit imports untextured - flat 0.906 grey at roughness 1.0. It
      reads at mean luma 0.26-0.39 under the 5-degree star, so it is not the
      black silhouette [[The-Planet]]'s lighting note would predict, but it has
      no material of its own yet. Look work, and deliberately unspent. #next
