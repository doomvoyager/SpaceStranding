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

Also built: coyote time (0.15 s), sprint, head lamp, `E` to board the [[Rover]],
`Esc` to release the mouse.

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
      it. Gated on how [[Cargo]] is carried on foot. #question
- [ ] TODO: suit systems - O₂, thermal, dose - are a separate survival system
      and are not written. #next
