extends Node3D
## Can a terrain tile be built off the main thread in Godot 4.7.1, and how
## long does one take either way?
##
## The streamed terrain wants to build tiles on `WorkerThreadPool` and only
## add them to the tree on the main thread. Whether the mesh and the collision
## shape can be made on a worker is an engine fact, not something to reason
## about, so this measures it:
##
##   1. Build one 129 x 129 tile on the main thread - heights, arrays, mesh,
##      trimesh - and time each stage.
##   2. Build eight of them on worker threads at once, **polling** for
##      completion from `_process` rather than blocking, and time the wall
##      clock.
##   3. Put a thread-built mesh and shape into the tree, step physics, and
##      raycast down through it. A shape that was built wrong on a thread
##      would show here as a miss, or not at all.
##
## **The first version of this deadlocked.** `Mesh.create_trimesh_shape()`
## fetches the surface arrays back from the RenderingServer, which from a
## worker thread is a synchronous call that waits for the main thread to
## flush the command queue - and the main thread was sitting in
## `wait_for_task_completion`. Every thread printed "mesh done" and none
## printed "trimesh done". So the worker path below builds the
## `ConcavePolygonShape3D` from the arrays it already has, and never asks a
## server for anything back.
##
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_tile_threads.tscn

const SAMPLES := 129
const SPACING := 4.0
const PARALLEL := 8
const FRAME_BUDGET := 600

var _frames := 0
var _threaded: Array = []
var _lock := Mutex.new()
var _ids: Array[int] = []
var _started_usec := 0
var _placed := false
var _placed_frame := 0


func _ready() -> void:
	# --- 1. Main thread, staged.
	var t0 := Time.get_ticks_usec()
	var heights := _heights(0)
	var t1 := Time.get_ticks_usec()
	var arrays := _arrays(heights)
	var t2 := Time.get_ticks_usec()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var t3 := Time.get_ticks_usec()
	var shape := mesh.create_trimesh_shape()
	var t4 := Time.get_ticks_usec()
	var faces_shape := _shape_from_arrays(arrays)
	var t5 := Time.get_ticks_usec()
	print("main thread, one %d x %d tile:" % [SAMPLES, SAMPLES])
	print("  heights            %6.1f ms" % ((t1 - t0) / 1000.0))
	print("  arrays             %6.1f ms" % ((t2 - t1) / 1000.0))
	print("  mesh               %6.1f ms" % ((t3 - t2) / 1000.0))
	print("  create_trimesh     %6.1f ms  (%d faces)" % [(t4 - t3) / 1000.0,
		(shape as ConcavePolygonShape3D).get_faces().size()])
	print("  shape from arrays  %6.1f ms  (%d faces)" % [(t5 - t4) / 1000.0,
		faces_shape.get_faces().size()])

	# --- 2. Worker threads, eight at once, polled.
	_started_usec = Time.get_ticks_usec()
	for i in PARALLEL:
		_ids.append(WorkerThreadPool.add_task(_build_tile.bind(i + 1), true))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > FRAME_BUDGET:
		print("FAIL: frame budget exhausted with %d of %d tiles built"
			% [_threaded.size(), PARALLEL])
		get_tree().quit(1)
		return
	if _placed:
		return
	for id in _ids:
		if not WorkerThreadPool.is_task_completed(id):
			return
	for id in _ids:
		WorkerThreadPool.wait_for_task_completion(id)
	var wall := (Time.get_ticks_usec() - _started_usec) / 1000.0
	print("worker threads, %d tiles at once: %.1f ms wall over %d frames, %d results"
		% [PARALLEL, wall, _frames, _threaded.size()])
	for r: Dictionary in _threaded:
		print("  tile %d  %.1f ms on thread %d, %d faces, surfaces %d"
			% [r.index, r.ms, r.thread, r.faces, r.surfaces])

	# --- 3. A thread-built tile into the tree.
	var first: Dictionary = _threaded[0]
	var mi := MeshInstance3D.new()
	mi.mesh = first.mesh
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = first.shape
	body.add_child(cs)
	add_child(body)
	var read_back: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	print("in tree: mesh vertex count reads back %d (want %d)"
		% [(read_back[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), SAMPLES * SAMPLES])
	_placed = true
	_placed_frame = _frames
	set_meta("index", first.index)


func _physics_process(_delta: float) -> void:
	if not _placed or _frames < _placed_frame + 3:
		return
	var index: int = get_meta("index")
	var space := get_world_3d().direct_space_state
	var hits := 0
	var misses := 0
	var worst := 0.0
	for i in 5:
		var x := 40.0 + i * 80.0
		var z := 60.0 + i * 70.0
		var expected := _height_at(index, x, z)
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(x, 500.0, z), Vector3(x, -500.0, z))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			misses += 1
			print("  ray at (%.0f, %.0f): MISS" % [x, z])
		else:
			hits += 1
			var y := (hit.position as Vector3).y
			worst = maxf(worst, absf(y - expected))
			print("  ray at (%.0f, %.0f): hit y %.3f, heightfield says %.3f"
				% [x, z, y, expected])
	print("raycasts against the thread-built trimesh: %d hit, %d missed, worst %.3f m off"
		% [hits, misses, worst])
	get_tree().quit(0 if misses == 0 and worst < 0.5 else 1)


# --- What a tile build is --------------------------------------------------

func _build_tile(index: int) -> void:
	var t0 := Time.get_ticks_usec()
	var heights := _heights(index)
	var arrays := _arrays(heights)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape := _shape_from_arrays(arrays)
	var t1 := Time.get_ticks_usec()
	# Appending to an Array from several threads is not safe; a mutex around
	# it is.
	_record({
		"index": index,
		"ms": (t1 - t0) / 1000.0,
		"thread": OS.get_thread_caller_id(),
		"faces": shape.get_faces().size(),
		"surfaces": mesh.get_surface_count(),
		"mesh": mesh,
		"shape": shape,
	})


func _record(r: Dictionary) -> void:
	_lock.lock()
	_threaded.append(r)
	_lock.unlock()


## The trimesh from the arrays in hand, without asking the RenderingServer for
## them back - which is what `create_trimesh_shape()` does, and what deadlocks
## a worker. Godot wants the faces as a flat list of triangle corners.
func _shape_from_arrays(arrays: Array) -> ConcavePolygonShape3D:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = verts[indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


func _height_at(index: int, x: float, z: float) -> float:
	# Cheap analytic relief, so the raycast check has an exact answer.
	return 20.0 * sin(x * 0.02 + index) * cos(z * 0.017) + 3.0 * sin(x * 0.11) * sin(z * 0.13)


func _heights(index: int) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(SAMPLES * SAMPLES)
	for z in SAMPLES:
		for x in SAMPLES:
			h[z * SAMPLES + x] = _height_at(index, x * SPACING, z * SPACING)
	return h


func _arrays(heights: PackedFloat32Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(SAMPLES * SAMPLES)
	normals.resize(SAMPLES * SAMPLES)
	uvs.resize(SAMPLES * SAMPLES)
	var inv_2r := 1.0 / (2.0 * SPACING)
	for z in SAMPLES:
		for x in SAMPLES:
			var i := z * SAMPLES + x
			verts[i] = Vector3(x * SPACING, heights[i], z * SPACING)
			var xm := heights[z * SAMPLES + maxi(x - 1, 0)]
			var xp := heights[z * SAMPLES + mini(x + 1, SAMPLES - 1)]
			var zm := heights[maxi(z - 1, 0) * SAMPLES + x]
			var zp := heights[mini(z + 1, SAMPLES - 1) * SAMPLES + x]
			normals[i] = Vector3(-(xp - xm) * inv_2r, 1.0, -(zp - zm) * inv_2r).normalized()
			uvs[i] = Vector2(x * SPACING, z * SPACING) / 16.0
	indices.resize((SAMPLES - 1) * (SAMPLES - 1) * 6)
	var at := 0
	for z in SAMPLES - 1:
		for x in SAMPLES - 1:
			var i := z * SAMPLES + x
			indices[at] = i
			indices[at + 1] = i + 1
			indices[at + 2] = i + SAMPLES
			indices[at + 3] = i + 1
			indices[at + 4] = i + SAMPLES + 1
			indices[at + 5] = i + SAMPLES
			at += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
