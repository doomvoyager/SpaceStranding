@tool
extends RefCounted
class_name RockMesh
## Procedural placeholder boulders, built from a noise-displaced icosphere.
##
## **Placeholder art.** These exist so [[Scatter]] has something to scatter
## before Mac models a real set; `RockScatter.rock_meshes` takes authored meshes
## and these are only used when that array is empty.
##
## Deliberately **flat shaded**. The painterly shader quantises lighting into
## three bands, and a smooth boulder turns those bands into concentric contour
## rings. Faceted, each plane takes one band and reads as a brushed plane -
## which is what the concept paintings do. It is also cheaper to generate: no
## normal averaging, and no index buffer.
##
## An icosphere rather than Godot's `SphereMesh`, which is a UV sphere: its
## poles pinch into a fan of slivers and displacement makes that obvious.

## Golden ratio - the icosahedron's whole construction.
const PHI := 1.618033988749895

## Vertices per shaped rock at each subdivision level: 0 is 20 triangles, 1 is
## 80, 2 is 320, 3 is 1280.
const NEAR_SUBDIVISIONS := 2
const FAR_SUBDIVISIONS := 1


## One rock, as an unindexed flat-shaded mesh sitting in a unit sphere - so a
## uniform scale of `s` gives a boulder `s` metres across.
##
## `roughness` is the fraction of the radius the noise is allowed to move a
## vertex; `squash` multiplies Y, because boulders come to rest wider than tall.
static func build(
	rng_seed: int,
	subdivisions := NEAR_SUBDIVISIONS,
	roughness := 0.34,
	squash := 0.78
) -> ArrayMesh:
	var verts := _base_verts()
	var faces := _base_faces()
	for i in subdivisions:
		faces = _subdivide(verts, faces)

	var shaped := _displace(verts, rng_seed, roughness, squash)
	return _flat_shaded(shaped, verts, faces)


# --- Icosahedron --------------------------------------------------------

static func _base_verts() -> Array[Vector3]:
	var v: Array[Vector3] = [
		Vector3(-1.0, PHI, 0.0), Vector3(1.0, PHI, 0.0),
		Vector3(-1.0, -PHI, 0.0), Vector3(1.0, -PHI, 0.0),
		Vector3(0.0, -1.0, PHI), Vector3(0.0, 1.0, PHI),
		Vector3(0.0, -1.0, -PHI), Vector3(0.0, 1.0, -PHI),
		Vector3(PHI, 0.0, -1.0), Vector3(PHI, 0.0, 1.0),
		Vector3(-PHI, 0.0, -1.0), Vector3(-PHI, 0.0, 1.0),
	]
	for i in v.size():
		v[i] = v[i].normalized()
	return v


static func _base_faces() -> Array:
	return [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]


## Splits every triangle into four, projecting the new midpoints back onto the
## sphere. `verts` grows in place; the returned faces index into it.
static func _subdivide(verts: Array[Vector3], faces: Array) -> Array:
	# Shared edges must produce the *same* midpoint vertex or the mesh cracks
	# open along every edge, so midpoints are cached by their vertex pair.
	var cache := {}
	var out: Array = []
	for f in faces:
		var a: int = f[0]
		var b: int = f[1]
		var c: int = f[2]
		var ab := _midpoint(verts, cache, a, b)
		var bc := _midpoint(verts, cache, b, c)
		var ca := _midpoint(verts, cache, c, a)
		out.append([a, ab, ca])
		out.append([b, bc, ab])
		out.append([c, ca, bc])
		out.append([ab, bc, ca])
	return out


static func _midpoint(verts: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := "%d_%d" % [mini(a, b), maxi(a, b)]
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	var idx := verts.size() - 1
	cache[key] = idx
	return idx


# --- Shaping ------------------------------------------------------------

## Pushes each vertex in or out along its own direction by layered noise, then
## squashes and renormalises so the result fills a unit sphere whatever the
## noise happened to do.
static func _displace(
	verts: Array[Vector3], rng_seed: int, roughness: float, squash: float
) -> Array[Vector3]:
	var noise := FastNoiseLite.new()
	noise.seed = rng_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.3
	noise.fractal_gain = 0.5

	# Noise is sampled on the unit sphere, which spans only [-1, 1] - at the
	# default frequency that is a fraction of one noise cell and every rock
	# comes out a smooth egg. Spreading the sample points is what buys lumps.
	const LUMPS := 1.9

	var out: Array[Vector3] = []
	out.resize(verts.size())
	var longest := 0.0
	for i in verts.size():
		var dir: Vector3 = verts[i]
		var n := noise.get_noise_3d(dir.x * LUMPS, dir.y * LUMPS, dir.z * LUMPS)
		var p := dir * (1.0 + n * roughness)
		p.y *= squash
		out[i] = p
		longest = maxf(longest, p.length())

	# Radius 0.5, so a uniform scale of `s` is a rock `s` metres across and the
	# scatter can talk in diameters.
	var k := 0.5 / maxf(longest, 0.0001)
	for i in out.size():
		out[i] *= k
	return out


# --- Output -------------------------------------------------------------

## Unindexed triangle soup with one normal per face.
##
## `sphere_dirs` is the pre-displacement unit sphere, used only for UVs - the
## painterly material has textures off, but a mesh that ships without UVs
## cannot be textured later without regenerating every rock.
static func _flat_shaded(
	shaped: Array[Vector3], sphere_dirs: Array[Vector3], faces: Array
) -> ArrayMesh:
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()

	for f in faces:
		var ia: int = f[0]
		var ib: int = f[1]
		var ic: int = f[2]
		var a: Vector3 = shaped[ia]
		var b: Vector3 = shaped[ib]
		var c: Vector3 = shaped[ic]
		var centroid := (a + b + c) / 3.0

		# Godot treats CLOCKWISE-wound triangles as front faces: terrain.gd's
		# up-facing quads have (b-a) x (c-a) pointing *down*. So an outward face
		# wants that cross product pointing *inward*, and the true outward
		# normal supplied explicitly. Wound the other way every rock is
		# inside-out and invisible.
		if (b - a).cross(c - a).dot(centroid) > 0.0:
			var swap := b
			b = c
			c = swap
			var swap_i := ib
			ib = ic
			ic = swap_i

		var geo := (b - a).cross(c - a)
		if geo.length_squared() < 1e-12:
			continue
		var normal := -geo.normalized()

		out_v.append(a)
		out_v.append(b)
		out_v.append(c)
		for _i in 3:
			out_n.append(normal)
		out_uv.append(_spherical_uv(sphere_dirs[ia]))
		out_uv.append(_spherical_uv(sphere_dirs[ib]))
		out_uv.append(_spherical_uv(sphere_dirs[ic]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_TEX_UV] = out_uv

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _spherical_uv(dir: Vector3) -> Vector2:
	return Vector2(
		atan2(dir.z, dir.x) / TAU + 0.5,
		acos(clampf(dir.y, -1.0, 1.0)) / PI
	)
