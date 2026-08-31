extends Node3D
## What can a headless test actually read back off a MultiMesh?
##
## The rock scatter's regression test asserted that every instance sat on the
## ground - and passed nonsense, because under `--headless` the dummy renderer
## accepts `set_instance_transform()` **without error** and hands identity back
## from `get_instance_transform()`. The same write reads back exactly under the
## real renderer. A test that reads instance transforms headlessly is testing
## the null driver, not the scatter.
##
## So this asks, property by property, which ones survive - and it is meant to
## be run BOTH ways and compared:
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##     res://tests/probe_multimesh_readback.tscn
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_multimesh_readback.tscn
##
## Anything marked DUMMY below is off limits to a headless assertion.

const WANT_ORIGIN := Vector3(1.0, 7.0, -3.0)
const WANT_SCALE := 2.5
const WANT_COUNT := 3
const WANT_AABB := AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 2.0, 8.0))
const WANT_RANGE := 120.0

var _frames := 0


func _physics_process(_d: float) -> void:
	_frames += 1
	if _frames != 2:
		if _frames > 4:
			get_tree().quit(0)
		return

	var mm := MultiMesh.new()
	# transform_format must be set while instance_count is still 0, or Godot
	# refuses the change and every later write lands on a Transform2D multimesh.
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = WANT_COUNT
	mm.set_instance_transform(0, Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * WANT_SCALE), WANT_ORIGIN
	))
	mm.custom_aabb = WANT_AABB

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = WANT_RANGE
	add_child(mmi)

	var got := mm.get_instance_transform(0)
	print("\n--- headless readback (%s) ---" % (
		"dummy renderer" if DisplayServer.get_name() == "headless" else DisplayServer.get_name()
	))
	_row("instance transform origin", got.origin == WANT_ORIGIN, str(got.origin))
	_row("instance transform scale",
		is_equal_approx(got.basis.get_scale().y, WANT_SCALE),
		str(got.basis.get_scale().y))
	_row("instance_count", mm.instance_count == WANT_COUNT, str(mm.instance_count))
	_row("custom_aabb", mm.custom_aabb == WANT_AABB, str(mm.custom_aabb))
	_row("visibility_range_end",
		is_equal_approx(mmi.visibility_range_end, WANT_RANGE),
		str(mmi.visibility_range_end))

	get_tree().quit(0)
	return


func _row(what: String, ok: bool, got: String) -> void:
	print("%-28s %-8s %s" % [what, "SURVIVES" if ok else "DUMMY", got])
