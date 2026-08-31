---
status: partial
verified: 2026-08-31
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

## The camera leans, it does not roll

`CamPivot` hangs off the chassis, so left alone it inherits the body's basis
whole - roll the rover and the horizon rolls with it, and on its roof the
player is upside down.

The camera keeps the lean, because that is what makes a side slope read as a
side slope, and throws away everything past `tilt_limit_deg` (18). A 15 degree
roll tilts the camera 15; 45, 90 and 180 all tilt it 18.

**The basis is rebuilt from scratch every frame rather than counter-rotated.**
A correction written back into the same local basis it was read from compounds,
and the symptom is a camera that slowly winds itself round over a few seconds
of driving rather than anything that looks like a bug on frame one. So the
pivot's orientation is assembled from three parts instead: world up rotated
toward the chassis up by `tilt_follow` of its tilt and never past the limit,
the chassis heading projected into that plane so the camera still sits behind
the rover through a turn, and the player's own yaw on top.

That is why the player's yaw is a `float` on the rover rather than the pivot's
rotation - the pivot's basis is overwritten every frame, so it cannot also be
where the yaw is stored. [[Debug-Panel|StickLook]] grew a `read()` returning
the stick's deltas for that; the astronaut, which is a `CharacterBody3D` and
never rolls, still uses `apply()` unchanged.

`tilt_smoothing` (0.12 s) is a time constant, not a per-frame factor, so the
response is the same at any tick rate. It exists because the rig passes
suspension chatter straight through and the clamp would otherwise snap on and
off against it. 0 restores the old rigid behaviour.

Asserted in `res://tests/test_camera_levelling.tscn`, which also checks the two
ways this can look right and be wrong: a camera pinned flat to horizontal
passes every clamp assertion and is a different feature, and a camera that has
eaten the heading no longer sits behind the rover.

## The spring arm, and two ways it collapsed

The chase arm shortens when something is in the way, which is right for terrain
and wrong for the rover itself. Two separate faults, both measured:

**The chassis was shoving its own camera.** `SpringArm3D` excludes nothing by
default, so the vehicle being filmed was just another obstacle. Pitching the
view up swings the arm down behind the rover and straight through the engine
bay: measured at **1.09 m of a 9 m arm** at `pitch_max`. That is not a wreck
case, it is looking up while driving. `add_excluded_object(get_rid())` in
`_ready()`.

**The camera mount flipped underneath the rover.** `CamPivot`'s position was
left in body space, so it followed exactly the roll the levelling exists to
ignore - upside down it sat 1.2 m *below* the chassis and the arm swept into
the ground, collapsing to 2.21 m. The mount now hangs off the *levelled* basis,
so it stays above the rover whatever the body is doing. Player yaw is
deliberately not applied to it: the mount stays put on the vehicle while only
the view turns around it.

Both are asserted in `test_camera_levelling.tscn`, and both were checked by
breaking them again afterwards - a test that passes before and after the fix is
worth nothing.

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
      reasoning, never against a human driving. All still provisional - but
      they are now all on sliders in the F1 panel ([[Debug-Panel]]), including
      the six wheels' built-in suspension and grip, so this is an evening of
      driving rather than a code change per guess. #playtest
- [ ] Wheels do not visually spin or steer - the meshes are static children.
- [ ] No rollover recovery. In 0.34 g a flipped rover is currently permanent -
      and a loaded roof rack makes flipping considerably easier. #next
- [ ] Nobody has driven it loaded. The centre-of-mass shift is arithmetically
      correct and completely untested against a human. #playtest

## Open

- [ ] TODO: tracks or wheels for the upgrade path, and does it change the
      physics model or just the numbers? #question
