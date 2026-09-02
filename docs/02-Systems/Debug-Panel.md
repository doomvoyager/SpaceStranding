---
status: built
verified: 2026-09-01
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

**This is the whole point.** There are eighty tunables across eight scripts and
a shader, and a hand-written panel would have been wrong the first time either
of us added an `@export`. This one cannot drift: add an export, get a slider.

A property with no `@export_range` gets a guessed range - `0` to `4x` the
authored value. When a guess feels wrong, the fix is to put a real
`@export_range` in the script, which improves the inspector at the same time.
Typed entry is deliberately **not** clamped to the range, so a guess that is
too narrow never blocks a value worth trying.

## Keeping a value

**The panel is still not a second source of truth.** It holds no values of its
own and the game never boots from it; the editor remains where numbers are
authored. What changed on 2026-09-01 is that you no longer transcribe them by
hand — "Save to project" writes each tweak back into the file it came from.

| Button | Does |
|---|---|
| Reset all | Back to the values the scenes and scripts were authored with |
| Copy changes | The differing values to the clipboard, to read across by hand |
| Save session / Load session | `user://tuning.json`, so a promising set survives a restart mid-iteration |
| **Save to project** | Rewrites the `.gd`, `.tscn` or `.tres` each value lives in |

### Where a value lives

One rule: **a value goes home to where it already is.** If a scene carries a
line for it, that line is updated. If nothing does, it is the script's own
`@export` default and the `.gd` is updated. A shader uniform goes to its
material. Nothing is ever *inserted*, so no new instance overrides are invented
and every file keeps exactly the shape it had, one number different.

The surprise when this was built is that **most tunables are script defaults,
not scene values.** `rover.tscn`'s root node carries exactly one override —
`mass` — and every other rover number is a `:=` in `rover.gd`. `World`,
`Lattice` and `Orders` are script autoloads with no scene anywhere. So the
common case is rewriting a line of GDScript, and patching a `.tscn` is the
exception. `Terrain` is the clearest illustration of both at once: `size` is
overridden in `test_world.tscn` and goes there, while `height_span` sits at its
script default and goes to `terrain.gd`.

Resolution order matches the engine's own: an instance override in the scene
that *placed* a node beats the value inside the node's own scene. A wheel's
`owner` is the Rover rather than the world, so wheel suspension resolves into
`rover.tscn` and never into `test_world.tscn`.

### Two clicks

The first click resolves every changed value to an exact file and line and
shows it — the full diff to the console, the first few lines in the panel. The
second writes. Touching any slider throws the plan away, because a plan is line
numbers and the values they were resolved against.

`apply()` re-checks that each line still says what the plan read, so a plan left
sitting while the editor saved the same file underneath cannot write to a line
that has moved. Line endings are preserved rather than normalised: the project
is CRLF on Windows, and a writer that rewrote them would turn a one-number tweak
into a whole-file diff.

This is the one system in the game that edits its own source, which is why
`test_tuning_writer.tscn` exists and why it does its patching against fixtures
in `user://` rather than against the real project.

## Targets

| Section | Reads from | Writes to |
|---|---|---|
| Planet | `World` | `World` |
| Astronaut | the player | the player |
| Rover | the rover | the rover, then `refresh_load()` |
| Rover wheels | wheel 1 | all six |
| Cargo | the first crate | every crate, re-queried at write time |
| Cargo racks | the first rack | both |
| Delivery pads | the first pad | every pad, by group |
| Post | the film material | the film material |
| Terrain | the terrain | the terrain, on drag release only |
| Rock scatter | the scatter | the scatter, on drag release only |
| Scanner | the scanner | the scanner |
| Lattice | `Lattice` | `Lattice`, then `rebuild()` on drag release |
| Orders | `Orders` | `Orders` |
| Facilities | the first facility | every facility, by group |
| Relays | the first relay | every relay, on drag release |
| HUD | the HUD | the HUD |

Reading from one and writing to many is what makes "all crates" a single set of
sliders rather than six identical copies. Terrain regenerates a six-figure mesh
on every write, and the rock scatter re-rolls a few thousand placements, so
they are the two targets that commit when a drag *ends*.

The scatter's four distance knobs are the exception within the exception: they
are properties on instances that already exist, so they retune live while
driving and never trigger a rebuild at all. See [[Scatter]].

## Reflection covers the properties, not the targets

This is the seam, and it is worth knowing about because it has already caught us
out. Which *properties* a target exposes is reflected and cannot drift — add an
`@export`, get a slider. Which *objects* are targets at all is `_discover()`,
and that is hand-written.

So a new system can ship with a dozen good tunables and reach nobody. Three did
on 2026-08-31 — [[Scanner]], [[The-Lattice]] and the [[Orders]] ledger — and the
only reason it was noticed is that Mac went looking for a slider that was not
there.

`_collect()` made it worse: a per-class `elif` chain meant teaching the panel a
system took two edits in two places, and making only the obvious one produced a
target that silently matched nothing. It now walks the script's own inheritance
chain, so adding a system is one `_collect` call and one `Target`. An
**autoload** still has to be named directly, because nothing that walks the
scene will ever find it.

Two smaller lessons in the same shape:

- **Prefer a group to `get_first_node_in_group`.** "Delivery pad" tuned the
  first pad in the tree and quietly left the others alone once there was a pad
  per facility — the same bug the HUD's receipt had.
- `test_debug_panel.tscn` now **prints every node with its own exports that no
  target covers**. That list found Facility, Relay and the second pad within a
  minute of existing. It prints rather than fails, because not every tunable
  belongs on a slider — but the next missing system is visible without anyone
  hunting for a control that is not there.

## Subgroups

`@export_subgroup` arrives in `get_property_list()` as its own entry, flagged
`PROPERTY_USAGE_SUBGROUP` - neither a group nor a script variable. It therefore
fell straight through to the discard that keeps engine headings out, and the
heading vanished.

Silent, in the way everything about a reflected panel is silent: the sliders
were all present, just anonymous. The rover's camera levelling knobs were the
first exports to sit under one and rendered as three unlabelled rows beneath
"Camera".

Handling them also surfaced the engine's own subgroups on the wheel target -
"Suspension" and "Damping" had always been in the list and never shown.

**Two targets are exceptions to the reflection rule**, and both take the same
explicit-list path.

Suspension stiffness, travel, damping and friction slip are built-in
`VehicleWheel3D` properties rather than script variables, so they are named
outright. They are also precisely the numbers [[Rover]] has been carrying as
tuned-by-reasoning-never-driven.

The post stack's tunables are shader uniforms on a `ShaderMaterial`, which
surface as `shader_parameter/<name>` with `PROPERTY_USAGE_EDITOR` but *not*
`PROPERTY_USAGE_SCRIPT_VARIABLE`. Their names are read from the shader's own
uniform list rather than hardcoded, so that target cannot drift either: change
a uniform in `film.gdshader` and the slider follows. `hint_range` comes through
as the bounds, and the `group_uniforms` headings survive as section titles.

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

`res://tests/debug_panel_capture.tscn` writes stills, and measures what the
panel costs to have open. Whether eighty generated rows scroll sensibly and the
labels fit is not something the headless test can judge.

## Known issues

- [ ] **"Save to project" cannot invent an override.** It updates lines that
      exist. Tuning a value that is a script default but wanted for one instance
      only writes the project-wide default, which is not what you meant — make
      that override in the inspector once and the panel will keep it after that.
- [ ] A declaration carrying a trailing `#` comment is refused rather than
      rewritten, because the rewrite would eat the comment. Set those by hand.
- [ ] Nothing coordinates with the editor. If Godot has the same file open with
      unsaved changes, one of the two wins on next save. In practice running the
      game saves first, so this only bites if you edit while it runs.
- [ ] Only float, int, bool, Vector3 and Color are supported. Strings, node
      paths and resources are skipped, so `cargo_name` and `surface_material`
      do not appear.
- [ ] Open, with 80 rows, the panel costs about 5% of a frame (0.969 to 1.021
      ms at 1600x900). Fine for tuning while driving; worth remembering before
      leaving it open during a performance measurement.
- [ ] Targets are discovered when the panel opens. Something that spawns while
      it is open needs a close and reopen - except crates, whose writes
      re-query the group.
- [ ] The star's slider re-aims the light through `World.changed`, but nothing
      else re-reads the planet yet, because nothing else caches it.

## Open

- [ ] TODO: should a saved `tuning.json` load automatically on boot? Convenient
      while iterating, and a superb way to spend an evening confused about why
      the game does not match the inspector. #question
