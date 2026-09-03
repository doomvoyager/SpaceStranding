extends Node3D
class_name CoverageMap
## Lattice coverage, painted on the ground. See docs/02-Systems/The-Lattice.md.
##
## **Coverage is not a radius, and this is the node that keeps it from becoming
## one.** The whole claim of [[The-Lattice]] is that a radius check makes the
## network a question of distance, which the map cannot argue with, while a
## sight line makes it a question of where the high ground is. Drawing coverage
## as circles would contradict that on screen, permanently — so the mask is
## range **and** line of sight, and the boundary has ridge-shadows bitten out of
## it. That is the mechanic, drawn.
##
## Built into an R8 mask spanning the terrain patch and handed to the terrain's
## material, which samples it through the same UV2 the macro albedo uses. Patch
## space rather than world space means the terrain's 1.3 km offset is handled
## for free, and there is no second copy of the extent to keep in step.
##
## **Rebuilt on the same signal the graph is, and never per frame.** A link's
## existence changes only when a site moves or the terrain is rebuilt, and
## coverage changes exactly when the graph does — so this hangs off
## `Lattice.coverage_changed` and `Terrain.rebuilt`, coalesced the same way.
##
## The cost stays small because only ground within a site's reach can be
## covered, so each site rasterises its own box rather than anything walking the
## map: a 45 m reach at 2 m per texel is about 2,000 texels and 45,000 height
## lookups per site, once, when the network changes.

## Metres per mask texel. The mask spans the whole patch, so this trades memory
## against how crisp a ridge-shadow can be: 2 m over a 4 km patch is a 2048²
## R8 image, 4 MB.
@export_range(0.5, 32.0, 0.5) var metres_per_texel := 2.0:
	set(v):
		metres_per_texel = maxf(v, 0.5)
		queue_rebuild()

## Metres over which coverage falls off as it reaches the range limit. The
## boundary the shader draws is the half-way point of this ramp, so widening it
## moves the line inward a little as well as softening it.
@export_range(0.5, 40.0, 0.5) var edge_softness := 6.0:
	set(v):
		edge_softness = maxf(v, 0.5)
		queue_rebuild()

## Height above the ground that has to see the mast, in metres. Coverage is for
## a person standing there, not for the dirt.
@export_range(0.0, 10.0, 0.1) var receiver_height := 1.7:
	set(v):
		receiver_height = v
		queue_rebuild()

@export_group("Look")
## Pushed to the terrain material on every rebuild, so these are live on the F1
## panel and do not need the material opening to try a colour.
@export_range(0.0, 1.0, 0.01) var intensity := 1.0:
	set(v):
		intensity = v
		_push_look()
@export var fill_color := Color(0.36, 0.78, 0.84):
	set(v):
		fill_color = v
		_push_look()
@export_range(0.0, 1.0, 0.01) var fill_strength := 0.10:
	set(v):
		fill_strength = v
		_push_look()
@export var edge_color := Color(0.55, 0.95, 1.0):
	set(v):
		edge_color = v
		_push_look()
@export_range(0.0, 4.0, 0.05) var edge_glow := 1.5:
	set(v):
		edge_glow = v
		_push_look()
@export_range(0.01, 0.45, 0.01) var edge_width := 0.10:
	set(v):
		edge_width = v
		_push_look()

## Emitted after the mask has been rebuilt. Tests wait on this rather than on a
## frame count, because _process and _physics_process do not interleave anything
## like realtime under --headless.
signal rebuilt

var _image: Image
var _texture: ImageTexture
var _terrain: TerrainSource
var _queued := false
## Texels across. Kept so a sampler does not have to re-derive it.
var _n := 0


func _ready() -> void:
	add_to_group("coverage_map")
	Lattice.coverage_changed.connect(queue_rebuild)
	queue_rebuild()


## Rebuilds are deferred and coalesced: six sites registering in one frame is
## one mask, not six. Same reason the graph does it.
func queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	_terrain = _find_terrain()
	if _terrain == null or not _terrain.is_built():
		return
	if not _terrain.rebuilt.is_connected(queue_rebuild):
		_terrain.rebuilt.connect(queue_rebuild)

	var ground := _terrain.extent()
	var span := ground.size.x
	_n = maxi(int(ceil(span / maxf(metres_per_texel, 0.5))), 4)
	if _image == null or _image.get_width() != _n:
		_image = Image.create_empty(_n, _n, false, Image.FORMAT_R8)
		_texture = null
	_image.fill(Color(0.0, 0.0, 0.0, 1.0))

	for site in Lattice.covering_sites():
		_paint(site, ground)

	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.update(_image)
	_push_look()
	rebuilt.emit()


## Rasterise one site's reach into the mask.
##
## Only the box within reach is visited. Walking the whole patch per site would
## be the obvious loop and is thousands of times the work for the same picture.
func _paint(site: Node, ground: Rect2) -> void:
	var mast: Vector3 = site.call("mast_point")
	var reach: float = site.call("link_range")
	if reach <= 0.0:
		return
	# World XZ throughout. The mask used to be indexed in the terrain's own
	# local space, which is only a coordinate system while there is one patch.
	var per_texel := ground.size.x / float(_n - 1)
	var radius := int(ceil(reach / per_texel)) + 1
	var cx := int(round((mast.x - ground.position.x) / per_texel))
	var cz := int(round((mast.z - ground.position.y) / per_texel))

	for j in range(maxi(cz - radius, 0), mini(cz + radius + 1, _n)):
		for i in range(maxi(cx - radius, 0), mini(cx + radius + 1, _n)):
			var wx := ground.position.x + float(i) * per_texel
			var wz := ground.position.y + float(j) * per_texel
			var at := _terrain.world_surface_at(wx, wz) 				+ Vector3(0.0, receiver_height, 0.0)
			var distance := at.distance_to(mast)
			if distance > reach:
				continue
			# The expensive half, and the whole point: a site covers what it can
			# see, so a ridge takes a bite out of its coverage.
			if not Lattice.has_line_of_sight(at, mast):
				continue
			var value := clampf((reach - distance) / maxf(edge_softness, 0.5),
				0.0, 1.0)
			# Sites overlap, and the strongest signal wins rather than the last
			# one painted — otherwise the boundary depends on dictionary order.
			if value > _image.get_pixel(i, j).r:
				_image.set_pixel(i, j, Color(value, 0.0, 0.0, 1.0))


## How covered a world point is, 0 to 1. The mask is the authority, so a
## gameplay check and the boundary on screen can never disagree about where the
## line is — they are the same numbers.
func coverage_at(world_x: float, world_z: float) -> float:
	if _image == null or _terrain == null or _n <= 0:
		return 0.0
	var ground := _terrain.extent()
	var per_texel := ground.size.x / float(_n - 1)
	var i := int(round((world_x - ground.position.x) / per_texel))
	var j := int(round((world_z - ground.position.y) / per_texel))
	if i < 0 or j < 0 or i >= _n or j >= _n:
		return 0.0
	return _image.get_pixel(i, j).r


## The mask, for anything that wants to draw it. Null until the first rebuild.
func mask_texture() -> ImageTexture:
	return _texture


func _push_look() -> void:
	var material := _surface_material()
	if material == null:
		return
	material.set_shader_parameter("coverage_enabled", true)
	material.set_shader_parameter("coverage_mask", _texture)
	material.set_shader_parameter("coverage_intensity", intensity)
	material.set_shader_parameter("coverage_fill_color", fill_color)
	material.set_shader_parameter("coverage_fill_strength", fill_strength)
	material.set_shader_parameter("coverage_edge_color", edge_color)
	material.set_shader_parameter("coverage_edge_glow", edge_glow)
	material.set_shader_parameter("coverage_edge_width", edge_width)


func _surface_material() -> ShaderMaterial:
	if _terrain == null:
		_terrain = _find_terrain()
	if _terrain == null:
		return null
	return _terrain.surface_material as ShaderMaterial


## Asked of the Lattice rather than looked up here: the terrain is not in a
## group in every scene, so finding it is a tree walk, and one copy of that is
## enough.
func _find_terrain() -> TerrainSource:
	return Lattice.terrain()
