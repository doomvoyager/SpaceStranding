extends Node3D
## Measures what the cargo damage model is actually fed, on the real rover over
## real terrain. Diagnostic — prints numbers, never fails.
##
## The thresholds in crate.gd have to sit somewhere specific: above anything
## ordinary driving produces, below anything that ought to cost you. Guessing
## them is how you end up with cargo that rots on a smooth road or survives
## being launched off a ridge.
##
## Two things this probe found that reasoning would not have:
##   - A *parked* loaded rover does not rest at one gravity. VehicleBody3D's
##     sprung chassis keeps working, so there is a real idle jitter to clear.
##   - The astronaut and the rover are wildly different instruments for the
##     same event, because move_and_slide zeroes velocity in a single frame.
##
## Runs as a scene, not via --script, because everything here reaches for World.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/probe_carrier_jolt.tscn

## Long enough for a dropped-in rover to stop bouncing on its own suspension.
const SETTLE := 180
const BASELINE := 90
const CRUISE := 600
## Teleport, then let it get properly into free fall before measuring — free
## fall reads zero, so this is a clean place to clear the teleport artefact.
const FREEFALL := 20
const FALL := 190

var _terrain: ProceduralTerrain
var _rover: Rover
var _astronaut: Astronaut
var _crate: Crate

var _phase := 0
var _phase_frame := 0
var _samples: Array[float] = []
var _raw: Array[float] = []
var _top_speed := 0.0
var _start_pos := Vector3.ZERO


func _ready() -> void:
	_terrain = ProceduralTerrain.new()
	_terrain.size = 256.0
	add_child(_terrain)

	_rover = load("res://scenes/vehicle/rover.tscn").instantiate()
	add_child(_rover)
	_put(_rover, Vector3(0.0, 0.0, 60.0), 1.6)

	_astronaut = load("res://scenes/player/astronaut.tscn").instantiate()
	add_child(_astronaut)
	_put(_astronaut, Vector3(20.0, 0.0, 60.0), 1.2)

	for i in 6:
		var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
		add_child(crate)
		_rover.cargo_rack().load_crate(crate)
	_rover.refresh_load()

	_crate = load("res://scenes/cargo/crate.tscn").instantiate()
	add_child(_crate)
	_put(_crate, Vector3(30.0, 0.0, 60.0), 0.5)

	print("--- carrier jolt probe ---")
	print("free fall reads 0; a still, unsprung body reads one gravity, %.2f m/s^2"
		% World.SURFACE_GRAVITY)


func _put(node: Node3D, at: Vector3, clearance: float) -> void:
	node.global_position = Vector3(
		at.x, _terrain.height_at(at.x, at.z) + clearance, at.z
	)


func _physics_process(_delta: float) -> void:
	_phase_frame += 1
	match _phase:
		0: _settle()
		1: _parked()
		2: _cruise()
		3: _rover_drop()
		4: _astronaut_fall()
		5: _crate_drop()


func _next() -> void:
	_phase += 1
	_phase_frame = 0
	_samples.clear()
	_raw.clear()
	_top_speed = 0.0


# 0 — let everything stop bouncing.
func _settle() -> void:
	if _phase_frame >= SETTLE:
		_next()


# 1 — THE NOISE FLOOR. Whatever this reads, the damage threshold must clear it,
#     or parked cargo decays while nobody is touching it.
func _parked() -> void:
	_samples.append(_rover.cargo_rack().jolt())
	_raw.append(_rover.cargo_rack().raw_jolt())
	if _phase_frame < BASELINE:
		return
	print("")
	print("PARKED, loaded rover — the noise floor to clear")
	_distribution("  rover rack ")
	print("  crate lying loose on the ground: %.2f m/s^2" % _crate.jolt())
	_reset_all()
	_rover.enter(_astronaut)
	Input.action_press("drive_forward")
	_start_pos = _rover.global_position
	_next()


# 2 — the case that must NOT damage cargo: driving hard over broken ground.
func _cruise() -> void:
	_top_speed = maxf(_top_speed, _rover.linear_velocity.length())
	_samples.append(_rover.cargo_rack().jolt())
	_raw.append(_rover.cargo_rack().raw_jolt())
	if _phase_frame < CRUISE:
		return
	Input.action_release("drive_forward")
	print("")
	print("CRUISING loaded, full throttle, %.1f s over broken terrain"
		% (float(CRUISE) / Engine.physics_ticks_per_second))
	print("  top speed %.1f m/s, travelled %.0f m"
		% [_top_speed, _rover.global_position.distance_to(_start_pos)])
	_distribution("  ")
	_damage("  after the drive")
	_rover.exit()
	_next()


# 3 — a real impact: drop the loaded rover onto the terrain.
func _rover_drop() -> void:
	if _phase_frame == 1:
		_put(_rover, Vector3(0.0, 0.0, 0.0), 7.0)
		_rover.linear_velocity = Vector3.ZERO
		_rover.angular_velocity = Vector3.ZERO
		return
	# Clear the teleport artefact while the rover is safely in free fall.
	if _phase_frame == FREEFALL:
		_reset_all()
		return
	if _phase_frame < FREEFALL:
		return
	_samples.append(_rover.cargo_rack().jolt())
	_raw.append(_rover.cargo_rack().raw_jolt())
	if _phase_frame < FREEFALL + FALL:
		return
	print("")
	print("ROVER DROPPED 7 m onto terrain, loaded")
	_distribution("  ")
	_damage("  on landing")
	_next()


# 4 — the astronaut's landing. move_and_slide zeroes velocity in one frame, so
#     this is the case the smoothing exists to make comparable.
func _astronaut_fall() -> void:
	if _phase_frame == 1:
		var back := _astronaut.back_rack()
		for i in 2:
			var crate: Crate = load("res://scenes/cargo/crate.tscn").instantiate()
			add_child(crate)
			back.load_crate(crate)
		_put(_astronaut, Vector3(20.0, 0.0, 0.0), 8.0)
		_astronaut.velocity = Vector3.ZERO
		return
	if _phase_frame == FREEFALL:
		_astronaut.back_rack().reset_jolt()
		for crate in _astronaut.back_rack().crates():
			crate.condition = 1.0
		return
	if _phase_frame < FREEFALL:
		return
	_samples.append(_astronaut.back_rack().jolt())
	_raw.append(_astronaut.back_rack().raw_jolt())
	if _phase_frame < FREEFALL + FALL:
		return
	print("")
	print("ASTRONAUT FELL 8 m carrying 2 crates")
	_distribution("  ")
	print("  worst crate condition %.4f" % _astronaut.back_rack().worst_condition())
	_next()


# 5 — a loose crate measuring itself, no rack involved at all.
func _crate_drop() -> void:
	if _phase_frame == 1:
		_crate.condition = 1.0
		var at := _crate.global_transform
		at.origin = Vector3(30.0, _terrain.height_at(30.0, 0.0) + 5.0, 0.0)
		_crate.release(self, at)
		return
	if _phase_frame < FREEFALL:
		return
	_samples.append(_crate.jolt())
	if _phase_frame < FREEFALL + FALL:
		return
	print("")
	print("LOOSE CRATE DROPPED 5 m, measuring itself")
	_distribution("  ")
	print("  condition %.4f (%s)" % [_crate.condition, _crate.condition_label()])
	print("")
	print("--- end probe ---")
	get_tree().quit(0)


# --- reporting ----------------------------------------------------------

func _distribution(indent: String) -> void:
	if _samples.is_empty():
		print(indent + "no samples")
		return
	var s := _samples.duplicate()
	s.sort()
	print(indent + "smoothed  median %6.2f  p95 %6.2f  p99 %6.2f  max %7.2f"
		% [_pct(s, 0.5), _pct(s, 0.95), _pct(s, 0.99), s[-1]])
	if _raw.is_empty():
		return
	var r := _raw.duplicate()
	r.sort()
	print(indent + "raw       median %6.2f  p95 %6.2f  p99 %6.2f  max %7.2f"
		% [_pct(r, 0.5), _pct(r, 0.95), _pct(r, 0.99), r[-1]])


func _pct(sorted: Array[float], p: float) -> float:
	var i := int(round(p * (sorted.size() - 1)))
	return sorted[clampi(i, 0, sorted.size() - 1)]


func _reset_all() -> void:
	_rover.cargo_rack().reset_jolt()
	for crate in _rover.cargo_rack().crates():
		crate.condition = 1.0


func _damage(label: String) -> void:
	var rack := _rover.cargo_rack()
	print("%s: worst crate condition %.4f (%s)"
		% [label, rack.worst_condition(), rack.crates()[0].condition_label()])
