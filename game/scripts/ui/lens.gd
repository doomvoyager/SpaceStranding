extends CanvasLayer
class_name Lens
## The camera's glass, as the post pass needs it: where the sun is in the
## frame, how big its disc is there, and how much regolith is on the lens.
##
## The script on the post layer, `scenes/postprocessing_effects.tscn`. It draws
## nothing. Every frame it works those numbers out for whichever camera is on
## screen and hands them to `film.gdshader` as shader globals, and the shader
## draws the flare, the lens dirt and the lens dust. See
## docs/02-Systems/Lens.md.
##
## **Whether the sun can be seen is not decided here.** The shader decides, by
## looking at the picture: the sky draws the disc far past white, and anything
## in front of the sun is seen from its unlit side, so a few taps inside the
## disc say how much of it is showing. That is exact with what is drawn, at any
## distance - where physics rays would miss every crater rim beyond the
## streamed collision, and the rover's wheels, which have no shapes at all.
## Measured in `tests/probe_sun_disc.tscn`. This script only says where to
## look.
##
## **It runs after everything that moves a camera.** A sun position from before
## the chase rig has levelled is a frame stale, and the disc is six pixels
## across at 900 lines: a stale disc is a missed one, and the flare would
## flicker while you turn.

## The light the sky draws its disc from, read for the disc's size. Empty means
## the first DirectionalLight3D in the scene this layer is instanced in.
@export var sun_path: NodePath

## Where the sun's centre is on screen, 0-1 with y down, like a canvas UV.
## Meaningless while `sun_ahead` is 0.
var sun_uv := Vector2(-1.0, -1.0)
## The disc's radius in the same units, per axis.
var sun_radius := Vector2.ZERO
## 1 while the sun is in front of the camera, 0 while it is behind.
var sun_ahead := 0.0
## 0-1: how much dust is on the lens of the camera on screen.
var dust := 0.0

## How far out along the sun's direction its centre is projected from.
## Anything will do - the sun is at infinity - as long as it is in front of
## the near plane.
const PROJECT_DISTANCE := 1000.0
## The sky's disc when no light says otherwise: the real sun, in degrees.
const DEFAULT_DIAMETER_DEG := 0.53

var _sun: DirectionalLight3D


func _ready() -> void:
	# After every camera rig; see the class note.
	process_priority = 1000
	if not sun_path.is_empty():
		_sun = get_node_or_null(sun_path) as DirectionalLight3D
	elif get_parent() != null:
		var lights := get_parent().find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			_sun = lights[0] as DirectionalLight3D


## The light the disc's size is read from, or null.
func sun_light() -> DirectionalLight3D:
	return _sun


func _process(_delta: float) -> void:
	refresh()


## Work the lens out for the camera on screen and push it to the shader.
func refresh() -> void:
	sun_ahead = 0.0
	dust = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		dust = LensDust.coverage_on(camera)
		_aim(camera)
	RenderingServer.global_shader_parameter_set(&"lens_sun_uv", sun_uv)
	RenderingServer.global_shader_parameter_set(&"lens_sun_radius", sun_radius)
	RenderingServer.global_shader_parameter_set(&"lens_sun_ahead", sun_ahead)
	RenderingServer.global_shader_parameter_set(&"lens_sun_color", World.sun_color)
	RenderingServer.global_shader_parameter_set(&"lens_dust", dust)


## The sun's angular radius, in radians.
func angular_radius() -> float:
	var diameter := DEFAULT_DIAMETER_DEG
	if _sun != null:
		diameter = _sun.light_angular_distance
	return deg_to_rad(diameter) * 0.5


func _aim(camera: Camera3D) -> void:
	var toward := -World.sun_direction()
	var centre := camera.global_position + toward * PROJECT_DISTANCE
	if camera.is_position_behind(centre):
		return
	var size := get_viewport().get_visible_rect().size
	var at := camera.unproject_position(centre)
	# Any direction square to the sun gives the radius. Crossing with the
	# camera's up only fails with the sun 90 degrees above or below the view,
	# far outside the frame, and then its right does instead.
	var side := toward.cross(camera.global_basis.y)
	if side.length_squared() < 1e-6:
		side = toward.cross(camera.global_basis.x)
	var limb := centre + side.normalized() * PROJECT_DISTANCE * tan(angular_radius())
	var r := camera.unproject_position(limb).distance_to(at)
	sun_uv = at / size
	sun_radius = Vector2(r / size.x, r / size.y)
	sun_ahead = 1.0
