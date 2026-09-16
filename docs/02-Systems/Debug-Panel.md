---
status: built
verified: 2026-09-16
godot: res://scripts/ui/debug_panel.gd
tags: [system, tooling]
---

# Debug panel

**F1.** Every tunable in the game, on a slider, while it runs.

## Behaviour

Autoloaded as `Debug`, so it exists in every scene - including the look-dev
captures - and no scene file had to be edited to host it. F1 opens it, releases
the mouse, and restores whatever the mouse was doing when it closes.

The readout at the top is the "debug" half, one subject to a line: frame rate,
physics tick rate and gravity; the rover's speed, how many wheels are touching
the ground and how far it is tilted; and the jolt its rack is riding through,
with the condition of the worst crate aboard.

## Finding a tunable

Ported from GrimdarkTank on 2026-09-13, when the panel had grown to two hundred
rows in one scroll. See the decision log.

- **Every section starts folded**, as a short noun with its row count:
  `>  ROVER  ·  29`. Click it to unfold. What was open stays open the next time
  F1 is pressed; it is not saved to disk, because it is a reading position and
  not a setting.
- **Sections sit under six cluster headings**, for what gets judged together
  rather than where the code lives: Driving, On foot, World, Network, Orders and
  routes, Interface. The rack and the crates are under Driving because a load
  changes how the rover drives.
- **The box above the list searches every section at once**, matching a row's
  own name *and* its surroundings - the section, its note and the headings above
  it - so "levelling" finds `tilt_follow`. Matching sections are forced open,
  showing only their matches, and the status line counts them. Clearing the box
  puts the folds back exactly as they were; clicking a heading clears it.
- **A section's note** - "rebuilds on release", "all 7" - is the first line when
  it is open, and the header's tooltip.
- **Fold all / Unfold all.** Unfold all is the old panel, if you want it.
- Enum properties (`cargo_owner`, the terrain's `height_source`) are dropdowns
  rather than sliders over a guessed integer range.

## It is generated, not written

The panel reads `get_property_list()` and builds a control for anything marked
`PROPERTY_USAGE_SCRIPT_VARIABLE` - exactly the set of `@export` vars a script
declares. `@export_group` headings come through as group entries;
`@export_range` hints become the slider bounds.

**This is the whole point.** There are 210 rows across 24 sections, and a
hand-written panel would have been wrong the first time either of us added an
`@export`. This one cannot drift: add an export, get a slider.

A property with no `@export_range` gets a guessed range - `0` to `4x` the
authored value. When a guess feels wrong, the fix is to put a real
`@export_range` in the script, which improves the inspector at the same time.
Typed entry is deliberately **not** clamped to the range, so a guess that is
too narrow never blocks a value worth trying.

## Keeping a value

**The panel is still not a second source of truth.** It holds no values of its
own and the game never boots from it; the editor remains where numbers are
authored. "Save to project" writes each tweak back into the file it came from,
so nothing has to be transcribed by hand.

| Button | Does |
|---|---|
| Reset all | Puts back everything the panel changed, each object to its own value |
| Copy changes | What the panel changed, to the clipboard, to read across by hand |
| Save session / Load session | `user://tuning.json`, so a promising set survives a restart mid-iteration |
| **Save to project** | Rewrites the `.gd`, `.tscn` or `.tres` each value lives in |

### What counts as a change

**Only what the panel itself wrote.** A crate's owner moves when it is
delivered; if every exported value were compared against a snapshot, that would
be offered to Save to project and undone by Reset. So the panel keeps a list of
the keys it has written, and a value the game moved is never tuning.

**Each object is remembered separately, and once.** A target reads from one
object and writes to many - all six wheels, every crate - and they do not have
to agree: the Recovered Mast is authored at value 200 among crates worth 0.
The panel records what *each* object said the first time it saw it, and Reset
hands each one back its own. Save to project is the only thing that moves that
record, because it is the moment the files agree with the sliders.

Before 2026-09-13 the panel got all three of these wrong - measured on the old
code: Reset gave every crate the sample's value and owner, closing and reopening
F1 quietly turned a tweak into the new "authored", and a value the game set was
reported as a change. See the decision log.

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

Only objects whose value actually moved are written: tune six wheels to a number
five of them already had, and one line changes.

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

## The keyboard

**Nothing on the panel takes keyboard focus except a text field.** The panel is
used while driving, and a focused control hears keys and sticks that gameplay
reads too - measured in `tests/probe_panel_focus.tscn`: a focused slider walks
32.0 to 31.92 under ten frames of left stick, which in the rover is steering,
and a focused button fires on Enter. The mouse works exactly as it did. This is
the map panel's rule too - "The panels take no keyboard focus at all".

**While a text field has the keyboard, the controls stand down.** A focused
field swallows W as an *event*, but `Input.is_action_pressed("move_forward")`
still reads it held - so without this, typing "wheel" into the search box opened
the throttle. `Astronaut.is_typing()` answers for any LineEdit or TextEdit with
focus, and both the astronaut and the rover's pedals check it. Enter, a click
outside the panel, or closing F1 hands the keyboard back - hiding the panel's
layer releases a field's focus by itself.

## Targets

In screen order.

| Cluster | Section | Reads from | Writes to |
|---|---|---|---|
| Driving | Rover | the rover | the rover, then `refresh_load()` |
| | Rover wheels | wheel 1 | all six |
| | Wheel dust | the rover's WheelDust | the WheelDust |
| | Lens dust | the chase camera's LensDust | the LensDust |
| | Cargo racks | the first rack | every rack |
| | Crates | the first crate | every crate, re-queried at write time |
| | Wheel tracks | the track map | the track map |
| On foot | Footprints | the footprints | the footprints |
| | Astronaut | the player | the player |
| | Astronaut rig | the rig | the rig |
| World | Planet | `World` | `World` |
| | Terrain | the terrain | the terrain, on drag release only |
| | Terrain field | the field | the field, on drag release only |
| | Rock scatter | the scatter | the scatter, on drag release only |
| | Post (Film) | the film material | the film material |
| Network | Lattice | `Lattice` | `Lattice`, then `rebuild()` on drag release |
| | Relays | the first relay | every relay, on drag release |
| | Coverage | the coverage map | the coverage map, on drag release |
| | Scanner | the scanner | the scanner |
| | Site signs | the first sign | every sign, by group |
| Orders and routes | Orders | `Orders` | `Orders` |
| | Facilities | the first facility | every facility, by group |
| | Delivery pads | the first pad | every pad, by group |
| | Route | `Route` | `Route` |
| | Route marks | the marks | the marks |
| | Map | the map panel | the map panel |
| | Map relief | the map terrain | the map terrain, on drag release |
| Interface | HUD | the HUD | the HUD |
| | Pad cursor | the cursor | the cursor |

Reading from one and writing to many is what makes "all crates" a single set of
sliders rather than seven identical copies. Terrain regenerates a six-figure
mesh on every write, and the rock scatter re-rolls a few thousand placements,
so they commit when a drag *ends*.

The scatter's distance knobs are the exception within the exception: they
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
chain, so adding a system is one `_collect` call and one `Target`, placed in
`_discover()` where it should appear on screen. An **autoload** still has to be
named directly, because nothing that walks the scene will ever find it.

Two smaller lessons in the same shape:

- **Prefer a group to `get_first_node_in_group`.** "Delivery pad" tuned the
  first pad in the tree and quietly left the others alone once there was a pad
  per facility — the same bug the HUD's receipt had.
- `test_debug_panel.tscn` now **prints every node with its own exports that no
  target covers**. That list found Facility, Relay and the second pad within a
  minute of existing. It prints rather than fails, because not every tunable
  belongs on a slider — but the next missing system is visible without anyone
  hunting for a control that is not there.

## Headings

`@export_subgroup` arrives in `get_property_list()` as its own entry, flagged
`PROPERTY_USAGE_SUBGROUP` - neither a group nor a script variable. It therefore
fell straight through to the discard that keeps engine headings out, and the
heading vanished. The rover's camera levelling knobs were the first exports to
sit under one and rendered as three unlabelled rows beneath "Camera". Handling
them also surfaced the engine's own subgroups on the wheel target - "Suspension"
and "Damping" had always been in the list and never shown.

**The same discard ate a heading whenever a group opened on an export the panel
cannot draw** - a NodePath, a material, a scene. Seven headings in six scripts,
found in the unfolded capture on 2026-09-13: the rover's "Brake light" opens on
`brake_light_path`, so its three rows sat under "Load". An unsupported export of
the script's own now skips its row and keeps the heading.

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

A reflection-driven panel fails *quietly* - a filter that stops matching
produces an empty panel, not an error - so each of these asserts on the thing
itself rather than on the panel existing.

- `res://tests/test_debug_panel.tscn` - real rows get built for real
  properties; a broadcast write lands on every crate; Reset hands each crate and
  each wheel its own value; a tweak survives closing and reopening; a value the
  game set is not a change; headings survive; retuning gravity makes a rigid
  body fall faster.
- `res://tests/test_debug_panel_ui.tscn` - titles carry no counts; everything
  starts folded with honest counts; the clusters are in order; a fold survives
  reopening; search shows only matches, reads context and puts the folds back;
  a heading click clears it; enums are dropdowns; only text fields take focus;
  closing F1 gives the keyboard back.
- `res://tests/test_typing_gate.tscn` - a focused field holds walking, jumping
  and the throttle, and lets go.
- `res://tests/probe_panel_focus.tscn` - prints what a focused button, slider and
  field do with Space, Enter, the stick and W.
- `res://tests/debug_panel_capture.tscn` - **windowed**; named shots of the
  folded list, the driving sections open, a search and everything unfolded, plus
  what the panel costs to have open (+1% of a frame at 1600x900 on 2026-09-13).
  Whether the list reads is not something a headless test can judge. Frames in
  `previews/2026-09-13/panel-*`.

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
- [ ] Targets are discovered when the panel opens. Something that spawns while
      it is open needs a close and reopen - except crates, whose writes
      re-query the group. A crate the panel has never seen has no remembered
      value, so Reset leaves it alone rather than guessing.
- [ ] Folded, the list is 30 lines and needs a short scroll for its last
      cluster at 1600x900.
- [ ] **A click outside the panel releasing a field is untested.** Headless
      reports junk mouse positions, and a windowed test would have to warp the
      real pointer. Enter and closing F1 are both tested; this one wants a
      hand on the mouse once. #playtest
- [ ] A `tuning.json` saved before 2026-09-13 keys on the old titles and matches
      nothing; the panel says so when you load it.
- [ ] Built-in rigid-body properties - the rover's `mass` above all - are not on
      the panel. Wanted; see [[Rover]].
- [ ] The star's slider re-aims the light through `World.changed`, but nothing
      else re-reads the planet yet, because nothing else caches it.
- [x] Fold, search and regroup, ported from GrimdarkTank; Reset per object;
      changes counted only when the panel made them; no focus but text fields.
      Done 2026-09-13. #now

## Open

- [ ] TODO: should a saved `tuning.json` load automatically on boot? Convenient
      while iterating, and a superb way to spend an evening confused about why
      the game does not match the inspector. #question
