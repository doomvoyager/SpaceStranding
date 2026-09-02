---
status: built
verified: 2026-09-02
godot: res://scripts/ui/map_panel.gd
tags: [system, ui, traversal]
---

# The map

**M**, and it works while driving. A 3D relief map you plan a trip on.

## Behaviour

A pan/orbit/zoom relief map of the patch, with the settlements, relays, the
rover and you on it, and a multi-stop route you draw by clicking the ground.

- **Click the ground** to add a stop. With a leg selected it is *inserted* after
  that one, which is what "I need to stop here on the way" means; with nothing
  selected it lands on the end, which is what drawing a route forward means.
- **Drag** to orbit, **right-drag** to pan, **wheel** to zoom. On a pad, right
  stick orbits, left stick pans.
- **Up / Down / Drop / Clear** reorder and edit the route.
- The side list shows each leg's length and whether that stop is inside
  coverage; the summary shows the whole trip.
- The HUD keeps a **next-stop line** with distance and a relative bearing when
  the map is closed. That is the point of planning: you put the map away and
  still know where you are going.

## It is a representation, not a screenshot

**The map is its own mesh with its own shader**, not a camera pointed at the
world. The world is lit by a red dwarf grazing the horizon through real fog; an
aerial view of it is a dark red smear — technically the truth and useless as a
map. So `MapTerrain` builds a low-resolution mesh from `Terrain.height_at()`
and draws it unshaded: elevation ramp, contour lines every 20 real metres, and
a hillshade from a conventional map light rather than from `World.star_direction()`.

Heights come from the same heightfield the game drives on, so the map cannot
drift from the ground. The mesh rebuilds on `Terrain.rebuilt`.

**Relief is exaggerated 2.5x.** 210 m across 2 km is nearly flat seen honestly,
and a relief map exists to make the shape of the land legible. Contours and
distances stay in real metres; only the mesh is stretched. `map_height()` is
the one place that knows, so the picker and the markers agree with what is
drawn.

**The elevation ramp fits the terrain and then bends.** Auto-ranged to the
heights actually present, *and* gamma-curved, because one massif owns the top
of the range: the authored map runs -19.8 m to 189.0 m while the ground you
walk on sits around 8. On a linear ramp that is 13% of the way up and the whole
map renders at the dark end with one bright peak.

## Coverage

The map samples **the same mask the ground draws**, through the same UV2 — see
[[The-Lattice]]. Sharing the texture rather than recomputing is what stops the
map and the world disagreeing about where the network reaches.

**Uncovered ground is shown and marked, not hidden.** Mac's call on
2026-09-02, against the alternative of resolving terrain only inside coverage.
It is a knowing exception to "dark zones are genuinely dark" — see
[[Decision-Log]]. Outside the boundary the ground is desaturated and dimmed,
and a stop in the dark is labelled `dark` in the leg list.

## Planning while moving

Opening the map hands the screen over the same way the order board does, via
`Astronaut.set_menu_open()`. **The world keeps running — this is not a pause.**

The [[Rover]] therefore lets go of its controls rather than freezing: throttle
released, engine braking on, steering held. A rover left rolling coasts instead
of stopping dead in mid-air. That gate did not exist before, because the order
board is only reachable on foot at a terminal and the map is the first panel
that can be opened at speed.

## The route in the world

**Built 2026-09-02.** Two readings, deliberately answering different
questions.

**A light pillar on the nearest remaining stop, and only that one.** It is a
horizon-finder: it answers *which way* from a kilometre out and nothing else.
A beam per stop would turn a planned trip into a field of columns with no way
to tell which one you were heading for. Additive, fixed-Y billboarded so it
stays upright when you look down at it from a rise, tapering out at the top so
it reads as light rather than as a bar. It hides once you are inside
`beam_near_cutoff`, because a 140 m column at arm's length is a wall.

**The whole route, on a scan pulse.** `Q` reveals the line you drew, following
the ground the same way the map's line and the leg lengths do, plus a triangle
at your feet aimed at the nearest stop. It fades with the pulse. This answers
*what was the plan* rather than *where next*, and it costs a ping — so the
route is something you check, not something permanently painted over the world.

The line and the pointer **mix rather than add**. Adding a bright cyan over the
terminator's pink ground comes out white; it is the same trap the scan dot had
to learn, and the route line carries its colour for the same reason.

## Arriving

**Reaching a stop clears it and everything before it.** Arrive at the third
having skipped the first two and all three go: those two are behind you, and
keeping them would leave the beam pointing back the way you came. Mac's rule.

`arrival_radius` is 16 m and generous on purpose — a stop is a place you meant
to go, not a target to touch, and in a rover at speed a tight radius is one you
drive straight through.

**`Route` watches for arrival itself**, not the marker node. A scene without
the markers should still tick stops off, and tying "have I arrived" to "can I
see where I am going" is a bug waiting for the first scene that omits one.

## On a controller

**Built 2026-09-02**, after the honest answer to "is this pad-friendly?" turned
out to be no: you could orbit and pan and nothing else — no placing a stop, no
zoom, no buttons, no list selection.

| | |
|---|---|
| Left stick | Move the pointer |
| `A` | Click |
| Right stick | Orbit |
| D-pad | Pan |
| Triggers | Zoom |
| `B` | Close |

`PadCursor` **moves the real pointer and synthesises real mouse events** rather
than drawing a cursor of its own. Every panel is already built out of Controls
that respond to a mouse, so warping the actual pointer means all of that keeps
working untouched and there is no second input path to keep in step. A panel
added later gets pad support for nothing.

It is live only while `Astronaut.is_menu_open()`, so it cannot interfere with
driving or walking. It reads the pad's axes directly rather than the
`move_*` actions, because those carry WASD too and a panel where `W` nudges the
pointer would be a strange thing to have built.

**The mouse takes the pointer back when it moves, not every frame.** Re-reading
the OS position each idle frame looks equivalent and hands authority to
whatever the platform last reported — which is a stale value the moment the
stick is driving.

The panel's controls take **no keyboard focus**. Everything is pointer-driven,
so focus navigation has nothing to add and leaving it on costs two real
conflicts: `ui_left`/`ui_right` would move focus instead of panning, and `A`
would press whichever button was focused *as well as* clicking where the
pointer was.

## Where the code is

| | |
|---|---|
| The panel, camera, markers, route line | `res://scripts/ui/map_panel.gd` |
| The relief mesh and the click picker | `res://scripts/ui/map_terrain.gd` |
| How it is drawn | `res://shaders/map_terrain.gdshader` |
| The route itself | `res://scripts/world/route_plan.gd`, autoloaded as `Route` |
| The pillar and the scan reveal | `res://scripts/world/route_marks.gd` |
| The beam | `res://shaders/route_beacon.gdshader` |
| The pad pointer | `res://scripts/ui/pad_cursor.gd` |

## The route

Autoloaded as **`Route`**, because a route outlives the screen you drew it on
and the HUD has to keep pointing at the next leg long after the map is closed.

**Waypoints are stored as X/Z and their height is solved**, never stored — the
same rule [[Placement]] holds for everything else standing on this terrain. A
stored Y is a lie the moment the terrain is re-baked.

**Leg lengths are ground distances, not straight lines.** A leg over a ridge is
longer than the map's flat picture of it, and that difference is the reason the
route is worth planning rather than eyeballing. Measured at 816 m flat against
837 m over the ground for one climb up the massif.

Clicks are turned into ground positions by **marching the heightfield**, not by
raycasting a collision shape: the map has no physics world of its own, and
giving it one would mean a 33k-triangle trimesh existing only to be clicked on.

## Verification

`res://tests/test_map_route.tscn` covers the parts that fail silently: that a
waypoint's height is solved rather than stored, that a leg is measured over the
ground and not across it, that a click lands where it was aimed and a ray at the
sky fails instead of inventing a hit, that reordering actually reorders, and
that opening the map takes the rover's controls.

`res://tests/map_capture.tscn` is the other half and must run **windowed**. The
map is a SubViewport with its own World3D and its own shader, and `--headless`
builds none of it: every assertion above can pass with the panel rendering a
blank rectangle. It is also what caught the winding bug below.

`res://tests/test_route_marks.tscn` covers the world half: that the beam
follows the *nearest* stop rather than the next one drawn, that there is one of
it, that reaching a stop clears everything behind it, that arrival works **while
driving** — the astronaut's node stops moving the moment you board — and that
the route line costs a pulse rather than being painted on.

`res://tests/route_marks_capture.tscn` is its windowed pair, and shoots the
same framing before and after a pulse: a reveal that faded and a reveal that
never drew look identical in one picture.

## Open

- [ ] **Markers pile up when zoomed out.** Five labels at the settlements
      overlap into noise. Needs declutter — fade by distance, or collapse a
      cluster into one marker. #next
- [ ] No slope shading, so the map answers "how far" and not "can the rover get
      up that", which is the question a traversal game's map should answer.
      Needs a slope threshold nobody has driven yet. #playtest
- [ ] The route is not saved. Closing the game loses the trip.
- [x] The route is drawn in the world — a light pillar on the next stop, and
      the whole line on a scan pulse. Done 2026-09-02.
- [ ] TODO: should a stop snap to a facility or a mast when you click near one?
      Free-floating waypoints beside a dock read as a near miss. #question
