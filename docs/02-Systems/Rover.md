---
status: partial
verified: 2026-08-30
godot: res://scripts/vehicle/rover.gd
tags: [system, traversal, core-loop]
---

# Rover

Six-wheel pressurised hauler. Driving and boarding are built; everything that
makes it a *cargo* vehicle is not.

## Behaviour

`VehicleBody3D`, six wheels, front pair steering, all six driven. Built today:

- Throttle, reverse, brake, engine braking
- **Speed-sensitive steering** - authority falls to 35% by 14 m/s. At a third of
  Earth's grip, full lock at speed puts you on your roof
- Slow hydraulic steering rate (1.6 rad/s), so it never darts
- Centre of mass dropped to −0.35 to resist rolling on side slopes
- Enter/exit with `E`, camera and input handover to and from the astronaut

Not built: [[Cargo]] racks and mass effects, flare shield, power, damage,
[[Progression]] upgrades.

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
- [ ] No rollover recovery. In 0.34 g a flipped rover is currently permanent.

## Open

- [ ] TODO: tracks or wheels for the upgrade path, and does it change the
      physics model or just the numbers? #question
