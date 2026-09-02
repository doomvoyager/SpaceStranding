---
status: built
verified: 2026-09-01
godot: res://scripts/world/spawn_point.gd
tags: [system, tooling, world]
---

# Placement

**Where things stand in the world, authored by dragging them.** Spawn markers
with viewport gizmos, and a ground snap that keeps everything sitting on the
heightmap while you move it.

## The rule

One line, and everything here exists to keep it true:

```
global_position.y == terrain height at (x, z)  +  ground_clearance
```

**X and Z are authored. Height is derived.** Always, in the editor and again on
load. That split is not a style preference — it is the only arrangement that
survives a re-baked terrain, and this project has already shipped the
alternative twice.

## Why

Three separate problems, which looked like one.

**Positions were literals in a script.** The astronaut, the rover and the beacon
were `Vector3`s inside `test_world.gd`'s `_ready()`. Invisible in the editor, a
code edit to move, and written against the **world origin** — a point that
stopped meaning anything the moment the authored heightmap put the terrain
1.3 km off it.

**Height was a lie in the viewport.** Crates, facilities and relays were
authored on X/Z with their height solved at runtime, so the number in the scene
file was whatever it had last been dragged to. That was survivable at
procedural-noise relief. Against [[Terrain]]'s 210 m of authored relief it was
metres: when this system was built the Hearth's stored Y was **7 m** off the
ground beneath it and the recovered mast was **6 m** off, and neither was
visible without pressing play.

**Nothing carried a facing.** The rover spawned pointing wherever its scene
default happened to aim.

## The parts

| Piece | Path | Runs |
|---|---|---|
| `SpawnPoint` marker | `res://scripts/world/spawn_point.gd` | game |
| Gizmo drawing | `res://addons/spawn_gizmos/spawn_point_gizmo.gd` | editor |
| Drag-follow snap | `res://addons/spawn_gizmos/ground_snapper.gd` | editor |
| Plugin, toolbar button | `res://addons/spawn_gizmos/plugin.gd` | editor |
| Runtime solve | `res://scripts/world/test_world.gd` | game |

### SpawnPoint

A plain `Node3D` with `spawn_id`, `ground_clearance`, and a yaw. It joins the
`spawn_point` group on ready; `SpawnPoint.find(tree, id)` is how anything
locates one. `place(node)` moves a node to it and takes the marker's **yaw
only** — a marker tilted by a careless drag must not lay the rover on its side.

`test_world.gd` resolves `astronaut`, `rover` and `beacon` this way, and falls
back to the literals it used to carry when a scene has no marker, so a
stripped-down test scene still works.

### The gizmo

An `EditorNode3DGizmoPlugin`, so it is drawn **straight into the viewport** and
is never a node. That is the reason it is an addon rather than `@tool` scripts
on the nodes: preview meshes would be real children, and this project has
already baked a six-figure-triangle mesh into a `.tscn` by giving a generated
node an `owner`. Gizmo geometry cannot make that mistake.

A SpawnPoint gets the full marker — stake, contact ring, facing arrow, and its
id as a `TextMesh`, because Godot 4 gizmos have no text call. Anything *else*
carrying `ground_clearance` gets just the tether and ring: those already have
meshes, and what they lack is any way to see the ground under them.

The one handle sets `ground_clearance`. It needs no reference to the terrain —
by the rule at the top, the ground is `y - clearance`.

### The snap

`ground_snapper.gd` polls the **selection** each editor frame:

- **X/Z moved** → height re-solved, clearance preserved.
- **Y moved alone** → the clearance absorbs it.

Both maintain the invariant. The second matters more than it looks: without it
the inspector and the scene file would disagree, and the runtime solve — which
trusts the clearance — would yank the node back down on play.

Only the selection, and only after it has moved: a node you have not touched is
never written, so the snap can only ever ride along with a drag the editor has
already recorded. It cannot dirty a scene on its own. The toolbar's **Snap to
ground** covers the case the drag-follow cannot — a node whose stored height
went stale because the *terrain* moved under it — and goes through undo.

### Opting in

**Anything with a `ground_clearance` property is anchored.** Not a hand-written
list of types: [[Debug-Panel]] keeps one of those and it is on record as the
reason three finished systems reached nobody. A new node opts in by declaring
the export, and the addon needs no edit.

`Facility`, `Relay` and `Crate` declare it. None of them is a `@tool` script —
an `@export` is visible to the inspector and to `get()` whether or not the
script runs in the editor, so the tooling never had to make them run there.

## Interactions

- [[Terrain]] — `world_height_at()` is the only height source, and `is_built()`
  is what stops the snapper writing when there is no heightfield to ask. An
  unbuilt terrain answers zero for every point, and zero is a plausible height.
- [[The-Lattice]] — relays link by line of sight over the terrain, so a relay at
  the wrong height links to the wrong places. This is why relay height is solved
  and not typed.
- [[Cargo]] — a crate's `ground_clearance` defaults to 0.31, half a crate plus a
  hair, so a world crate starts *resting*. One spawned even 15 cm up lands hard
  enough to register damage, and the whole world would begin pre-scuffed.
- [[Scatter]] — rocks are placed by `rock_scatter.gd` against the same heights.
  Not markers; there are thousands of them.

## Tests

```bash
engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/test_spawn_points.tscn
```

Asserts the invariant across every settled node in the world scene, against a
terrain that is deliberately **not** at the origin. The load-bearing check is
that `ground_snapper.gd` and `test_world.gd` agree: two implementations of one
rule is the shape that drifts, and the drift would be invisible until something
spawned inside a hill.

The marker test moves the astronaut marker *before* the scene enters the tree,
so it has to land where no literal ever would — asserting against the authored
position would pass just as well with a dead marker and the fallback running.

```bash
engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game res://tests/probe_world_placement.tscn
```

Reports where everything sits relative to the ground. The fastest way to see a
terrain change having buried something.

## Known issues

- [ ] **The gizmo half cannot be tested headlessly.**
      `EditorNode3DGizmoPlugin` can only be instantiated by the editor, so
      `_redraw`, the handle drag and the TextMesh label are verified by eye. The
      arithmetic underneath them is not: the invariant, the anchor rule and the
      snapper's solver are all covered.
- [ ] The snap follows the selection, so a multi-select drag of fifty crates
      re-solves fifty heights per frame. Fine at the current scale; a real
      streamed terrain would want this throttled.
- [ ] A marker keeps its own stored Y at runtime — nothing repositions the
      marker itself, only the thing it places. Harmless, and slightly untidy if
      you inspect a running scene.

## Open

- [ ] **The marker and the thing it places can drift apart in the editor.** The
      Astronaut, Rover and Beacon nodes are seeded at their markers, so opening
      the world scene shows it as it runs - but drag a marker afterwards and
      only the marker moves until you press play. The fix is a
      `preview_target: NodePath` on `SpawnPoint` that the snapper carries along
      with the marker, which would also let `test_world.gd` stop keeping its own
      id-to-node mapping. Small, and deliberately not built in the same pass
      that introduced everything else. Mac's call. #next
- [ ] **Slope alignment.** `align_to_slope` was designed and then cut: nothing
      currently spawned wants it. The astronaut and the rover are bodies that
      settle, and the beacon is a mast that should stand upright whatever it is
      standing on. It needs a `normal_at()` on [[Terrain]], which is central
      differences on the heightfield and cheap. Worth doing the first time
      something wants to lie flat.
- [ ] **Markers for what facilities issue.** A facility puts crates on its dock
      by slot; there is no marker for where an overflow crate lands. Not a
      problem yet — overflow goes to the shelf, not the ground.
- [ ] Extend the gizmo to draw a relay's `link_range` as a ring, so siting one
      on high ground is judged in the viewport rather than by running the game.
      #next
