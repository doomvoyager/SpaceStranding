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

   They are **`@export var`, not `const`**, and named in snake_case, because the
   F1 panel retunes them while the game runs. Anything derived from one is a
   *function* (`gravity_ratio()`, `horizon_distance()`, `star_direction()`),
   never a stored copy, so nothing can go stale. Anything that caches a derived
   value listens to `World.changed`.

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
| Look-dev renders, one folder per day | `previews/YYYY-MM-DD/` - gitignored, see below |
| Godot engine binary | `engine/` - gitignored, see below |
| Standalone authoring tools | `tools/` at the repo root, **not** `game/tools/` |
| Authored game tables (TSV) | `game/data/` - edit with `tools/tsv-editor.ps1` |
| Terrain masters - gitignored, 420 MB | `game/assets/terrain/_source/` - bake with `tools/bake-terrain.py` |

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

**Never pipe an `--import` into `head`.** The pipe closing kills Godot partway
through, and a half-written `.import` is not an error you get told about - see
the `.import` entry under "Verified engine facts". Redirect to a file and grep
that.

Run the regression tests - non-zero exit on failure:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_rover_controls.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_cargo_flow.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_analog_input.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_cargo_damage.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_debug_panel.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_rock_scatter.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_camera_levelling.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_orders.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_interact_aim.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_storage.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_lattice.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_scanner.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_heightmap_terrain.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_spawn_points.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_tuning_writer.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_mast_survey.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_mast_readout.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_mast_raise.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_coverage_map.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_map_route.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_route_marks.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_pad_cursor.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_brake_light.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_rollover_recovery.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_site_sign.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_speedometer.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_terrain_field.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/test_astronaut_rig.tscn
```

**Never add `--quit-after` to a test run.** It forces exit 0 when the frame
budget runs out, so it converts both a hang and a genuine failure into a pass.
It is a debugging aid for a scene that will not exit, nothing more.

Capture stills of the look, or of the loaded cargo racks. Both must run
**windowed** - `--headless` is the dummy renderer and writes no image:

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/cargo_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/scatter_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/camera_levelling_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/facility_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/scan_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/terrain_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/coverage_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/map_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/route_marks_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/brake_light_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/rollover_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/speedo_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/astronaut_capture.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/probe_sign_size.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/probe_far_render.tscn
```

**Every rendered image that gets looked at is kept, in `previews/`.** A capture
scene writes to Godot's `user://` first, because that is where a running game
can write without touching the project; the shots are then copied into
`previews/YYYY-MM-DD/` - one folder per day - and named
`<capture-set>-<shot>.png` so a day browses flat as thumbnails. Do this at the
end of a capture run, before writing up what the images showed. The folder is
gitignored apart from its README; see `previews/README.md`.

Tuning sweeps count, and are the reason the rule exists: the seven frames that
settled `brake_light_energy` at 0.9 were rendered against values that no longer
exist in the project, so the capture scene cannot reproduce them. A note that
says "1.4 starts washing out" is worth more with the frame beside it.

```bash
mkdir -p "previews/$(date +%F)"
```

Time where the frame goes during a scan pulse, with and without the map. Also
windowed - `--headless` renders nothing and times nothing:

```bash
engine/Godot.app/Contents/MacOS/Godot --path game res://tests/probe_scan_cost.tscn
```

Run a standalone engine-behaviour probe. These build what they need from
scratch so they work under `--script`, where autoloads do not exist:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/probe_vehicle_axes.gd
```

Probes that need autoloads or a viewport run as a scene instead:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/probe_headless_unproject.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/probe_pad_bindings.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/probe_float_precision.tscn
```

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/probe_astronaut_clips.tscn
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
  **Wrong winding does not draw nothing, which is what makes it hard to see.**
  It draws the faces pointing *away* from the camera — so a heightfield viewed
  from above renders as a few bright slivers on the steepest far slopes and
  everything else as void. That reads exactly like a colour or lighting bug,
  and cost a long chase through elevation ramps, auto-ranging and gamma before
  a flat-colour render showed **0.1% of the viewport drawn** and named it. When
  a generated mesh looks too dark, render it one flat colour first: it
  separates "wrong colour" from "not there" in one capture. Copy the winding
  from `terrain.gd` rather than re-deriving it.
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
- **`Input.get_vector()` returns the stick's throw as the vector's length**, and
  normalising the direction you build from it silently discards that - half a
  stick then walks at full speed. Keep the magnitude separately. The keyboard
  produces exactly 1, so the bug is invisible without a pad.
- **`Input.get_action_strength()` rescales by the deadzone**, it does not just
  gate on it. A raw axis at 0.5 through a 0.2 deadzone reads **0.375**, not 0.5.
  Worth knowing before concluding an analog input is behaving as a switch -
  synthesise events through the real `InputMap` with
  `tests/probe_analog_input.gd` rather than guessing.
- **A one-frame velocity change reads as an acceleration of `dv/dt`, so any
  impact model built on raw acceleration is frame-rate dependent.** The same
  landing costs four times as much at 120 Hz as at 30 Hz. Worse, the two body
  types are not comparable instruments: `move_and_slide` zeroes a
  `CharacterBody3D` in a *single* frame, while a `RigidBody3D` collision is
  spread over several by the solver - measured at 434 m/s^2 against 181 for a
  similar event. Smoothing the signal with a time constant in *seconds* fixes
  both at once, because the smoothed peak of an impulse is `dv/tau` regardless
  of tick rate. Measured across 30-120 Hz in `tests/test_cargo_damage.tscn`:
  2.7% variation. See [[Cargo]].
- **Proper acceleration, `|dv/dt - g|`, is almost always the quantity you
  want** when asking how violent something was. Free fall reads zero and
  resting reads one gravity, which is exactly right for damage, comfort or
  camera shake - and it costs one vector subtraction.
- **A boarded astronaut stops moving, so its `global_position` is wherever you
  got in.** `board_vehicle()` hides the node and disables its physics and
  nothing moves it again until `disembark`, so anything asking where the player
  is while they drive is answering about a parked ghost — silently, and only
  while driving, which is the half nobody tests. The scanner had a private
  helper for this from the start; a second copy in the HUD's route bearing was
  wrong the whole time it existed. `Astronaut.vantage()` is the one answer now.
- **A synthesised mouse event does not reach the GUI under `--headless`.**
  `Input.parse_input_event()` delivers it — it turns up in `_unhandled_input`
  with the position you gave it — but with no window there is nothing to
  hit-test against, so Godot never finds the Control under the pointer and
  `gui_input` is never emitted. A test that clicks a button or a viewport
  therefore fails headless and passes windowed, which looks exactly like a
  broken click path. `DisplayServer.get_name() == "headless"` is the check;
  skip the claim loudly rather than weakening it. `tests/test_pad_cursor.gd`.
- **`Camera3D.unproject_position()` works perfectly well under `--headless`**,
  and so does `is_position_behind()`. Both are arithmetic on the camera's own
  projection against `get_visible_rect()`, which the dummy display server still
  reports at the configured window size - measured at 1600x900, with a point
  dead ahead landing exactly on the centre pixel. Worth stating because the
  neighbouring facts about synthesised mouse events make screen-space work look
  untestable headless, and `test_scanner.gd` switched its tag separation *off*
  on that assumption rather than measuring. Screen-space declutter is testable;
  `tests/probe_headless_unproject.gd`.
- **"Is that join a cliff?" is not a question an absolute threshold can
  answer.** A seam test asserting "no more than 0.25 m across a tile boundary"
  failed at 18 m on ground where the same straddle in *open terrain* stepped
  9.9 m - the number was measuring how rough the noise was, not whether the
  tiles met. What separates a slope from a discontinuity is what happens when
  you look closer: a slope's step shrinks in proportion to the straddle
  (measured 19.1 / 4.78 / 1.195 / 0.119 m at 16 / 4 / 1 / 0.1 m, exactly
  linear), a cliff does not move. Compare seam against open ground **at the
  same small straddle** and the instrument calibrates itself against whatever
  the terrain is doing. Same family as the jitter probe below: both times the
  first draft measured the fixture instead of the thing.
  `tests/test_terrain_field.tscn`.
- **A resting `RigidBody3D` reports exactly zero velocity, because Jolt has
  put it to sleep.** So a probe measuring rest jitter measures *whether the
  body is asleep* - it read a flat `0.0` at every distance out to 40 km, which
  looked like a clean result and was no result at all. `can_sleep = false` is
  what makes a resting contact keep being solved and therefore keep being
  measurable. The neighbouring trap is the opposite: the first version of the
  same probe dropped its body on procedural relief and read **1.8 m** of
  jitter at the origin - a box sliding down a slope, with a 2.4 m/s rest speed
  saying so. Measure resting contact on flat ground, awake.
  `tests/probe_float_precision.tscn`.
- **float32 is not the constraint on a 12 km world.** Measured across 0 to
  40 km from the origin: one float step is **0.49 mm** at 8.7 km (a centred
  3x3 corner) and 2 mm at 40 km, the `to_local`/`to_global` round trip is
  **exact**, an awake resting body shows **zero** jitter at every distance,
  and the whole world translated out and re-rendered is visually identical -
  no shadow acne, no depth fighting, mean luma 0.2005 against 0.1983. So a
  3x3 grid of 4096 m tiles needs **no floating origin**, which was the one
  result that could have invalidated the plan. Do not re-derive this from
  first principles; the arithmetic bound alone predicts trouble that Jolt and
  the renderer do not actually have. `tests/probe_far_render.tscn`.
- **A 5-degree sun makes Lambert useless, and no ambient setting rescues it.**
  Vesper c is tidally locked and the star sits ~5 deg above the horizon, so
  `N.L` on flat ground is about **0.09** - the terrain renders essentially
  black under ordinary diffuse lighting. Sky-sourced ambient cannot fix it
  because the sky is nearly black too (`sky_top_color` 0.07 over a 0.09 ground
  hemisphere), and a coloured ambient cannot either: swept, the environment's
  blue ambient at 1.0-1.8 turns red regolith **violet** long before the
  foreground is readable, and pure sky ambient at 3.0 leaves it where it
  started. What actually works is a flat fill multiplied by ALBEDO, which is
  why `surface.gdshader` keeps `render_mode ambient_light_disabled` and rolls
  its own - not a style choice, a consequence of the star not moving. The
  deleted painterly shader got the same lift a second way, from `light_wrap`
  in its custom `light()`, which is worth knowing before concluding a scene
  has gone dark for some other reason. Sweeps in `previews/2026-09-03/`.
- **Godot's built-in `ui_*` actions carry the left stick, and `ui_accept` does
  not carry the pad at all.** Neither appears in `project.godot` unless it has
  been overridden, so these are the bindings nobody writes and therefore nobody
  reads. Measured in 4.7.1: `ui_left`/`ui_right`/`ui_up`/`ui_down` are each
  *arrow key + d-pad button + left-stick axis*, so one stick deflection returns
  a full-magnitude `get_vector` on `ui_*` **and** whatever else is reading that
  stick - which had the map panel panning itself out from under the pointer the
  pointer was aiming. And `ui_accept` is Enter, KP Enter and Space with **no
  joypad event**, so `A` presses nothing, which is easy to write a confident
  comment about and wrong. A *pad* feature should read the pad
  (`Input.is_joy_button_pressed`, `Input.get_joy_axis`) rather than an InputMap
  action, because an action carries bindings you did not write. Note the second
  half is also a hazard in reverse: binding `A` into `ui_accept` globally makes
  it press a *focused* control as well as clicking under an emulated pointer.
  `tests/probe_pad_bindings.tscn` prints both.
- **`get_viewport().get_mouse_position()` returns junk under `--headless`**
  and a stale value in a window whenever something other than the mouse is
  driving the pointer. Anything emulating a cursor has to arbitrate on
  *movement* — compare against the last value seen — rather than re-reading the
  OS position every frame, or the platform silently wins every tie.
- **An `Area3D` is a trigger, not a floor.** A pad built as a bare `Area3D`
  detected crates perfectly and let them fall straight through onto the terrain
  beneath, where they still counted as delivered. Every headless test passed;
  only a render showed it. Anything meant to be stood on needs its own
  `StaticBody3D`.
- **A test scene whose script fails to compile runs forever.** Godot loads
  the scene without the script, nothing calls `get_tree().quit()`, and the
  headless process sits there until something kills it - so the documented
  "non-zero exit on failure" check hangs instead of failing. The parse error is
  printed at the top of the output and then buried. If a test stops exiting,
  read the *first* lines of output, not the last. The fix is to fix the script;
  `--quit-after` "fixes" it by reporting success, which is worse than the hang.
- **Setting `physics/3d/default_gravity` at runtime does nothing.** The value is
  read when the space is created, and `ProjectSettings.set_setting` afterwards
  leaves a falling body at exactly its old rate. Gravity for a running world
  lives on the space:
  `PhysicsServer3D.area_set_param(get_viewport().find_world_3d().space,
  PhysicsServer3D.AREA_PARAM_GRAVITY, v)` - measured tracking to within 3% at
  1.0 and 20.0 m/s^2 by `tests/probe_runtime_gravity.tscn`. Note this does not
  touch anything applying gravity by hand, like the astronaut.
- **GDScript's `%` format has no `%g`.** It compiles and then raises "String
  formatting error: unsupported format character" at runtime, once per call, so
  a formatter in a per-frame UI path floods the log rather than failing loudly.
  `String.num(v, 6)` is the short-and-exact equivalent.
- **A reflected UI still needs telling what to reflect.** The F1 panel builds
  its controls from `get_property_list()` and cannot drift from a script's
  exports - but the list of *objects* it inspects is hand-written, so a whole
  new system reaches nobody until it is added there. Three did exactly that in
  one day, and none of them errored. When adding a tunable system, add it to
  `debug_panel.gd`'s `_discover()`; an autoload has to be named directly,
  because nothing walking the scene will find it. `test_debug_panel.tscn` prints
  what it cannot reach.
- **`PROPERTY_USAGE_SCRIPT_VARIABLE` is what separates a script's own `@export`
  vars from the hundred built-ins** in `get_property_list()`. `@export_group`
  survives into the list as a `PROPERTY_USAGE_GROUP` entry - but so do the
  engine's own groups, and a heading has to be discarded the moment a
  non-script property follows it, or the delivery pad inherits `Area3D`'s
  "Reverb Bus" as a section title. Used by the F1 panel; see [[Debug-Panel]].
- **A `canvas_item` shader declaring `hint_screen_texture` with
  `filter_linear_mipmap` already gets a full mip chain, with no `BackBufferCopy`
  in front of it.** Worth knowing before building a chain of full-screen
  effects: each `BackBufferCopy` is a full-screen copy *plus* a mip rebuild, and
  four stacked ColorRects cost three of each per frame for nothing. Merging the
  post stack to one pass took it from 1.174 ms/frame to 0.965 at 1600x900 with
  a mean per-channel difference of 0.13/255. Adding a `BackBufferCopy` back
  changes the image not at all. Measured by `tests/probe_post_cost.tscn`.
- **A missing `#include` in a shader reports as a tokenizer error, not a missing
  file.** Godot's shader preprocessor hands the unresolved text straight to the
  tokenizer, which stops on the `#` and says `Unknown character #35: '#'` - which
  reads like `#include` is unsupported rather than like the target is absent.
  Check the path exists before believing the message.
- **A `ShaderMaterial` exposes its uniforms as `shader_parameter/<name>`** with
  `PROPERTY_USAGE_EDITOR` but *not* `PROPERTY_USAGE_SCRIPT_VARIABLE`, so
  reflection that filters on script variables will not see them.
  `hint_range` survives into `hint_string`, and `get()`/`set()` round-trip.
- **`Area3D` overlap lists only refresh on a physics step.** Teleporting a body
  and asking `get_overlapping_bodies()` in the same frame returns the old list.
  Tests that move things and then probe interaction range have to step physics
  in between.
- **`visibility_range_end` does nothing to a MultiMesh that covers the whole
  map.** The range is measured against the instance's AABB, and a MultiMesh is
  *one* instance holding every transform - so if its AABB spans the patch, the
  camera is always inside it and nothing is ever culled. Measured: a 120 m
  range on a whole-patch MultiMesh of 8192 rocks dropped **exactly zero** of
  its 1,376,256 primitives. Splitting the same rocks into 32 m cells and
  ranging each dropped 93%. The other edge is real too: 16 m cells with nothing
  culling them cost *more* than one big MultiMesh, because hundreds of tiny
  draw calls beat one large one. `tests/probe_scatter_cull.tscn`.
- **A MultiMesh's per-instance transforms do not survive `--headless`.** The
  dummy renderer accepts `set_instance_transform()` **without an error** and
  returns identity from `get_instance_transform()`; the same write round-trips
  exactly under the real renderer. A headless test asserting on instance
  transforms is testing the null driver - `test_rock_scatter.gd` did, and
  reported every rock 12 m off the ground. `instance_count`, `custom_aabb` and
  `visibility_range_end` *do* survive. Measured both ways in
  `tests/probe_multimesh_readback.tscn`. Anything that needs to know where
  instances are has to keep its own record.
- **`MultiMesh.use_custom_data` has the same rule as `transform_format` and
  fails more quietly.** Both can only be set while `instance_count` is 0. Turn
  custom data on afterwards and the engine refuses, then every
  `set_instance_custom_data()` is dropped without a word - where the transform
  format at least errors. A shader reading `INSTANCE_CUSTOM` then sees zeroes
  and simply draws nothing, which looks like a shader bug.
- **`MultiMesh.transform_format` can only be set while `instance_count` is 0.**
  Set it after and Godot refuses the change, then every write fails with "Can't
  set Transform3D on a Multimesh configured to use Transform2D" - loud, at
  least, unlike the two above.
- **`SpringArm3D` excludes nothing by default, including the vehicle it is
  bolted to.** The rover's own chassis was shortening its chase arm to 1.09 m of
  9 m whenever the view pitched up, because that swings the arm down through the
  engine bay - normal driving, not a wreck. `add_excluded_object(get_rid())`.
  Note the arm is also only as good as where it starts: a mount left in body
  space follows the roll it exists to ignore, and upside down it ends up under
  the vehicle with the arm sweeping into the ground.
- **`@export_subgroup` reaches `get_property_list()` as its own entry**, flagged
  `PROPERTY_USAGE_SUBGROUP` (256) - neither `PROPERTY_USAGE_GROUP` nor a script
  variable. Reflection that only knows about groups drops the heading *and*, if
  it discards a pending heading on any unrecognised entry, can take the parent
  group's heading with it. The engine puts subgroups in the list too, so
  handling them surfaces built-in ones like `VehicleWheel3D`'s "Suspension".
  Used by the F1 panel; see [[Debug-Panel]].
- **A `FREEZE_MODE_KINEMATIC` body moved by writing `global_transform` reports
  a derived `linear_velocity`.** So anything watching a carrier's velocity -
  the `CargoRack` measures its load's jolt that way - sees a hand-driven motion
  as real acceleration, exactly as if physics had produced it. That is what
  makes the rollover recovery's duration load-bearing rather than cosmetic:
  measured, the same righting peaks at **9.14 m/s^2** over 2.4 s and
  **30.96** over 0.25, against a `jolt_floor` of 12. Had the frozen body
  reported zero, the cargo would have been trivially safe at any speed and the
  slow version would have been theatre. `tests/test_rollover_recovery.tscn`.
- **A function returning `Variant` poisons `:=` at every call site.** The same
  family as the untyped `const Array` below, and it reads worse: the parse
  error is "The variable type is being inferred from a Variant value" pointing
  at the *caller's* variable, with nothing naming the function that caused it.
  A `-> Variant` used to mean "or null" is the usual way in. Take the fallback
  as a parameter and return the real type instead - `Rover.ground_below()`.
- **`advance_mode = ENABLED` on a state machine transition means "only via
  `travel()`".** It reads like the opposite - the alternative is `DISABLED` - so
  an `advance_condition` set beside it looks armed and is not. The condition is
  evaluated by `AUTO` (2), and nothing warns: the transition loads, the condition
  goes true every frame, and the machine sits in its start state forever. Cost
  three "never reached" failures in `test_astronaut_rig.gd` that read exactly
  like the conditions were being written to the wrong parameter path.
- **`AnimationNodeStartState` and `AnimationNodeEndState` cannot be written into
  a `.tscn`.** The state machine constructs its own, so a saved scene carries
  only `states/Start/position` - naming a type for them fails with "Cannot get
  class", which takes the *whole scene* down and, through a `preload`, the script
  that referenced it. Hand-authoring an AnimationTree is otherwise
  straightforward; this is the one thing the editor writes that you cannot.
- **The FBX importer scales an unrigged mesh with a 100x node scale and leaves
  the mesh's own AABB in raw file units.** So `mesh.get_aabb()` on an imported
  character reports 2 *centimetres* for a 2 m figure, and the node transform is
  where the truth is. A **skinned** mesh is worse: its AABB is the bind pose in
  skin space and matches the rendered size not at all - measured, a correctly
  standing 2.03 m astronaut whose mesh AABB reads 0.015 x 0.006 x 0.021 under an
  identity transform. Judge an imported character's scale off the skeleton's bone
  rests, or off a render against a metre stick. `tests/astronaut_capture.gd`.
- **A hand-edited `.import` that Godot cannot parse is rewritten with values you
  did not choose, silently.** A mangled `_subresources` block came back with
  `fbx/importer` flipped from ufbx to FBX2glTF, which is not installed - and the
  failure surfaces as "Failed loading resource", naming the *asset*. Nothing
  mentions the setting that changed, and the asset had imported cleanly minutes
  earlier. Diff the `.import` before believing the resource is at fault.
- **Correcting a child node's global basis every frame compounds, because the
  correction lands back in the basis it was read from.** The rover camera hangs
  off the chassis and has to have the body's roll clamped out of it; writing a
  counter-rotation to the pivot works on frame one and then winds the camera
  round over the next few seconds, which reads as drift rather than as a bug in
  the clamp. Rebuild such a basis from scratch each frame from independent
  parts, and keep anything the player accumulated - a look yaw - somewhere that
  is not the basis being overwritten. `tests/test_camera_levelling.tscn` asserts
  no drift over 120 frames at a fixed attitude.

- **An `Area3D` only reports overlapping *bodies*, so anything the player must
  interact with has to be a body.** A facility terminal built as an `Area3D`
  is invisible to the astronaut's interact zone - not an error, just silence.
  `StaticBody3D` is both the working shape and the honest one, since a terminal
  you can walk through would be strange. The same trap catches the reverse
  case: a crate riding in a `CargoRack` is *stowed*, and every "find the nearest
  loose crate" helper skips it by design - so cargo issued onto a dock is
  invisible to the pick-up verb and can be looked at but never carried. Both
  cost a bug, and both passed every headless assertion, because the nodes
  existed and were exactly where they were supposed to be.
- **A verb that acts on "the nearest thing" has a bug waiting in it.** An
  interaction sphere finds everything nearby, and resolving the ambiguity with
  a fixed order of preference means the common case loses: a crate lying beside
  the rover is picked up when you meant to drive. Score the candidates on how
  well they line up with the look direction instead - the sphere stays as the
  broad phase, and there is no ordering left to get wrong. Note Godot has **no
  cone collision primitive**, so the tempting literal reading of "interaction
  cone" costs a convex shape re-oriented every frame, for a worse result.
- **`_process` and `_physics_process` do not interleave anything like realtime
  under `--headless`.** A test that ticks its stages on physics frames and
  asserts against state advanced in `_process` will read zero progress two
  frames after starting something, and a finished-and-gone effect 150 frames
  later. Drive such a test off the state it is asserting on, with a frame budget
  as the failure case, rather than off a frame number.
- **An overlay drawn into `EMISSION` must own the pixel, not add to it.** Two
  separate ways to get this wrong, both of which look like a shader bug: adding
  a saturated colour over a bright surface comes out **white**, because ACES
  tonemapping clamps saturation hardest where it is brightest; and darkening
  `ALBEDO` first is still not enough if anything earlier in `fragment()` has
  already written to `EMISSION` using the original albedo - a fill or ambient
  term will, and the overlay becomes a wash over it. Replace both channels.
- **A node re-entering the tree does not run `_ready()` again.** Anything that
  registers itself with an autoload on ready is therefore scenery the second
  time around - present, visible, and absent from every system that cares.
  `request_ready()` before `add_child()` restores it. Only bites re-parenting,
  not a freshly instantiated node, so it hides until a test moves something.
- **Iterating an untyped `const Array` yields `Variant`, which poisons `:=` two
  lines later.** `for size in SIZES:` then `var x := something * size` fails to
  compile with "Cannot infer the type of x because the value doesn't have a set
  type" - pointing at `x`, not at the loop that caused it. Same for any function
  whose return type the parser cannot resolve. Write `for size: float in SIZES:`
  or give the variable an explicit type. Cost two hangs today, because a test
  scene whose script will not compile runs forever.
- **Godot cannot import TIFF, and expands a one-channel float EXR to three.**
  The TIFF importer does not exist - the format is unsupported, so an 8-bit RGB
  master arrives unusable whatever the import settings say. The EXR importer
  does exist and is worse than it looks: a 218 MB single-channel ZIP EXR became
  an **805 MB** `CompressedTexture2D`, three channels of uncompressed float
  holding the same value. Both facts decide the shape of any authored-art
  pipeline before a line of it is written. Godot *does* preserve full float on
  the way in - worst error 4.7e-9 against ground truth, and a 4.2 M-float bulk
  readback in under 10 ms via `Image.convert(FORMAT_RF)` then
  `get_data().to_float32_array()`. `tests/probe_heightmap_import.gd`.
- **`detect_3d/compress_to` will silently re-import a data texture as lossy.**
  It defaults to on, and fires the first time a texture is used in a 3D
  material - re-encoding to a VRAM format. Harmless for an albedo, fatal for a
  heightfield, which changes shape with nothing logged. Any texture carrying
  data rather than colour needs `detect_3d/compress_to=0` written into its
  `.import` by hand. The mirror of this is that leaving an albedo to detect_3d
  means it sits **unmipmapped** until something trips the re-import, and a large
  map with no mipmaps aliases at distance and crawls under camera motion.
- **`PackedFloat32Array` has no `min()`/`max()`, and cannot be probed for them.**
  It is a builtin Variant type, not an Object, so `has_method()` does not exist
  either - both the call *and* the guard around it are **parse** errors, which
  take the whole script down rather than failing at the call site. A loop is the
  only option: ~150 ms over 4.2 M floats, which is fine once and not per frame.
  Same family as `%g`: GDScript's `%` format has no `%e` either.
- **A verb, a spawn or a scatter that assumes "the terrain is at the origin"
  breaks the moment it isn't.** Swapping the procedural patch for an authored
  map offset it by 1.3 km, and three separate systems had quietly baked the old
  assumption in: `rock_scatter.gd` drew positions in world space from
  `-half..+half`, and the facilities and relay carried hand-tuned Y values. The
  Hearth ended up **13.6 m underground**, and every headless test still passed,
  because the nodes existed and were exactly where they had been told to be.
  Anything hand-placed should have its X/Z authored and its *height solved* -
  which the crates already did, and nothing else had been given.
- **`owner` is a `Node` property**, so a script that wants to record who
  something belongs to must not call its field `owner`. Shadowing it breaks
  scene serialisation in ways that do not announce themselves. `Crate` uses
  `cargo_owner`.
- **`EditorNode3DGizmoPlugin` can only be instantiated by the editor**, so no
  gizmo code can be exercised from a game run - `.new()` fails with "can only be
  instantiated by editor", the following line calls a method on `Nil`, and
  because a test scene whose script errors never quits, the run *hangs* rather
  than failing. Verify a gizmo plugin by printing from its `_enter_tree()` under
  `--headless --editor --quit-after`, which does construct it. Everything
  underneath - the placement arithmetic, the type rule - has to live outside the
  gizmo class if it is to be tested at all. See [[Placement]].
- **An `@export` is visible to the inspector and to `get()` whether or not the
  script is `@tool`.** Worth knowing before adding `@tool` to a gameplay script
  just so an editor tool can read a field off it: `@tool` also starts running
  that script's `_ready()` in the editor, which for anything registering with an
  autoload is a different and worse problem. Editor tooling that keys off a
  property rather than a type needs nothing from the node's script at all.
- **A node created with `.new()` and never added to a tree is never freed.**
  Nodes are not reference counted, so a test that builds one to probe an
  unbuilt-state code path leaks it, and the report arrives at exit as RID and
  ObjectDB leak errors naming engine internals rather than the test. `free()` it
  by hand; a teardown walking `get_children()` will not reach it.
- **`res://` is fully writable from a running debug build**, existing `.tscn`
  and `.gd` files included - `FileAccess.open(path, WRITE)` succeeds and
  `ProjectSettings.globalize_path` points at the real project folder. Only an
  *exported* build has it sealed inside the pack, and `OS.has_feature("editor")`
  is what tells the two apart. This is what makes the F1 panel's "Save to
  project" possible at all; see [[Debug-Panel]].
- **`Script.get_property_default_value(name)` works at runtime** and returns the
  value the script authored, which is the only reliable way to ask whether a
  property was overridden in a scene or left at its default. `property_can_revert()`
  looks like the right question and is not: it returns **false** for every
  property tested, script variables and built-ins alike, so the revert value is
  never available.
- **The project's files are CRLF on Windows, and `FileAccess.get_as_text()`
  keeps the `\r`.** Any line-based rewrite has to split on and rejoin with the
  separator the file already uses, or changing one number rewrites every line in
  the file and the diff is useless.
- **A group-then-walk lookup is a walk if nothing ever joins the group.**
  `Lattice._terrain()` checked the `terrain` group and fell back to a recursive
  tree walk "for scenes where it is not in a group" - and `terrain.gd` never
  called `add_to_group`, so the fallback *was* the implementation: 10.5 us over
  9,524 nodes, on the one function every height query in the project goes
  through. The route line called it four hundred times a frame and the scan
  pulse cost 6 ms. Nothing errored and the fast path read as deliberate. **A
  fallback that is never measured is the code you are running.** Fixed by
  joining the group *and* holding the reference; `tests/probe_scan_cost.tscn`
  reports the per-call cost and the node count behind it.
- **`Performance.TIME_PROCESS` is a per-second peak, not a per-frame average.**
  It refreshes once a second and holds the *worst* process step of that second -
  measured, it changed four times in 600 frames - so it can legitimately read
  higher than the frame time beside it, which is what makes it look broken. It
  is a spike detector. For an average, time wall clock between two
  `RenderingServer.frame_post_draw` yourself. `tests/probe_scan_cost.tscn`.
- **A per-frame rebuild is worth pricing against what actually changed.** Both
  route lines were hundreds of ground-height lookups a frame for a shape in
  which only the *first* vertex - the one at the player's feet - ever moved.
  Rebuilding on a movement threshold instead took `scan + map` from 8.67 ms to
  1.38 ms, 115 fps to 725. The corollary is a new way to fail: `visible` is now
  a claim about geometry an *earlier* frame built, so a throttle that never
  releases leaves a visible node holding an empty mesh. Assert on the vertex
  count, not on visibility. Note `ImmediateMesh` has no `surface_get_array_len`,
  but `surface_get_arrays(0)` works and survives `--headless` - measured, not
  assumed, because `MultiMesh` readback does not.
- **A `"""..."""` literal in a CRLF source file contains CRLF.** A test fixture
  built by `TEXT.replace("\n", "\r\n")` therefore becomes `\r\r\n`, and the
  "does this handle CRLF" assertion tests something that cannot occur. Normalise
  a multi-line literal with `.replace("\r\n", "\n")` before relying on its
  endings. Cost two false failures that looked like writer bugs.

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
  navigation, and the performance budget. The art-direction note is **frozen**
  as of 2026-09-03 - `docs/99-Archive/Visual-Direction.md`, moved out of the
  build tables at Mac's request while the style is still being developed. Do
  not build against anything in it, and do not spend on look work unasked.
- **Flares replace timefall. The Lattice replaces the chiral network.** Both are
  deliberate structural analogues, rewritten to be ours.
- **The Lander is a commitment, not a fast-travel button.** If hopping ever
  reads as a menu teleport, the system has failed.

---

## Git

Mac pushes manually. Claude commits; Claude does not push.
