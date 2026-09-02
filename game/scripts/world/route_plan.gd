extends Node
## The planned trip. Autoloaded as `Route`.
##
## A list of waypoints on the ground, in the order you mean to visit them. Owned
## globally rather than by the map panel for the same reason the ledger is: a
## route outlives the screen you drew it on, and the HUD has to keep pointing at
## the next leg long after the map is closed.
##
## **Waypoints are stored as X/Z and their height is solved**, never stored —
## the same rule [[Placement]] holds for everything else standing on this
## terrain. A stored Y is a lie the moment the terrain is re-baked, and this
## project has already paid for that once: three systems carried hand-tuned
## heights through the heightmap swap and put the Hearth 13.6 m underground.
##
## Distances are ground distances, not straight lines through the air, for the
## same reason: a route over a ridge is longer than the map's flat picture of
## it, and the number the panel shows is the one you have to drive.

## The route changed — a leg added, removed, reordered, or the whole thing
## cleared. The map panel and the HUD both redraw on this.
signal changed

## Metres between samples when measuring a leg over the ground. Fine enough that
## a ridge in the middle of a leg is paid for, coarse enough that a fifty-leg
## route is not a per-frame cost. Only ever walked when the route changes.
const SAMPLE_STEP := 8.0

## World X/Z of each waypoint, in visiting order.
var _points: PackedVector2Array = PackedVector2Array()


func count() -> int:
	return _points.size()


func is_empty() -> bool:
	return _points.is_empty()


## World X/Z of waypoint `i`.
func point_2d(i: int) -> Vector2:
	if i < 0 or i >= _points.size():
		return Vector2.ZERO
	return _points[i]


## Waypoint `i` standing on the ground, height solved now rather than recalled.
## Returns the flat point at y = 0 when there is no terrain to ask.
func point(i: int) -> Vector3:
	var flat := point_2d(i)
	return Vector3(flat.x, ground_height(flat.x, flat.y), flat.y)


## The solved ground height at a world X/Z, or 0 with no terrain.
func ground_height(world_x: float, world_z: float) -> float:
	var terrain := Lattice.terrain()
	if terrain == null or not terrain.is_built():
		return 0.0
	return terrain.world_height_at(world_x, world_z)


# --- Editing -------------------------------------------------------------

## Append a waypoint. Returns its index.
func add(world_x: float, world_z: float) -> int:
	_points.append(Vector2(world_x, world_z))
	changed.emit()
	return _points.size() - 1


## Put one in the middle of the route rather than on the end, which is what
## "I need to stop here on the way" means.
func insert(at: int, world_x: float, world_z: float) -> int:
	var index := clampi(at, 0, _points.size())
	_points.insert(index, Vector2(world_x, world_z))
	changed.emit()
	return index


func remove_at(i: int) -> void:
	if i < 0 or i >= _points.size():
		return
	_points.remove_at(i)
	changed.emit()


## Move a waypoint to a new position in the order. Returns where it ended up, so
## a list can keep the same row selected after the move.
func move(from: int, to: int) -> int:
	if from < 0 or from >= _points.size():
		return from
	var target := clampi(to, 0, _points.size() - 1)
	if target == from:
		return from
	var moved := _points[from]
	_points.remove_at(from)
	_points.insert(target, moved)
	changed.emit()
	return target


func clear() -> void:
	if _points.is_empty():
		return
	_points.clear()
	changed.emit()


# --- Measuring -----------------------------------------------------------

## Ground distance between two world X/Z points, following the terrain.
##
## Straight-line distance is what a map picture shows and is not what you drive.
## A leg that crosses a ridge is measurably longer than the line across it, and
## that difference is the entire reason the route is worth planning rather than
## eyeballing.
func ground_distance(from: Vector2, to: Vector2) -> float:
	var flat := from.distance_to(to)
	if flat < 0.001:
		return 0.0
	var steps := maxi(int(ceil(flat / SAMPLE_STEP)), 1)
	var total := 0.0
	var previous := Vector3(from.x, ground_height(from.x, from.y), from.y)
	for i in range(1, steps + 1):
		var at := from.lerp(to, float(i) / float(steps))
		var here := Vector3(at.x, ground_height(at.x, at.y), at.y)
		total += previous.distance_to(here)
		previous = here
	return total


## Length of the leg arriving at waypoint `i`, measured from `start` for the
## first one — which is wherever the player happens to be, so it changes as they
## drive and is passed in rather than remembered.
func leg_length(i: int, start: Vector2) -> float:
	if i < 0 or i >= _points.size():
		return 0.0
	var from := start if i == 0 else _points[i - 1]
	return ground_distance(from, _points[i])


## The whole trip from `start`, over the ground.
func total_distance(start: Vector2) -> float:
	var total := 0.0
	for i in _points.size():
		total += leg_length(i, start)
	return total
