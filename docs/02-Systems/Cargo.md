---
status: partial
verified: 2026-09-02
godot: res://scripts/cargo/cargo_rack.gd
tags: [system, core-loop]
---

# Cargo

Cargo is the verb of the game, so it has to have texture.

The slot mechanics, the load's effect on the [[Rover]], crate condition and
delivery payout are built. What is still missing is everything that makes one
crate different from another: thermal needs, radiation sensitivity, size.

## Behaviour

Since 2026-08-31 a crate also carries an **owner** and a **value**, both set
from `data/orders.tsv` when a facility issues it. Ownership is what decides
whether cargo is yours to use, and it is deliberately a different axis from what
is *in* the box - see [[Orders]].

Every item carries:

- **Mass** - affects [[Rover]] handling, braking, climb ability, and on-foot
  stamina. *Built for the rover; there is no stamina system yet.*
- **Volume** - competes for rack space. *Built, as one crate per slot.*
- **Fragility** - impact and vibration damage it. *Built - see "Damage",
  below. `fragility` on the crate is the per-item multiplier.*
- **Special needs** - thermal (stay hot/cold), radiation-sensitive (see
  [[Flares]]), pressure-sensitive, live samples, unstable. *Not built.*

Placement on the rover matters. High loads raise the centre of mass; uneven
loads pull the vehicle in turns. In 0.55 g a badly balanced rover does not
skid - it *tips*, slowly, with plenty of time to watch it happen.

Delivery pays on **condition**, not just arrival. *Built - see "Delivery".*

## Damage

Cargo takes damage from **jolt** - proper acceleration, the thing an
accelerometer bolted to the crate would read. Proper rather than coordinate
acceleration because that is what cargo actually feels: in free fall an
accelerometer reads zero and a falling crate is perfectly comfortable, and all
the damage happens on the landing. Subtracting the gravity vector buys that
distinction for nothing.

Damage is **integrated over time**, not applied on a threshold crossing:

```
excess = max(0, jolt - jolt_floor)
damage = (excess / (jolt_ruin - jolt_floor))^2 * dt * fragility
```

No edge detection to get wrong, no double-counting a landing that spans several
frames, and the same total cost at any tick rate. The square is what makes one
hard landing matter more than a long rough drive.

### Who measures what

**A stowed crate cannot measure itself.** It is frozen with its collision
switched off, so it can never receive a contact event - which is not a
limitation to work around but the honest case. Strapped-down cargo is not hurt
by its own collisions, it is hurt by the vehicle slamming into things. So the
**rack** watches the carrier and passes the jolt down to whatever it holds, and
the damage a load takes is a direct read on how the [[Rover]] is being driven.

A loose crate is its own carrier and measures itself. One damage curve, two
sources, and `JoltMeter` is shared by both.

### The numbers came from measuring

`res://tests/probe_carrier_jolt.tscn` drives the loaded rover over real terrain
and reports the distribution. That is where `jolt_floor` comes from:

| | smoothed jolt, m/s2 |
|---|---|
| Parked, loaded | 3.96 |
| 10 s of full throttle over broken ground | 7.44 peak |
| Crate resting on the ground | 6.32 |
| Loaded rover dropped 7 m | 33 at p99, 58 peak |
| Astronaut falling 8 m | 65 at p99, 123 peak |

`jolt_floor` is 12 - clear of everything ordinary with real headroom, because
the shipping terrain and a retuned engine will both push the driving numbers
up. Ordinary driving costs exactly nothing, and that is asserted, not hoped.

The astronaut hits roughly twice as hard as the rover for a comparable fall,
and that is kept deliberately: the rover has suspension and a person does not.
It makes the rover the safe way to move something delicate, which is most of
the point of having one.

### Smoothing is load-bearing

The jolt is exponentially smoothed with a 0.05 s time constant before anything
reads it. This is not cosmetic. `move_and_slide` zeroes the astronaut's
velocity in a **single frame**, so the raw signal is a spike of dv/dt whose
height depends on the tick rate rather than on the severity of the landing -
measured at 434 m/s2 against the rover's 181 for a similar event. Smoothing
makes the two instruments comparable, gives a brief impact enough duration to
be integrated, and makes the cost of an event independent of frame rate.
Measured across 30-120 Hz: 2.7% variation.

It also models the real thing it stands in for. Straps and packing have give,
so cargo never feels an infinitely sharp edge.

## Cargo you site, rather than deliver

**Added 2026-09-02.** A crate can carry `deploys_as: PackedScene` - what it
becomes when it is raised in the field. Empty for nearly everything; set on a
relay mast.

That one property is the difference between freight with an address and freight
where *the address is the decision*. A mast has no destination pad: where it
ends up is the point, which is why carrying one turns on the site survey in the
HUD (see [[The-Lattice]]).

A property rather than a subclass or a list of types, for the same reason
`ground_clearance` is one - a new deployable opts in by declaring what it
becomes, and nothing anywhere else has to learn it exists. See the 2026-09-01
entry in [[Decision-Log]].

`Crate.is_deployable()` is the query; `Astronaut.carried_deployable()` answers
for the back rack specifically, because a mast riding on the rover is still
freight and a mast on your back is a thing you are looking for somewhere to
put. **Raising one is not built yet** - the property currently only drives the
readout.

## Delivery

`DeliveryPad` is an `Area3D` with a solid deck. Set a crate down on it and it
is accepted, graded and paid for, once.

```
payout = base_value * condition ^ payout_exponent
```

`payout_exponent` is 1.5, so damage bites harder than linearly - a
half-condition crate pays 42 of 120, not 60. That is what makes "arrive slowly"
a strategy rather than a preference.

**Cargo has to be taken off the rack and set down.** Nobody wrote that rule: a
stowed crate sits on collision layer 0 so the camera spring arm ignores the
tower on the astronaut's back, which means an `Area3D` cannot see it either.
Driving a loaded rover across the pad delivers nothing. The same accident that
fixed the camera gives us the depot.

Condition is graded in words, not percentages - pristine, scuffed, damaged,
failing, ruined - because the player should be reading the crate, not a number.
`Crate.label_for()` is static and shared, so the HUD and the receipt can never
grade the same crate differently.

## Where the code is

| | |
|---|---|
| Slots, occupancy, load maths, carrier jolt | `res://scripts/cargo/cargo_rack.gd` |
| Condition, fragility, the damage curve | `res://scripts/cargo/crate.gd` |
| Proper-acceleration measurement | `res://scripts/cargo/jolt_meter.gd` |
| Acceptance and payout | `res://scripts/cargo/delivery_pad.gd` |
| Who a crate belongs to | `Crate.cargo_owner` - see [[Orders]] |
| A crate that is on a shelf rather than in the world | `res://scripts/orders/stored_item.gd` |

## Racks and slots

`CargoRack` is one script used twice: six slots on the rover's roof deck in a
2×3 grid, two on the astronaut's back. **The slots are the node's Node3D
children.** That is the entire configuration - drag a marker to move a slot, add
or delete one to change the capacity. No slot count exists in code, and the
rover's centre-of-mass maths reads the markers Mac actually placed.

Occupancy is always derived by walking the slots, never cached, so there is no
second copy of the truth to fall out of sync with the scene tree.

A crate is a `RigidBody3D` and stays the same node its whole life. Stowing
freezes it, switches its collision off and reparents it into a slot; putting it
down reverses that. Nothing is destroyed and respawned, so a crate cannot lose
its identity - or, later, its accumulated damage - by being carried.

**Being carried is the scope of that rule.** Cargo put into a facility's storage
*is* destroyed, and rebuilt with the same condition when it comes out, because
on a shelf it has stopped being a physical object at all - see [[Orders]]. The
distinction is what keeps a warehouse from being a free repair shop, and
`test_storage.tscn` asserts it.

Stowed crates sit on collision layer 0, which means the astronaut's camera
spring arm passes straight through the tower on their back rather than shoving
the camera into their helmet. That fell out of the design rather than being
planned, but it is load-bearing now.

## Loaded mass

The rover's `mass` in the inspector is the **empty** rover; `refresh_load()`
adds the crates on top and recomputes the centre of mass as the mass-weighted
blend of the empty chassis and the occupied slots. Six 35 kg crates is +22% mass
and lifts the centre of mass from −0.35 to roughly −0.10. Load one side only and
it moves sideways too.

Slots fill front pair, middle pair, rear pair, so a part-loaded rack stays
laterally balanced unless you deliberately unbalance it.

## Controls

Two verbs that never compete for the same press:

| | Keyboard | Gamepad | Does |
|---|---|---|---|
| Interact | `E` | `A` | A loose crate, a facility terminal, or board the [[Rover]] |
| Move cargo | `F` | `X` | Carrying: onto a rack with room, else put down. Empty-handed: off a rack that has something. Racks are the rover's and a facility dock's |

Boarding therefore never competes with unloading - walking up to a loaded rover
to drive it always just drives it. The HUD asks the astronaut what each key
*would* do right now, so the prompt can never disagree with what the key does.

**Which of several things in reach a verb acts on is decided by where you are
looking**, as of 2026-08-31. A crate lying beside the rover used to be picked up
whatever you wanted, because `E` tried crates first; there is no priority order
now. See [[Astronaut-Traversal]] for the scoring and the [[Decision-Log]] for
the measured arcs.

## Interactions

[[Rover]] · [[Astronaut-Traversal]] · [[Flares]] · [[Progression]] ·
[[Settlements-and-Cast]] · [[Orders]]

## Verification

`res://tests/test_cargo_flow.tscn` drives the whole round trip - ground → back →
rack → back → ground - and asserts mass and centre of mass at each hop. Its real
job is the one failure a stowed crate can hide: it is frozen with its collision
off, so nothing in the physics world complains if it silently stops tracking its
slot. The test drives the rover 11 m and asserts the crate is still exactly on
the slot.

`res://tests/test_cargo_damage.tscn` covers condition, the damage model and
payout. It has a deterministic half that never touches the physics engine at
all - it feeds a synthetic velocity profile straight through `JoltMeter` and
`Crate.apply_jolt` at 30, 60 and 120 Hz, because tick-rate independence is the
property the whole design rests on and nothing else would catch it regressing.
The physics half asserts the thing that would ruin the game if it broke:
**ordinary driving must cost nothing.**

`res://tests/cargo_capture.tscn` writes stills of the loaded racks. Slot
*placement* is the one thing the headless test cannot judge - it proves a crate
is on its slot, not that the slot is anywhere sensible. Re-run it after moving
any marker. `res://tests/delivery_capture.tscn` does the same job for the pad,
and earned its keep immediately: the pad shipped as a bare `Area3D` with no
solid deck, so crates fell straight through it and rested on the terrain
underneath. Nothing headless noticed, because delivery still worked.

## Open

- [x] Fragility, condition, and a delivery point that grades them. Built
      2026-08-31.
- [ ] TODO: damage is invisible. A ruined crate looks exactly like a pristine
      one - only the HUD word and the receipt differ. It needs to read on the
      crate itself: dents, a cracked lid, a spilled load. Mac's call on how far
      that goes. **Parked 2026-08-31** to make room for [[Orders]] - the
      mechanic works, it is only unreadable.
- [x] There is one pad, found by group, and the HUD shows the first one in the
      tree rather than the one you are standing at. Closed 2026-08-31 by
      [[Orders]]: a pad is a child of a Facility and answers to its `id`, it
      refuses cargo addressed elsewhere, and the HUD shows the receipt from
      whichever pad last took something - a receipt goes stale in seconds, so
      at most one is ever live.
- [x] Crates are one size and share one `base_value`. Contracts, cargo types
      and per-item value are the next layer. Answered by [[Orders]]
      2026-08-31: `orders.tsv` sets mass, fragility and value per crate, and
      ownership - not type - is what makes cargo yours or someone else's.
- [ ] TODO: does carrying cargo on foot affect balance and stumble the way
      Death Stranding's does? Two slots exist; nothing reads them yet. #next
- [ ] TODO: the back rack fills a lot of the third-person camera's lower frame
      at 2/2. Authentic to the parent, possibly bad to play. Mac's call.
      #playtest
- [ ] TODO: crates are one size. Volume as a real axis needs multi-slot items
      or a second crate size. #question

## Where a world crate starts

A crate authored into a scene carries `ground_clearance`, defaulting to **0.31 m**
- half the 0.6 m crate plus a hair - so it begins *resting* rather than falling.
One spawned even 15 cm up lands hard enough to register damage, which would have
every crate in the world pre-scuffed at session start for no reason the player
could see.

X and Z are hand-placed; the height is solved, in the editor while you drag and
again on load. See [[Placement]]. The constant used to live in `test_world.gd`,
which meant it only applied to crates parented under one particular node - the
recovered mast under `LooseCargo` was quietly exempt and kept a hand-tuned Y.
