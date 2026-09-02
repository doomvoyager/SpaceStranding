---
status: partial
verified: 2026-09-02
godot: res://scripts/world/lattice.gd
tags: [system, progression, core-loop]
---

# The Lattice

The relay network. **This is the spine - the system everything else hangs off**,
and the main thing separating this from its inspiration.

**The coverage half is built** as of 2026-08-31: sites link by range and line of
sight, a terminal reads a linked facility's shelves and board, and stock can be
asked for and takes time to arrive. **Placing relays is not** - they are authored
in the scene. The payoff had to exist first, or there would be nothing to place
one *for*.

## Behaviour

Relays are line-of-sight masts on high ground. Placing one means hauling the
mast and a power core to a site that has LOS to an existing relay - so surveying
for a site is itself gameplay, and terrain occlusion is a real constraint rather
than a radius check.

Coverage grants:

- Navigation and terrain data - uncovered ground is dead reckoning only
- **Hopper jump targets** - [[The-Lander]] cannot jump somewhere unlinked
- Contract visibility from distant settlements
- **Remote Facility storage** - see a linked Facility's stock, then later
  request a transfer from it. The chiral network's convenience without any of
  its magic. **Per-facility storage itself is built** as of 2026-08-31, so this
  has something real to hang off: `Orders.stock_of(id)` already answers for any
  facility, loaded or not, which is exactly the query a coverage check would
  gate. See [[Orders]]
- Longer [[Flares]] warning windows
- *(Later)* visibility of other players' persistent structures

Dark zones are genuinely dark: no map, no contracts, no warning.

## How linking is decided

Facilities and relays are both **sites**. Two sites link when they are within
range **and** can see each other over the terrain; coverage is which sites end
up in the same connected component as the one you are standing at.

Line of sight is the whole point and not a flourish. A radius check would make
the network a question of *distance*, which the map cannot argue with. Sampling
the terrain between two masts makes it a question of *where the high ground is*,
which is what surveying a route is supposed to be about.

**Solved at build time and cached** - that was the open question in this note. A
link's existence changes only when a site moves or the terrain is rebuilt, and
both are events we already have. Rebuilds are deferred and coalesced, so
registering six sites in one frame is one solve rather than six. Live solving
would re-sample a few hundred points per pair per frame for an answer that had
not changed since anyone last asked.

Sites are **duck-typed** - `lattice_id()`, `link_range()`, `mast_point()` -
because Facility and Relay both extend `Node3D` and GDScript has single
inheritance. Three methods is a small enough contract to carry by hand.

`mast_point()` is deliberately the top of the mast, and for a facility it is the
position of its name sign: already the highest authored point, and it moves when
the facility moves, so there is no second height to keep in step.

## What coverage grants, so far

A terminal's **Network** tab reads any linked facility's shelves and its order
board. A facility nothing can see shows as **no signal** and nothing else - not
greyed out, not partially readable. Dark zones are supposed to be genuinely
dark, and the panel asks `facilities_reachable_from()`, which does not list what
it cannot see.

**Requesting stock** takes it off the source's shelf immediately, holds it in
flight, and deposits it at the destination when it arrives. Being on neither
shelf while travelling is the honest reading and also means nothing can be
requested twice or withdrawn out from under a transfer.

It costs **time and nothing else** - Mac's call. Duration is a dispatch delay
plus distance over a speed that is deliberately slower than the rover: asking
the Lattice is the patient option, never the efficient one. If the network ever
beat driving there yourself, the rover would be a worse vehicle than a menu.

## Why it works

One system justifies field construction, the mobile base, surveying, and the
async multiplayer hooks all at once. Extending the Lattice **is** the campaign.

## Interactions

[[Flares]] · [[The-Lander]] · [[Science]] · [[Progression]] · [[Orders]]

## Where the code is

| | |
|---|---|
| Sites, linking, line of sight, coverage | `res://scripts/world/lattice.gd` |
| A mast | `res://scripts/world/relay.gd` |
| Surveying a prospective site | `res://scripts/world/lattice.gd` |
| The boundary on the ground | `res://scripts/world/coverage_map.gd` |
| Drawing it | `res://shaders/painterly.gdshader`, `coverage_*` uniforms |
| What a survey answers | `res://scripts/world/site_survey.gd` |
| The carried readout | `res://scripts/ui/hud.gd` |
| Transfers in flight | `res://scripts/orders/order_book.gd` |
| The Network tab | `res://scripts/ui/order_panel.gd` |

Autoloaded as **`Lattice`**, alongside `World`, `Orders` and `Debug`. It has to
be global for the same reason the ledger does: coverage is a property of the
world, not of whichever scene happens to be loaded.

## Verification

`res://tests/test_lattice.tscn` builds two facilities too far apart to see each
other and one mast between them, then checks the three things that would each
let the system look like it worked while being something else:

- **The relay is load-bearing.** Dark, then linked, then dark again when the
  mast is taken away. Any one of those failing would mean the link was a radius
  check, or a constant, or nothing.
- **Line of sight means something.** A mast five metres underground cannot see
  out, against a real generated terrain. Without this, *where* a relay goes
  stops mattering, which is the one thing it is supposed to be about.
- **A transfer takes time and lands on the right shelf**, at the condition it
  left with. Instant arrival would make this a teleporter.

`res://tests/test_mast_survey.tscn` covers the survey arithmetic against a real
generated terrain: that a site in range but buried loses to a clear one further
away, that the margin is the *minimum* of the two slacks rather than the
friendlier one, that ground out of everything's reach says so, and that
`survey_mast_height` still matches the antenna in `relay.tscn`.

`res://tests/test_mast_readout.tscn` covers the half that assertions usually
miss: whether anyone ever *sees* it. It loads the real world scene, puts a
deployable crate on the astronaut's back and checks the line appears - and puts
ordinary freight there and checks it does not. Correct-and-invisible is this
project's most repeated failure, and it has never once been caught by testing
the arithmetic.

`res://tests/test_mast_raise.tscn` covers the verb: that a mast raised between
two dark facilities links them, that it stands exactly where the survey said,
that lowering hands back the *same* crate at the same condition and takes the
site out of the graph, that dark ground is allowed, and that an authored relay
cannot be lowered. It also raises **two** masts, which is the only way to catch
them sharing a name - and did, the first time it ran.

`res://tests/test_coverage_map.tscn` covers the mask, and its first assertion
is the one the feature lives or dies on: that the covered region is **strictly
smaller** than the disc it sits in. A clean circle would look perfectly fine on
screen while quietly contradicting the mechanic. It also checks that a mast
connected to nothing paints nothing, that bridging to a dark facility lights
its ground, and that `is_covered()` agrees with the mask.

`res://tests/coverage_capture.tscn` is the other half, and must run
**windowed**: `--headless` is the dummy renderer and never builds a shader, so
every assertion above can pass with the overlay failing to compile. It shoots
the Hearth from three heights and then repeats two of them with the overlay
off, because a pair is the only honest way to tell a coverage artefact from one
the terrain already had.

`res://tests/probe_relay_site.gd` is how the test world's relay site was chosen.
It scans ground that is in range of both facilities and can see both, and scores
each candidate on its **weakest** margin. Ranking on sight-line clearance alone
picked a site sitting at 44.0 m of a 45 m reach - fine until anything moved. The
relay went to (-12, 14) with 8.2 m of clearance and 9.0 m of range to spare.

## Open

- [x] LOS solve - cache or live? **Cached**, rebuilt on `Terrain.rebuilt` and on
      any site registering. Answered 2026-08-31.
- [x] **Relays can be placed.** The mast is cargo, siting it is surveyed, and
      `R` / `Y` raises it where you stand or takes it back down. Done
      2026-09-02. What it opens rather than closes is below.
- [ ] TODO: **masts are unlimited.** Nothing consumes one, nothing costs
      anything, and a crate that deploys is otherwise ordinary cargo. Where
      masts come from is the whole economy of extending the network and it is
      currently "the one in order 105". #question
- [ ] TODO: **order 105 says bring the mast in; you can now stand it up in the
      field instead.** The order and the verb want different things from the
      same crate. Either the order becomes "raise it somewhere useful" or
      raising order-owned cargo is refused. Mac's call. #question
- [ ] TODO: nothing shows where coverage *would* reach from a prospective site
      - the readout answers "does this link", not "what does this buy". The
      gizmo ring in [[Placement]] is the editor half of the same gap. #next
- [ ] TODO: do relays need maintenance, or are they fire-and-forget? Maintenance
      creates return-trip content but risks becoming a chore. #question
- [x] What does the coverage map look like on screen? **A boundary drawn on the
      ground**, range intersected with line of sight, not a ring. Answered and
      built 2026-09-02 - see below.
- [ ] TODO: transfer speed and dispatch delay are guesses (2.5 m/s, 20 s). They
      only become judgeable once facilities are a real distance apart. #playtest

## Surveying a site

**Built 2026-09-02.** `Lattice.survey_at(x, z)` asks the coverage question of
ground that is not a site yet: it stands a prospective mast on the terrain at
that spot and runs the same range-and-sight-line test the graph runs, against
every registered site. It answers with a `SiteSurvey` - linked or not, which
site, and how much slack there is.

**The slack is the weakest of two margins**, never the kinder one: metres of
link range left over, and the smallest gap between the sight line and the
ground under it. This is the same rule `probe_relay_site` used to choose the
world's own relay site, and it exists because ranking on clearance alone picks
sites sitting at 44.0 m of a 45 m reach - fine until anything moves.

It is **carried, not consulted.** While a mast is on the astronaut's back the
HUD shows one coarse line - *links to Longshadow - 9 m margin*, or *no link
from here* - refreshed four times a second rather than per frame. The interval
is a design choice and is on the F1 panel: a per-frame readout stops reading as
an instrument and starts reading as a compass needle pointing at the answer,
and following a gradient is not the same activity as choosing a site.

Three answers, not two. `unknown` is distinct from *no link* - an unbuilt
terrain answers zero for every height and zero is a plausible height, so
"cannot say" has to be sayable.

The mast height the survey stands on (`survey_mast_height`, 11 m) is a second
copy of `relay.tscn`'s antenna, kept because a survey has to answer for a mast
that is not a node yet and instancing the scene four times a second would be
absurd. `test_mast_survey` fails if the two ever disagree.

What the survey deliberately does **not** do: refuse anything. It is an
instrument, not a gate. Whether a bad site is forbidden or merely a bad idea is
open, and is a question for when raising a mast exists.

## Raising one

**Built 2026-09-02.** `R` / gamepad `Y` raises the mast on your back where you
stand, or takes down one you raised earlier and are looking at.

Its own key, not an overload of `interact`. "The nearest thing" is exactly the
ambiguity that verb has already had a bug in, and raising a mast when you meant
to board the rover is not worth one saved binding. A mast is also excluded from
both other verbs, so `E` and `F` behave exactly as they did.

**The mast lands where the readout said**, because both go through the same
`survey_at` - there is one ground solve, not two that could drift.

**Raising is reversible, and the crate is never destroyed.** The crate is stowed
inside the relay and hidden, the same freeze-and-reparent a rack does, so
lowering hands back that exact node with its accumulated damage and its owner
intact. Siting is meant to be something you can be wrong about: a mast planted
on the wrong ridge that could never be recovered would push people to look the
answer up rather than survey for it, which is the opposite of the point.
Authored relays have no crate inside them and cannot be lowered.

**A dark site is allowed.** The survey warns and does not refuse - dark ground
is a real place, and a mast raised as a step toward a further one is a
legitimate thing to do.

Every raised mast gets its own id from `Lattice.unique_site_id()`, assigned
unconditionally rather than only when blank: `relay.tscn` carries an authored
id, so a blank check gives every raised mast the same name and the second
silently replaces the first in the graph.

## The boundary on the ground

**Built 2026-09-02.** Coverage is painted on the terrain as a bright edge with
a faint tint inside it - the chiral network read, and the answer to the
question this note carried for two days.

**It is not a ring, and that is the entire point.** A circle would contradict
the system it is drawing: the claim above is that a radius check makes the
network a question of distance, which the map cannot argue with. So the mask is
range **and** line of sight, and a ridge takes a bite out of a site's coverage.
Measured on generated terrain by `test_coverage_map`: a site sitting on the
ground covers about **82%** of the disc it sits in, and the missing fifth is
the shape of the land.

**Only sites that chain back to `anchor_id` paint.** A mast raised out of reach
of everything lights nothing - otherwise the boundary would stop meaning
"connected" and start meaning "there is a mast here", which is the one thing it
must not mean. Extending the network is what makes the ground grow, which is
the loop the whole feature exists to show.

`CoverageMap` builds an R8 mask spanning the patch, rebuilt on the same
`coverage_changed` the graph emits and coalesced the same way - never per
frame. Only ground within a site's reach can be covered, so each site
rasterises its own box: about 2,000 texels and 45,000 height lookups per site
at 2 m per texel, once, when the network changes. The terrain shader samples it
through the UV2 the macro albedo already uses, so the patch's 1.3 km world
offset is handled for free.

The **mask is the authority for gameplay too**. `Lattice.is_covered()` reads it
rather than recomputing, so a flare warning and the line on the ground can
never disagree about where the edge is. This is the first thing to implement
the coverage promises at the top of this note; nothing consumes it yet.

[[The-Map]] draws the **same mask** through the same UV2, so the boundary on
the map and the boundary on the ground are one texture and cannot disagree.
Note the map shows terrain outside coverage rather than hiding it - a
deliberate exception to "dark zones are genuinely dark", argued and decided on
2026-09-02; see [[Decision-Log]].

The edge owns both channels it draws into and the fill only tints `ALBEDO` -
an overlay that adds to `EMISSION` over bright ground comes out white. The
scan pulse is drawn after it, so a ping paints over the boundary rather than
under it.

## Siting a relay

A relay is authored on X and Z; its **height is solved**, never typed. That is
not tidiness - links are decided by line of sight over the terrain, so a mast
sitting two metres below the ridge it was meant to see over links to a different
set of sites than the one you placed. See [[Placement]], which draws the tether
down to the contact point so the offset is visible before you press play.

Drawing `link_range` as a gizmo ring, so siting is judged in the viewport, is
open there.
