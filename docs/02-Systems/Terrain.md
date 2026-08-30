---
status: built
verified: 2026-08-30
godot: res://scripts/world/terrain.gd
tags: [system, world, scaffolding]
---

# Terrain

> **Placeholder.** This exists so there is ground to drive on. The shipping
> terrain will be a streamed, chunked, artist-authored setup (Terrain3D or
> equivalent). **Gameplay code must not depend on anything in here.**

## Behaviour

A `@tool` script generating a single 512 m heightfield patch at 2 m spacing from
three layered `FastNoiseLite` passes - FBM base, ridged spines, fine detail.
Normals come from central differences on the heightfield rather than from
`generate_normals()`, which is both cheaper and exact.

`height_at()` gives a bilinear lookup so objects can be dropped on the ground
without a physics query. `test_world.gd` uses it to place the player, rover and
beacon.

## Two things that will bite anyone editing this

**Winding.** Godot treats *clockwise* triangles as front faces. Wound the other
way the whole terrain is backface-culled and you fall through an invisible
world. The index loop is commented accordingly.

**Collision is a trimesh, not `HeightMapShape3D`.** The height shape samples on
a fixed 1-unit grid, which would force a non-uniform scale on the
`CollisionShape3D` to reach our 2 m spacing - and **Jolt rejects non-uniformly
scaled height shapes.** The trimesh costs more memory and is correct.

The generated `MeshInstance3D` and `StaticBody3D` are deliberately created with
**no `owner`**, so they are never serialised into the `.tscn`. Setting owner
would bake a six-figure-triangle mesh into the scene file on every save.

## Known issues

- [ ] Single patch, no streaming, no LOD. Fine at 512 m, will not scale.
- [ ] Regenerates on every load, in GDScript. Noticeable at higher resolutions.

## Open

- [ ] TODO: pick the real terrain solution. Terrain3D is the obvious candidate.
      Gated on knowing the map size - see [[The-Planet]]. #next
