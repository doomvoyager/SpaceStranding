---
status: design
verified: 2026-08-30
godot:
tags: [system, progression]
---

# The Lander

A hopper - a rocket-propelled mobile base that makes suborbital hops between
regions.

## Behaviour

- Refuel by harvesting volatiles (water ice → LH₂/LOX) and processing them
- Fuel cost scales with hop distance; long hops are expensive commitments
- The destination must be linked on [[The-Lattice]]
- It is the workshop, the store, the respawn point, and the only real safety

**Moving it should feel like a decision, not a fast-travel button.** If it ever
reads as a menu teleport, the system has failed.

## Interactions

[[The-Lattice]] · [[Flares]] · [[Progression]] · [[Science]]

## Open

- [ ] TODO: is the hop played out, or a transition? A flown landing is a whole
      flight model; a cutscene undercuts the commitment. #question
- [ ] TODO: what happens if you strand yourself with no fuel and no reachable
      ice? Needs a floor that isn't a soft-lock. #question #blocking
