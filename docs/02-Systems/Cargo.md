---
status: partial
verified: 2026-08-30
godot: res://scripts/cargo/cargo_rack.gd
tags: [system, core-loop]
---

# Cargo

Cargo is the verb of the game, so it has to have texture.

The slot mechanics and the load's effect on the [[Rover]] are built. Everything
that gives a crate *character* - fragility, thermal needs, condition on delivery
- is not.

## Behaviour

Every item carries:

- **Mass** - affects [[Rover]] handling, braking, climb ability, and on-foot
  stamina. *Built for the rover; there is no stamina system yet.*
- **Volume** - competes for rack space. *Built, as one crate per slot.*
- **Fragility** - impact and vibration damage it. *Not built.*
- **Special needs** - thermal (stay hot/cold), radiation-sensitive (see
  [[Flares]]), pressure-sensitive, live samples, unstable. *Not built.*

Placement on the rover matters. High loads raise the centre of mass; uneven
loads pull the vehicle in turns. In 0.34 g a badly balanced rover does not
skid - it *tips*, slowly, with plenty of time to watch it happen.

Delivery pays on **condition**, not just arrival. *Not built.*

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
| Interact | `E` | `A` | Pick up a loose crate; otherwise board the [[Rover]] |
| Move cargo | `F` | `X` | Carrying: stow on the rover if beside it, else put down. Empty-handed beside a loaded rover: take one off |

Boarding therefore never competes with unloading - walking up to a loaded rover
to drive it always just drives it. The HUD asks the astronaut what each key
*would* do right now, so the prompt can never disagree with what the key does.

## Interactions

[[Rover]] · [[Astronaut-Traversal]] · [[Flares]] · [[Progression]] ·
[[Settlements-and-Cast]]

## Verification

`res://tests/test_cargo_flow.tscn` drives the whole round trip - ground → back →
rack → back → ground - and asserts mass and centre of mass at each hop. Its real
job is the one failure a stowed crate can hide: it is frozen with its collision
off, so nothing in the physics world complains if it silently stops tracking its
slot. The test drives the rover 11 m and asserts the crate is still exactly on
the slot.

`res://tests/cargo_capture.tscn` writes stills of the loaded racks. Slot
*placement* is the one thing the headless test cannot judge - it proves a crate
is on its slot, not that the slot is anywhere sensible. Re-run it after moving
any marker.

## Open

- [ ] TODO: fragility and condition. Crates currently arrive in the state they
      left in, which removes the entire reason to drive carefully. #now
- [ ] TODO: does carrying cargo on foot affect balance and stumble the way
      Death Stranding's does? Two slots exist; nothing reads them yet. #next
- [ ] TODO: the back rack fills a lot of the third-person camera's lower frame
      at 2/2. Authentic to the parent, possibly bad to play. Mac's call.
      #playtest
- [ ] TODO: crates are one size. Volume as a real axis needs multi-slot items
      or a second crate size. #question
