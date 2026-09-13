---
status: design
verified: 2026-08-30
godot:
tags: [system, hazard, core-loop]
---

# Flares

> **Written for Vesper c's red dwarf, and not yet rewritten for the Moon.** The
> shape carries over - solar particle events are real, warned by the X-ray
> flash ahead of the protons, and survivable - but two things below do not: the
> source is the sun, and a storm arrives from much of the sky, so shelter is
> *mass* rather than a shadow. The nightside refuge in particular has no lunar
> equivalent. Queued in [[The-Planet]].

The core environmental hazard, and the structural replacement for timefall.

## Behaviour

Vesper flares on an irregular schedule. A flare gives a **warning window** - the
relay network picks up the precursor X-ray spike before the particle front
arrives, so more [[The-Lattice]] coverage means longer warning. Then it hits.

Caught in the open, you accumulate **dose**:

- Suit and rover electronics degrade and fail
- Radiation-sensitive [[Cargo]] is corrupted or destroyed
- You take injury that persists until treated at a settlement

Shelter is anything that puts mass between you and the sky:

- A settlement, or [[The-Lander]]
- The [[Rover]] with its shield deployed - costs power, immobilises you
- A field shelter you built
- **Terrain** - a canyon, an overhang, the lee of a ridge
- The nightside

## Why it works

It makes every route a judgement about shelter *spacing* rather than distance,
and it gives [[The-Lattice]] a protective function instead of a merely
convenient one. Terrain becomes cover, which means the map reads differently on
the way out than on the way back.

## Interactions

[[The-Lattice]] · [[Cargo]] · [[Rover]] · [[The-Lander]] · [[The-Planet]]

## Open

- [ ] TODO: is the flare schedule seeded and knowable, or genuinely random?
      Knowable makes it a planning game; random makes it a nerve game. #question
- [ ] TODO: does dose decay over time, or need active treatment? #question
- [ ] TODO: how does terrain shelter get evaluated - skylight occlusion sampling,
      or authored volumes? #question
