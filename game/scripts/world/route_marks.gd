extends Node3D
class_name RouteMarks
## How a planned route appears in the world. See [[The-Map]].
##
## Two readings of the same route, deliberately different in what they tell you:
##
##   * **A light pillar on the nearest remaining stop**, and only that one. It
##     is a horizon-finder — it answers "which way" from a kilometre out and
##     nothing else. Showing every stop would turn a planned trip into a field
##     of beams with no way to tell which one you were heading for.
##
##   * **The whole route, on a scan pulse.** Q reveals the line you drew and a
##     triangle at your feet pointing at the nearest stop, then it fades with
##     the pulse. This is the reading that answers "what was the plan" rather
##     than "where next", and it costs a ping — so the route is something you
##     check, not something permanently painted over the world.
##
## Arrival is not handled here. `Route` watches for it itself, because a scene
## without this node should still tick stops off, and tying "have I arrived" to
## "can I see the marker" would be a bug waiting for the first scene that omits
## the marker.

@export_group("Pillar")
## Metres. Tall enough to clear the ridges you would be looking over.
@export_range(10.0, 400.0, 5.0) var beam_height := 140.0
@export_range(0.5, 30.0, 0.5) var beam_width := 8.0
@export var beam_color := Color(0.55, 1.0, 0.72)
@export_range(0.0, 4.0, 0.05) var beam_intensity := 1.05
## Stop drawing the beam once you are this close. Inside the arrival radius it
## is about to vanish anyway, and a 140 m column at arm's length is a wall.
@export_range(0.0, 80.0, 1.0) var beam_near_cutoff := 22.0

@export_group("Scan reveal")
## Colour of the route line and the pointer drawn during a pulse.
@export var reveal_color := Color(0.36, 0.95, 1.0)
## Metres above the ground the revealed line floats, so it is not z-fighting the
## terrain it follows.
@export_range(0.1, 6.0, 0.1) var reveal_lift := 1.2
## Size of the pointer triangle, in metres.
@export_range(0.5, 12.0, 0.25) var pointer_size := 4.0
## Metres in front of the player the pointer sits.
@export_range(0.0, 20.0, 0.5) var pointer_offset := 4.0

## Metres the player can walk before the revealed line is rebuilt.
##
## **The line does not change while you stand still.** Every vertex of it is a
## height lookup — four hundred of them for a route across the patch — and the
## only thing that moves between one frame and the next is the first vertex,
## which is at your feet. Rebuilding the lot every frame for that was 1.2 ms of
## a pulse's frame; at two metres the difference is behind the camera.
##
## Zero rebuilds every frame, which is what this used to do. See
## tests/probe_scan_cost.tscn.
@export_range(0.0, 20.0, 0.5) var reveal_rebuild_step := 2.0

var _pillar: MeshInstance3D
var _beam_material: ShaderMaterial
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _line_material: StandardMaterial3D
var _pointer: MeshInstance3D
var _pointer_material: StandardMaterial3D

var _scanner: Node
var _player: Astronaut
var _terrain: TerrainSource
## Seconds since the last pulse, or -1 when there has not been one.
var _since_ping := -1.0
## Where the player stood when the line was last built, and whether anything
## has happened since that changes its shape rather than just where it starts.
var _line_from := Vector2.ZERO
var _line_stale := true


func _ready() -> void:
	add_to_group("route_marks")
	_build_pillar()
	_build_reveal()
	Route.changed.connect(_on_route_changed)


func _build_pillar() -> void:
	_pillar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(beam_width, beam_height)
	_pillar.mesh = quad
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = load("res://shaders/route_beacon.gdshader")
	_pillar.material_override = _beam_material
	# The beam is billboarded in the vertex shader, so its real bounds bear no
	# relation to the quad's. Without a margin it is culled by its own
	# unrotated AABB the moment you look at it from the side — which is most of
	# the time, and which reads as the beam flickering rather than as culling.
	_pillar.extra_cull_margin = beam_height
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.visible = false
	add_child(_pillar)
	_push_beam_look()


func _build_reveal() -> void:
	_line = MeshInstance3D.new()
	_line_mesh = ImmediateMesh.new()
	_line.mesh = _line_mesh
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# **Mixed, not added.** Adding a bright cyan over the terminator's pink
	# ground comes out white — the same trap the scan dot had to learn, and the
	# route line carries its colour for the same reason the dot does. Mixing
	# keeps the hue at the cost of not glowing, which is the right trade for a
	# line you are meant to read rather than admire.
	_line_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_line.visible = false
	add_child(_line)

	_pointer = MeshInstance3D.new()
	_pointer.mesh = _build_triangle()
	_pointer_material = StandardMaterial3D.new()
	_pointer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pointer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pointer_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_pointer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pointer.material_override = _pointer_material
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pointer.visible = false
	add_child(_pointer)


## A flat triangle lying in XZ, nose toward -Z, so `look_at` aims it.
func _build_triangle() -> ArrayMesh:
	var half := pointer_size * 0.5
	var points := PackedVector3Array([
		Vector3(0.0, 0.0, -pointer_size),
		Vector3(-half, 0.0, half * 0.6),
		Vector3(half, 0.0, half * 0.6),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _push_beam_look() -> void:
	if _beam_material == null:
		return
	_beam_material.set_shader_parameter("beam_color", beam_color)
	_beam_material.set_shader_parameter("intensity", beam_intensity)


func _on_route_changed() -> void:
	# Nothing cached about the route survives a change to it; the next frame
	# rebuilds both readings from scratch.
	_line_stale = true
	if Route.is_empty():
		_pillar.visible = false
		_line.visible = false
		_pointer.visible = false


# --- What is on screen, for tests -----------------------------------------
##
## The same reason the HUD publishes its survey line: a marker that is correct
## and never drawn is this project's most repeated failure, and only the
## visibility half is easy to miss.

func beacon_visible() -> bool:
	return _pillar != null and _pillar.visible


## Where the beam is standing. Its origin is the middle of the quad, so this
## reports the foot, which is the bit that is meant to be on a stop.
func beacon_foot() -> Vector3:
	if _pillar == null:
		return Vector3.ZERO
	return _pillar.global_position - Vector3(0.0, beam_height * 0.5, 0.0)


func reveal_visible() -> bool:
	return _line != null and _line.visible


func pointer_visible() -> bool:
	return _pointer != null and _pointer.visible


## Vertices in the revealed line. The line is only rebuilt when the player has
## moved (see `reveal_rebuild_step`), so `reveal_visible()` on its own no longer
## proves there is anything to see — a throttle that never released would leave
## a visible node holding an empty mesh.
func reveal_vertex_count() -> int:
	if _line_mesh == null or _line_mesh.get_surface_count() == 0:
		return 0
	# ImmediateMesh has no surface_get_array_len; surface_get_arrays does work,
	# and does so under --headless - measured, because a Mesh readback that
	# quietly returns nothing on the dummy renderer is a trap this project has
	# already met with MultiMesh.
	var arrays := _line_mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


## Unit XZ direction the pointer is aiming, or zero when it is not drawn.
func pointer_heading() -> Vector2:
	if _pointer == null or not _pointer.visible:
		return Vector2.ZERO
	var nose := -_pointer.global_transform.basis.z
	return Vector2(nose.x, nose.z).normalized()


## A rebuilt terrain moves the ground the line is drawn on, so the line the
## last build cached is no longer standing on it.
##
## Connected lazily for the same reason the scanner is: neither exists yet when
## this node is ready, and a scene can be given a terrain later.
func _watch_terrain() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		return
	_terrain = Lattice.terrain()
	if _terrain != null and not _terrain.rebuilt.is_connected(_on_terrain_rebuilt):
		_terrain.rebuilt.connect(_on_terrain_rebuilt)
		_line_stale = true


func _on_terrain_rebuilt() -> void:
	_line_stale = true


func _find_scanner() -> Node:
	if _scanner == null or not is_instance_valid(_scanner):
		_scanner = get_tree().get_first_node_in_group("scanner")
		if _scanner != null and _scanner.has_signal("pinged") \
				and not _scanner.is_connected("pinged", _on_ping):
			_scanner.connect("pinged", _on_ping)
	return _scanner


func _on_ping(_origin: Vector3) -> void:
	_since_ping = 0.0


func _process(delta: float) -> void:
	_find_scanner()
	_watch_terrain()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Astronaut
	if _player == null or Route.is_empty():
		_pillar.visible = false
		_line.visible = false
		_pointer.visible = false
		return
	var at := _player.vantage()
	var flat := Vector2(at.x, at.z)
	_draw_pillar(flat)
	if _since_ping >= 0.0:
		_since_ping += delta
	_draw_reveal(flat)


## One beam, on the nearest remaining stop.
func _draw_pillar(from: Vector2) -> void:
	var i := Route.nearest_index(from)
	if i < 0:
		_pillar.visible = false
		return
	var target := Route.point_2d(i)
	if from.distance_to(target) < beam_near_cutoff:
		_pillar.visible = false
		return
	var ground := Route.ground_height(target.x, target.y)
	_pillar.visible = true
	_pillar.global_position = Vector3(target.x, ground + beam_height * 0.5, target.y)


## The whole route, for as long as a pulse lasts.
func _draw_reveal(from: Vector2) -> void:
	var strength := _reveal_strength()
	if strength <= 0.001:
		_line.visible = false
		_pointer.visible = false
		return

	# The fade is the material's, not the mesh's, so it costs nothing to run it
	# every frame while the geometry underneath stays put.
	var colour := Color(reveal_color.r, reveal_color.g, reveal_color.b, strength)
	_line_material.albedo_color = colour
	_pointer_material.albedo_color = colour

	if _line_stale or from.distance_to(_line_from) > reveal_rebuild_step:
		_rebuild_line(from)
	_line.visible = true

	# And the pointer, at your feet, aimed at the one the beam is standing on.
	# Three vertices and one height lookup, so this one does follow you every
	# frame - it is the line behind it that does not need to.
	var i := Route.nearest_index(from)
	if i < 0:
		_pointer.visible = false
		return
	var target := Route.point_2d(i)
	var to := (target - from)
	if to.length_squared() < 0.0001:
		_pointer.visible = false
		return
	to = to.normalized()
	var here := from + to * pointer_offset
	var ground := Route.ground_height(here.x, here.y) + reveal_lift
	_pointer.global_position = Vector3(here.x, ground, here.y)
	# The triangle's nose is -Z, which is what look_at points at a target.
	_pointer.look_at(Vector3(target.x, ground, target.y), Vector3.UP)
	_pointer.visible = true


## The whole route, from `from` to the last stop, hugging the ground.
##
## Follows the ground the same way the map's line does and the leg lengths are
## measured, so all three agree about where the route runs.
func _rebuild_line(from: Vector2) -> void:
	_line_stale = false
	_line_from = from
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_material)
	var chain: Array[Vector2] = [from]
	for i in Route.count():
		chain.append(Route.point_2d(i))
	for leg in range(1, chain.size()):
		var a := chain[leg - 1]
		var b := chain[leg]
		var steps := maxi(int(ceil(a.distance_to(b) / Route.SAMPLE_STEP)), 1)
		var first := 0 if leg == 1 else 1
		for step in range(first, steps + 1):
			var p := a.lerp(b, float(step) / float(steps))
			_line_mesh.surface_add_vertex(Vector3(
				p.x, Route.ground_height(p.x, p.y) + reveal_lift, p.y))
	_line_mesh.surface_end()


## How strongly the reveal is showing, 0 to 1.
##
## Matched to the scanner's own envelope rather than given its own timing, so
## the route arrives with the pulse and leaves with it. Read off the scanner's
## exports because it does not publish a strength.
func _reveal_strength() -> float:
	if _since_ping < 0.0:
		return 0.0
	var scanner := _find_scanner()
	var hold := 4.0
	var fade := 2.5
	if scanner != null:
		hold = float(scanner.get("hold"))
		fade = maxf(float(scanner.get("fade")), 0.01)
	if _since_ping <= hold:
		return 1.0
	return clampf(1.0 - (_since_ping - hold) / fade, 0.0, 1.0)
