# Space Stranding

A traversal-first, non-combat cargo-hauling game set on a tidally locked
exoplanet. Godot 4.7.1, third-person 3D, GDScript.

Death Stranding is the acknowledged parent. The divergences that have to carry
their own weight are in `docs/01-Pillars.md`.

**Roles:** Mac is the designer and 3D artist. Claude handles scripting and
mechanics. Mac makes their own scene edits between sessions.

---

## Hard rules

1. **Propose before implementing.** Architectural decisions get discussed
   first. Mac defers the *how* to Claude but expects to be consulted before the
   change lands. Never do a large refactor unprompted.

2. **Check the [[Decision-Log]] before re-proposing anything.**
   `docs/07-Decisions/Decision-Log.md`. Settled arguments are settled.

3. **Everything must stay visible and editable in the Godot editor.** Any
   refactor that trades editor visibility for architectural tidiness is a hard
   no.

4. **Planetary constants live in exactly one place.** `World`
   (`res://scripts/core/world_constants.gd`) is autoloaded. Never hardcode
   gravity, pressure, or star direction anywhere else - retuning the planet has
   to stay a one-file change. Project gravity is 3.34 m/s² in `project.godot`,
   so every rigid body is low-g by default rather than by per-script correction.

5. **Measure engine behaviour, don't reason about it.** See "Verified engine
   facts" below. Every entry there cost a bug first.

> **Scene authoring is an open question, and it differs from StarChef.** There,
> `.tscn` files are Mac's alone and Claude only describes what to wire up. Here
> Claude authored `astronaut.tscn`, `rover.tscn` and `test_world.tscn`, and Mac
> was happy with the result. Treat that as provisional rather than settled - ask
> before hand-editing a scene Mac has since touched.

---

## Where things live

| What | Path |
|---|---|
| Godot project (`res://`) | `game/` |
| Design docs (Obsidian vault) | `docs/` |
| Dashboard - start here | `docs/00-Index.md` |
| Pitch, tone, hard nos | `docs/01-Pillars.md` |
| System specs | `docs/02-Systems/` |
| Settled arguments, rejected ideas | `docs/07-Decisions/Decision-Log.md` |
| Session history | `docs/05-Sessions/` |
| HTML reports and audits | `docs/09-Reports/` |
| Godot engine binary | `engine/` - gitignored, see below |
| Standalone authoring tools | `tools/` at the repo root, **not** `game/tools/` |

`res://scripts/Foo.gd` on disk is `game/scripts/Foo.gd`.

Inside `game/`, scripts and scenes mirror each other: `scripts/player/` pairs
with `scenes/player/`, and so on for `vehicle/`, `world/`, `core/`, `cargo/`,
`ui/`.

---

## The engine

**Godot lives in `engine/` inside the repo.** It is a portable install, not a
system one. `engine/` is gitignored because each machine keeps its own build -
macOS on the MacBook, Windows on the PC - so the folder exists locally on both
machines but never travels through Git. There is nothing in `/Applications`,
Program Files, or `$PATH`; don't go looking.

| Machine | Binary |
|---|---|
| macOS | `engine/Godot.app/Contents/MacOS/Godot` |
| Windows | `engine/Godot_v4.7.1-stable_win64_console.exe` |

Version is **4.7.1 stable**, matching StarChef. `project.godot` declares 4.7.

Open the editor:

```bash
engine/Godot.app/Contents/MacOS/Godot --path game
```

Boot headless and surface script errors - fast, and the first thing to run
after touching any `.gd` or `.tscn`:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game --quit-after 120
```

**After adding or renaming any script with a `class_name`, run an import first**
or the boot above will report every new class as undefined - see "Verified
engine facts":

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game --import
```

Run the regression tests - non-zero exit on failure:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_rover_controls.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_cargo_flow.tscn
```

Capture stills of the look, or of the loaded cargo racks. Both must run
**windowed** - `--headless` is the dummy renderer and writes no image:

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/cargo_capture.tscn
```

Run a standalone engine-behaviour probe. These build what they need from
scratch so they work under `--script`, where autoloads do not exist:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/probe_vehicle_axes.gd
```

Tests that touch project scripts must run **as a scene**, like the rover test
above, because those scripts reach for `World`.

Two gotchas carried over from StarChef and still true: a `--script` file
compiles *before* autoloads exist, so a script touching `World` at class level
won't compile that way - build what you need inside the probe instead; and
`--check-only --script` always reports autoloads as undefined, so boot the
project rather than trusting it.

---

## Verified engine facts

Measured on Godot 4.7.1 with Jolt. Each one caused, or would have caused, a bug.

- **`VehicleBody3D` drives toward +Z on positive `engine_force`**, while the
  chassis faces −Z like every other node. `ENGINE_FORCE_SIGN` in `rover.gd`
  corrects it. Getting it wrong makes the rover drive backwards, which *also*
  reads as inverted steering - so the tempting fix is to invert both, which
  leaves steering genuinely wrong. On the corrected throttle, positive
  `steering` yaws left, which is already what `A` produces. Re-measure with
  `tests/probe_vehicle_axes.gd` rather than reasoning about it.
- **`AMBIENT_LIGHT` is not a spatial-shader built-in in 4.7.1** - not in
  `fragment()` and not in `light()`. Both fail to compile with "Unknown
  identifier". A stylized shader that needs ambient control has to set
  `render_mode ambient_light_disabled` and roll its own fill term. Measured
  both function bodies rather than trusting the docs.
- **Quantising a noisy signal amplifies the noise into a visible pattern.**
  Godot's soft-shadow filter carries per-pixel PCSS dither that is invisible
  against a smooth penumbra. Fold `ATTENUATION` in *before* a banding `floor()`
  and it becomes a loud ordered stipple along every shadow edge. Band the
  terminator only; apply shadow smoothly on top. Applies to any stylized
  quantisation, not just this shader.
- **Godot treats clockwise-wound triangles as front faces.** Wound the other
  way, generated terrain is backface-culled and the player falls through an
  invisible world.
- **Jolt rejects non-uniformly scaled `HeightMapShape3D`.** The height shape
  samples on a fixed 1-unit grid, so any sample spacing other than 1 m needs a
  scale Jolt won't take. `terrain.gd` uses a trimesh instead.
- **Procedurally generated nodes must not be given an `owner`** in a `@tool`
  script, or they are serialised into the `.tscn` - baking a six-figure-triangle
  mesh into the scene file on every save.
- **A new `class_name` is invisible until the project is imported.** The global
  class cache is only rebuilt by a filesystem scan, so a plain headless boot
  after adding a script reports *every* new class as "Could not find type" -
  including ones with no dependencies at all. Run `--import` first. The symptom
  is a dead ringer for a cyclic dependency and will send you chasing one.
- **`get_tree().quit(code)` only schedules the exit.** Execution continues to
  the end of the function, so a test that calls `quit(0)` on success and falls
  through to `quit(1)` always exits 1 - it prints PASS and reports failure.
  `test_rover_controls.gd` did exactly this from the day it was written, which
  made the documented CI check useless. Always `return` after `quit()`.
- **`Area3D` overlap lists only refresh on a physics step.** Teleporting a body
  and asking `get_overlapping_bodies()` in the same frame returns the old list.
  Tests that move things and then probe interaction range have to step physics
  in between.

---

## Documentation discipline

Every note in `docs/02-Systems/` has frontmatter:

```yaml
status: built | partial | parked | inert | design | reference
verified: YYYY-MM-DD
godot: res://path/to/the/thing.gd
```

- **When a system changes, update its note in the same session.** Bump
  `verified`, change `status` if it moved.
- **If `godot:` can't be filled in, the status is `design`, not `built`.** That
  field is the drift detector - it's the whole point.
- The full status vocabulary is documented in `docs/_templates/System-Note.md`.
- At the end of a session, write `docs/05-Sessions/YYYY-MM-DD.md` from the
  template in `docs/_templates/`.

**Never publish an Artifact from a scratchpad.** Write the source into
`docs/09-Reports/` as `YYYY-MM-DD-slug.html`, publish from there, and revise by
editing the file and republishing to the **same** URL.

## Task discipline

Tasks live as checkboxes inside the system note they belong to, not in a central
list. `docs/00-Index.md` aggregates them with Dataview.

**WIP limit: at most three `#now` tags across the entire vault.** If Mac asks
for a fourth, say so and ask what gets demoted. This is the anti-overwhelm
mechanism - protect it.

---

## Design decisions already settled

Do not relitigate without Mac raising them first. Reasoning is in
`docs/07-Decisions/Decision-Log.md`.

- **Godot, decided on Claude's ability to author content directly.** The costs -
  weaker terrain tooling, no Nanite/Lumen, float precision at map scale - were
  priced in. Never propose an engine switch as the fix for any of them.
- **No combat.** The environment is the antagonist, and there is no BT
  analogue. Pressure is environmental; the pull is the `Science` mystery.
- **The star never moves.** Tidal locking is load-bearing for the look, the
  navigation, and the performance budget. See `docs/04-Art/Visual-Direction.md`.
- **Flares replace timefall. The Lattice replaces the chiral network.** Both are
  deliberate structural analogues, rewritten to be ours.
- **The Lander is a commitment, not a fast-travel button.** If hopping ever
  reads as a menu teleport, the system has failed.

---

## Git

Mac pushes manually. Claude commits; Claude does not push.
