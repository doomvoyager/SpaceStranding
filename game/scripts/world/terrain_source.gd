@tool
extends Node3D
class_name TerrainSource
## The four questions anything is allowed to ask the ground, and the only type
## the rest of the project should name.
##
## **This is the seam, as a type.** It was a *convention* first — five systems
## were narrowed onto `world_height_at`, `world_surface_at`, `extent()` and
## `sample_step()` on 2026-09-03, so that swapping what is behind them would be
## a contained change. This is the other half: something for `Lattice.terrain()`
## to return, so a `TerrainField` of nine tiles can stand where a single
## `ProceduralTerrain` used to without every caller being retyped.
##
## Two implementations:
##
## * `ProceduralTerrain` — one patch, from authored art or noise.
## * `TerrainField` — a grid of those, answering as one piece of ground.
##
## `world_surface_at` is concrete because both implementations had the same
## one-line copy of it. Everything else is a stub that errors rather than
## answering, because the alternative is a plausible zero: this project has
## already had "the ground is at height 0" pass every test and put the Hearth
## 13.6 m underground.

## Emitted after the ground has been rebuilt. Anything that placed objects on
## the surface — `RockScatter`, the spawn points — has to put them back, or a
## retune leaves them hanging over the new shape.
##
## Declared here rather than on each implementation: GDScript will not let a
## subclass redeclare a signal, and a listener should not have to know which
## kind of ground it attached to.
signal rebuilt


## Whether there is a heightfield to query yet.
##
## Worth asking before trusting any height, because an unbuilt terrain answers
## zero for every point rather than failing — and zero is a plausible height, so
## anything solving positions against it piles the whole scene onto the origin.
func is_built() -> bool:
	push_error("TerrainSource.is_built() not overridden by %s" % get_class())
	return false


## Ground height in world space at a world X/Z.
func world_height_at(_world_x: float, _world_z: float) -> float:
	push_error("TerrainSource.world_height_at() not overridden by %s" % get_class())
	return 0.0


## The surface point under a world X/Z — `world_height_at` with the X and Z
## carried through, which is what most callers actually wanted. Concrete, and
## the one method here that does not need overriding.
func world_surface_at(world_x: float, world_z: float) -> Vector3:
	return Vector3(world_x, world_height_at(world_x, world_z), world_z)


## Where the ground is, as a footprint in world X/Z. Position is the minimum
## corner, size is the span in metres.
func extent() -> Rect2:
	push_error("TerrainSource.extent() not overridden by %s" % get_class())
	return Rect2()


## World metres between height samples — the finest detail the ground carries,
## and the step anything walking it should use rather than inventing one.
func sample_step() -> float:
	push_error("TerrainSource.sample_step() not overridden by %s" % get_class())
	return 1.0
