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

## The route changed — a leg added, removed, reordered, arrived at, or the whole
## thing cleared. The map panel, the HUD and the world markers all redraw on it.
signal changed

## A stop was reached. `index` is where it sat in the route, `cleared` is how
## many stops went with it — one when you arrive in order, more when you skipped
## some to get there.
signal arrived(index: int, cleared: int)

@export_group("Arrival")
## Metres from a stop that counts as reaching it.
##
## Generous on purpose. A stop is a place you meant to go, not a target you have
## to touch, and in a rover at speed a tight radius is one you drive through
## without tripping. Sized against the [[Rover]] rather than the astronaut for
## that reason.
@export_range(2.0, 60.0, 0.5) var arrival_radius := 16.0

## Whether arriving clears stops. Off makes the route a fixed plan you tick off
## by hand; the panel has no such button yet, so this is really a test and F1
## switch.
@export var clear_on_arrival := true

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


# --- Arriving -------------------------------------------------------------

## The remaining stop nearest to `from`, or -1 with no route.
##
## Nearest rather than next-in-order, because that is what the world marker
## points at: a stop behind you is not the one you are heading for, whatever
## order it was drawn in.
func nearest_index(from: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in _points.size():
		var d := from.distance_squared_to(_points[i])
		if d < best_distance:
			best_distance = d
			best = i
	return best


## Straight-line metres from `from` to the nearest remaining stop, or -1.
##
## Straight line, not over the ground: this is "am I there yet", and a ground
## distance would say no while you stood on top of it.
func nearest_distance(from: Vector2) -> float:
	var i := nearest_index(from)
	return -1.0 if i < 0 else from.distance_to(_points[i])


## Check whether `from` has reached a stop, and clear it if so.
##
## **Reaching a stop clears everything up to and including it.** Arriving at the
## third stop having skipped the first two means the first two are behind you —
## keeping them would leave the marker pointing back the way you came, which is
## worse than being wrong about your intent. Mac's rule, 2026-09-02.
##
## Returns the index reached, or -1.
func check_arrival(from: Vector2) -> int:
	if not clear_on_arrival or _points.is_empty():
		return -1
	var reached := -1
	for i in _points.size():
		if from.distance_to(_points[i]) <= arrival_radius:
			reached = i
			break
	if reached < 0:
		return -1
	var cleared := reached + 1
	for i in cleared:
		_points.remove_at(0)
	changed.emit()
	arrived.emit(reached, cleared)
	return reached


## Watched here rather than by whatever happens to be drawing the route.
##
## The marker node is scenery — a scene without it should still tick stops off —
## and putting the check anywhere that draws would mean arriving depended on
## being able to see where you were going.
func _process(_delta: float) -> void:
	if _points.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Astronaut
	if player == null:
		return
	var at := player.vantage()
	check_arrival(Vector2(at.x, at.z))
