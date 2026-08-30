---
status: partial
verified: 2026-08-30
godot: res://scripts/vehicle/rover.gd
tags: [system, traversal, core-loop]
---

# Rover

Six-wheel pressurised hauler. Driving, boarding and the roof rack are built;
everything else that makes it a *cargo* vehicle is not.

## Behaviour

`VehicleBody3D`, six wheels, front pair steering, all six driven. Built today:

- Throttle, reverse, brake, engine braking
- **Speed-sensitive steering with a dead band** - full lock below 5 m/s, falling
  to 35% by 14 m/s. At a third of Earth's grip, full lock at speed puts you on
  your roof; but the ramp has to *start* above manoeuvring speed. See below
- Slow hydraulic steering rate (1.6 rad/s), so it never darts
- Centre of mass dropped to −0.35 to resist rolling on side slopes
- Enter/exit with `E` / gamepad `A`, camera and input handover to and from the
  astronaut. Right stick looks; it is polled in `_process` rather than handled
  as an event, because a stick reports a held position and not a delta
- **A six-slot roof rack that changes how it drives** - see below

Not built: flare shield, power, damage, [[Progression]] upgrades.

## Pedals

| | Keyboard | Gamepad | |
|---|---|---|---|
| Throttle | `W` | `RT` | Analog on the trigger |
| Decelerate | `S` | `LT` | Brakes while rolling forward, reverses once stopped |
| Full brake | `Space` | `B` | Shares its binding with jump, as it always has |
| Steer | `A` `D` | Left stick | |

**Throttle is `drive_forward` / `drive_back`, not `move_forward` / `move_back`.**
Those carry the left stick, which the astronaut needs to walk with on foot; in
the rover the stick steers and nothing else. Two separate actions is what keeps
both true at once, and `test_rover_controls.tscn` asserts that holding
`move_forward` leaves the rover coasting down rather than accelerating.

The decelerate pedal is a brake above `reverse_threshold` (0.6 m/s forward) and
reverse below it. Applying reverse torque to wheels that are still rolling
forward at a third of Earth's grip does not stop you - it just spins them.

## The steering dead band

The falloff originally ramped from a standstill, so the first metre per second
already ate your lock: 32° at rest, 26.9° at walking pace, 14.9° by 11.6 m/s.
Because the only way to gain speed is the throttle, this read as **the throttle
stealing the steering** - hold `RT` and the wheels straighten themselves.

`steer_falloff_start` (5 m/s) fixes it. Below that you get the full lock, and the
ramp to `steer_falloff_floor` runs from there to `steer_falloff_speed`. Parking,
turning around and picking a line through rocks all happen under 5 m/s and now
keep every degree.

Measured, not reasoned: `res://tests/probe_steer_under_throttle.gd` prints the
angle actually reached against speed, and `test_analog_input.tscn` asserts that
holding the throttle at manoeuvring speed still gives full lock.

## The load

`mass` in the inspector is the **empty** rover. `refresh_load()` adds whatever
is on the rack and recomputes the centre of mass as the mass-weighted blend of
the empty chassis and the occupied slots, read from the slot markers themselves
rather than from numbers in code.

A full rack is +22% mass and lifts the centre of mass from −0.35 to about −0.10
- which is the point. The low centre of mass exists to resist rolling on side
slopes, and loading the roof spends exactly that margin. An unbalanced load
moves it sideways as well. See [[Cargo]].

## The engine_force sign

**Godot's `VehicleBody3D` drives toward +Z on a positive `engine_force`**, while
the chassis faces −Z like every other node in the engine. `ENGINE_FORCE_SIGN`
in `rover.gd` corrects for it.

Getting this wrong makes the rover drive backwards, which *also* reads as
inverted steering because you are watching the vehicle come at the camera - so
the tempting fix is to invert both, which leaves steering genuinely wrong once
the throttle is corrected. Measured with `res://tests/probe_vehicle_axes.gd` and
locked in by `res://tests/test_rover_controls.tscn`, which drives the real
rover and asserts both axes. Re-run them rather than reasoning about it. See [[Decision-Log]].

## Interactions

[[Astronaut-Traversal]] · [[Cargo]] · [[Flares]] · [[Progression]]

## Known issues

- [ ] Suspension stiffness, friction slip and engine force were tuned by
      reasoning, never against a human driving. All still provisional. #playtest
- [ ] Wheels do not visually spin or steer - the meshes are static children.
- [ ] No rollover recovery. In 0.34 g a flipped rover is currently permanent -
      and a loaded roof rack makes flipping considerably easier. #next
- [ ] Nobody has driven it loaded. The centre-of-mass shift is arithmetically
      correct and completely untested against a human. #playtest

## Open

- [ ] TODO: tracks or wheels for the upgrade path, and does it change the
      physics model or just the numbers? #question
