extends MeshInstance3D
class_name MapTerrain
## The map's own low-resolution copy of the terrain.
##
## **Not a camera pointed at the world.** A map is a representation, and the
## world is lit by a red dwarf grazing the horizon through real fog — an aerial
## shot of it is a dark red smear. So this is a separate mesh at map resolution
## with a map material: elevation ramp, hillshade from a conventional direction,
## contour lines, and the coverage mask.
##
## Heights come from `Terrain.world_height_at()`, so there is one heightfield in the
## project and the map cannot drift from the ground you drive on. The mesh is
## rebuilt on `Terrain.rebuilt` for the same reason.
##
## Vertical exaggeration is a map convention, not a mistake: 210 m of relief
## across 2 km is nearly flat seen honestly, and the whole point of a relief map
## is to make the shape of the land legible. Contour labels stay in real metres.

## Quads across the patch. 128 is ~33k triangles, which is nothing, and gives a
## 16 m sample over a 2 km patch — coarse enough to miss a boulder and fine
## enough to show every ridge that matters to a route.
@export_range(16, 512, 8) var grid := 128:
	set(v):
		grid = maxi(v, 16)
		queue_rebuild()

## How much taller than life. 1.0 is honest and unreadable.
@export_range(1.0, 8.0, 0.1) var relief_exaggeration := 2.5:
	set(v):
		relief_exaggeration = maxf(v, 1.0)
		queue_rebuild()

## Fit the elevation ramp to the heights this terrain actually has.
##
## On by default because the alternative is a number in a material that has to
## be kept in step with a heightfield by hand, and the first authored map made
## that obvious: with the ramp fixed at 0-220 m and a patch whose ground sits
## around 8 m, the whole map rendered at the dark end of the ramp with one
## bright peak. Technically correct and unreadable.
@export var auto_range := true:
	set(v):
		auto_range = v
		queue_rebuild()

## Emitted after the mesh is rebuilt, so a test can wait on the thing rather
## than on a frame count.
signal rebuilt

var _terrain: TerrainSource
var _queued := false
## Patch extent the current mesh was built for, in metres.
var _span := 0.0
## Real world metres, low and high, from the last build. Diagnostics and the
## capture, which is where a ramp that fits the terrain badly shows up.
var _low := 0.0
var _high := 0.0


func _ready() -> void:
	add_to_group("map_terrain")
	Lattice.coverage_changed.connect(_push_coverage)
	queue_rebuild()


func queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	_terrain = Lattice.terrain()
	if _terrain == null or not _terrain.is_built():
		return
	if not _terrain.rebuilt.is_connected(queue_rebuild):
		_terrain.rebuilt.connect(queue_rebuild)

	# World space throughout. This walked the terrain's own local grid and put
	# each sample through `to_global`, which is the same picture only while
	# there is one patch to be local to.
	var ground := _terrain.extent()
	_span = ground.size.x
	var verts := grid + 1
	var step := _span / float(grid)

	var positions := PackedVector3Array()
	var uv2s := PackedVector2Array()
	positions.resize(verts * verts)
	uv2s.resize(verts * verts)
	var lowest := INF
	var highest := -INF

	for z in verts:
		for x in verts:
			var wx := ground.position.x + float(x) * step
			var wz := ground.position.y + float(z) * step
			# The terrain node carries its own transform, including a Y scale
			# used to flatten the world in the editor. `world_height_at` is
			# where that conversion lives; treating a local height as a world
			# one is the difference between a map and a map at twice the
			# altitude, and it has been shipped once already.
			var world := _terrain.world_surface_at(wx, wz)
			var i := z * verts + x
			# Kept in world X/Z so the map and the world share a coordinate
			# system and a marker needs no conversion.
			positions[i] = Vector3(world.x, world.y * relief_exaggeration, world.z)
			lowest = minf(lowest, world.y)
			highest = maxf(highest, world.y)
			# The same 0..1 patch span the coverage mask is indexed by, so the
			# mask can be sampled here exactly as the ground samples it.
			uv2s[i] = Vector2(float(x), float(z)) / float(verts - 1)

	var indices := PackedInt32Array()
	indices.resize(grid * grid * 6)
	var at := 0
	for z in grid:
		for x in grid:
			var i := z * verts + x
			# The same winding terrain.gd uses, and copied from it rather than
			# re-derived: Godot treats clockwise-wound triangles as front faces,
			# and wound the other way the map is backface-culled from above,
			# which is the only angle anybody looks at it from. Getting this
			# wrong does not draw nothing — it draws the slopes that face
			# *away*, so a mostly flat map renders as a few bright ridge
			# slivers and reads as a colour bug rather than a winding one.
			indices[at + 0] = i
			indices[at + 1] = i + 1
			indices[at + 2] = i + verts
			indices[at + 3] = i + 1
			indices[at + 4] = i + verts + 1
			indices[at + 5] = i + verts
			at += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices

	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Normals from the geometry rather than by hand: the hillshade is the only
	# thing that reads them and a generated normal is exactly right here.
	var tool := SurfaceTool.new()
	tool.create_from(built, 0)
	tool.generate_normals()
	mesh = tool.commit()

	_push_elevation_range(lowest, highest)
	_push_coverage()
	rebuilt.emit()


## Fit the colour ramp to the heights that are actually out there.
##
## The ramp is in **real** world metres, not exaggerated ones, so the colours
## and any contour reading stay honest however tall the mesh is drawn.
func _push_elevation_range(lowest: float, highest: float) -> void:
	if lowest > highest:
		return
	_low = lowest
	_high = highest
	if not auto_range:
		return
	var material := get_active_material(0) as ShaderMaterial
	if material == null:
		return
	# A hair of headroom so the highest point is not exactly the end of the
	# ramp, which would flatten every peak to one colour.
	var span := maxf((highest - lowest) * 1.05, 1.0)
	material.set_shader_parameter("elevation_floor", lowest)
	material.set_shader_parameter("elevation_span", span)


## Hand the map material the same mask the ground is drawing, so the two cannot
## disagree about where the network reaches.
func _push_coverage() -> void:
	var material := get_active_material(0) as ShaderMaterial
	if material == null:
		return
	var map := get_tree().get_first_node_in_group("coverage_map")
	if map == null:
		material.set_shader_parameter("coverage_enabled", false)
		return
	# **Listen to the mask, not to the graph.** Both this and CoverageMap hang
	# off Lattice.coverage_changed and both rebuild deferred, so whichever runs
	# first wins — and when this one did, it read a mask that did not exist yet,
	# set coverage_enabled false, and never looked again. The map then drew a
	# perfectly good relief with no network on it at all.
	if not map.is_connected("rebuilt", _push_coverage):
		map.connect("rebuilt", _push_coverage)
	var texture: Texture2D = map.call("mask_texture")
	material.set_shader_parameter("coverage_enabled", texture != null)
	material.set_shader_parameter("coverage_mask", texture)


## Map-space Y for a world X/Z — the height this mesh draws, exaggeration
## included. Anything placed on the map surface has to go through this or it
## floats above the terrain it is meant to be standing on.
func map_height(world_x: float, world_z: float) -> float:
	if _terrain == null:
		return 0.0
	return _terrain.world_height_at(world_x, world_z) * relief_exaggeration


## A point on the map surface for a world X/Z.
func map_point(world_x: float, world_z: float, lift := 0.0) -> Vector3:
	return Vector3(world_x, map_height(world_x, world_z) + lift, world_z)


## Low and high real world height from the last build, in metres.
func elevation_range() -> Vector2:
	return Vector2(_low, _high)


## Metres across the patch. Zero until the first build.
func span() -> float:
	return _span


## World centre of the patch, which is where the camera starts looking.
func centre() -> Vector3:
	if _terrain == null:
		return Vector3.ZERO
	return Vector3(_terrain.global_position.x, 0.0, _terrain.global_position.z)


## Where a ray hits the drawn surface, or `false` if it never does.
##
## Marched against the heightfield rather than raycast against a collision
## shape: the map has no physics world of its own, and giving it one would mean
## a 33k-triangle trimesh existing only to be clicked on. Marching also has the
## right failure mode — a ray fired at the sky simply runs out.
func surface_hit(from: Vector3, direction: Vector3, limit := 12000.0) -> Dictionary:
	if _terrain == null or _span <= 0.0:
		return {"hit": false, "point": Vector3.ZERO}
	var dir := direction.normalized()
	# Coarse enough to be quick, fine enough not to step over a ridge; the
	# bisection below recovers the precision.
	var step := maxf(_span / 512.0, 1.0)
	var travelled := 0.0
	var previous := from
	var previous_gap := from.y - map_height(from.x, from.z)
	while travelled < limit:
		travelled += step
		var here := from + dir * travelled
		var gap := here.y - map_height(here.x, here.z)
		if gap <= 0.0 and previous_gap > 0.0:
			# Straddled the surface. Bisect the last step rather than accept a
			# whole step of error, which at this scale is metres.
			var lo := previous
			var hi := here
			for i in 24:
				var mid := (lo + hi) * 0.5
				if mid.y - map_height(mid.x, mid.z) > 0.0:
					lo = mid
				else:
					hi = mid
			var point := (lo + hi) * 0.5
			return {"hit": true, "point": point}
		previous = here
		previous_gap = gap
	return {"hit": false, "point": Vector3.ZERO}
