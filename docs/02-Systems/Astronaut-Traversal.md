---
status: built
verified: 2026-08-30
godot: res://scripts/player/astronaut.gd
tags: [system, traversal, core-loop]
---

# Astronaut traversal

On-foot movement in 0.34 g. Complete for the traversal slice.

## Behaviour

`CharacterBody3D`, third-person, camera-relative movement with the body turning
to face travel. Jump height is specified in metres and solved against actual
gravity (`v = √(2gh)`), so retuning [[The-Planet]] does not silently break the
jump.

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

Two verbs, and they never compete for the same press:

- **`E` / `A`** - pick up a loose crate if one is in range, otherwise board the
  [[Rover]].
- **`F` / `X`** - carrying: stow on the rover if beside it, else put it down.
  Empty-handed beside a loaded rover: take one off the rack.

Boarding therefore never competes with unloading. The alternative - one key,
priority-ordered - hands you a crate when you walk up to a loaded rover meaning
to drive it. `interact_prompt()` and `cargo_prompt()` expose what each key would
do right now, and the HUD only renders those, so the prompt cannot drift from
the behaviour.

## Input handover

Boarding sets a `_driving` flag that suppresses the astronaut's own look and
interact handling, and both sides call `set_input_as_handled()` on the boarding
press. Without that, a single `E` reaches both nodes in the same frame and you
enter and immediately exit. Node order between the two is not guaranteed, so
both sides guard.

## Interactions

[[Rover]] · [[Cargo]] · [[Flares]]

## Open

- [ ] TODO: balance and stumble under load, the way Death Stranding handles
      it. The two back slots now exist and carry real mass; nothing on foot
      reads it yet. #next
- [ ] TODO: suit systems - O₂, thermal, dose - are a separate survival system
      and are not written. #next
