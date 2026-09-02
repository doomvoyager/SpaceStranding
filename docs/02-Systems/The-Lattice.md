---
status: partial
verified: 2026-09-01
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

`res://tests/probe_relay_site.gd` is how the test world's relay site was chosen.
It scans ground that is in range of both facilities and can see both, and scores
each candidate on its **weakest** margin. Ranking on sight-line clearance alone
picked a site sitting at 44.0 m of a 45 m reach - fine until anything moved. The
relay went to (-12, 14) with 8.2 m of clearance and 9.0 m of range to spare.

## Open

- [x] LOS solve - cache or live? **Cached**, rebuilt on `Terrain.rebuilt` and on
      any site registering. Answered 2026-08-31.
- [ ] TODO: **relays are authored, not placed.** Making one haulable is the
      campaign: the mast becomes cargo, and choosing where it goes becomes the
      survey. Order 105 already puts a downed mast in the world waiting for it.
      #now
- [ ] TODO: do relays need maintenance, or are they fire-and-forget? Maintenance
      creates return-trip content but risks becoming a chore. #question
- [ ] TODO: what does the coverage map actually look like on screen? The Network
      tab is a list, which answers "what can I reach" but not "where is the
      hole". #question
- [ ] TODO: transfer speed and dispatch delay are guesses (2.5 m/s, 20 s). They
      only become judgeable once facilities are a real distance apart. #playtest

## Siting a relay

A relay is authored on X and Z; its **height is solved**, never typed. That is
not tidiness - links are decided by line of sight over the terrain, so a mast
sitting two metres below the ridge it was meant to see over links to a different
set of sites than the one you placed. See [[Placement]], which draws the tether
down to the contact point so the offset is visible before you press play.

Drawing `link_range` as a gizmo ring, so siting is judged in the viewport, is
open there.
