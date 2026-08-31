---
status: design
verified: 2026-08-31
godot:
tags: [system, progression, core-loop]
---

# The Lattice

The relay network. **This is the spine - the system everything else hangs off**,
and the main thing separating this from its inspiration.

## Behaviour

Relays are line-of-sight masts on high ground. Placing one means hauling the
mast and a power core to a site that has LOS to an existing relay - so surveying
for a site is itself gameplay, and terrain occlusion is a real constraint rather
than a radius check.

Coverage grants:

- Navigation and terrain data - uncovered ground is dead reckoning only
- **Hopper jump targets** - [[The-Lander]] cannot jump somewhere unlinked
- Contract visibility from distant settlements
- **Remote Facility storage** - see a linked Facility's stock, then later
  request a transfer from it. This is the ladder [[Orders]] hangs its
  per-Facility storage on, and the chiral network's convenience without any of
  its magic
- Longer [[Flares]] warning windows
- *(Later)* visibility of other players' persistent structures

Dark zones are genuinely dark: no map, no contracts, no warning.

## Why it works

One system justifies field construction, the mobile base, surveying, and the
async multiplayer hooks all at once. Extending the Lattice **is** the campaign.

## Interactions

[[Flares]] · [[The-Lander]] · [[Science]] · [[Progression]] · [[Orders]]

## Open

- [ ] TODO: LOS solve - raycast against terrain at placement time and cache, or
      live? Caching is cheap but breaks if terrain deforms. #question
- [ ] TODO: do relays need maintenance, or are they fire-and-forget? Maintenance
      creates return-trip content but risks becoming a chore. #question
- [ ] TODO: what does the coverage map actually look like on screen? #question
