extends Node
## Constants for the Moon, at the south polar rims.
##
## Autoloaded as `World`. Everything that needs to know what body we are on
## reads it from here, so that retuning the world is a one-file change. Moved
## from the fictional Vesper c on 2026-09-13; see [[The-Planet]].
##
## **These used to be `const`, and are now `@export var`.** The debug panel
## (F1) retunes the world while the game is running, and a `const` cannot be
## written to. The one-place rule is unchanged and arguably stronger: retuning
## went from a one-file change to a no-file change. What it costs is that these
## are no longer compile-time constants, so they are named in snake_case like
## the variables they now are — a SHOUTING name that can be reassigned
## underneath you is worse than the churn of renaming it.
##
## Anything derived from a tunable value is a **function**, not a stored copy,
## so nothing can go stale when the value moves.
##
## **There is no atmosphere here, and nothing pretends there is.** Vesper c's
## pressure, air density and thermal axis went with it: nothing had ever read
## them, and a vacuum has no values worth a slider.

## Emitted whenever any value is retuned. Things that cached a value derived
## from one — the sun's aim, a JoltMeter's gravity vector — listen for this and
## refresh.
signal changed

# --- Gravity ------------------------------------------------------------

## A real constant, not a setting.
const EARTH_GRAVITY := 9.80665

@export_group("Gravity")
## Surface gravity, m/s^2 - the Moon's 1.62, a sixth of Earth's. Mirrored into
## project.godot -> physics/3d/default_gravity for the authored value, and pushed
## to the physics server when changed at runtime — setting the project setting
## alone does nothing to a running space. Measured: tests/probe_runtime_gravity.tscn.
##
## **Changing this retunes every vehicle whether you meant it to or not.** Grip
## and suspension scale with weight: the rover was set for 5.39 and, at 1.62 with
## nothing else touched, stopped more than half as hard and lifted its inside
## wheels in every corner. `tests/probe_rover_spec.tscn` prints the sheet.
@export_range(0.1, 25.0, 0.01) var surface_gravity := 1.62:
	set(v):
		surface_gravity = maxf(v, 0.001)
		_push_gravity()
		changed.emit()


## ~0.165 g. A function rather than a stored ratio, so it cannot go stale.
func gravity_ratio() -> float:
	return surface_gravity / EARTH_GRAVITY

# --- Body ---------------------------------------------------------------

@export_group("Body")
## Metres. The Moon's mean radius.
##
## A tunable rather than a constant because the horizon is going to be built on
## it, and exaggerating curvature on a slider is the fastest way to see what a
## close horizon does to a map. From a standing eye it is 2.43 km away.
@export_range(100_000.0, 10_000_000.0, 1000.0) var body_radius := 1_737_400.0:
	set(v):
		body_radius = maxf(v, 1.0)
		changed.emit()


## Distance to the visible horizon for an eye `eye` metres above flat ground.
## sqrt(2 * R * h): 2.43 km at 1.7 m, 2.95 km at 2.5 m, 5.9 km from 10 m up -
## which is why high ground matters, and why a relay mast's height is range.
func horizon_distance(eye := 1.7) -> float:
	return sqrt(2.0 * body_radius * eye)


## How far the ground falls away below a flat plane at `distance` metres,
## d^2 / 2R: 1.7 m at the horizon, 22 m at the corner of a 3x3 world.
func curvature_drop(distance: float) -> float:
	return distance * distance / (2.0 * body_radius)

# --- The sun ------------------------------------------------------------

@export_group("The sun")
## Degrees above the horizon. At the south polar rims the sun never climbs far:
## between 85 and 88 degrees south it swings through about +/-6.5 to 3.5 degrees
## over a lunar day, circling the horizon rather than crossing the sky.
##
## 5.5 is inside that band, and it is also where the old red star sat - kept
## because a grazing directional light makes shadow maps fall apart below it,
## and because every look value was chosen under it.
@export_range(-10.0, 90.0, 0.1) var sun_elevation_deg := 5.5:
	set(v):
		sun_elevation_deg = v
		changed.emit()
## Degrees. Where the sun is on the horizon; it defines "sunward" for the map.
##
## Fixed for now. At the pole it really moves 0.51 degrees an hour, once round
## the horizon a month - whether it holds still within a session is Mac's call.
@export_range(-180.0, 180.0, 0.1) var sun_azimuth_deg := 0.0:
	set(v):
		sun_azimuth_deg = v
		changed.emit()
## White, not red: there is no atmosphere between the sun and the ground to
## redden it, even at five degrees.
@export var sun_color := Color(1.0, 0.97, 0.92):
	set(v):
		sun_color = v
		changed.emit()
## Raised from 0.46 on 2026-09-14 with the lunar reflectance model: regolith
## is dark - a real albedo near 0.12 - and a sun that has to make it read as
## bright ground under a black sky has to be strong. Everything else in the
## sun, a white suit or a crate, is brighter than it was by the same ratio and
## sits where a camera exposed for the ground would put it. The sweep is in
## `previews/2026-09-14/regolith-*`.
@export_range(0.0, 6.0, 0.01) var sun_energy := 0.8:
	set(v):
		sun_energy = v
		changed.emit()


## Unit vector pointing *from* the sun *toward* the surface — i.e. the direction
## a DirectionalLight3D should face.
##
## Not static: it reads tunable values, and a static function cannot.
func sun_direction() -> Vector3:
	var elev := deg_to_rad(sun_elevation_deg)
	var azim := deg_to_rad(sun_azimuth_deg)
	return Vector3(
		-cos(elev) * sin(azim),
		-sin(elev),
		-cos(elev) * cos(azim)
	).normalized()

# --- Runtime ------------------------------------------------------------


func _ready() -> void:
	# project.godot carries the authored gravity so bodies are low-g from the
	# first frame; push once on boot so this file stays the authority if the
	# two ever drift.
	_push_gravity()


## Setting `physics/3d/default_gravity` at runtime does **nothing** to a space
## that already exists — measured, not assumed. The running world's gravity
## lives on its space, and this is the call that moves it.
func _push_gravity() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var world := vp.find_world_3d()
	if world == null:
		return
	PhysicsServer3D.area_set_param(
		world.space, PhysicsServer3D.AREA_PARAM_GRAVITY, surface_gravity
	)


## The gravity vector, for anything that needs the direction as well as the
## magnitude — JoltMeter, mainly.
func gravity_vector() -> Vector3:
	return Vector3(0.0, -surface_gravity, 0.0)
