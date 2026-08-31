---
status: partial
verified: 2026-08-31
godot: res://scripts/orders/order_book.gd
tags: [system, core-loop, cargo]
---

# Orders

The layer between [[Cargo]] and the world: who wants a thing moved, from where,
to where, and what it is worth. [[Cargo]] built the *verb*; this is the
**reason**.

Written from Mac's inbox note of 2026-08-31. The three forks in it are settled -
see the [[Decision-Log]] entry of the same date.

**Built the same day, as far as the slice goes.** Two facilities, a board you
press `E` at, cargo with an address, and the existing `DeliveryPad` closing the
job. What is *not* built is storage as a real place, the inventory reader, the
[[The-Lattice]] ladder, and construction - so the status is `partial`, not
`built`. "Where the code is" at the bottom says which is which.

## Facility, and what it is not

A **Facility** is anywhere with an identity, a terminal, storage and a pad. A
**Settlement** is a Facility with people in it.

That split is the whole reason for two words. It buys unmanned depots, relay
stations and drop sites without inventing a second system for them, and it keeps
[[Settlements-and-Cast]] free to be about characters rather than about logistics
fixtures.

A Facility owns:

| Part | Job |
|---|---|
| `id` | short stable string - `hearth`, `relay-7`. Everything else keys off it |
| Terminal | interact to open the order panel |
| Storage | this Facility's stock. **Not** a global pool - see below |
| Dock | the pallet accepted cargo is placed on, to be stowed by hand |
| Pad | the existing `DeliveryPad`, now a child rather than a loner |
| *(later)* | flare shelter, upgrade install, [[The-Lattice]] anchor |

Making the pad a child of the Facility answers the `#next` that has been sitting
in [[Cargo]] since the pad was built: the HUD showed the first pad in the tree
rather than the one you are standing at, because a pad had no identity to show.
Now it inherits one.

## An order is a named crate

**Settled: accepting order 217 spawns 217's crates.** The order is not a
requirement to be satisfied from stock - it is those specific boxes, and they
carry the code.

The alternative - *"deliver 120 kg of ore, fill it from anything qualifying"* -
is a better logistics game and a worse fit for what exists. It needs Facility
Storage to be deep before the first order is interesting, and it makes the crate
anonymous exactly when [[Cargo]]'s damage model wants it to be a specific object
with a history. Kept in reserve; it is what Facility Storage grows into if
hauling ever feels too thin.

## The panel must not delete a verb

Stowing is physical: `F` at the rack, six markers, and the rover's centre of
mass derived from which slots are occupied. That is one of the better things
already built, and a menu that "assigns cargo to the rover" would erase it.

So the terminal panel moves crates **Storage to Dock** and stops there. The
player still walks them onto the rack. The menu does the warehouse half, which
is bookkeeping; the world keeps the loading half, which is the game.

The second panel Mac's note asks for - player inventory and order management -
is a **reader**, not a mover. It answers *what am I carrying, whose is it, where
does it go*. Nothing moves cargo except the two verbs in [[Cargo]].

## Abandoning is a clean restart

An accepted order can be handed back at any terminal. It returns to the
Facility's board exactly as it was offered, and **its crates are recalled to the
origin's Storage and reconditioned to pristine**. Mac's call, 2026-08-31: a run
that went badly should be restartable with a fair shot at it, not survivable
only by hauling a wreck home.

The board has to allow it or it becomes a trap that fills with things that
cannot be finished. The reconditioning is the part that was argued and settled -
see the [[Decision-Log]] for the case against.

**The recall is what keeps it from being free.** Crates come back to the
*origin*, so re-running the order costs the whole outbound leg again.
Abandon-and-reaccept is therefore a repair priced at a round trip, not a reset
button, and a player unwilling to backtrack still eats the payout loss. That
leaves `payout = base_value * condition^1.5` with its teeth while stopping it
being a one-way ratchet.

The price is set entirely by **how far apart Facilities are**, which
[[Settlements-and-Cast]] already carries as its `#blocking` question. Close them
up and reconditioning is nearly free and damage stops mattering on short routes;
spread them out and abandoning is a real decision. It is the same number, and
this is now a second thing riding on it.

**Recall takes every crate the order owns, wherever it is** - on the rack, on
the astronaut's back, or at the bottom of a ravine nothing can drive back into.
That removes a whole category of bad outcome: in a game with no combat and no
fail state, an order made unfinishable because a box is somewhere unreachable is
worse than any exploit it might permit. Nothing can be permanently stranded.

The fiction carries it. The Facility takes the shipment back and reconditions
it, which is a thing warehouses actually do.

**Putting a crate down is not abandoning the order.** `F` drops a box anywhere,
any time; it stays owned by its order and the order stays accepted. So a crate
you walked away from in the field is *your own lost cargo* - mechanically the
same object as an orbital drop, and recoverable on the same terms. Abandonment
needs no rule about crates left in the world, because that case is already the
loose-cargo case, and recall sweeps them up if you would rather start over.

A ruined order needs no special handling either. A wrecked crate is still
deliverable and pays `base_value * 0^1.5`, which is nothing - so hauling the
wreck home closes the board entry for a player who would rather not backtrack.
Abandoning is the other door out of the same room.

## No deadlines, for now

Timed orders are **parked, not rejected**. `payout = base_value * condition^1.5`
exists so that arriving slowly is a strategy; a clock says the opposite, and the
two only coexist under conditions strict enough that it is not worth paying for
them yet. The reasoning is preserved in the [[Decision-Log]] so it can be picked
up whole rather than re-argued.

`deadline_s` stays in the schema at `0`. The TSV editor deliberately does not add
columns, so a column that costs nothing now is cheaper than hand-surgery on the
file later.

## Ownership is not type

Mac's note had three cargo types: materials, materials-as-quest-cargo, and
upgrades. The first two are the same **contents** with different **ownership**,
and tangling those makes "why can't I use this one" a rule to memorise.

Split:

- **`owner`** - `PLAYER`, `FACILITY:<id>`, or `ORDER:<code>`. Can you consume it
  for construction? Only if it is yours. Delivering an order-owned crate
  transfers it to the destination Facility and pays out.
- **`type`** - what is actually in the box: materials, upgrade, sample, personal
  effect. Free to mean one thing now.

Loose cargo found in the world is `owner: NONE` until picked up.

Combat is unresolved, so weapon cargo is not a type. It costs nothing to add one
later; it costs something to design around a maybe.

## The table

`game/data/orders.tsv`, keyed by `code`.

| Column | |
|---|---|
| `code` | 100-999, opaque, sequential, **never reused** |
| `title` | player-facing name |
| `origin` | Facility `id`, or `world` for loose cargo |
| `destination` | Facility `id` |
| `type` | materials / upgrade / sample / personal |
| `crates` | how many boxes spawn |
| `mass_kg` | per crate - **sets** the crate's `mass`, not a second copy of it |
| `fragility` | per crate - sets `crate.fragility` |
| `value` | per crate - sets `base_value` |
| `deadline_s` | 0 = untimed. Parked, see above |
| `requires` | `code` that must close first, blank for none |
| `issuer` | whose voice the terminal speaks in |
| `blurb` | one line of terminal text |

`origin: world` carries no coordinates. Mac places the crate in the scene and
gives it a code; the row supplies everything else. Placement stays a thing you
drag in the editor, which is hard rule 3 and also simply better than authoring
positions in a spreadsheet.

**The code is diegetic, not a database key.** Stencil it on the crate, print it
on the receipt, let a character say it over comms. "Bring me 217" then refers to
one object across the HUD, the pad and the script without a shared string
anywhere.

It stays **opaque**. Encoding the origin in the first digit is the obvious
convenience, and it means moving a Facility renumbers the world.

## The TSV is a catalogue, never a save

Parsed once at load into an in-memory catalogue. **Nothing writes to it at
runtime.** Order state - offered, accepted, picked up, delivered - is savegame
data keyed by `code`, in whatever form is convenient.

The moment the table is written to, it stops being a file Mac can edit and
becomes a save file that looks like one.

`tools/tsv-editor.html` comes over from StarChef unchanged. It is generic by
design - it reads any TSV, infers columns and types, and knows nothing about the
game it serves. StarChef's `clients.tsv` arrived months after the tool was built
and needed **no work at all**: byte-identical round trip on the first try. The
only port cost is that `tsv-editor.sh` is bash and this machine is Windows.

## Loose cargo obligates nobody

Cargo lying in the world - an orbital drop, or just there - shows its destination
and its payout when picked up, and appears in the order list. It **never expires
and never fails**. Picking something up must not hand the player an obligation
they did not accept.

That keeps it as pure opportunity: a reason to steer toward the glint on the
ridge, which is the traversal pillar paying for itself rather than a second quest
system bolted alongside it. Drop events pair naturally with [[Flares]] and
[[Science]].

## Storage is per-Facility, and that is [[The-Lattice]]'s payoff

Stock left at a Facility is *at* that Facility. On its own that is a chore
generator - "the part you need is six kilometres away" is only interesting once.

### It holds records, not nodes

A warehouse of frozen `RigidBody3D`s would be a great deal of physics for cargo
nobody can see, touch or collide with. Depositing records what a crate **is** -
name, mass, fragility, value, **condition**, owner - and frees the node; taking
it out builds one that is identical in every way the game reads.

That reads against [[Cargo]]'s rule that a crate is the same node its whole
life, so the line is worth stating precisely: **that rule is about being
carried.** A crate must not launder its damage by riding on a rack, and it still
cannot. Going into a warehouse is not carrying, and `recall()` already
established despawn-into-storage as the honest shape for cargo that has stopped
being a physical object. `test_storage.tscn` asserts condition survives the
round trip, because a shelf that quietly repaired things would undo the
abandonment argument by the back door.

### Deposit is physical, withdraw is the panel

`F` while carrying, facing the intake, hands a crate over. No menu: handing
something in needs no choosing. Taking one out is choosing one of forty, which
is what a list is for - so it lives on the terminal's Storage tab and puts the
crate **on the dock**. That is the settled Storage → Dock rule, now with a real
Storage on the other end of it.

The facility's own stock shows on the shelf and cannot be taken. You can see
what a depot is holding without helping yourself to it.

### Uncapped

Mac's call, 2026-08-31. The reason to consolidate should be that you want
something *here* rather than *there* - which is the ladder below - and not that
a number ran out. A cap would turn a depot into inventory tetris and add a
failure case with no good answer: where does an overflowing delivery go?

### Two things it fixed on the way

**Dock overflow used to be dumped on the sand.** Nine crates for eight slots
meant a pile of loose bodies beside the pallet and a way to lose cargo under the
terrain. Storage was always the right answer; there was simply nowhere to put it.

**A delivered crate used to sit on the pad forever**, so a busy depot silted up
with cargo that had already been paid for. It is now taken in and *consumed* -
not shelved, because fifty spent crates would bury the player's own things under
a receipt log. Storage is a locker, not a junk drawer.

What makes it a system is that it is the ladder [[The-Lattice]] climbs:

| Coverage | Grants | |
|---|---|---|
| none | you must be standing there to know what is there | **built** |
| linked | **see** a remote Facility's stock, and its order board | **built** |
| linked | **request a transfer** - it arrives later, on its own time | **built** |
| late | standing routes between linked Facilities | design |

Built 2026-08-31. Seeing and requesting turned out to be the same rung rather
than two: once a terminal can read a remote shelf, refusing to let it ask for
anything is a gate with nothing behind it. See [[The-Lattice]].

That is the chiral network's convenience with none of its magic, and it means
stranded stock is a problem you solve by *building the network* - which is
already what the campaign is supposed to be.

## What the build found

Three things the design above did not anticipate, all of them the same shape:
the system was correct and unusable.

**A docked crate is stowed, so `E` cannot see it.** `nearest_loose_crate()`
skips anything in a rack, and `F` only knew about the rover - so the board
issued cargo that nothing could then pick up. Every headless assertion passed,
because the crates existed and were sitting exactly on their slots. `F` now
treats a dock the way it treats the rover's rack, in both directions, so cargo
can be staged on a pallet as well as lifted off one.

**Loose cargo could never be delivered.** The pad only takes crates whose order
is accepted, and found cargo is never on a board to be accepted from. Picking it
up now accepts it - which turned out to be the right fiction as well as the fix:
`Orders.notice_found()` is the moment a thing lying in the dirt becomes a thing
with a destination.

**Recall would have deleted an authored crate.** Order 105's box is placed in the
scene, not spawned, so freeing it would have destroyed something of Mac's with
nothing to put it back. `recall()` refuses loose orders outright.

The through-line is that none of the three would have shown up in a headless
test written from the design. They needed the question *can a player actually
do this*, which is why `facility_capture.tscn` exists.

## Where the code is

| | |
|---|---|
| The catalogue, the state, the board's rules | `res://scripts/orders/order_book.gd` |
| One parsed row | `res://scripts/orders/order.gd` |
| Identity, issuing, recall | `res://scripts/world/facility.gd` |
| The thing you press `E` at | `res://scripts/world/facility_terminal.gd` |
| Two panes, accept and hand back | `res://scripts/ui/order_panel.gd` |
| Storage, and what is on a shelf | `res://scripts/orders/stored_item.gd` |
| Transfers between facilities | `res://scripts/orders/order_book.gd` |
| The table | `game/data/orders.tsv` |
| Editing the table | `tools/tsv-editor.ps1` |

`OrderBook` is autoloaded as **`Orders`**, alongside `World` and `Debug`. It has
to be global for the same reason `World` does: there is one catalogue and one
set of accepted orders, and both outlive any scene. Nothing else about the
system is global - a Facility is an ordinary node authored in the editor, and
the panel is found by group.

## Verification

`res://tests/test_orders.tscn` runs the whole loop: parse, issue, deliver to the
wrong facility, deliver to the right one, part-deliver, close, unlock a
prerequisite, hand back, re-take, and lift a crate off a dock.

Four of those would not be caught by anything else:

- **A crate delivered to the wrong facility must pay nothing.** Without the
  address check every order is "drive to the nearest pad" and the `destination`
  column means nothing. Nothing would look broken.
- **Handing an order back must take the cargo with it**, or the order can be
  taken again while the first lot is still on the dock. A crate duplicator, and
  a quiet one.
- **Re-taking must issue pristine cargo.** That is the whole of the 2026-08-31
  call, and it would rot silently.
- **Cargo on a dock must be liftable off it** - the bug above, now asserted.

`res://tests/test_storage.tscn` covers the shelf: that condition survives it,
that Hearth's shelf is not Longshadow's, that dock overflow lands on it, that
handing an order back sweeps it, and that house stock cannot be withdrawn.

`res://tests/facility_capture.tscn` writes stills. It earned its keep
immediately: the first facility was three props scattered on open sand, and the
parts only read as one place once they shared an apron. `probe_facility_sites.gd`
is how the two sites were chosen - it scans the terrain for the flattest 10 x 4 m
footprint, because the first pair were placed by eye at `y = 0` and were buried.

## Interactions

[[Cargo]] · [[Settlements-and-Cast]] · [[The-Lattice]] · [[Progression]] ·
[[Flares]] · [[Science]]

## Open

- [x] The vertical slice - two Facilities, `orders.tsv`, a terminal, a panel,
      and the existing `DeliveryPad` closing the job. Built 2026-08-31.
- [x] Port `tools/tsv-editor.html` from StarChef with a `.ps1` launcher. Done
      2026-08-31, and the tool needed no changes at all - byte-identical round
      trip on `orders.tsv` through its own parser, first try.
- [x] **Storage is a place.** Per facility, uncapped, holding records rather
      than nodes; deposit at the intake, withdraw from the terminal. Built
      2026-08-31.
- [x] The [[The-Lattice]] ladder - seeing a linked facility's stock from
      elsewhere and requesting a transfer that takes real time. Built
      2026-08-31.
- [ ] TODO: the inventory-and-orders reader Mac's note asks for - what am I
      carrying, whose is it, where does it go. The HUD manifest line covers the
      driving case; a full panel is for when the manifest gets long. #next
- [ ] TODO: is the terminal panel a fullscreen overlay or a screen rendered in
      the world? The second is the genre and costs readability; the first is
      readable and costs the fiction. #question
- [ ] TODO: `crates` above 1 means one order can outgrow the rover's six slots,
      making it a two-trip order. That is either the best content in the game or
      simply tedious, and only driving it will say which. #playtest
- [x] Does Storage have a capacity? **No.** Mac's call 2026-08-31 - see
      "Uncapped" above.
- [ ] TODO: nothing seeds a facility with starting stock, so a depot is empty
      until the player fills it. Probably wants a column in a table rather than
      an inspector array. #question
- [ ] TODO: abandoning reconditions the cargo, and the only thing charging for
      that is the drive back to the origin. On a short route the repair is
      nearly free and damage stops mattering. Watch for it once two Facilities
      exist at a real spacing - it may want a small fee after all, or it may be
      that Facilities are simply never that close. #playtest
- [ ] TODO: timed orders, if they ever come back, need the flare interaction
      solved first - sheltering must not cost the window. See [[Flares]].
