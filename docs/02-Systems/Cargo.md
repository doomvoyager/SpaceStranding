---
status: design
verified: 2026-08-30
godot:
tags: [system, core-loop]
---

# Cargo

Cargo is the verb of the game, so it has to have texture.

## Behaviour

Every item carries:

- **Mass** - affects [[Rover]] handling, braking, climb ability, and on-foot stamina
- **Volume** - competes for rack space
- **Fragility** - impact and vibration damage it
- **Special needs** - thermal (stay hot/cold), radiation-sensitive (see
  [[Flares]]), pressure-sensitive, live samples, unstable

Placement on the rover matters. High loads raise the centre of mass; uneven
loads pull the vehicle in turns. In 0.34 g a badly balanced rover does not
skid - it *tips*, slowly, with plenty of time to watch it happen.

Delivery pays on **condition**, not just arrival.

## Interactions

[[Rover]] · [[Flares]] · [[Progression]] · [[Settlements-and-Cast]]

## Open

- [ ] TODO: is loading a physics placement puzzle on the rack, or a slot grid
      with derived centre of mass? Physics is the better fantasy and the worse
      UX. #question #blocking
- [ ] TODO: does the astronaut carry cargo on foot too, and does it affect
      balance the way Death Stranding's does? #question
