extends Node
class_name LensDust
## Regolith on a camera's lens: what the rover's wheels throw at its chase
## camera, building up while you drive and fading once you stop.
##
## A child of the camera it dirties. It only keeps `coverage`, 0 to 1; the
## specks themselves are drawn by the post pass (`film.gdshader`), which the
## `Lens` script on the post layer tells how dusty the camera on screen is. See
## docs/02-Systems/Lens.md.
##
## **This is the game's version, not a simulation of which grains reach the
## glass.** A real rooster tail at the governed 4 m/s tops out about 2.5 m up
## and the chase camera rides above that, so honest ballistics would never dust
## it. What is kept from the physics is the direction. The spray goes behind the
## travel, so a camera looking on from behind gets it, one looking from the
## side or the front does not, and reversing throws it the other way.
## `WheelDust.exposure_at()` works that out wheel by wheel, so it holds for
## whatever rover it is on.
##
## **Only the lens on screen changes.** It builds and fades only while you are
## looking through it, so a spell in the cab finds the dust where you left it.
## Climbing out wipes it - `Rover.exit()` calls `clear()`.

@export_group("Spray")
## The spray that dirties this lens. Empty means the WheelDust on the vehicle
## this camera rides on - the nearest VehicleBody3D above it - so a rebuilt
## camera rig needs no path.
@export var wheel_dust_path: NodePath
## Coverage gained a second with every wheel throwing at its full rate straight
## at the lens. A skidding wheel throws more and dusts it faster. The chase
## camera, 9 m behind the rover at its governed 4 m/s, measures an exposure of
## about 0.5 - so at 0.04 a clean lens is fully dusted in about 50 s.
@export_range(0.0, 1.0, 0.001) var build_rate := 0.04
## Metres. How far toward the lens the spray carries: a wheel this far off
## counts half, and less with the square of the distance beyond.
@export_range(0.5, 60.0, 0.5) var reach := 10.0
## How squarely the lens has to sit behind a wheel's throw. 1 is a broad cone;
## higher narrows it toward dead behind.
@export_range(0.1, 8.0, 0.1) var aim_sharpness := 2.0

@export_group("Clearing")
## Coverage lost a second once nothing is reaching the lens. 0.033 clears a
## fully dusted lens in half a minute; 0 keeps it until you climb out.
@export_range(0.0, 1.0, 0.001) var fade_rate := 0.033
## Seconds with nothing reaching the lens before it starts to fade, so a
## moment's lift off the throttle does not start wiping it.
@export_range(0.0, 30.0, 0.1) var fade_delay := 2.0
## Climbing out of the rover wipes the lens.
@export var clear_on_exit := true

## 0 is clean glass; 1 is every speck in the dust texture landed.
var coverage := 0.0
var _quiet := 0.0
var _source: WheelDust


func _ready() -> void:
	# Without one the lens only changes when something sets `coverage`, which
	# is a lens too; test_lens_dust checks the rover's finds its wheels.
	_source = _find_source()


func _physics_process(delta: float) -> void:
	var camera := get_parent() as Camera3D
	if camera == null or not camera.current:
		return
	var exposure := 0.0
	if _source != null:
		exposure = _source.exposure_at(camera.global_position, reach, aim_sharpness)
	step(exposure, delta)


## The spray this lens is watching, or null.
func source() -> WheelDust:
	return _source


## Advance the lens `delta` seconds under `exposure`, the share of a full spray
## reaching it. Separate from the physics tick so the rules can be tested
## without a rover.
func step(exposure: float, delta: float) -> void:
	if exposure > 0.0:
		coverage = minf(coverage + exposure * build_rate * delta, 1.0)
		_quiet = 0.0
		return
	_quiet += delta
	if _quiet >= fade_delay:
		coverage = maxf(coverage - fade_rate * delta, 0.0)


## Clean glass.
func clear() -> void:
	coverage = 0.0
	_quiet = 0.0


func _find_source() -> WheelDust:
	if not wheel_dust_path.is_empty():
		return get_node_or_null(wheel_dust_path) as WheelDust
	var n := get_parent()
	while n != null:
		if n is VehicleBody3D:
			for child in n.get_children():
				var dust := child as WheelDust
				if dust != null:
					return dust
			return null
		n = n.get_parent()
	return null


## How dusty `camera`'s lens is: its LensDust's coverage, or 0 without one.
static func coverage_on(camera: Camera3D) -> float:
	for child in camera.get_children():
		var lens := child as LensDust
		if lens != null:
			return lens.coverage
	return 0.0
