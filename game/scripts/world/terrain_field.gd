@tool
extends TerrainSource
class_name TerrainField
## A grid of `ProceduralTerrain` tiles that behaves like one piece of ground.
##
## **It answers the seam, so nothing downstream knows it is not a single
## patch.** `world_height_at`, `world_surface_at`, `extent()` and
## `sample_step()` are the whole contract five systems were narrowed onto on
## 2026-09-03; a field satisfies it by finding the tile under the query and
## asking that. See [[Terrain]].
##
## ## Standing in for art that does not exist yet
##
## The world is 3x3 tiles of 4096 m and Mac has one 8193² master, which covers
## 8192 m at native resolution — two tiles' worth. Until nine are authored,
## every tile samples the same master, **mirrored on alternate rows and
## columns**.
##
## Mirroring rather than stretching, for two reasons that both matter more than
## how it looks:
##
##   1. **Grades survive.** Stretching one 210 m master over 12,288 m keeps the
##      relief and triples the run, so every slope divides by three: the
##      measured median 3 deg becomes 1 and the p99 17 becomes 6. That is a
##      pancake, and it would invalidate the drivability tuning the rover was
##      re-seated against this week. Mirroring changes no slope anywhere.
##   2. **It keeps tile bugs loud.** Nine tiles sampling one *contiguous*
##      stretched map means a wrong tile index still produces plausible ground,
##      and the bug hides. Nine discrete tiles means a wrong index shows up as
##      a discontinuity you cannot miss. A placeholder should fail visibly.
##
## The seams are continuous by construction: a tile and its mirrored neighbour
## meet on the same edge row of the master. The crease is real — slope flips
## across the join — but it reads as a ridge or a gully rather than a wall.
##
## Nine copies of one mountain is obviously repetitive, and that is expected.
## This exists so the chunking, culling and streaming can be built and measured
## against nine real heightfields; it is thrown away when the art arrives.

@export_group("Layout")
## Tiles per side. 3 is the world; 1 makes this a single patch with extra steps.
@export var tiles_across := 3:
	set(v):
		tiles_across = maxi(v, 1)
		_queue_rebuild()
## Side length of one tile, metres.
@export var tile_size := 4096.0:
	set(v):
		tile_size = maxf(v, 16.0)
		_queue_rebuild()
## Metres between height samples within a tile.
@export var tile_resolution := 4.0:
	set(v):
		tile_resolution = maxf(v, 0.5)
		_queue_rebuild()
## Mirror alternate rows and columns so neighbours share an edge. Off makes
## every tile identical and puts a cliff at every seam, which is worth being
## able to see on purpose.
@export var mirror_tiles := true:
	set(v):
		mirror_tiles = v
		_queue_rebuild()

@export_group("Source")
@export var height_source: ProceduralTerrain.HeightSource = \
		ProceduralTerrain.HeightSource.HEIGHTMAP:
	set(v):
		height_source = v
		_queue_rebuild()
@export var heightmap: Texture2D:
	set(v):
		heightmap = v
		_queue_rebuild()
## Metres from a tile's lowest sample to its highest.
@export var height_span := 210.0:
	set(v):
		height_span = v
		_queue_rebuild()
@export var height_floor := 0.0:
	set(v):
		height_floor = v
		_queue_rebuild()

@export_group("Look")
@export var surface_material: Material = preload("res://materials/regolith.tres"):
	set(v):
		surface_material = v
		for tile in _tiles:
			tile.surface_material = v

@export_group("Actions")
@export var rebuild := false:
	set(_v):
		rebuild = false
		_build()

var _tiles: Array[ProceduralTerrain] = []
var _rebuild_queued := false
var _pending := 0


func _ready() -> void:
	# The group is how everything else finds the ground. Safe to join now that
	# `Lattice.terrain()` returns `TerrainSource` rather than the single-patch
	# type - before that, a field found here failed the cast and handed back
	# null, and every height query in the project would have quietly answered
	# zero instead of erroring.
	add_to_group("terrain")
	_build()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_queued_rebuild.call_deferred()


func _do_queued_rebuild() -> void:
	_rebuild_queued = false
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	for tile in _tiles:
		tile.queue_free()
	_tiles.clear()

	var half := (float(tiles_across) - 1.0) * 0.5
	_pending = tiles_across * tiles_across
	for tz in tiles_across:
		for tx in tiles_across:
			var tile := ProceduralTerrain.new()
			tile.name = "Tile_%d_%d" % [tx, tz]
			tile.height_source = height_source
			tile.heightmap = heightmap
			tile.height_span = height_span
			tile.height_floor = height_floor
			tile.size = tile_size
			tile.resolution = tile_resolution
			tile.surface_material = surface_material
			if mirror_tiles:
				tile.map_flip_x = (tx % 2) != 0
				tile.map_flip_z = (tz % 2) != 0
			tile.position = Vector3(
				(float(tx) - half) * tile_size, 0.0,
				(float(tz) - half) * tile_size)
			# **Never given an owner.** A @tool script that owns its generated
			# children serialises them into the .tscn, which would bake nine
			# six-figure-triangle meshes into the scene file on every save.
			add_child(tile)
			tile.rebuilt.connect(_on_tile_built)
			_tiles.append(tile)


func _on_tile_built() -> void:
	_pending -= 1
	if _pending <= 0:
		rebuilt.emit()


# --- The seam -----------------------------------------------------------

func is_built() -> bool:
	if _tiles.is_empty():
		return false
	for tile in _tiles:
		if not tile.is_built():
			return false
	return true


## Ground height in world space, from whichever tile covers the point.
##
## Off the field entirely, the nearest tile answers rather than returning zero:
## a query a metre past the edge should give the edge's height, not sea level,
## which is the same clamping a single patch already does at its own border.
func world_height_at(world_x: float, world_z: float) -> float:
	var tile := _tile_at(world_x, world_z)
	if tile == null:
		return 0.0
	return tile.world_height_at(world_x, world_z)


## The whole field's footprint, world X/Z — the union of its tiles.
func extent() -> Rect2:
	if _tiles.is_empty():
		return Rect2()
	var box := _tiles[0].extent()
	for i in range(1, _tiles.size()):
		box = box.merge(_tiles[i].extent())
	return box


func sample_step() -> float:
	if _tiles.is_empty():
		return tile_resolution
	return _tiles[0].sample_step()


## How many tiles the field is made of. For tests and the F1 panel; nothing in
## the game should care.
func tile_count() -> int:
	return _tiles.size()


## The tile covering a world point, or the nearest one if the point is outside.
##
## Indexed arithmetically rather than by walking the list: nine is small today
## and this is on the path every height query in the project takes, which is
## the function that turned out to be a tree walk once already.
func _tile_at(world_x: float, world_z: float) -> ProceduralTerrain:
	if _tiles.is_empty():
		return null
	var box := extent()
	var span := maxf(box.size.x / float(tiles_across), 0.001)
	var ix := clampi(int(floor((world_x - box.position.x) / span)),
		0, tiles_across - 1)
	var iz := clampi(int(floor((world_z - box.position.y) / span)),
		0, tiles_across - 1)
	return _tiles[iz * tiles_across + ix]
