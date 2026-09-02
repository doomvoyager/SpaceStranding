---
tags: [decisions]
---

# Decision log

Settled arguments and rejected ideas. **Check here before re-proposing
anything.** Newest first.

---

## 2026-09-02 - Raising a mast: reversible, warned not refused, its own key

Three calls made while building the raise verb. Mac was asked and said go, so
these were Claude's; all three are the looser option, which is easier to
tighten later than to loosen.

**Raising is reversible.** A raised mast can be lowered back into the crate it
came from - the same node, with its accumulated damage and its order ownership
intact. The crate is stowed inside the relay and hidden rather than consumed,
which is the same freeze-and-reparent a rack already does. Nothing else in the
game destroys and respawns a crate and a mast was not the place to start. The
design reason is stronger than the tidiness one: siting has to be something you
can be *wrong* about, or people will look the answer up instead of surveying
for it, which is the opposite of the point.

**A dark site is allowed, with a warning.** The survey is an instrument, not a
gate. Dark zones being genuinely dark is a pillar, and a mast raised as a step
toward a further one is a legitimate move. Refusing would also make the survey
authoritative when it is advisory. The readout says "no link from here" and the
verb goes ahead.

**Its own key (`R` / `Y`), not an overload of `interact`.** "The nearest thing"
is the exact ambiguity `interact` has already had a bug in, and raising a mast
when you meant to board the rover is not worth one saved binding. Masts are
excluded from both other verbs so `E` and `F` are unchanged.

**Rejected: naming a raised mast only when its id is blank.** `relay.tscn`
carries an authored id, so the blank check never fires and every raised mast
comes out called "relay" - the second silently replacing the first in the
graph, leaving a mast standing in the world that coverage cannot see. Raised
masts are named unconditionally from `Lattice.unique_site_id()`. This shipped
and passed its test; what caught it was raising a *second* mast, and the test
now does.


## 2026-09-02 - The planet is 0.55 g, not 0.34 g

Mac played at 0.55 g on the F1 slider and it felt better. Made permanent:
`surface_gravity` 3.34 -> **5.39 m/s^2**, mirrored into `project.godot`.
This revises the gravity figure in the Vesper c entry below; nothing else in
that entry moves.

**The fiction got better, not worse.** At the unchanged 3,300 km radius,
0.55 g implies a bulk density around 5.8 g/cm^3 - a dense, iron-rich small
body, squarely Mercury-like (5.43). The old 0.34 g implied about 3.6, which was
light for a rocky world. The planet is now meaningfully *above* Mars rather
than just below it, so "low gravity" stays true while "floaty" softens.

**What it broke: the rover, badly, and silently.** Grip scales with weight, so
the corners improved - but rolling resistance and climbing out of undulations
scale with weight too, and on broken ground they win. Ten seconds of full
throttle went from 4.7 m/s and 29 m to **1.9 m/s and 7 m**. All fifteen
regression tests passed throughout; only `probe_carrier_jolt` saw it, because
it is the only thing that drives. `max_engine_force` re-seated 900 -> **1170**
by bisection, which restores the 29 m with the load still pristine. See
[[Rover]] for the table.

**What it did not break: the damage thresholds.** `jolt_floor` (12) and
`jolt_ruin` (45) stay. They are absolute m/s^2 of proper acceleration, and a
heavier planet making a fall more expensive is the physics working, not a
calibration going stale. Re-measured: a full-throttle run over the worst
ground still leaves cargo pristine, while a 7 m drop of the loaded rover went
from costing a tenth of the load's condition to costing 0.22. Falls hurt about
twice as much and that is the intended reading. Revisit only if it plays mean.

**Still un-instrumented:** brakes. `max_brake_force` has been 26 across both
planets and no probe stops the rover. Suspension stiffness likewise carries
62% more weight than it was set for.


## 2026-09-01 - F1 tweaks go home to the file they came from

Mac asked for a way to save panel tweaks straight into the project. That
reopens [[Debug-Panel]]'s "explicitly not a second source of truth", which Mac
is entitled to do - and on inspection it did not have to be overturned. That
decision's premise was *the editor stays where values are authored, and the
panel tells you what to transcribe*. Automating the transcription leaves the
premise intact. What would have broken it is a side-car tuning file the
inspector knows nothing about, which is the option that was rejected here.

**A value goes home to where it already is.** If a scene carries a line for it,
that line is updated; if nothing does, it is the script's `@export` default and
the `.gd` is updated; a shader uniform goes to its material. Nothing is ever
*inserted*, so no instance override is ever invented and every file keeps the
shape it had with one number different. The cost accepted: a value that is a
script default but wanted for one instance only cannot be promoted from the
panel. Make the override once in the inspector and the panel maintains it after.

**Most tunables turned out to be script defaults, not scene values**, which is
the opposite of what the panel looks like from the front. `rover.tscn`'s root
carries exactly one override - `mass` - and `World`, `Lattice` and `Orders` are
script autoloads with no scene at all. So the common path rewrites a line of
GDScript and the `.tscn` writer is the exception. `Terrain` shows both: `size`
is overridden in the world scene, `height_span` is not.

**Two clicks, and a plan that can go stale.** The first resolves every change to
a file and line and shows the diff; the second writes. Any slider throws the
plan away, and `apply()` re-checks that each line still says what the plan read,
so a plan left sitting while the editor saved underneath cannot write to a line
that has moved. Rejected: writing on one click with a git-clean check instead,
which is faster but makes the review optional.

**Rejected: handing off to an editor plugin.** Applying values to the open scene
through undo/redo would have been the safest thing for `.tscn` files, but it
reaches nothing outside the open scene - and since the majority of tunables are
script defaults and autoloads, it could not have stood on its own.

## 2026-09-01 - X and Z are authored; height is always solved

Mac asked for gizmos to position the things scripts were spawning, now that
there is a heightmap to position them against. Four calls came out of it.

**One invariant, kept in two places on purpose.** `y == ground(x, z) +
ground_clearance`. The editor maintains it while you drag; `test_world.gd`
re-derives it on load. That duplication is deliberate - the editor's copy makes
the scene file honest to read and diff, and the runtime's copy is what catches a
re-baked or retuned terrain moving the ground under an authored position.
Rejected: dropping the runtime solve once the editor writes a real Y, which
would make the `.tscn` the single source of truth and leave everything floating
after a re-bake until each scene was reopened. `test_spawn_points.tscn` asserts
the two solvers agree, because two implementations of one rule is exactly the
shape that drifts.

**Dragging vertically edits the clearance, it does not fight you.** The
alternative - snapping Y back to the solved height - makes the node
unmovable on one axis. Letting the clearance absorb the drag keeps the inspector
number and the scene file agreeing, which is the whole invariant. It has one
wart: undoing a snap restores the old Y and the follow-up absorb turns that into
a clearance. That is self-consistent, and cheaper than the alternative.

**Editor tooling keys off a property, not a list of types.** Anything carrying
`ground_clearance` is anchored. [[Debug-Panel]] keeps a hand-written
`_discover()` list and it is already on record as the reason three finished
systems reached nobody in one day. A new node opts in by declaring the export
and the addon needs no edit. The corollary is that `facility.gd`, `relay.gd` and
`crate.gd` did **not** become `@tool` scripts: an `@export` is readable through
`get()` without one, and `@tool` would have started running their `_ready()` -
and their autoload registrations - inside the editor.

**A real gizmo addon, not `@tool` preview meshes.** Mac's call, and the right
one: gizmo geometry is drawn into the viewport and is never a node, so it cannot
be serialised into a `.tscn`. This project has already baked a six-figure-
triangle mesh into a scene file by giving a generated node an `owner`. The cost
is that the drawing half cannot be tested headlessly at all -
`EditorNode3DGizmoPlugin` refuses to instantiate outside the editor - so the
arithmetic under it was deliberately kept in classes that can be.

The scene file was lying by metres when this landed: the Hearth's stored Y was
7 m off the ground beneath it, the recovered mast 6 m. Both now seeded from a
solved height.

## 2026-09-01 - The terrain is authored art; the map is 4096 m across

Mac delivered two 8193x8193 Gaea exports and asked whether they could replace
the procedural terrain, keeping the noise available for testing. They could.
Four calls in it are worth keeping.

**The map is 4096 m across, not 2048 or 8192.** 8192 m would use the master at
its native 1 m/px and cost 67 M triangles, which is the chunking-and-LOD
conversation, not a drop-in. 4096 m keeps a single 1025 grid at 4 m spacing -
about 2 M triangles, the same cost as the 2048 m patch it replaced - and leaves
the master with 8x detail still in reserve. This also answers the map-size
question that [[Terrain]]'s "pick the real terrain solution" was gated on.

**Relief is 210 m, chosen from the grade it produces, not from taste.** The
export is normalised 0..1 with no absolute vertical scale, so the metres were
ours to pick. Measured across the whole map at mesh resolution: 210 m gives a
median grade of 3 degrees, p90 of 9 and p99 of 17, with the massif past 60 on
its steep faces. Drivable everywhere the player will spend time, genuinely
impassable where it should be. `height_span` is exposed as *relief in metres*
rather than as a scale factor, so it stays meaningful across a re-export.

**The colour master replaces the base albedo outright.** Mac's call, over
blending it under the painterly bands. The brush stamps still modulate it, which
matters because 1 m/texel is soft underfoot and the detail has to come from
somewhere. The master is pinker and more saturated than [[Visual-Direction]]
asks for; `macro_tint` and `macro_saturation` exist so that is a slider rather
than a re-bake.

**The masters stay out of git.** 420 MB, gitignored on the same rule as the
asset zips - the repo holds what the game uses, not what it was delivered in.
`tools/bake-terrain.py` produces the ~19 MB that is committed. This was a real
choice against Git LFS, which would put 420 MB through every clone on two
machines for masters that change rarely and belong to one person.

**Two engine facts that cost time, recorded so they are not rediscovered.**
Godot cannot import TIFF at all, so a colour master arrives unusable whatever
the settings say. And Godot expands a one-channel float EXR to three-channel
uncompressed float on import - the 218 MB master became an 805 MB texture cache
before anything asked it to.

## 2026-08-31 - The scan says what the rover can drive, not how steep it is

Mac asked for a Death Stranding scanner: a pulse on `Q`/`LB`, tags on anything
usable, and a dot grid on the terrain coloured red for difficult and green for
easy. Built as [[Scanner]]. Two calls in it are worth keeping.

**Green and red are calibrated against the [[Rover]], not against steepness.**
`probe_rover_climb.tscn` puts the loaded rover on slopes of known angle at full
throttle and measures how far it gets up each in a fixed run. It turns out the
rover does not *stall* anywhere useful - it slows smoothly, from 37 m on the
flat to 19.6 m at 24° and 8.9 m at 40°, sliding backwards only at 56°. So there
is no cliff to put the threshold on, and the honest one is where progress
**halves**: 25.5°, rounded to 26. Red then promises "this will cost you half
your speed or worse". Any other number makes the scan a picture of steepness,
which the player can already see.

**The pulse rides on global shader uniforms; the tunables do not.** One scanner
drives every surface with a single write, rather than holding a list of
materials and keeping it in step with the scene. But the *look* lives as
`@export` vars on `scanner.gd` and is pushed into those globals, because a
ShaderMaterial's uniforms are `PROPERTY_USAGE_EDITOR` and not
`PROPERTY_USAGE_SCRIPT_VARIABLE` - already recorded as an engine fact - so the
[[Debug-Panel]] cannot see them. A number nobody can move while driving is a
number nobody will tune.

**Costs accepted:**

- The grid ignores line of sight and tags through hills. [[The-Lattice]] has a
  sight-line solve that could be reused; whether the scanner *should* be
  occluded is a design question, not only a cost one.
- Fixed world-space dot spacing, so the grid is dense far away and sparse up
  close. Worth judging against terrain with real relief.
- No icons: a crate, an order's cargo and a facility differ only by tint.

Recorded because it caught three of us out and would again: **a holographic
overlay must own its pixel, not add to it.** Emission alone came out white
under ACES, and darkening the albedo was not enough either, because the
material's own fill term had already written ambient into `EMISSION` using the
red albedo. Both `ALBEDO` and `EMISSION` have to be replaced under the dot. See
[[Scanner]].

---

## 2026-08-31 - The Lattice links by line of sight, and transfers cost time

The coverage half of [[The-Lattice]], built. **Placing** relays is deliberately
not in it: they are authored in the scene, because the payoff had to exist first
or there would be nothing to place one *for*. Extending the network is still
meant to be the campaign; this is the reason it will be worth doing.

**Sites link by range AND line of sight**, and coverage is the connected
component. A radius check would make the network a question of *distance*, which
the map cannot argue with; sampling the terrain between two masts makes it a
question of *where the high ground is*, which is what surveying is supposed to
be about. `test_lattice.tscn` asserts a mast five metres underground cannot see
out - without that assertion the whole thing is a distance check wearing a
raycast's clothes, and where a relay goes stops mattering.

**Solved at build time and cached**, answering the open question in the note. A
link changes only when a site moves or the terrain rebuilds, and both are events
we already have. Rebuilds are deferred and coalesced.

**Transfers cost time and nothing else.** Mac's call, from three options - time
only, time plus a fee, time plus a shared power budget. Duration is a dispatch
delay plus distance over a speed **deliberately slower than the rover**: asking
the Lattice is the patient option, never the efficient one. If the network ever
beat driving there yourself, the rover would be a worse vehicle than a menu. The
stock is off both shelves while it travels, which is the honest reading and also
stops it being requested twice.

**Remote boards as well as remote shelves.** Mac's call. The note already
promised "contract visibility from distant settlements", it was nearly free once
the graph existed, and it turns a terminal into a route-planning tool rather
than a warehouse window.

**A dark facility is unreadable, not greyed out.** The panel asks
`facilities_reachable_from()`, which does not return what it cannot see. Dark
zones being genuinely dark is the line the note has carried since it was
written, and it only means something if the UI cannot cheat.

Sites are **duck-typed** on three methods rather than sharing a base class,
because Facility and Relay both extend `Node3D` and GDScript has single
inheritance.

Costs accepted: transfer speed and dispatch delay are guesses that cannot be
judged until facilities are a real distance apart, and the Network tab is a list
- it answers "what can I reach" but not "where is the hole", which is still the
open coverage-map question.

---

## 2026-08-31 - Storage holds records, and is uncapped

Cargo was abstract until an order was taken and gone once it was handed back, so
*"the part you need is at the other facility"* could not happen - and that is the
premise [[The-Lattice]]'s whole ladder rests on. Storage had to become a place.

**It holds records, not nodes.** A warehouse of frozen `RigidBody3D`s is a great
deal of physics for cargo nobody can see, touch or collide with. Depositing
records name, mass, fragility, value, **condition** and owner, then frees the
node; withdrawing builds one that is identical in every way the game reads.

This reads against [[Cargo]]'s founding rule that a crate is the same node its
whole life, so the line is worth stating: **that rule is about being carried.** A
crate must not launder its damage by riding on a rack, and it still cannot.
`Facility.recall()` had already established despawn-into-storage as the honest
shape for cargo that has stopped being a physical object. `test_storage.tscn`
asserts condition survives the round trip, because a shelf that quietly repaired
things would undo the abandonment argument by the back door.

**Deposit is physical; withdraw is the panel.** `F` at the intake hands a crate
over - handing something in needs no choosing. Taking one out is choosing one of
forty, which is what a list is for, and it lands on the dock. That is the
Storage → Dock rule from earlier the same day, now with a real Storage on the
other end.

**Uncapped.** Mac's call. The reason to consolidate should be that you want
something *here* rather than *there*, not that a number ran out; a cap turns a
depot into inventory tetris and creates a failure case with no good answer -
where does an overflowing delivery go? Revisit only if hoarding turns out to be
a problem, which it cannot be until there is something to build.

**Accepting an order still spawns onto the dock, not into storage.** Mac's note
originally described accept → storage → assign to dock. Rejected as a toll booth:
it adds a click to every single order for the sake of the uncommon case. Storage
is the persistent home and the overflow, not a step on the way out.

**State lives in the `Orders` autoload keyed by facility id**, not on the
Facility node. The Lattice ladder means reading a linked facility's stock without
that facility necessarily being loaded, and one blob keyed by id is the shape the
save wants. That makes `order_book.gd` the **facility ledger** rather than only
the board - orders are what a facility wants moved, storage is what it is
holding, and delivery turns one into the other. Splitting them across two
autoloads would only have meant two globals talking about one fact.

Two things fixed on the way, both of which had been wrong since the day they
shipped and neither of which had anywhere better to go until now:

- **Dock overflow was dumped on the sand** - loose bodies beside the pallet, and
  a way to lose cargo under the terrain.
- **A delivered crate sat on the pad forever**, so a busy depot silted up with
  cargo already paid for. It is now consumed rather than shelved: fifty spent
  crates would bury the player's own things under a receipt log.

---

## 2026-08-31 - Interaction follows the look direction

Mac hit it in play: a crate lying beside the rover was always picked up,
because `E` tried crates first. **This does not overturn "two cargo verbs, not
one priority-ordered interact" from 2026-08-30 - it finishes it.** That decision
split `E` and `F` so boarding could never compete with unloading, and it stands.
What it left behind was a fixed order *inside* `E`, and that is what broke.

**Scoring, not a cone.** Mac asked for an interaction cone. Godot has no cone
collision primitive, and a `ConvexPolygonShape3D` one would have to be
re-oriented every frame to follow the camera. So the 3.5 m sphere stays as the
broad phase - *what is nearby* - and everything it finds is scored on how well
it lines up with the look direction. Lowest score wins. That is what "in front
of me" actually means, it needs no new geometry, and it degrades gracefully: a
lone crate slightly off-axis is still reachable, where a hard cone edge would
drop it in silence.

The priority list is gone entirely, in both verbs. `F` no longer needs the rover
to beat the dock, either.

**Camera forward, not body forward.** The body only turns while you are moving,
so aiming off it would mean turning the camera while standing still changed
nothing about what you could reach. **Horizontal only**, because a crate at your
feet is far below the camera's forward ray and a full 3D dot product would rule
it out for being on the ground.

Rejected: a **screen-centre raycast**, the other standard answer. The chase
camera sits behind and above, so a ray through the reticle spends most of its
time hitting terrain short of anything worth touching.

**The arcs were measured, not argued.** `probe_interact_aim.tscn` sweeps the look
direction through a full circle and reports which arc gives which answer, at
`half_angle` 80 deg and `aim_bias` 3.0:

| | crate | rover | neither |
|---|---|---|---|
| crate beside the rover | 109 deg | 83 deg | 168 deg |
| crate almost in the way | 160 deg | 20 deg | 180 deg |
| crate well off to one side | 113 deg | 104 deg | 143 deg |
| crate on the far side | 160 deg | 160 deg | 40 deg |

**The 20 deg case is kept.** With the crate nearly on the sightline to the
rover, looking at the rover *is* looking through the crate, and no `aim_bias`
fixes that without making everything else twitchy - it would need about 12,
against the 3.0 that serves every other case. A step to either side resolves it,
and so does picking the crate up.

Cost accepted: **every test now has to aim before it presses a key.** That is a
better test than what it replaced - it asserts what a player experiences rather
than what the code happens to accept - but it did mean going back through
`test_cargo_flow` and `test_orders`. `test_orders` had been passing only because
the dock happened to sit on the default look axis.

---

## 2026-08-31 - Orders: a named crate, authored in a TSV, with no clock on it

Mac's inbox note specified order management. Three forks in it were real, and
all three are now called. See [[Orders]].

**An order is a named crate, not a requirement.** Accepting 217 spawns 217's
boxes; the alternative - *deliver 120 kg of ore, fill it from anything
qualifying* - needs Facility Storage to be deep before the first order is
interesting, and makes the crate anonymous exactly when [[Cargo]]'s damage model
wants a specific object with a history. Not rejected, deferred: it is what
Storage grows into if hauling ever feels thin.

**The terminal panel moves cargo Storage to Dock, and no further.** A menu that
assigned crates straight to the rover would delete the physical stow verb and
the derived centre of mass from 2026-08-30, which is one of the better things
built. The menu does the warehouse half; the world keeps the loading half. The
inventory panel Mac asked for is a **reader** - nothing moves cargo except `F`.

**Deadlines are parked, not rejected.** `payout = base_value * condition^1.5`
was built so arriving slowly is a strategy, and a clock says the opposite. The
conditions under which the two coexist are known and strict - timed orders a
minority, the window quoted against the estimated drive rather than in raw
minutes, and a missed window decaying the bonus rather than failing the order -
but they cost more than they are worth before there is a single route to drive.
The [[Flares]] interaction is the blocker if it comes back: sheltering from a
flare must not cost you the window, or the game punishes obedience to its own
safety rule. `deadline_s` stays in the schema at 0, because the TSV editor
deliberately cannot add columns.

Three smaller calls made at the same time:

- **Facility is the generic; a Settlement is a Facility with people.** Two words
  were already in use for one thing - [[Settlements-and-Cast]] listed exactly
  the jobs Mac's note gave Facility. The split buys unmanned depots, relays and
  drop sites for free.
- **Ownership is a separate axis from type.** "Materials" and "materials you
  cannot use" are the same contents with different owners. `owner` is
  `PLAYER` / `FACILITY:<id>` / `ORDER:<code>`, and "can I build with this?" is
  just "is it mine?".
- **The TSV is a catalogue, never a save.** Parsed once at load; runtime state
  is savegame data keyed by `code`. Mac's call, and the right one - the moment
  the table is written at runtime it stops being a file that can be edited.
  `tools/tsv-editor.html` ports from StarChef unchanged, because it is generic
  by design; only its bash launcher needs replacing on Windows.

**Abandoning an order is a clean restart, cargo condition included.** Mac's
call. An accepted order can be handed back at any terminal; it returns to the
board as if never taken, and its crates are recalled to the origin's Storage and
reconditioned to pristine. The reasoning is that a run which went badly should
be restartable with a fair shot at it, in a game that has no combat and no fail
state.

Claude argued against the reconditioning first, on the grounds that it is a
damage launderer - accept, wreck the cargo, drive back, abandon, re-accept,
collect a pristine crate - and that it reads against `condition^1.5` and against
[[Cargo]]'s rule that a crate is the same node its whole life. Mac reaffirmed,
and on a second look the objection is weaker than it appeared:

- **The recall prices it.** Crates return to the *origin*, so re-running the
  order costs the whole outbound leg again. It is a repair costing a round trip,
  not a free reset, and a player unwilling to backtrack still takes the payout
  loss. The pressure survives; it stops being a one-way ratchet.
- **It closes a worse hole.** Recall takes every crate the order owns wherever
  it is, including one at the bottom of a ravine nothing can drive back into. An
  order made permanently unfinishable by an unreachable box is a worse outcome
  than any exploit this permits.
- The fiction is free: the Facility takes the shipment back and reconditions it.

**The price is set by Facility spacing**, which [[Settlements-and-Cast]] already
carries as `#blocking`. Close Facilities make reconditioning nearly free and
damage stop mattering on short routes. That is now a second thing riding on that
number, and a `#playtest` in [[Orders]].

Two cases need no rules of their own either way. Putting a crate down is not
abandoning the order, so a box left in the field is the player's own lost cargo
on the same terms as an orbital drop. And a ruined crate is still deliverable at
`base_value * 0^1.5`, so hauling a wreck home clears the entry for a player who
would rather not backtrack - abandoning is the other door out of the same room.

Kept deliberately: **the three-digit code is diegetic.** Stencilled on the
crate, printed on the receipt, spoken over comms, so one number refers to one
object across the HUD, the pad and the script. It stays **opaque** - encoding
the origin Facility in the first digit is the obvious convenience and means
moving a Facility renumbers the world.

## 2026-08-31 - Rocks are cells of MultiMesh, and only the big ones are solid

Mac asked for rocks scattered on the terrain with distance culling. Two things
were decided; the rest is sliders.

**Cells, not one big MultiMesh.** This was measured before it was designed,
because the obvious implementation silently does not work.
`visibility_range_end` is measured against the *instance's* AABB, and a
MultiMesh is one instance holding every transform - so a whole-patch MultiMesh
has a whole-patch AABB, the camera is permanently inside it, and the range
never fires. A 120 m range on 8192 rocks in one MultiMesh dropped **exactly
zero** of its 1,376,256 primitives. The same rocks in 32 m cells drew 96,768.

Cells are therefore the unit of the whole system, not a tuning detail, and they
have a floor as well as a ceiling: 16 m cells with nothing culling them cost
more than doing nothing, because hundreds of small draw calls beat one big one.
The default landed at 48 m rather than the synthetic 32, because the real
scatter has a multiplier the probe did not - a MultiMesh holds exactly one
mesh, so every rock variant is its own instance in every cell.

**Big rocks collide, gravel does not.** Rocks at or above 1.4 m get a convex
hull; everything smaller is visual only. A shape per pebble is both expensive
and unpleasant to drive over, and "picking a line through rocks" in [[Rover]]
is about boulders, not grit. Collision is deliberately *not* distance-culled:
you cannot reach a rock the renderer has not already drawn, so there is no
invisible-wall case to solve.

Rejected on the way past: per-rock `StaticBody3D` nodes (hundreds of nodes for
no benefit over shapes under a per-cell body), and driving the culling from
GDScript (`visibility_range_*` is done by the render server, so the system runs
no per-frame code at all).

The rock meshes are procedural placeholders and say so. `rock_meshes` takes
authored meshes and the generator steps aside - that is the intended path once
Mac models a set. See [[Scatter]].

## 2026-08-31 - The post pass is on trial, and merged to one draw

Mac brought the film post stack they had already built for StarChef and wired
it in, explicitly to see what it does here. **This does not overturn "surface
treatment only, no post-process pass" from 2026-08-30** - Mac named that
decision as settled while asking, and the reasoning behind it is untouched.
Post cannot create the painterly look, only unify it. What is on trial is
whether it flatters the surface treatment or fights it, which is a judgement to
make while driving.

The one thing that *was* decided: **it runs as a single pass.** It arrived as
four ColorRects with a `BackBufferCopy` between each, and `film.gdshader` -
which came over in the same import - already existed to replace exactly that
shape. Merged, measured, and kept:

- 1.174 ms/frame to 0.965 at 1600x900. The post work alone drops from 0.30 ms
  to 0.10, about a third of the cost, because three full-screen copies and
  three mip-chain rebuilds per frame go away.
- The merged pass renders the same frame: mean per-channel difference of
  0.13/255, against 2.47/255 for the no-post control.
- All 19 settings preserved, none renamed, all still exposed - which was Mac's
  one condition. They are now on sliders in the F1 panel as well.

`film_material.tres` was carrying StarChef's tuning, which is a *different
look*; it now carries the values Space Stranding was actually running. The
StarChef numbers are in git at 253e9f4 if they are ever wanted.

Measured, not assumed: a `canvas_item` shader declaring `hint_screen_texture`
with `filter_linear_mipmap` already receives a full mip chain, so the merged
pass needs **no** `BackBufferCopy` in front of it. Adding one changes the image
not at all and costs 0.01 ms.

## 2026-08-31 - The tuning panel is generated by reflection

Mac asked for an F1 panel with sliders for every tunable. The shape of it was
the only real decision, and it went to reflection rather than a hand-written
list.

The panel reads `get_property_list()` and builds a control for anything marked
`PROPERTY_USAGE_SCRIPT_VARIABLE`, which is exactly a script's own `@export`
vars. `@export_group` headings and `@export_range` bounds come through with
them.

**A hand-written panel would have been wrong the first time either of us added
an export.** There are about fifty tunables across seven scripts today. The
generated one cannot drift: add an export, get a slider. It also puts pressure
in the right direction - when a guessed slider range feels wrong, the fix is to
write a real `@export_range` in the script, which improves the inspector too.

**The panel is explicitly not a second source of truth.** Nothing it does
writes to a scene or to `project.godot`, because the editor stays where values
are authored (hard rule 3). "Copy changes" reports only what differs from the
authored values, as a short list to read across into the inspector. A JSON
save/load in `user://` covers surviving a restart mid-iteration.

Costs accepted: only float, int, bool, Vector3 and Color are supported, so
strings and resources are skipped; targets are discovered when the panel opens;
and the six wheels' suspension and grip had to be named explicitly, because
they are built-in `VehicleWheel3D` properties rather than script variables.
That last one is worth the exception - they are the numbers [[Rover]] has been
carrying as tuned-by-reasoning-never-driven.

## 2026-08-31 - World's constants became variables

Forced by the panel, and worth recording because it reads against hard rule 4
at a glance.

**It is not a weakening of the one-place rule.** `world_constants.gd` is still
the only place a planetary number is written down; the values simply became
`@export var` so they can be moved while the game runs. Retuning the planet
went from a one-file change to a no-file change.

Two things it did cost. The names went to snake_case, because a SHOUTING name
that can be reassigned underneath you is worse than the churn of renaming seven
call sites. And anything *derived* from a tunable had to become a function
rather than a stored value - `gravity_ratio()`, `horizon_distance()`,
`star_direction()`, which also stopped being `static` - so nothing can go stale
when a value moves. Anything caching a derived value listens to
`World.changed`.

Gravity needed one more thing: `project.godot`'s `default_gravity` is read when
the physics space is created, so setting it at runtime does nothing at all.
`World` pushes each change to the space itself. Measured, not assumed - see
`tests/probe_runtime_gravity.tscn`.

## 2026-08-31 - Cargo damage comes from the carrier's jolt

Mac asked for crate fragility. The obvious implementation - crates take damage
from their own collisions - **cannot work for the case that matters**, and
finding that out first is what set the design.

A stowed crate is frozen with its collision switched off, so it can never
receive a contact event. All the damage that matters happens while cargo is on
a rack, which is exactly when the crate is blind. So the **rack** measures the
carrier and passes the jolt down to whatever it is holding.

That is not a workaround. Strapped-down cargo is not hurt by its own
collisions, it is hurt by the vehicle slamming into things - so the damage a
load takes is a direct read on how the [[Rover]] is being driven, which is the
mechanic we actually wanted. A loose crate is its own carrier and measures
itself, so there is one damage curve with two sources.

**Jolt is proper acceleration**, `|dv/dt - g|` - what an accelerometer bolted
to the crate would read. Free fall reads zero, which is correct: falling is
free and the landing is what costs. Damage is integrated over time rather than
fired on a threshold crossing, so there is no edge detection to get wrong, no
double-counting a landing that spans frames, and no frame-rate dependence.

**The thresholds were measured, not chosen.** `probe_carrier_jolt.tscn` drives
the loaded rover over real terrain: parked reads 3.96, ten seconds of full
throttle over broken ground peaks at 7.44, a 7 m drop runs 33 at p99. The floor
sits at 12 - clear of everything ordinary, with headroom for a shipping terrain
and a retuned engine. The first guess had been 8, which left 7% margin.

**Costs accepted:**

- Damage is invisible on the crate itself. Only the HUD word and the delivery
  receipt change. That is now the top `#now` in [[Cargo]] and it is Mac's call
  how far the art goes.
- The astronaut hits about twice as hard as the rover for a comparable fall,
  because `move_and_slide` stops dead where a sprung chassis does not. Kept
  deliberately - it makes the rover the safe way to move something delicate.
- The jolt is smoothed over 0.05 s, without which the same landing would cost
  four times as much at 120 Hz as at 30 Hz.

## 2026-08-31 - Delivery pays on condition, and cargo must be set down

The other half of the same decision: damage that is never scored is a hidden
number, and a hidden number changes nobody's driving.

`DeliveryPad` grades a crate on arrival and pays
`base_value * condition ^ 1.5`. The exponent is above 1 on purpose - a
half-condition crate pays 42 of 120, not 60 - so "arrive slowly" is a strategy
rather than a preference.

**Cargo has to come off the rack and be set down on the pad.** Nobody chose
that either: a stowed crate is on collision layer 0 so the camera spring arm
ignores the tower on the astronaut's back, which means an `Area3D` cannot see
it. Driving a loaded rover across the pad delivers nothing. The same accident
that fixed the camera gives us the depot, and unloading becomes a deliberate
act rather than a drive-through.

Condition is graded in words, never a percentage, from one static shared
function - so the HUD and the receipt cannot disagree about the same crate.

## 2026-08-30 - Triggers drive the rover; the stick only steers

Mac's call, immediately after the first gamepad pass bound throttle to the left
stick's Y axis like the keyboard's `W`/`S`. **`RT` accelerates, `LT`
decelerates, and the stick steers only.**

The implementation constraint worth remembering: `move_forward` /
`move_back` are shared between the astronaut on foot and the rover, so the stick
could not simply be unbound - that would have killed on-foot walking. The rover
got its own `drive_forward` / `drive_back` actions instead (`W`/`S`, `RT`/`LT`,
no stick binding). Two actions rather than one is what lets the same stick mean
different things in the two contexts without either script inspecting where the
input came from.

**`LT` brakes before it reverses**, above 0.6 m/s forward. Read literally,
"decelerate" could have been brake-only - but with throttle off the stick that
would leave a gamepad with no reverse at all. Brake-then-reverse is the
universal driving convention and satisfies both readings. `S` behaves the same
way, which is a change to the keyboard, and a deliberate one: the two should not
diverge. `Space` / `B` remain the separate full brake.

## 2026-08-30 - Cargo is a slot grid, not a physics placement puzzle

Answers the `#blocking` question that had been sitting in [[Cargo]] since the
note was written: *is loading a physics placement puzzle on the rack, or a slot
grid with derived centre of mass?* Mac chose the slot grid, with the load
feeding back into the rover's mass and centre of mass.

The note itself said physics was "the better fantasy and the worse UX". What
tips it is that the slot grid keeps most of the fantasy: mass and *placement*
still change how the rover drives, because the centre of mass is derived from
which slots are occupied. What is given up is the fiddling, not the consequence.

**Six slots on the rover in a 2×3 roof grid, two on the astronaut's back.** The
slots are Node3D children of a `CargoRack`, so capacity and layout are authored
by dragging markers in the editor and no slot count exists in code. One script
serves both racks.

Costs accepted: crates are one size, so *volume* is not yet a real axis - every
item occupies exactly one slot. Multi-slot items would be the way back toward
the puzzle if the load ever feels too frictionless.

## 2026-08-30 - Two cargo verbs, not one priority-ordered interact

`E` already boarded the rover, and cargo needed pick up, stow and unload. The
tempting shape is a single context-sensitive `E` that tries the nearest thing
first.

Rejected because it makes the common case worst: walk up to a **loaded** rover
intending to drive it and a priority-ordered `E` hands you a crate. Instead:

- **`E` / `A` - deal with the world.** Loose crate in range, or board the rover.
- **`F` / `X` - move cargo.** Carrying: stow on the rack or put it down.
  Empty-handed beside a loaded rover: take one off.

Boarding never competes with unloading, and unloading needs no third binding.
The HUD asks the astronaut what each key *would* do rather than describing the
rules itself, so a prompt cannot drift from the behaviour it describes.

Gamepad was wired at the same time on Mac's request - deliberately early, while
there is little enough input code that parity is cheap.

## 2026-08-30 - Stylized painterly, saturated, surface treatment only

Mac brought their own space paintings and asked for that look. Nothing in this
log had settled render style, so it was open.

**Three calls, all Mac's:**

- **Painterly, yes.** The specific version is cheap to shade: the stamps in the
  reference are *rectangular and hard-edged*, not organic brushwork. Organic
  strokes need a flow field and swim under camera motion; blocky patches hold
  still. This is why the look is achievable at all.
- **Saturated, not the muted palette.** This **supersedes** "desaturated browns
  and rust, not orange cartoon" in [[Visual-Direction]]. The paintings are
  ferociously red with teal accents and the saturation carries the appeal.
- **Surface treatment only.** Banded lighting, no specular, brush stamps in
  albedo. **No post-process pass** - deliberately rejected for now. Post alone
  cannot create the look, only unify it, and leading with it is the standard
  way to end up with a realistic game wearing a filter. Geometry stays grounded.

Costs accepted: normal, roughness and metallic maps stop earning their keep, so
Mac's Blender workflow moves toward silhouette and flat painted albedo. The
poly budget goes *down*.

The direction is not proven until it has been judged **in motion** - stills
cannot show swimming, which is the one failure mode that would sink it.

## 2026-08-30 - Godot 4, not Unity or Unreal

Mac was openly willing to switch engines and asked which one Claude could
manipulate most directly. Decided on capability, not familiarity.

Godot's `.tscn` / `.tres` / `project.godot` are plain text, so Claude authors
scenes, resources and materials as directly as code and verifies headlessly.
Unity would force Claude to write scene-*generating* editor scripts instead of
scenes - its YAML is keyed by fileID + GUID across sidecar `.meta` files and is
too fragile to hand-edit - at 30-60 s per batchmode iteration. Unreal's binary
`.uasset` cannot be read or written at all, and Blueprints are fully opaque.

**The known costs were priced in and accepted:** weaker terrain tooling, no
Nanite or Lumen, and large-map float precision needing floating origin or a
double-precision build. Do not propose an engine switch as the fix for any of
them. If switching comes up again, the deciding question is whether Mac still
wants Claude authoring content directly.

## 2026-08-30 - Vesper c: tidally locked, red dwarf, 0.34 g

> **Gravity revised to 0.55 g on 2026-09-02** - see the entry at the top of
> this log. Everything else here stands.

Chosen from four options (Europa-like ice moon, Titan, Mars, free-invention
exoplanet). Mac picked far-future exoplanet and left the specifics to Claude.

Tidal locking is doing real work, not flavour: it fixes the star on the horizon
(see [[Visual-Direction]]), gives the map a thermal axis, strings the
settlements into a natural chain, and makes the nightside flare-shadowed - so
the safest place from the sky is the most hostile on the ground.

Mars was rejected as well-trodden. Titan remains the strongest unused
alternative if the fixed-star look ever fails to land.

## 2026-08-30 - Flares replace timefall; the Lattice replaces the chiral network

Both are deliberate structural analogues of Death Stranding systems, kept
because they carry the same tension, and rewritten so they are ours. See
[[Flares]] and [[The-Lattice]].

**No supernatural threat.** There is no BT analogue. Pressure comes from the
environment and the pull comes from the [[Science]] mystery.

## 2026-08-30 - Godot's VehicleBody3D drives toward +Z

Not a design decision - an engine fact that cost a bug, recorded so it is not
rediscovered.

Positive `engine_force` pushes toward **+Z**, while the chassis faces −Z like
every other Godot node. The rover therefore drove backwards, which **also read
as inverted steering** because the vehicle was coming at the camera.

Mac reported both as flipped and asked for both to be inverted. Inverting both
would have left the steering genuinely wrong: measured on the corrected
throttle, positive `steering` yaws left, which is already what `A` produces.
**One sign fixed both.** Verified with
`res://tests/probe_vehicle_axes.gd` - re-run it rather than reasoning about it.
