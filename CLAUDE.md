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
  navigation, and the performance budget. See `docs/04-Art/Visual-Direction.md`.
- **Flares replace timefall. The Lattice replaces the chiral network.** Both are
  deliberate structural analogues, rewritten to be ours.
- **The Lander is a commitment, not a fast-travel button.** If hopping ever
  reads as a menu teleport, the system has failed.

---

## Git

Mac pushes manually. Claude commits; Claude does not push.
