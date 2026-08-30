extends Node
## Planetary constants for Vesper c.
##
## Autoloaded as `World`. Everything that needs to know what planet we are on
## reads it from here, so that retuning the world is a one-file change.

# --- Gravity ------------------------------------------------------------

const EARTH_GRAVITY := 9.80665
## Surface gravity, m/s^2. Mirrored in project.godot -> physics/3d/default_gravity.
const SURFACE_GRAVITY := 3.34
const GRAVITY_RATIO := SURFACE_GRAVITY / EARTH_GRAVITY  # ~0.34 g

# --- Atmosphere ---------------------------------------------------------

## Surface pressure in pascals. Thin: enough for wind, dust and muffled sound,
## nowhere near enough to breathe.
const ATMOSPHERIC_PRESSURE := 18000.0
## kg/m^3 — used for drag on the rover and on dust particles.
const ATMOSPHERIC_DENSITY := 0.31

# --- Body ---------------------------------------------------------------

const PLANET_RADIUS := 3_300_000.0  # metres
## Distance to the visible horizon for an eye height of 1.7 m, in metres.
## sqrt(2 * R * h) — noticeably closer than Earth's, which is why high ground matters.
const HORIZON_DISTANCE := 3350.0

# --- The star -----------------------------------------------------------

## Vesper sits permanently just above the horizon on the twilight band and never
## moves. Elevation in degrees; azimuth defines "starward" for the whole map.
## A true 4 deg elevation is the design intent, but a grazing directional light
## makes shadow maps fall apart. 5.5 still reads as "sitting on the horizon"
## while keeping shadows usable. Revisit if we move to baked lighting.
const STAR_ELEVATION_DEG := 5.5
const STAR_AZIMUTH_DEG := 0.0
## Dim, red, and large in the sky.
const STAR_COLOR := Color(1.0, 0.42, 0.22)
const STAR_ENERGY := 0.85

## Unit vector pointing *from* the star *toward* the surface — i.e. the direction
## a DirectionalLight3D should face.
static func star_direction() -> Vector3:
	var elev := deg_to_rad(STAR_ELEVATION_DEG)
	var azim := deg_to_rad(STAR_AZIMUTH_DEG)
	return Vector3(
		-cos(elev) * sin(azim),
		-sin(elev),
		-cos(elev) * cos(azim)
	).normalized()

# --- Thermal ------------------------------------------------------------

const TEMP_SUBSTELLAR := 90.0    # deg C, directly under the star
const TEMP_TERMINATOR := -55.0   # deg C, the Verge
const TEMP_ANTISTELLAR := -140.0 # deg C, the dark side
