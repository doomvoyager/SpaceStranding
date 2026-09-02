extends Node
## Planetary constants for Vesper c.
##
## Autoloaded as `World`. Everything that needs to know what planet we are on
## reads it from here, so that retuning the world is a one-file change.
##
## **These used to be `const`, and are now `@export var`.** The debug panel
## (F1) retunes the planet while the game is running, and a `const` cannot be
## written to. The one-place rule is unchanged and arguably stronger: retuning
## the planet went from a one-file change to a no-file change. What it costs is
## that these are no longer compile-time constants, so they are named in
## snake_case like the variables they now are — a SHOUTING name that can be
## reassigned underneath you is worse than the churn of renaming it.
##
## Anything derived from a tunable value is a **function**, not a stored copy,
## so nothing can go stale when the value moves.

## Emitted whenever any planetary value is retuned. Things that cached a value
## derived from one — the star's aim, a JoltMeter's gravity vector — listen for
## this and refresh.
signal changed

# --- Gravity ------------------------------------------------------------

## A real constant, not a planet setting.
const EARTH_GRAVITY := 9.80665

@export_group("Gravity")
## Surface gravity, m/s^2. Mirrored into project.godot -> physics/3d/default_gravity
## for the authored value, and pushed to the physics server when changed at
## runtime — setting the project setting alone does nothing to a running space.
## Measured: tests/probe_runtime_gravity.tscn.
@export_range(0.1, 25.0, 0.01) var surface_gravity := 5.39:
	set(v):
		surface_gravity = maxf(v, 0.001)
		_push_gravity()
		changed.emit()


## ~0.55 g. A function rather than a stored ratio, so it cannot go stale.
func gravity_ratio() -> float:
	return surface_gravity / EARTH_GRAVITY

# --- Atmosphere ---------------------------------------------------------

@export_group("Atmosphere")
## Surface pressure in pascals. Thin: enough for wind, dust and muffled sound,
## nowhere near enough to breathe.
@export_range(0.0, 120000.0, 100.0) var atmospheric_pressure := 18000.0:
	set(v):
		atmospheric_pressure = v
		changed.emit()
## kg/m^3 — used for drag on the rover and on dust particles.
@export_range(0.0, 3.0, 0.01) var atmospheric_density := 0.31:
	set(v):
		atmospheric_density = v
		changed.emit()

# --- Body ---------------------------------------------------------------

## Metres. Not a feel value — it sets the horizon and nothing tunes it live.
const PLANET_RADIUS := 3_300_000.0


## Distance to the visible horizon for an eye height of `eye`, in metres.
## sqrt(2 * R * h) — noticeably closer than Earth's, which is why high ground
## matters.
func horizon_distance(eye := 1.7) -> float:
	return sqrt(2.0 * PLANET_RADIUS * eye)

# --- The star -----------------------------------------------------------

@export_group("The star")
## Vesper sits permanently just above the horizon on the twilight band and never
## moves. Elevation in degrees; azimuth defines "starward" for the whole map.
## A true 4 deg elevation is the design intent, but a grazing directional light
## makes shadow maps fall apart. 5.5 still reads as "sitting on the horizon"
## while keeping shadows usable. Revisit if we move to baked lighting.
@export_range(-10.0, 90.0, 0.1) var star_elevation_deg := 5.5:
	set(v):
		star_elevation_deg = v
		changed.emit()
@export_range(-180.0, 180.0, 0.1) var star_azimuth_deg := 0.0:
	set(v):
		star_azimuth_deg = v
		changed.emit()
## Dim, red, and large in the sky.
@export var star_color := Color(1.0, 0.42, 0.22):
	set(v):
		star_color = v
		changed.emit()
@export_range(0.0, 6.0, 0.01) var star_energy := 0.85:
	set(v):
		star_energy = v
		changed.emit()


## Unit vector pointing *from* the star *toward* the surface — i.e. the direction
## a DirectionalLight3D should face.
##
## No longer static: it reads tunable values, and a static function cannot.
func star_direction() -> Vector3:
	var elev := deg_to_rad(star_elevation_deg)
	var azim := deg_to_rad(star_azimuth_deg)
	return Vector3(
		-cos(elev) * sin(azim),
		-sin(elev),
		-cos(elev) * cos(azim)
	).normalized()

# --- Thermal ------------------------------------------------------------

@export_group("Thermal")
## deg C, directly under the star.
@export_range(-200.0, 200.0, 1.0) var temp_substellar := 90.0
## deg C, the Verge.
@export_range(-200.0, 200.0, 1.0) var temp_terminator := -55.0
## deg C, the dark side.
@export_range(-200.0, 200.0, 1.0) var temp_antistellar := -140.0

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
