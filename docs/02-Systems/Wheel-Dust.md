---
status: built
verified: 2026-09-14
godot: res://scripts/vehicle/wheel_dust.gd
tags: [system, vehicle, look]
---

# Wheel dust

Regolith thrown off the rover's wheels. Mac asked for "puffs of dust from
under the wheels" on 2026-09-14; what was built is the lunar version, which
is not a puff.

## The physics, and why it decides the look

There is no air. Every grain a tyre throws flies a clean parabola at
1.62 m/s² and drops; nothing billows, nothing hangs, nothing drifts. The
Apollo rover's rooster tails are sharp sheets of grains, and a grain thrown
at 4 m/s at 45° climbs 2.5 m and is up for 3.5 s - the long, lazy arc that
makes lunar footage look wrong to Earth eyes. So: no drag, no damping,
gravity read from `World` and refreshed on `World.changed`, and a grain is a
small opaque speck rather than a soft puff.

## How it works

`WheelDust` (`scripts/vehicle/wheel_dust.gd`, a child of the rover) makes
one `GPUParticles3D` per wheel. Every physics tick it:

- reads the tyre's surface speed off `get_rpm()` and its radius, and its
  skid off `get_skidinfo()`, and sets the emitter's `amount_ratio` for a
  rate that ramps to `max_rate` at `full_speed`, times 1 plus `skid_boost`
  at a full slide, and is zero off the ground or under a crawl;
- parks the emitter `birth_lift` above and `birth_back` behind the contact
  point, aimed back along the travel and up by `throw_angle_deg`, and writes
  the throw speed - `throw_fraction` of the tyre's - into that wheel's own
  copy of the process material.

Grains land on a `GPUParticlesCollisionHeightField3D` that rides under the
rover in steps of `ground_step`, seeing render layer 1 only (the terrain and
the rocks; the hull is on its own layer and would be a hump the grains hit
in mid-air), and hide on contact. A `GPUParticlesCollisionBox3D` fitted round
the hull's meshes stops the front wheels' throw at the deck - the fender the
blockout does not have.

## Where the numbers are

The throw and the amounts are exports on the node; the F1 panel lists it
under Driving as "Wheel dust". The shape of a spray - spread, scale range,
colour, hide-on-contact - is `materials/wheel_dust.tres`, and what a grain is
drawn with is `materials/dust_grain.tres`: a round speck, **unshaded on
purpose**. A billboard's normal faces the eye, so a lit quad goes dark
exactly cross-sun, where a spray is most visible, while a real grain is a
sunlit sphere bright from every side. What that costs is a grain in the
rover's shadow staying bright.

## What the sweep found

`previews/2026-09-14/dust-v1..v4`, then `dust-after-*`:

- **Born on the ground, a grain dies at birth.** The first pass put the
  emitters at the contact point; six wheels reported throwing and almost
  nothing was in the air, because a grain starting on the landing field was
  already in contact. `birth_lift` 0.1 m fixed it.
- **The chase camera comes back with the driver.** `Rover.enter()` makes its
  own camera current, and a capture that set its camera before boarding shot
  every frame from inside the trailing spray. Take the camera back after.
- **At 60% of tyre speed and 35° the spray hugs the wheels.** At the tyre's
  own speed and 45° it is a rooster tail.

## Verified

- `tests/test_wheel_dust.tscn` - the rate rule (off the ground, parked, a
  twitch, the ramp, saturation, reverse, skid), the ratio for a capacity,
  the throw direction; then the rover scene on a floor: one emitter per
  wheel, all quiet parked, a landing field in world space on layer 1, a box
  round the hull, gravity the World's and following a change, no drag,
  hide-on-contact; boarded and driven, six of six throwing, aimed behind
  the travel and up, at a fraction of the tyre's speed. 28 checks.
- `tests/dust_capture.tscn` - drives cross-sun and shoots from behind, from
  the side low, at a rear wheel, then braking and stopped, while moving.

## Open

- [ ] Grains in the rover's shadow stay bright (unshaded). A spatial shader
      that lights a billboard as a sphere would fix it; wait until it shows.
- [ ] Dust off the boots. The same emitter and rules would hang off
      `Footprints`' landings; a step throws far less than a tyre.
- [ ] The rate saturates at 4 m/s, the governed top speed. If the governor
      moves, `full_speed` should follow it.
