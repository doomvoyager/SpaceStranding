---
status: built
verified: 2026-09-02
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

## Input handover

Boarding sets a `_driving` flag that suppresses the astronaut's own look and
interact handling, and both sides call `set_input_as_handled()` on the boarding
press. Without that, a single `E` reaches both nodes in the same frame and you
enter and immediately exit. Node order between the two is not guaranteed, so
both sides guard.

## Interactions

[[Rover]] · [[Cargo]] · [[Flares]] · [[Orders]] · [[Scanner]]

## Open

- [ ] TODO: balance and stumble under load, the way Death Stranding handles
      it. The two back slots now exist and carry real mass; nothing on foot
      reads it yet. #next
- [ ] TODO: suit systems - O₂, thermal, dose - are a separate survival system
      and are not written. #next
