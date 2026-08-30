---
status: built
verified: 2026-08-31
godot: res://scripts/ui/debug_panel.gd
tags: [system, tooling]
---

# Debug panel

**F1.** Every tunable in the game, on a slider, while it runs.

## Behaviour

Autoloaded as `Debug`, so it exists in every scene - including the look-dev
captures - and no scene file had to be edited to host it. F1 opens it, releases
the mouse, and restores whatever the mouse was doing when it closes.

Alongside the sliders it carries a live readout: frame rate, current gravity,
rover speed, the jolt its rack is riding through, and the condition of the worst
crate aboard. That is the "debug" half - the numbers you want while driving,
not after.

## It is generated, not written

The panel reads `get_property_list()` and builds a control for anything marked
`PROPERTY_USAGE_SCRIPT_VARIABLE` - exactly the set of `@export` vars a script
declares. `@export_group` headings come through as group entries;
`@export_range` hints become the slider bounds.

**This is the whole point.** There are around fifty tunables across seven
scripts, and a hand-written panel would have been wrong the first time either
of us added an `@export`. This one cannot drift: add an export, get a slider.

A property with no `@export_range` gets a guessed range - `0` to `4x` the
authored value. When a guess feels wrong, the fix is to put a real
`@export_range` in the script, which improves the inspector at the same time.
Typed entry is deliberately **not** clamped to the range, so a guess that is
too narrow never blocks a value worth trying.

## What it does not do

**It is not a second source of truth.** Nothing here writes to a scene or to
`project.godot`. The editor stays the place values are authored; the panel is
where you find them.

"Copy changes" puts only what differs from the authored values on the
clipboard, in a form you can read straight across into the inspector - a short
list to transcribe rather than fifty lines. "Save" and "Load" keep a session's
tuning in `user://tuning.json` so a promising set survives a restart while you
are still iterating. "Reset all" restores what the scenes were authored with.

## Targets

| Section | Reads from | Writes to |
|---|---|---|
| Planet | `World` | `World` |
| Astronaut | the player | the player |
| Rover | the rover | the rover, then `refresh_load()` |
| Rover wheels | wheel 1 | all six |
| Cargo | the first crate | every crate, re-queried at write time |
| Cargo racks | the first rack | both |
| Delivery pad | the pad | the pad |
| Terrain | the terrain | the terrain, on drag release only |

Reading from one and writing to many is what makes "all crates" a single set of
sliders rather than six identical copies. Terrain regenerates a six-figure mesh
on every write, so it is the one target that commits when a drag *ends*.

**The wheels are the exception to the reflection rule.** Suspension stiffness,
travel, damping and friction slip are built-in `VehicleWheel3D` properties, not
script variables, so they are named explicitly. They are also precisely the
numbers [[Rover]] has been carrying as tuned-by-reasoning-never-driven.

## Two things it forced

Gravity could not be tuned at all until `World`'s constants became variables -
see [[The-Planet]]. And a slider on `World.surface_gravity` moves nothing on
its own: `project.godot`'s `default_gravity` is read when the physics space is
created, so `World` pushes each change to the space itself. Measured in
`res://tests/probe_runtime_gravity.tscn`.

## Verification

`res://tests/test_debug_panel.tscn`. A reflection-driven panel fails *quietly* -
a filter that stops matching produces an empty panel, not an error - so the
test asserts that real rows get built for real properties, that a broadcast
write lands on every crate, that Reset restores the authored values, and that
retuning gravity actually makes a rigid body fall faster.

`res://tests/debug_panel_capture.tscn` writes stills. Whether sixty generated
rows scroll sensibly and the labels fit is not something the headless test can
judge.

## Known issues

- [ ] Only float, int, bool, Vector3 and Color are supported. Strings, node
      paths and resources are skipped, so `cargo_name` and `surface_material`
      do not appear.
- [ ] Targets are discovered when the panel opens. Something that spawns while
      it is open needs a close and reopen - except crates, whose writes
      re-query the group.
- [ ] The star's slider re-aims the light through `World.changed`, but nothing
      else re-reads the planet yet, because nothing else caches it.

## Open

- [ ] TODO: should a saved `tuning.json` load automatically on boot? Convenient
      while iterating, and a superb way to spend an evening confused about why
      the game does not match the inspector. #question
