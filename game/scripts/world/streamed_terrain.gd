@tool
extends TerrainSource
class_name StreamedTerrain
## The world's ground: one resident heightfield, and a quadtree of mesh tiles
## streamed around whoever is looking.
##
## **The seam is answered by the data, not by the tiles.** `world_height_at`,
## `extent()` and `sample_step()` read the [Heightfield] directly, so the
## Lattice, the map, placement and the scatter never learn that meshes come
## and go. `is_built()` means the heights have loaded. Tiles are a view.
##
## **Every tile is the same 65 x 65 grid**, at a spacing that doubles per
## level: 4 m over 256 m at the finest, 128 m over 8192 m at the root. A tile
## splits into its four children while the viewer is within `split_ratio`
## tile-widths of it, which gives the 4 / 16 / 64 m rings of the plan without
## hollowing coarse tiles around fine ones. Measured at the spawn on the real
## ground (a `--script` count of `select_tiles`, 2026-09-14): 65-sample tiles
## at a ratio of 1.5 are 212 tiles and 1.85 M triangles with 4 m ground out
## to 1.3 km; 129-sample tiles at the same ratio are 170 tiles and 5.7 M,
## because every ring is twice as wide in metres. The old single patch was
## 2 M, and that is the budget.
##
## Each vertex is an exact sample of the same function the seam answers, so
## placement and physics agree the way they did on the single patch, and a
## coarse tile's edge passes through the same points its finer neighbour's
## does. The gaps left between those points are hidden by **skirts**: a wall
## hung below every edge, exactly as deep as the ground dips under that edge
## - measured against the data along it while the tile is built - plus
## `skirt_margin`. The first version dropped every edge a whole spacing, and
## at a 5.5 degree sun a 64 m wall throws a 660 m shadow and lights up as a
## bright streak on every shadowed slope. Skirts are their own mesh under the
## tile, with shadow casting off.
##
## **Tiles are built on `WorkerThreadPool` and added to the tree here.** The
## probe (`tests/probe_tile_threads.tscn`) measured a tile at ~22 ms and eight
## at once at 48 ms wall - and found that `Mesh.create_trimesh_shape()`
## **deadlocks** on a worker, because it asks the RenderingServer for the
## arrays back and that call waits for a main thread which is waiting for it.
## `_shape_from_arrays` builds the trimesh from the arrays in hand instead,
## and nothing on a worker asks any server for anything. Collision exists only
## on tiles within `collision_radius`; the ones under the viewer are built
## synchronously at ready so nothing ever falls through.
##
## A tile that stops being wanted is hidden and kept in a small cache, so
## turning round does not rebuild what was just torn down. A tile is only
## removed once whatever replaces it - its children, or its parent - is
## resident, so the ground never shows a hole while the swap is in flight.
##
## The UV2 every tile writes spans the **whole tiled extent** 0..1, not the
## tile, so the coverage mask - built over `extent()` by `CoverageMap` and
## sampled through UV2 by the surface shader - keeps working unchanged.
##
## Generated nodes are never given an owner: this is a @tool script, and an
## owned child is serialised into the .tscn on every save.

@export_group("Source")
## The heightfield, as written by `tools/lola-window.py --raw`. The scene
## names it; a bare node has no ground until it is given one here or through
## `set_heightfield`.
@export_file("*.hf") var heightfield_path := "":
	set(v):
		heightfield_path = v
		_queue_reload()

@export_group("Tiles")
## Samples along one edge of every tile, at every level. 65 is 64 quads,
## which is the whole reason the level sizes are powers of two. Bigger tiles
## are fewer draw calls and wider rings: 129 at the same ratio is three times
## the triangles.
@export_range(17, 513, 16) var tile_samples := 65:
	set(v):
		tile_samples = v
		_queue_rebuild()
## Metres between samples on the finest tiles.
@export_range(0.5, 64.0, 0.5) var leaf_spacing := 4.0:
	set(v):
		leaf_spacing = v
		_queue_rebuild()
## Quadtree depth. Six levels of 65-sample tiles at 4 m is a root tile of
## 8192 m at 128 m spacing, and 3 x 3 of those is the 24.6 km world.
@export_range(1, 8) var levels := 6:
	set(v):
		levels = v
		_queue_rebuild()
## A tile splits while the viewer is within this many tile-widths of it.
## Higher is more triangles and finer ground further out.
@export_range(0.5, 4.0, 0.05) var split_ratio := 1.5:
	set(v):
		split_ratio = v
		_dirty = true
## Metres added to every skirt beyond the dip the data shows under the
## edge, so a crack a hair wider than measured is still covered.
@export_range(0.0, 8.0, 0.05) var skirt_margin := 0.5:
	set(v):
		skirt_margin = v
		_queue_rebuild()

@export_group("Streaming")
## Tiles within this distance of the viewer carry a trimesh. Normally that
## is the finest ring, which reaches 1.3 km at the default ratio; a coarser
## tile inside the radius gets one too rather than leaving a gap in the
## ground, which a low ratio would otherwise open.
@export_range(0.0, 5000.0, 50.0) var collision_radius := 1000.0:
	set(v):
		collision_radius = v
		_dirty = true
## Finished tiles added to the tree per frame. Adding is cheap; the number
## bounds how many first-frame draws land at once.
@export_range(1, 16) var builds_per_frame := 2
## Tiles kept hidden after they stop being wanted, so a return costs nothing.
@export_range(0, 512) var cache_tiles := 64:
	set(v):
		cache_tiles = v
		_trim_cache()
## The viewer has to move this far before the tile set is reconsidered.
@export_range(1.0, 200.0, 1.0) var update_distance := 16.0
## Whose position the tiles follow. Empty means the current camera, or the
## editor's camera in the editor, or the world origin if there is neither.
@export var viewer_path: NodePath:
	set(v):
		viewer_path = v
		_dirty = true

@export_group("Look")
@export var surface_material: Material = preload("res://materials/regolith.tres"):
	set(v):
		surface_material = v
		for record: Dictionary in _resident.values():
			_apply_material(record.node)
		for record: Dictionary in _cache.values():
			_apply_material(record.node)

@export_group("Actions")
## Inspector button: reloads the heightfield and rebuilds every tile.
@export var rebuild := false:
	set(_v):
		rebuild = false
		_reload()

var _field: Heightfield
var _tiles_root: Node3D
## key -> {node, body, shape, tris, level, used}
var _resident: Dictionary = {}
var _cache: Dictionary = {}
## key -> WorkerThreadPool task id
var _pending: Dictionary = {}
## key -> build result, filled from workers under `_lock`
var _results: Dictionary = {}
var _lock := Mutex.new()
var _desired: Dictionary = {}
var _desired_list: Array[Vector3i] = []
var _last_viewer := Vector2(INF, INF)
var _dirty := true
var _reload_queued := false
var _rebuild_queued := false
var _tick := 0


func _ready() -> void:
	add_to_group("terrain")
	_reload()


## Workers hold a bound method on this node, and a Callable does not keep a
## Node alive. A task still running when the node is freed - which is every
## exit while something is streaming in - writes into a dead object and takes
## the process down at quit. So nothing leaves the tree with a build in
## flight; see `_finish_pending`.
func _exit_tree() -> void:
	_finish_pending()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_finish_pending()


## Blocks until every queued build has run. Safe to block on: nothing in a
## build asks a server for anything back, which is the deadlock the probe
## found and `_shape_from_arrays` exists to avoid.
func _finish_pending() -> void:
	for id in _pending.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()
	if _lock != null:
		_lock.lock()
		_results.clear()
		_lock.unlock()


func _process(_delta: float) -> void:
	if _field == null:
		return
	_tick += 1
	var viewer := _viewer_local_xz()
	if _dirty or viewer.distance_to(_last_viewer) >= update_distance:
		_last_viewer = viewer
		_dirty = false
		_reselect(viewer)
	_collect_finished()
	_retire_unwanted()
	_update_collision(viewer)


# --- Loading ------------------------------------------------------------

func _queue_reload() -> void:
	if not is_inside_tree() or _reload_queued:
		return
	_reload_queued = true
	_do_queued_reload.call_deferred()


func _do_queued_reload() -> void:
	_reload_queued = false
	_reload()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_queued_rebuild.call_deferred()


func _do_queued_rebuild() -> void:
	_rebuild_queued = false
	_rebuild_tiles()


## Loads (or reloads) the heightfield, then rebuilds the tiles on it.
func _reload() -> void:
	if not is_inside_tree():
		return
	_clear_tiles()
	_field = null
	if heightfield_path == "":
		return
	_field = Heightfield.load_file(heightfield_path)
	if _field == null:
		push_warning("StreamedTerrain: no heightfield at '%s'; the ground is empty."
			% heightfield_path)
		return
	_rebuild_tiles()
	rebuilt.emit()


## Give the terrain a field directly - tests and probes, which want relief
## with no asset behind it. Takes the place of `heightfield_path`.
func set_heightfield(field: Heightfield) -> void:
	_clear_tiles()
	_field = field
	if is_inside_tree():
		_rebuild_tiles()
		rebuilt.emit()


## Drops every tile and builds the ones under the viewer synchronously, so
## the ground is solid before the next physics tick.
func _rebuild_tiles() -> void:
	if not is_inside_tree():
		return
	_clear_tiles()
	if _field == null:
		return
	if _tiles_root == null:
		_tiles_root = Node3D.new()
		_tiles_root.name = "Tiles"
		add_child(_tiles_root)
	var viewer := _viewer_local_xz()
	_last_viewer = viewer
	_dirty = false
	# The finest tiles within collision range are built here and now, on the
	# main thread: the rover is placed on `world_height_at` during the same
	# ready pass and falls through anything that is not there by the first
	# physics frame. Everything else streams in behind.
	_desired_list = select_tiles(viewer)
	_desired.clear()
	for key in _desired_list:
		_desired[key] = true
	for key in _desired_list:
		if _distance_to(viewer, tile_rect(key)) < collision_radius:
			_place(key, _build(key, _params(key, true)))
	_reselect(viewer)


func _clear_tiles() -> void:
	# Workers hold the field; wait for them before anything replaces it.
	_finish_pending()
	for record: Dictionary in _resident.values():
		(record.node as Node).queue_free()
	for record: Dictionary in _cache.values():
		(record.node as Node).queue_free()
	_resident.clear()
	_cache.clear()
	_desired.clear()
	_desired_list.clear()
	_last_viewer = Vector2(INF, INF)
	_dirty = true


# --- The seam -----------------------------------------------------------

func is_built() -> bool:
	return _field != null and _field.is_loaded()


func world_height_at(world_x: float, world_z: float) -> float:
	if _field == null:
		return 0.0
	var local := to_local(Vector3(world_x, 0.0, world_z))
	return to_global(Vector3(local.x, _field.height_at(local.x, local.z), local.z)).y


## The tiled footprint in world X/Z: the root grid, clipped to the data. The
## roots cover 24,576 m of a 24,580 m window, so this is the smaller of the
## two rather than either alone.
func extent() -> Rect2:
	if _field == null:
		return Rect2()
	var local := _tiled_rect()
	var lo := to_global(Vector3(local.position.x, 0.0, local.position.y))
	var hi := to_global(Vector3(local.end.x, 0.0, local.end.y))
	return Rect2(minf(lo.x, hi.x), minf(lo.z, hi.z), absf(hi.x - lo.x), absf(hi.z - lo.z))


## World metres between height samples - the data's, through the node scale.
func sample_step() -> float:
	if _field == null:
		return leaf_spacing
	return (to_global(Vector3(_field.spacing, 0.0, 0.0)) - to_global(Vector3.ZERO)).length()


# --- Layout -------------------------------------------------------------

func spacing_at(level: int) -> float:
	return leaf_spacing * float(1 << level)


func tile_size_at(level: int) -> float:
	return spacing_at(level) * float(tile_samples - 1)


## How many root tiles across each axis cover the data.
func roots_across() -> Vector2i:
	if _field == null:
		return Vector2i.ZERO
	var root := tile_size_at(levels - 1)
	return Vector2i(int(ceil(_field.span_x() / root)), int(ceil(_field.span_z() / root)))


## Where the root grid starts, in local metres: the data's minimum corner.
func _grid_origin() -> Vector2:
	return _field.rect().position


func _tiled_rect() -> Rect2:
	var roots := roots_across()
	var root := tile_size_at(levels - 1)
	var grid := Rect2(_grid_origin(), Vector2(roots.x * root, roots.y * root))
	return grid.intersection(_field.rect())


## A tile's footprint in local metres. `key` is (level, ix, iz).
func tile_rect(key: Vector3i) -> Rect2:
	var size := tile_size_at(key.x)
	return Rect2(_grid_origin() + Vector2(key.y, key.z) * size, Vector2(size, size))


## The tiles a viewer at `viewer` (local X/Z) should see: the quadtree split
## toward the viewer until the finest level, or until a tile is further away
## than `split_ratio` of its own width.
func select_tiles(viewer: Vector2) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if _field == null:
		return out
	var roots := roots_across()
	var data := _field.rect()
	for iz in roots.y:
		for ix in roots.x:
			_select_into(Vector3i(levels - 1, ix, iz), viewer, data, out)
	return out


func _select_into(key: Vector3i, viewer: Vector2, data: Rect2, out: Array[Vector3i]) -> void:
	var rect := tile_rect(key)
	# A tile with no data under any of it is not ground; one that overhangs
	# the edge samples clamped heights past it, which is the same rule the
	# single patch had at its border.
	if not rect.intersects(data):
		return
	if key.x > 0 and _distance_to(viewer, rect) < rect.size.x * split_ratio:
		for cz in 2:
			for cx in 2:
				_select_into(Vector3i(key.x - 1, key.y * 2 + cx, key.z * 2 + cz),
					viewer, data, out)
		return
	out.append(key)


static func _distance_to(point: Vector2, rect: Rect2) -> float:
	var nearest := point.clamp(rect.position, rect.end)
	return point.distance_to(nearest)


# --- Streaming ----------------------------------------------------------

func _viewer_local_xz() -> Vector2:
	var at := to_local(_viewer_global())
	return Vector2(at.x, at.z)


func _viewer_global() -> Vector3:
	if viewer_path != NodePath(""):
		var node := get_node_or_null(viewer_path) as Node3D
		if node != null:
			return node.global_position
	if Engine.is_editor_hint():
		# Named dynamically: `EditorInterface` does not exist in an exported
		# build and naming it would fail the parse there.
		var editor := Engine.get_singleton("EditorInterface")
		if editor != null:
			var viewport: Object = editor.call("get_editor_viewport_3d", 0)
			if viewport != null:
				var camera := viewport.call("get_camera_3d") as Camera3D
				if camera != null:
					return camera.global_position
		return Vector3.ZERO
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null:
			return camera.global_position
	return Vector3.ZERO


func _reselect(viewer: Vector2) -> void:
	_desired_list = select_tiles(viewer)
	_desired.clear()
	for key in _desired_list:
		_desired[key] = true
	# Nearest first, so the ground under the viewer arrives before the
	# horizon does.
	var missing: Array[Vector3i] = []
	for key in _desired_list:
		if _resident.has(key) or _pending.has(key):
			continue
		if _cache.has(key):
			_restore(key)
			continue
		missing.append(key)
	missing.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _distance_to(viewer, tile_rect(a)) < _distance_to(viewer, tile_rect(b)))
	for key in missing:
		var wants_shape := _distance_to(viewer, tile_rect(key)) < collision_radius
		_pending[key] = WorkerThreadPool.add_task(
			_build_task.bind(key, _params(key, wants_shape)), true)


func _collect_finished() -> void:
	if _pending.is_empty():
		return
	var placed := 0
	for key: Vector3i in _pending.keys():
		if placed >= builds_per_frame:
			return
		var id: int = _pending[key]
		if not WorkerThreadPool.is_task_completed(id):
			continue
		WorkerThreadPool.wait_for_task_completion(id)
		_pending.erase(key)
		_lock.lock()
		var result: Dictionary = _results.get(key, {})
		_results.erase(key)
		_lock.unlock()
		if result.is_empty():
			continue
		_place(key, result)
		placed += 1


## A tile that is resident but no longer wanted goes only once everything
## that covers its ground is there - otherwise the swap shows a hole.
func _retire_unwanted() -> void:
	for key: Vector3i in _resident.keys():
		if _desired.has(key):
			continue
		var rect := tile_rect(key)
		var covered := true
		for want in _desired_list:
			if not _resident.has(want) and tile_rect(want).intersects(rect):
				covered = false
				break
		if covered:
			_stash(key)


func _update_collision(viewer: Vector2) -> void:
	var built_shape := false
	for key: Vector3i in _resident.keys():
		var record: Dictionary = _resident[key]
		var wanted := _distance_to(viewer, tile_rect(key)) < collision_radius
		var has_body: bool = record.body != null
		if wanted and not has_body:
			if record.shape == null:
				# Missed on the worker because the tile was out of range when
				# it was built. ~4 ms on the main thread; one a frame.
				if built_shape:
					continue
				record.shape = _shape_from_arrays(record.arrays)
				built_shape = true
			_attach_body(key, record)
		elif has_body and not wanted:
			(record.body as Node).queue_free()
			record.body = null


# --- Tile lifecycle -----------------------------------------------------

func _place(key: Vector3i, result: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "L%d_%d_%d" % [key.x, key.y, key.z]
	mi.mesh = result.mesh
	if result.skirt != null:
		var skirt := MeshInstance3D.new()
		skirt.name = "Skirt"
		skirt.mesh = result.skirt
		# A wall under the ground must not throw a shadow across it.
		skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(skirt)
	_apply_material(mi)
	_tiles_root.add_child(mi)
	var record := {
		"node": mi,
		"body": null,
		"shape": result.shape,
		"arrays": result.arrays,
		"tris": result.tris,
		"level": key.x,
		"used": _tick,
	}
	_resident[key] = record
	if not _desired.has(key):
		# Wanted when it was queued, not any more. Straight into the cache.
		_stash(key)
		return
	# A shape built with the tile means it was in collision range when it
	# was queued; the body goes on now rather than a frame later, so the
	# synchronous build at ready is solid before the first physics tick.
	if result.shape != null:
		_attach_body(key, record)


func _apply_material(tile: Node) -> void:
	var material := _resolve_material()
	(tile as MeshInstance3D).material_override = material
	var skirt := tile.get_node_or_null("Skirt") as MeshInstance3D
	if skirt != null:
		skirt.material_override = material


func _attach_body(key: Vector3i, record: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.shape = record.shape
	body.add_child(shape)
	(record.node as Node).add_child(body)
	record.body = body
	_resident[key] = record


func _stash(key: Vector3i) -> void:
	var record: Dictionary = _resident[key]
	_resident.erase(key)
	if record.body != null:
		(record.body as Node).queue_free()
		record.body = null
	(record.node as Node3D).visible = false
	record.used = _tick
	_cache[key] = record
	_trim_cache()


func _restore(key: Vector3i) -> void:
	var record: Dictionary = _cache[key]
	_cache.erase(key)
	(record.node as Node3D).visible = true
	record.used = _tick
	_resident[key] = record


func _trim_cache() -> void:
	while _cache.size() > cache_tiles:
		var oldest: Vector3i
		var oldest_tick := _tick + 1
		for key: Vector3i in _cache.keys():
			var used: int = _cache[key].used
			if used < oldest_tick:
				oldest_tick = used
				oldest = key
		(_cache[oldest].node as Node).queue_free()
		_cache.erase(oldest)


# --- Building -----------------------------------------------------------

## Everything a build needs, captured on the main thread so a worker never
## reads an export that a slider is moving.
func _params(key: Vector3i, with_shape: bool) -> Dictionary:
	return {
		"field": _field,
		"rect": tile_rect(key),
		"spacing": spacing_at(key.x),
		"samples": tile_samples,
		"skirt_margin": skirt_margin,
		"uv2_rect": _tiled_rect(),
		"shape": with_shape,
	}


func _build_task(key: Vector3i, params: Dictionary) -> void:
	var result := _build(key, params)
	_lock.lock()
	_results[key] = result
	_lock.unlock()


## One tile: heights from the field, arrays, mesh, and the trimesh if asked.
## Runs on a worker or on the main thread alike; asks no server for anything.
static func _build(_key: Vector3i, p: Dictionary) -> Dictionary:
	var field: Heightfield = p.field
	var rect: Rect2 = p.rect
	var s: float = p.spacing
	var n: int = p.samples
	var margin: float = p.skirt_margin
	var uv2_rect: Rect2 = p.uv2_rect

	# One sample of margin all round, so the edge normals are central
	# differences too and shade continuously into the neighbour.
	var m := n + 2
	var heights := PackedFloat32Array()
	heights.resize(m * m)
	for z in m:
		var lz := rect.position.y + float(z - 1) * s
		for x in m:
			heights[z * m + x] = field.height_at(rect.position.x + float(x - 1) * s, lz)

	var count := n * n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	verts.resize(count)
	normals.resize(count)
	uvs.resize(count)
	uv2s.resize(count)
	var inv_2s := 1.0 / (2.0 * s)
	var uv2_scale := Vector2(1.0 / uv2_rect.size.x, 1.0 / uv2_rect.size.y)
	for z in n:
		var lz := rect.position.y + float(z) * s
		for x in n:
			var i := z * n + x
			var h := z + 1
			var lx := rect.position.x + float(x) * s
			verts[i] = Vector3(lx, heights[h * m + x + 1], lz)
			var dx := (heights[h * m + x + 2] - heights[h * m + x]) * inv_2s
			var dz := (heights[(h + 1) * m + x + 1] - heights[(h - 1) * m + x + 1]) * inv_2s
			normals[i] = Vector3(-dx, 1.0, -dz).normalized()
			uvs[i] = Vector2(lx, lz) / 16.0
			uv2s[i] = (Vector2(lx, lz) - uv2_rect.position) * uv2_scale

	# Godot treats CLOCKWISE-wound triangles as front faces. Wound the other
	# way the whole tile is backface-culled and you fall through an invisible
	# world. The grid winding is copied from terrain.gd.
	var quads := (n - 1) * (n - 1)
	var indices := PackedInt32Array()
	indices.resize(quads * 6)
	var at := 0
	for z in n - 1:
		for x in n - 1:
			var i := z * n + x
			indices[at] = i
			indices[at + 1] = i + 1
			indices[at + 2] = i + n
			indices[at + 3] = i + 1
			indices[at + 4] = i + n + 1
			indices[at + 5] = i + n
			at += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skirt := _skirt(field, rect, s, n, margin, verts, normals, uvs, uv2s)
	# The grid alone for collision. A skirt is a wall hanging below the
	# ground and nothing should ever touch it.
	var grid_arrays := [verts, indices]
	var shape: ConcavePolygonShape3D = null
	if p.shape:
		shape = _shape_from_arrays(grid_arrays)
	return {
		"mesh": mesh,
		"skirt": skirt,
		"shape": shape,
		"arrays": grid_arrays,
		"tris": indices.size() / 3 + 4 * (n - 1) * 2,
	}


## The skirt: every rim vertex again, dropped by how far the ground dips
## below this tile's straight edge, with the same normal and UVs so the wall
## shades like the rim it hangs from. Depth is measured, per edge, against
## the data at its own spacing - a coarse tile over rough ground gets a deep
## skirt and a tile on the plain gets `margin` and nothing more.
static func _skirt(field: Heightfield, _rect: Rect2, s: float, n: int, margin: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, uv2s: PackedVector2Array) -> ArrayMesh:
	# Rim indices per edge - north, south, west, east - in the order the wall
	# is walked.
	var rims: Array[PackedInt32Array] = []
	for e in 4:
		var rim := PackedInt32Array()
		rim.resize(n)
		for k in n:
			match e:
				0: rim[k] = k
				1: rim[k] = (n - 1) * n + k
				2: rim[k] = k * n
				_: rim[k] = k * n + (n - 1)
		rims.append(rim)

	# The deepest the data goes below any edge's straight segments.
	var step := field.spacing
	var dip := 0.0
	for e in 4:
		var rim := rims[e]
		for k in n - 1:
			var a := verts[rim[k]]
			var b := verts[rim[k + 1]]
			var t := step
			while t < s:
				var at := a.lerp(b, t / s)
				dip = maxf(dip, at.y - field.height_at(at.x, at.z))
				t += step
	var depth := dip + margin

	var count := 8 * n
	var sverts := PackedVector3Array()
	var snormals := PackedVector3Array()
	var suvs := PackedVector2Array()
	var suv2s := PackedVector2Array()
	sverts.resize(count)
	snormals.resize(count)
	suvs.resize(count)
	suv2s.resize(count)
	for e in 4:
		var rim := rims[e]
		for k in n:
			var top := e * n + k
			var bottom := 4 * n + e * n + k
			var src := rim[k]
			sverts[top] = verts[src]
			sverts[bottom] = verts[src] - Vector3(0.0, depth, 0.0)
			snormals[top] = normals[src]
			snormals[bottom] = normals[src]
			suvs[top] = uvs[src]
			suvs[bottom] = uvs[src]
			suv2s[top] = uv2s[src]
			suv2s[bottom] = uv2s[src]

	# Clockwise seen from outside the tile. North (z min, seen from -Z) and
	# east (x max, seen from +X) run right-to-left on screen, so their winding
	# is the mirror of south and west, which run left-to-right.
	var indices := PackedInt32Array()
	indices.resize(4 * (n - 1) * 6)
	var at := 0
	for e in 4:
		var mirrored := e == 0 or e == 3
		for k in n - 1:
			var r0 := e * n + k
			var d0 := 4 * n + e * n + k
			at = _skirt_quad(indices, at, r0, d0 + 1, r0 + 1, d0, mirrored)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = sverts
	arrays[Mesh.ARRAY_NORMAL] = snormals
	arrays[Mesh.ARRAY_TEX_UV] = suvs
	arrays[Mesh.ARRAY_TEX_UV2] = suv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Two triangles for one skirt quad: rim vertices `r0`, `r1` and the dropped
## copies `d1`, `d0`. `mirrored` flips the winding for the edges that read
## right-to-left from outside.
static func _skirt_quad(indices: PackedInt32Array, at: int,
		r0: int, d1: int, r1: int, d0: int, mirrored: bool) -> int:
	if mirrored:
		indices[at] = r0
		indices[at + 1] = d1
		indices[at + 2] = r1
		indices[at + 3] = r0
		indices[at + 4] = d0
		indices[at + 5] = d1
	else:
		indices[at] = r0
		indices[at + 1] = r1
		indices[at + 2] = d1
		indices[at + 3] = r0
		indices[at + 4] = d1
		indices[at + 5] = d0
	return at + 6


## The trimesh from vertices and indices in hand. `Mesh.create_trimesh_shape()`
## would fetch the arrays back from the RenderingServer, which deadlocks on a
## worker and costs four times as much on the main thread.
static func _shape_from_arrays(grid_arrays: Array) -> ConcavePolygonShape3D:
	var verts: PackedVector3Array = grid_arrays[0]
	var indices: PackedInt32Array = grid_arrays[1]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = verts[indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


func _resolve_material() -> Material:
	if surface_material != null:
		return surface_material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.57, 0.53, 0.48)
	mat.roughness = 0.94
	return mat


# --- Read-outs ----------------------------------------------------------

## Whether every wanted tile is resident and nothing is in flight.
func is_settled() -> bool:
	if not _pending.is_empty():
		return false
	for key in _desired_list:
		if not _resident.has(key):
			return false
	return true


func resident_keys() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for key: Vector3i in _resident.keys():
		out.append(key)
	return out


func desired_keys() -> Array[Vector3i]:
	return _desired_list.duplicate()


func resident_triangles() -> int:
	var total := 0
	for record: Dictionary in _resident.values():
		total += int(record.tris)
	return total


func collided_tiles() -> int:
	var total := 0
	for record: Dictionary in _resident.values():
		if record.body != null:
			total += 1
	return total


func pending_tiles() -> int:
	return _pending.size()


func cached_tiles() -> int:
	return _cache.size()


func heightfield() -> Heightfield:
	return _field


## Reconsider the tile set for where the viewer is now, without waiting for
## it to have moved `update_distance` - for tests, and for the F1 panel.
func refresh() -> void:
	if _field == null:
		return
	_last_viewer = _viewer_local_xz()
	_dirty = false
	_reselect(_last_viewer)
