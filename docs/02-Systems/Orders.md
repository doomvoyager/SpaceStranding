---
status: design
verified: 2026-08-31
godot:
tags: [system, core-loop, cargo]
---

# Orders

The layer between [[Cargo]] and the world: who wants a thing moved, from where,
to where, and what it is worth. [[Cargo]] built the *verb*; this is the
**reason**.

Written from Mac's inbox note of 2026-08-31. The three forks in it are settled -
see the [[Decision-Log]] entry of the same date.

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

## Abandoning: the row resets, the boxes do not

An accepted order can always be handed back. It returns to the Facility's board
exactly as it was offered - Mac's call, 2026-08-31, and the board has to work
that way or it becomes a trap that fills up with things you cannot finish.

**Its crates keep their condition.** They go back into the origin's Storage in
whatever state you left them, still owned by `ORDER:<code>`, and re-accepting
hands the same battered boxes back.

That one exception to "reset" is load-bearing. A clean reset would be a **damage
launderer**: accept, batter the cargo, drive back, abandon, re-accept, and
collect a pristine crate for free. It would undo `payout = base_value *
condition^1.5`, which is the only reason careful driving pays. It would also
break [[Cargo]]'s founding rule - a crate is the same node its whole life
precisely so it cannot lose its history by being carried.

**Abandonment happens at a terminal, so the return trip is the penalty.** No
fee, no standing hit, nothing invented: the geography already charges for it.
Being six kilometres out and deciding the run has gone badly is then a real
decision rather than a menu click.

**Putting a crate down is not abandoning the order.** `F` drops a box anywhere,
any time; it stays owned by its order and the order stays accepted. So a crate
you walked away from in the field is *your own lost cargo* - mechanically the
same object as an orbital drop, and recoverable on the same terms. Abandonment
needs no rule about crates left in the world, because that case is already the
loose-cargo case.

A ruined order needs no special handling either. A wrecked crate is still
deliverable and pays `base_value * 0^1.5`, which is nothing - so hauling the
wreck home for zero closes the board entry. Nothing has to detect a dead order
or respawn its cargo.

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

What makes it a system is that it is the ladder [[The-Lattice]] climbs:

| Coverage | Grants |
|---|---|
| none | you must be standing there to know what is there |
| linked | **see** a remote Facility's stock, and its order board |
| upgraded | **request a transfer** - it arrives later, on its own time |
| late | standing routes between linked Facilities |

That is the chiral network's convenience with none of its magic, and it means
stranded stock is a problem you solve by *building the network* - which is
already what the campaign is supposed to be.

## Interactions

[[Cargo]] · [[Settlements-and-Cast]] · [[The-Lattice]] · [[Progression]] ·
[[Flares]] · [[Science]]

## Open

- [ ] TODO: the vertical slice - two Facilities, one `orders.tsv`, one order.
      Terminal to accept, crates on the origin dock, drive, existing
      `DeliveryPad` grades and closes it. Reuses the whole cargo stack and only
      adds Facility identity, the terminal, the panel and the loader. #now
- [ ] TODO: port `tools/tsv-editor.html` from StarChef and write a `.ps1`
      launcher - the `.sh` will not run here. The tool itself needs no changes.
      #next
- [ ] TODO: is the terminal panel a fullscreen overlay or a screen rendered in
      the world? The second is the genre and costs readability; the first is
      readable and costs the fiction. #question
- [ ] TODO: `crates` above 1 means one order can outgrow the rover's six slots,
      making it a two-trip order. That is either the best content in the game or
      simply tedious, and only driving it will say which. #playtest
- [ ] TODO: does Storage have a capacity? Infinite is kinder and removes every
      reason to consolidate, which is the thing the Lattice ladder feeds on.
      #question
- [ ] TODO: timed orders, if they ever come back, need the flare interaction
      solved first - sheltering must not cost the window. See [[Flares]].
