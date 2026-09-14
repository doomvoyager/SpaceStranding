---
status: partial
verified: 2026-09-14
godot: res://scripts/vehicle/rover.gd
tags: [system, traversal, core-loop]
---

# Rover

Six-wheel pressurised hauler. Driving, boarding and the roof rack are built;
everything else that makes it a *cargo* vehicle is not.

## Behaviour

`VehicleBody3D`, six wheels, front and middle pairs steering, all six driven.
Tuned for the Moon on 2026-09-13 - see "Drivetrain, on the Moon". Built today:

- Throttle, reverse, brake, engine braking, all in newtons
- **Parked with the brake on from the start of the level**, not only once
  somebody has climbed out. Before 2026-09-13 an empty rover sat on a free
  wheel and rolled 4.2 m down its slope in ten seconds on lunar grip
- **A governor at 4 m/s** (1.5 in reverse) - nothing else limits speed
- **Speed-sensitive steering with a dead band** - full lock below 5 m/s, falling
  to 35% by 14 m/s. Under the governor it only engages running downhill past
  the cap; the ramp still has to *start* above manoeuvring speed. See below
- Slow hydraulic steering rate (1.6 rad/s), so it never darts
- Centre of mass dropped to −0.35 to resist rolling on side slopes
- Enter/exit with `E` / gamepad `A`, camera and input handover to and from the
  astronaut. Right stick looks; it is polled in `_process` rather than handled
  as an event, because a stick reports a held position and not a delta
- **First person from the cab** on `V` / D-pad up, the same key as on foot,
  with the hull culled from the eye - see "The driver's eye"
- **A six-slot roof rack that changes how it drives** - see below
- **A brake light that follows the pedals, not the brake force** - see below
- **Rollover recovery** - you climb out and heave it over. See below

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
forward on low grip does not stop you - it just spins them.

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

## The driver's eye

`V` / D-pad up while driving. Added 2026-09-14; the shared half - one key,
each context remembering its own view, the handover on climbing out - is in
[[Astronaut-Traversal]] under "Views".

**The eye rides the chassis.** `Eye` is a plain child of the rover at
(0, 1.12, -1.55), inside the blockout cab, and `_aim_eye()` writes the
player's yaw and pitch into its local basis every frame - the same two numbers
the chase rig uses, so the two views agree about where you are looking. No
levelling and no clamp: a side slope tilts the horizon by exactly the slope and
a rollover turns the world over, which is what sitting in a cab means. Measured:
rolled 40°, the eye tilts 40.0 and the chase pivot 18.0. The
`previews/2026-09-14/view-15_*` / `view-16_*` pair is the same 30° roll seen
from both.

**The eye does not see the rover.** The hull, the nose wedge, the rack deck, the
brake light bar and the six wheel meshes are on render layer 3, "Rover hull",
and the eye's cull mask leaves it out - both authored in the scene, where a
mesh's layer belongs. The blockout cab is 0.77 m deck to roof and the nose
wedge rises to its roofline, so an eye anywhere inside it looks straight at the
inside of a slab: `view-14_rover_first_hull_visible` is that frame. Lifting the
eye above the roof was the alternative, and reads as standing on it. An
authored interior goes on a layer the eye keeps; the exterior stays on 3.
GrimdarkTank's gunner sight culls its tank the same way.

**Where the eye sits is Mac's.** A seated eye would be 1.1-1.2 m above the
floor and the cab is 0.77 m tall; 1.12 m is a low, reclined seat, and the node
moves in the editor. The crates on the roof rack are not hull and stay visible,
so looking back over your shoulder shows the load.

Climbing out hands the astronaut `view_heading()` - the flat yaw of whichever
camera was on screen - so you land facing the way you were looking.

## The brake light

`BrakeLightBar` on the back of the hull, lit by driving the emission energy of
its own `StandardMaterial3D`. Colour is authored on the material in the
inspector; `rover.gd` drives only the brightness, so there is one place to
change the red and one place to change the behaviour.

**It follows the pedals, not `brake`.** Engine braking applies 2.5 brake units
whenever the throttle is closed, so a light wired to the brake *force* is lit
almost permanently - and a brake light that is always on is indistinguishable,
in a screenshot, from a brake light that works. Only the two deliberate inputs
count:

| | Lit |
|---|---|
| Full brake (`Space` / `B`) | yes |
| Decelerate pedal (`S` / `LT`), rolling forward | yes |
| Decelerate pedal, once it has become reverse | yes, unless `brake_light_on_reverse` is cleared |
| Throttle | no |
| Coasting, under engine braking | **no** |
| Parked, nobody driving | no |

The reverse case is a deliberate choice rather than an accident of the
threshold. That pedal is a brake above `reverse_threshold` and reverse below
it, and both are the driver asking not to go forward - so the bar follows the
pedal and does not blink off at the instant the rover comes to rest under it.
A road vehicle would show white here; this is one bar. `brake_light_on_reverse`
turns it off for anyone who disagrees.

**The energy is low, and it has to be.** ACES tonemapping desaturates hardest
where the image is brightest, so a saturated red past about 1.2 stops being red
and becomes an orange-white smear that spills over the whole hull. Swept
against the real scene at twilight, which is the brightest ambient this planet
ever has:

| `brake_light_energy` | Reads as |
|---|---|
| 0.5 | red, but flat - paint, not a lamp |
| **0.9** | **red, with just enough bloom to read as lit** |
| 1.4 | washing out through the middle of the bar |
| 5.0 | orange-white, and the hull glows with it |

`res://tests/brake_light_capture.tscn` writes the off/on pair; re-run it after
touching the material or the energies, because this is the half a headless test
cannot judge. `res://tests/test_brake_light.tscn` asserts the material's
emission energy - not just the boolean - through throttle, coast, brake,
decelerate, reverse and exit. It was checked by wiring the light to `brake > 0`
and confirming the coasting assertion fires.

The bar's material is `duplicate()`d in `_ready()`, because a sub-resource in a
scene is shared by every instance of that scene and a second rover would
otherwise light this one's bar.

## The speedometer

`hud.gd`, drawn bottom-right, on screen only while somebody is driving. Added
2026-09-02 at Mac's request.

**It reads m/s**, which is the unit every other number in this project speaks -
`reverse_threshold`, `steer_falloff_speed`, the F1 sliders. km/h would give a
livelier 0-23 against a top speed of about 6.5 m/s, and would mean the figure
you read while driving was not the figure you tune with. One decimal, because a
whole number would spend most of a drive showing `4`.

**`Rover.ground_speed()` is horizontal, not `linear_velocity.length()`.** The
vertical component is not speed you are making toward anywhere, and folding it
in means a rover dropped off a ledge reads *faster* the further it falls - a
gauge that peaks while you are in the air is reporting the wrong quantity at
exactly the moment somebody is looking at it. Its sign comes off
`forward_speed()` rather than off the flat vector, so a rover sliding sideways
down a slope still reads positive; reversing is the only thing that makes it
negative.

**The dead band is load-bearing, not cosmetic.** `REV` is driven by that sign,
and a rover settling on its suspension crosses zero in both directions several
times a second - so without `speedo_deadband` a parked vehicle strobes REV at
you. 0.15 m/s, on an F1 slider.

The figure is set in JetBrains Mono, which was already in the project and used
nowhere. A proportional font shifts the digits sideways as the number changes,
which is exactly what a readout updating sixty times a second must not do. It is
a `theme_override_fonts/font` on one label and comes straight back out if Mac
would rather it matched the prompts.

`res://tests/test_speedometer.tscn` covers the half that hides: not on screen on
foot, on screen and saying something once boarded, a flat zero with no marker
inside the dead band, a fall reported as no speed at all, and reverse marked in
the marker rather than by a minus sign in front of the figure. Every stage waits
for the *panel* to catch up rather than reading it on the next physics frame -
the first version passed its reverse check on a REV left over from the rover
rolling backwards while parked. `res://tests/speedo_capture.tscn` is the look
pass and runs **windowed**.

## The load

**`empty_mass` is the rover with nothing aboard, and the number to tune** - on
F1 under Body, live. `refresh_load()` sets `mass` to it plus whatever is on the
rack and recomputes the centre of mass as the mass-weighted blend of the empty
chassis and the occupied slots, read from the slot markers themselves rather
than from numbers in code. `mass` itself used to be the inspector value, and
could not be tuned live: `refresh_load()` rewrote it from a copy taken at
`_ready`. The scene no longer carries a `mass` line at all.

Mass is not grip. `VehicleBody3D` multiplies each wheel's spring and friction by
the chassis mass, so a heavier rover rides and grips the same and is only slower
to speed up and to stop - the drive and brake forces are newtons.

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

## Drivetrain, on the Moon

Retuned for 1.62 m/s^2 on 2026-09-13. Every number here comes from
`tests/probe_rover_spec.tscn`, on flat ground, unless it says otherwise - run it
with `--fixed-fps 60` and it takes a second.

**What the Moon would have done to the old rover, and what it does now:**

| | 5.39, old tuning | 1.62, old tuning | **1.62, lunar tuning** |
|---|---|---|---|
| Launch, empty | 6.25 m/s^2 | 3.06 m/s^2 | **1.74 m/s^2** (1.29 loaded) |
| Speed after 3 s | 17.3 m/s | 8.2 m/s | **3.9 m/s, governed** |
| Full brake from 4 m/s | 1.0 m | 1.7 m | **5.8 m** (7.1 m loaded) |
| Coast from 4 m/s | 7 m | 7 m | **24 m** |
| Sag | 4.1 cm, 13% of travel | 1.2 cm, 4% | **9 cm, 28%** |
| Full lock, loaded | turns | inside wheels lift at every speed | **turns: 7 m circle at 2 m/s, 10 m at the cap** |
| 0.5 m lip, loaded | stays down | 1.0 s with every wheel off at 5 m/s | **stays down at 4 m/s** |

The old columns were measured with Godot's default linear damping of 0.1/s,
which the Moon no longer has.

**Two of `VehicleBody3D`'s numbers do not mean what they say.** Both measured:

- **`engine_force` is given to every driven wheel.** The old 1170 was 7,020 N:
  6.25 m/s^2 off the line against 7.39 predicted per wheel, 1.23 as a total.
  `drive_force` is now a total, split across the driven wheels.
- **`brake` is a per-wheel impulse per physics tick**, so the same number was a
  stronger brake at a higher tick rate - 8.7 m/s^2 at 60 Hz, 12.3 at 120.
  `brake_force` is newtons, converted each tick: 5.84 m at 60 Hz, 5.82 at 120.

**Nothing capped the top speed.** There is no rolling resistance under power,
so the old rover did 17 m/s on flat ground; the 6.5 m/s it used to reach was the
terrain. Hence `top_speed`, a governor: full drive until the last
`governor_band`, fading to nothing at the cap. It settles at 3.9. A downhill can
still carry the rover past it - the cap is on the motors, and holding it back is
the brake's job.

**The springs were set for a heavier planet.** Sag is gravity over the summed
stiffness and does not depend on mass - measured 4.3 cm against 4.1 predicted
at 5.39. A wheel's whole margin is its sag, so at 1.62 on the old stiffness of
22 the inside wheels left the ground in every corner while the body rolled less
than two degrees. **Stiffness 3** gives 9 cm, 28% of travel; **damping 0.5 /
0.7** puts it near 0.7 Hz at roughly a third and a half of critical damping:
soft, and settled within a few seconds. All six wheels now
stay down through a loaded full-lock turn and over a 0.5 m lip.

**Grip is not the same in both directions, and that shaped everything else.**
`VehicleBody3D` caps straight-line force at about twice `wheel_friction_slip`
times gravity - at a slip of 0.2 the rover braked at 0.65 m/s^2 with 3,000 N of
brake or 9,000 - but its sideways grip is nearer 0.6 to 0.7 of the slip times
gravity, read off the turning circles. One slip cannot give both a lunar
stopping distance and steering worth having. So **slip 1.25 is chosen for the
steering**, and the stopping distance and the pull are set by `brake_force` and
`drive_force`, which the grip cap sits well above.

**Drive force was chosen on the climb, not the launch.** Loaded, at 1.62, capped
at 4 m/s (`probe_rover_climb` and `probe_carrier_jolt`):

| `drive_force` | Progress halves at | 10 s over broken ground | Jolt p99 |
|---|---|---|---|
| 1200 | 18.0° | 15 m, top 2.7 m/s | 2.9 |
| 1600 | 21.3° | 24 m, top 3.2 m/s | 3.6 |
| **2000** | **25.0°** | **26 m, top 3.4 m/s** | **4.7** |
| 2400 | 28.7° | 27 m, top 3.5 m/s | 5.6 |

1200 was sluggish, which is not the same thing as careful. **2000** brings the
scanner's red ground back to where it has always been (25°, was 26) and covers
nearly the old 29 m in ten seconds while held to the cap. Cargo came through
every run pristine; a loaded 7 m drop now costs 0.6%, against 22% at 0.55 g,
because the soft springs take the landing.

**Brakes 1250 N, engine braking 300 N.** Stopping from the cap takes 5.8 m
empty and 7.1 loaded, and letting go rolls on for 24 m. Momentum is the thing
low gravity is about; a rover that stopped when you lifted off would hide it.

**Driven on 2026-09-14 and kept.** Mac: slower and more careful is exactly the
feel asked for. Every number is still on F1 under Body, Drivetrain and Brakes,
and the wheels' grip and springs under Rover wheels.

### Before the Moon: what 0.55 g cost it

Grip scales with normal force, so a heavier planet is *kinder* to a vehicle in
the corners - but the same weight costs more in rolling resistance and in
climbing out of every undulation, and on broken ground the second effect wins.

Moving the planet from 0.34 g to 0.55 g on 2026-09-02 took ten seconds of
full throttle over broken ground from **4.7 m/s and 29 m** to **1.9 m/s and
7 m**, at an unchanged 900 N. That is not a feel regression, it is a hauler
that can no longer haul, and no test caught it - every one of the fifteen
passed at 900 N on the heavier planet. `probe_carrier_jolt` caught it, because
it is the one thing that drives.

Re-seated by bisection against the old figures:

| `max_engine_force` | Top speed | Distance / 10 s | Load after |
|---|---|---|---|
| 900 (unchanged) | 1.9 m/s | 7 m | pristine |
| 1050 | 4.4 m/s | 17 m | pristine |
| **1170** | **6.5 m/s** | **29 m** | **pristine** |
| 1450 | 7.6 m/s | 37 m | scuffed |
| *900 at 0.34 g* | *4.7 m/s* | *29 m* | *pristine* |

**1170 restores the ground covered, not the top speed.** Distance over ten
seconds is the honest measure - top speed is one sample - and the peak comes
out livelier than it was because the added grip pays off on the clear
stretches. 1450 was rejected for scuffing cargo on an ordinary drive, which is
the line between rough terrain and bad driving.

`max_reverse_force` was scaled by the same 1.3 so the drivetrain keeps its
shape. Brakes were not touched and were not measured then; the spec probe is the
instrument that was missing.

## Behind a panel

**The rover lets go of its controls while a full-screen panel is up**, rather
than freezing: throttle released, engine braking on, steering held. The world
is not paused, so a rover left rolling coasts instead of stopping dead in
mid-air.

This did not exist before 2026-09-02. The order board is only reachable on
foot at a terminal, so nothing could be opened while driving until [[The-Map]]
got its own key.

**It lets go the same way while a text field has the keyboard** - the F1
panel's search box, or one of its value fields. The pedals are polled, and a
focused field swallows W as an event while `drive_forward` still reads it
held, so typing "wheel" opened the throttle. See `Astronaut.is_typing()` and
`tests/test_typing_gate.tscn`. Added 2026-09-13.

## Rollover recovery

In 0.55 g a flipped rover used to be permanent, and a loaded roof rack makes
flipping considerably easier - the load lifts the centre of mass from −0.35 to
about −0.10, which is exactly the margin the low mass was buying. The job was
to stop a flip ending a run without turning it into a keypress.

**The astronaut rights it from outside, by hand.** Climb out, walk round, hold
`E` / `A` for 1.2 s and the rover rolls back onto its wheels over 2.4 s. The
verb lives on the astronaut, not the rover, because that is what makes it a job
rather than a key - you are out of the cab and standing in the weather for the
length of it. Mac's call, over righting it from the driver's seat.

**On `interact`, held, rather than on a binding of its own.** [[Decision-Log]]
gave the mast its own key because "the nearest thing" is the exact ambiguity
`interact` has already had a bug in - but that was ambiguity between two
*different objects*, and this is one object in two states. An upside-down rover
cannot be boarded, so `E` facing one has exactly one possible meaning, and the
aim scoring already picks the rover out from whatever is lying beside it. A
verb used once an hour is not worth a top-level binding. The press path is
guarded too: `E` on a wreck does not climb into it.

The prompt fills in as you hold - `Righting the rover ||||||....`. This is the
only hold in the game, and a verb that ignores a tap in silence looks broken.

### It is driven, not thrown

The obvious implementation is an angular impulse, and it is the wrong one: a
950 kg body in low gravity needs a large one to turn over at all, the amount
depends on how it happens to be lying, and everything it does to the load is an
accident.

So the body is frozen `FREEZE_MODE_KINEMATIC` and its transform is interpolated
by hand over `righting_duration`, eased at both ends with a `smoothstep`.
Heading is kept - you flipped going somewhere. The landing height is *solved*:
a ray finds the ground below, and the chassis is placed so the lowest wheel's
contact point clears it by `righting_clearance` (0.08 m), with the wheel drop
read off the wheels themselves rather than typed in.

### A recovery costs time and nothing else

Mac's choice, and it is measured rather than asserted. Six crates on the roof,
rover on its back, righted:

| | |
|---|---|
| Peak jolt through the recovery | **9.14 m/s²** |
| `jolt_floor` (below which nothing is damaged) | 12.0 m/s² |
| Condition lost | **0.0000** |

`righting_duration` is what buys that, and the test proves it by breaking it:
at 0.25 s instead of 2.4 the same recovery peaks at **30.96 m/s²** and starts
taking the load apart. A flip already cost you the crash; the recovery does not
bill you twice.

**A kinematic body moved by writing `global_transform` does report a derived
`linear_velocity`**, which is why the duration matters at all - the rack
watches the carrier, so a driven motion is measured as real acceleration just
like a physical one. Had it reported zero the cargo would have been trivially
safe at any speed, and the 0.25 s run shows it is not.

`res://tests/test_rollover_recovery.tscn` asserts the whole path - rolled-over
detection, that `E` refuses to board a wreck, that the hold does not fire early,
upright afterwards, on the ground, six crates, no condition lost.
`res://tests/rollover_capture.tscn` writes the sequence, which is the half no
headless test judges.

### Climbing out of a wreck

`exit()` used to hand `_exit_point.global_position` straight to `disembark()`,
and the marker sits at (−2.1, −0.5, 0) in **body** space - so it followed every
degree of roll the rover had. Upside down that is half a metre *up* on the
wrong side; on its flank it is 2.1 m straight down, inside the terrain.

That was survivable while nothing needed you outside a wrecked rover. It is
load-bearing now, because on foot is the only place the verb that rights it
exists. `exit_position()` takes the marker's offset in a **levelled** frame and
solves the height against the ground - the same rule the crates already
followed and nothing else had been given. Asserted in the recovery test, which
checks the exit point is above ground with the rover inverted.

## Known issues

- [x] ~~The lunar tuning has never been driven by a human.~~ Mac drove it on
      2026-09-14: "feels nice, exactly what I had in mind with slower and more
      careful driving." The numbers stand; every one is still on F1 - Body,
      Drivetrain, Brakes, and the six wheels' springs and grip. #playtest
- [ ] Wheels do not visually spin or steer - the meshes are static children.
- [x] ~~No rollover recovery.~~ Built 2026-09-02 - see above.
- [ ] The righting pivots about the chassis origin, so mid-roll the rover
      clips through the ground rather than levering up off its contact edge.
      It is kinematic through that, so nothing collides and nothing breaks -
      it just reads as a rotation rather than as a heave. Rotating about the
      ground contact line would fix it. Judge it from
      `rollover_capture.tscn` before spending anything on it. #next
- [ ] A rover flipped *against* a rock is righted straight through the rock.
      The landing height is solved against the ground below and nothing
      checks the space it sweeps. #next
- [ ] Nobody has driven it loaded. The centre-of-mass shift is arithmetically
      correct and completely untested against a human. #playtest

## Open

- [x] Tunable like GrimdarkTank's tank, and slower, for the Moon: the spec
      probe at both gravities, `empty_mass`, a governor, drive and brakes in
      newtons, and a lunar retune. Done 2026-09-13; see "Drivetrain, on the
      Moon". Ride sag and damping *ratios* were left out - the wheels keep their
      stiffness and damping in the inspector, and F1's readout shows the sag
      they add up to. #now
- [ ] TODO: tip first or slide first? On the lunar tuning a loaded rover at full
      lock does neither: the front washes out and the circle widens, 7 m at
      2 m/s to 10 m at the cap. Raising `wheel_friction_slip` trades that for a
      tighter turn and, eventually, a roll. A feel choice to make with the
      slider. #playtest
- [ ] Since 702b214 the middle wheels steer by the front pair's angle from a
      different distance to the rear axle, so the two axles cannot share a
      turning centre and scrub each other through a turn. Whether that is felt
      at all is a driving question. #playtest
- [ ] TODO: tracks or wheels for the upgrade path, and does it change the
      physics model or just the numbers? #question
