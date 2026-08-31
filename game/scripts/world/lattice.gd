extends Node
## The relay network. Autoloaded as `Lattice`.
##
## Sites — facilities and relays — link to each other when they are **within
## range and can see each other over the terrain**. The network is the graph
## that falls out of that, and coverage is simply which sites end up in the same
## connected component as the one you are standing at.
##
## Line of sight is the whole point. A radius check would make the network a
## question of *distance*, which the map cannot argue with; sampling the terrain
## between two masts makes it a question of *where the high ground is*, which is
## the thing surveying a route is supposed to be about. See
## docs/02-Systems/The-Lattice.md.
##
## **Solved at build time and cached**, not per query — that was the open
## question in the note. A link's existence changes only when a site moves or
## the terrain is rebuilt, and both of those are events we already have. Live
## solving would re-sample a few hundred points per pair per frame for an answer
## that had not changed since the last time anybody asked.
##
## Sites are duck-typed rather than sharing a base class: Facility and Relay
## both extend Node3D and GDScript has single inheritance. A site is anything
## with `lattice_id()`, `link_range()` and `mast_point()`.

## The graph was rebuilt. Anything showing coverage should redraw.
signal coverage_changed

@export_group("Linking")
## Metres between two masts before the link drops, regardless of terrain. The
## smaller of the two sites' ranges wins, so a short-range facility cannot be
## reached from further away just because the relay is a good one.
@export_range(10.0, 2000.0, 1.0) var default_range := 45.0

@export_group("Line of sight")
## Metres between terrain samples along a prospective link. Smaller catches
## narrower ridges and costs more; this only runs on a rebuild, so it can afford
## to be fine.
@export_range(0.5, 20.0, 0.5) var los_step := 2.0

## How far under the line the ground has to stay. A link that grazes a ridge
## exactly is not a link you would trust, and a little clearance also absorbs
## the bilinear height lookup disagreeing with the mesh by a few centimetres.
@export_range(0.0, 10.0, 0.1) var los_clearance := 1.0

## id -> site node.
var _sites: Dictionary = {}
## id -> Array[String] of ids it links to directly.
var _links: Dictionary = {}
var _rebuild_queued := false


func _ready() -> void:
	# Sites register during their own _ready, which happens before the terrain
	# has necessarily built. The first rebuild is deferred either way.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	var terrain := node as ProceduralTerrain
	if terrain != null and not terrain.rebuilt.is_connected(_queue_rebuild):
		terrain.rebuilt.connect(_queue_rebuild)
		_queue_rebuild()


# --- Sites --------------------------------------------------------------

## Register anything with `lattice_id()`, `link_range()` and `mast_point()`.
func register_site(node: Node) -> void:
	var id := String(node.call("lattice_id"))
	if id == "":
		printerr("LATTICE: a site registered with no id")
		return
	if _sites.has(id) and _sites[id] != node:
		printerr("LATTICE: two sites both call themselves '%s'" % id)
	_sites[id] = node
	_queue_rebuild()


func unregister_site(node: Node) -> void:
	var id := String(node.call("lattice_id"))
	if _sites.get(id, null) == node:
		_sites.erase(id)
		_queue_rebuild()


func site(id: String) -> Node:
	return _sites.get(id, null)


func site_ids() -> Array:
	return _sites.keys()


# --- The graph ----------------------------------------------------------

## Rebuilds are deferred and coalesced: registering six sites in one frame is
## one solve, not six.
func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	_links.clear()
	var ids := _sites.keys()
	for id in ids:
		_links[id] = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := String(ids[i])
			var b := String(ids[j])
			if not _can_link(a, b):
				continue
			_links[a].append(b)
			_links[b].append(a)
	coverage_changed.emit()


func _can_link(a: String, b: String) -> bool:
	var node_a: Node = _sites[a]
	var node_b: Node = _sites[b]
	if node_a == null or node_b == null:
		return false
	var from: Vector3 = node_a.call("mast_point")
	var to: Vector3 = node_b.call("mast_point")
	var reach: float = minf(node_a.call("link_range"), node_b.call("link_range"))
	if from.distance_to(to) > reach:
		return false
	return has_line_of_sight(from, to)


## Whether the ground stays out of the way between two points.
##
## Endpoints are not sampled: a mast standing *on* the ground would fail its own
## test at t=0, and what matters is the span in between.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var terrain := _terrain()
	if terrain == null:
		return true
	var span := from.distance_to(to)
	var steps := maxi(int(ceil(span / maxf(los_step, 0.1))), 2)
	for i in range(1, steps):
		var point := from.lerp(to, float(i) / float(steps))
		if terrain.world_height_at(point.x, point.z) > point.y - los_clearance:
			return false
	return true


func _terrain() -> ProceduralTerrain:
	for node in get_tree().get_nodes_in_group("terrain"):
		var terrain := node as ProceduralTerrain
		if terrain != null:
			return terrain
	# Not in a group in every scene, so fall back to a walk of the tree.
	return _find_terrain(get_tree().root)


func _find_terrain(node: Node) -> ProceduralTerrain:
	var terrain := node as ProceduralTerrain
	if terrain != null:
		return terrain
	for child in node.get_children():
		var found := _find_terrain(child)
		if found != null:
			return found
	return null


# --- Coverage -----------------------------------------------------------

## Sites `id` links to directly.
func neighbours(id: String) -> Array:
	return _links.get(id, [])


## Every site reachable from `id` through any chain of links, excluding itself.
func reachable_from(id: String) -> Array:
	var seen := {id: true}
	var queue: Array = [id]
	var out: Array = []
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next in neighbours(current):
			var next_id := String(next)
			if seen.has(next_id):
				continue
			seen[next_id] = true
			out.append(next_id)
			queue.append(next_id)
	return out


func are_linked(a: String, b: String) -> bool:
	if a == b:
		return true
	return reachable_from(a).has(b)


## Facilities reachable from `id`, in id order. What a terminal can talk to.
func facilities_reachable_from(id: String) -> Array:
	var out: Array = []
	for other in reachable_from(id):
		var node := site(String(other))
		if node is Facility:
			out.append(String(other))
	out.sort()
	return out


## Straight-line distance between two sites, or -1 if either is unknown. Used to
## price a transfer in seconds; the network moves things over the ground it
## covers, so distance is the honest measure rather than hop count.
func distance_between(a: String, b: String) -> float:
	var node_a := site(a)
	var node_b := site(b)
	if node_a == null or node_b == null:
		return -1.0
	var from: Vector3 = node_a.call("mast_point")
	var to: Vector3 = node_b.call("mast_point")
	return from.distance_to(to)


## Diagnostics: how many links exist in total.
func link_count() -> int:
	var n := 0
	for id in _links:
		n += _links[id].size()
	return n / 2
