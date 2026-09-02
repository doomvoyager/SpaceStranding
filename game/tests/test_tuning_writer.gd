extends Node
## Regression test for writing F1 panel tweaks back into the project.
##
## This is the one system in the game that **edits its own source**, so the cost
## of a mistake is not a wrong number on screen - it is a mangled `.gd` that no
## longer parses, or a silently changed property type. The test is split in two
## so that neither half has to take that risk:
##
##   1. **Patching** runs against fixtures written into `user://`. Every shape
##      of declaration this project actually uses is in there, including the
##      ones that bite: a trailing `:` opening a setter, an `int` that must not
##      acquire a `.0`, and `size` sitting next to `size_min`.
##   2. **Resolution** runs against the real project, read-only. `plan()` never
##      writes, so this can assert that `Terrain.size` lands in the world scene
##      while `Terrain.height_span` lands in `terrain.gd` - the distinction the
##      whole feature turns on - without touching either file.
##
## Nothing here writes to `res://`. If a future change makes it, that is the bug.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot_v4.7.1-stable_win64_console.exe --headless --path game \
##        res://tests/test_tuning_writer.tscn

const SCRIPT_FIXTURE := "user://fixture_tuning.gd.txt"
const SCENE_FIXTURE := "user://fixture_tuning.tscn.txt"
const RESOURCE_FIXTURE := "user://fixture_tuning.tres.txt"

const SCRIPT_TEXT := """extends Node

@export var plain := 1.0
@export_range(0.0, 10.0, 0.1) var ranged := 2.5:
	set(v):
		ranged = v
@export_range(0, 30000, 1) var counted := 9000
@export var flag := true
@export var tint := Color(1.0, 0.42, 0.22)
@export var offset := Vector3(1.0, 2.0, 3.0)
@export var typed: float = 4.0
@export var size_min := 0.5
@export var size := 7.0
@export var commented := 1.0  # do not eat this
var not_exported := 5.0
"""

const SCENE_TEXT := """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://x.gd" id="1"]

[node name="Root" type="Node3D"]
mass = 950.0

[node name="Child" type="Node3D" parent="."]
size = 2048.0
resolution = 4.0

[node name="Deep" type="Node3D" parent="Child"]
value = 1.0
"""

const RESOURCE_TEXT := """[gd_resource type="ShaderMaterial" format=3]

[resource]
resource_name = "Film"
shader_parameter/grain = 0.12
shader_parameter/ca_amount = 0.003
"""

var _failures: Array[String] = []
var _writer := TuningWriter.new()


## The fixture text with LF endings, whatever this source file happens to use.
##
## A `"""..."""` literal in a CRLF source file **contains CRLF** — the constants
## above arrive carrying whatever endings git left on this script. Without this,
## the fixtures are not the line endings the test believes they are, and the
## CRLF case below silently tests "\r\r\n" instead.
static func lf(text: String) -> String:
	return text.replace("\r\n", "\n")


static func crlf(text: String) -> String:
	return lf(text).replace("\n", "\r\n")


func _ready() -> void:
	_check_literals()
	_check_script_patching()
	_check_scene_patching()
	_check_resource_patching()
	_check_apply_round_trip()
	_check_apply_preserves_crlf()
	_check_apply_refuses_a_stale_plan()
	_check_real_project_resolution()
	_cleanup()

	for f in _failures:
		print("FAIL: ", f)
	if _failures.is_empty():
		print("PASS: tuning writer")
		get_tree().quit(0)
		return
	get_tree().quit(1)
	return


func _fail(msg: String) -> void:
	_failures.append(msg)


# --- Literals -----------------------------------------------------------

## The `.0` is the whole point. `var x := 3` declares an int, so a float written
## back without a decimal point changes the property's type and everything
## downstream that divides by it starts doing integer division.
func _check_literals() -> void:
	var cases := [
		[3.5, "3.5"], [2048.0, "2048.0"], [0.0, "0.0"], [-1.0, "-1.0"],
		[0.003, "0.003"], [9000, "9000"], [true, "true"], [false, "false"],
	]
	for case: Array in cases:
		var got := TuningWriter.literal(case[0])
		if got != case[1]:
			_fail("literal(%s) = '%s', expected '%s'" % [case[0], got, case[1]])

	if TuningWriter.literal(Vector3(1.0, 2.5, 3.0)) != "Vector3(1.0, 2.5, 3.0)":
		_fail("Vector3 literal: %s" % TuningWriter.literal(Vector3(1.0, 2.5, 3.0)))
	if TuningWriter.literal(Color(1.0, 0.42, 0.22, 1.0)) != "Color(1.0, 0.42, 0.22, 1.0)":
		_fail("Color literal: %s" % TuningWriter.literal(Color(1.0, 0.42, 0.22, 1.0)))


# --- Patching, against fixtures -----------------------------------------

func _check_script_patching() -> void:
	_put(SCRIPT_FIXTURE, lf(SCRIPT_TEXT))

	_expect_script("plain", 3.5, "@export var plain := 3.5")
	# The trailing colon opens a setter. Losing it takes the setter with it and
	# the file stops parsing.
	_expect_script("ranged", 7.25, "@export_range(0.0, 10.0, 0.1) var ranged := 7.25:")
	_expect_script("counted", 120, "@export_range(0, 30000, 1) var counted := 120")
	_expect_script("flag", false, "@export var flag := false")
	_expect_script("tint", Color(0.5, 0.25, 0.125, 1.0),
		"@export var tint := Color(0.5, 0.25, 0.125, 1.0)")
	_expect_script("offset", Vector3(4.0, 5.0, 6.0),
		"@export var offset := Vector3(4.0, 5.0, 6.0)")
	_expect_script("typed", 9.5, "@export var typed: float = 9.5")
	# `size` must not match the declaration of `size_min` two lines above it.
	_expect_script("size", 12.0, "@export var size := 12.0")
	_expect_script("size_min", 0.75, "@export var size_min := 0.75")

	# A trailing comment would be eaten by the rewrite, so it is refused.
	var edit := TuningWriter.Edit.new()
	_writer._locate_export(edit, SCRIPT_FIXTURE, "commented", 2.0)
	if edit.ok():
		_fail("a commented declaration was rewritten, eating the comment")

	# Only exported vars are tunable, so only exported vars are writable.
	var plain_var := TuningWriter.Edit.new()
	_writer._locate_export(plain_var, SCRIPT_FIXTURE, "not_exported", 2.0)
	if plain_var.ok():
		_fail("a non-exported var was matched")


func _expect_script(prop: String, value: Variant, expected: String) -> void:
	var edit := TuningWriter.Edit.new()
	_writer._locate_export(edit, SCRIPT_FIXTURE, prop, value)
	if not edit.ok():
		_fail("script '%s': %s" % [prop, edit.problem])
		return
	if edit.after != expected:
		_fail("script '%s' became\n    %s\n  expected\n    %s"
			% [prop, edit.after, expected])


func _check_scene_patching() -> void:
	_put(SCENE_FIXTURE, lf(SCENE_TEXT))

	# "." is the root, matching what get_path_to reports for a scene's own root.
	_expect_scene(".", "mass", 700.0, "mass = 700.0")
	_expect_scene("Child", "size", 4096.0, "size = 4096.0")
	_expect_scene("Child", "resolution", 2.0, "resolution = 2.0")
	_expect_scene("Child/Deep", "value", 8.0, "value = 8.0")

	# A property the scene does not override is not the scene's to write - that
	# is exactly the signal that sends the writer to the script default.
	var missing := TuningWriter.Edit.new()
	_writer._locate_in_node(missing, SCENE_FIXTURE, "Child", "nothing_here", 1.0)
	if missing.ok():
		_fail("found a scene line for a property the scene does not carry")

	# `size` is authored under Child, not under Root. Blocks must not leak.
	var wrong_node := TuningWriter.Edit.new()
	_writer._locate_in_node(wrong_node, SCENE_FIXTURE, ".", "size", 1.0)
	if wrong_node.ok():
		_fail("a property from the Child block was found under Root")


func _expect_scene(path: String, prop: String, value: Variant, expected: String) -> void:
	var edit := TuningWriter.Edit.new()
	_writer._locate_in_node(edit, SCENE_FIXTURE, path, prop, value)
	if not edit.ok():
		_fail("scene '%s'.%s: %s" % [path, prop, edit.problem])
		return
	if edit.after != expected:
		_fail("scene '%s'.%s became '%s', expected '%s'"
			% [path, prop, edit.after, expected])


func _check_resource_patching() -> void:
	_put(RESOURCE_FIXTURE, lf(RESOURCE_TEXT))
	var edit := TuningWriter.Edit.new()
	_writer._locate_in_section(edit, RESOURCE_FIXTURE, "[resource]",
		"shader_parameter/grain", 0.4)
	if not edit.ok():
		_fail("resource: %s" % edit.problem)
		return
	if edit.after != "shader_parameter/grain = 0.4":
		_fail("resource became '%s'" % edit.after)


# --- Applying -----------------------------------------------------------

## The file must come back with exactly one line different.
func _check_apply_round_trip() -> void:
	_put(SCRIPT_FIXTURE, lf(SCRIPT_TEXT))
	var edits: Array[TuningWriter.Edit] = []
	for spec: Array in [["plain", 3.5], ["ranged", 7.25], ["counted", 120]]:
		var edit := TuningWriter.Edit.new()
		_writer._locate_export(edit, SCRIPT_FIXTURE, spec[0], spec[1])
		edits.append(edit)

	var result := _writer.apply(edits)
	if int(result["written"]) != 3:
		_fail("apply wrote %s of 3, failures: %s" % [result["written"], result["failed"]])
		return

	var before := lf(SCRIPT_TEXT).split("\n")
	var after := FileAccess.get_file_as_string(SCRIPT_FIXTURE).split("\n")
	if before.size() != after.size():
		_fail("apply changed the line count: %d -> %d" % [before.size(), after.size()])
		return
	var differing := 0
	for i in before.size():
		if before[i] != after[i]:
			differing += 1
	if differing != 3:
		_fail("apply changed %d lines, expected exactly 3" % differing)

	var text := FileAccess.get_file_as_string(SCRIPT_FIXTURE)
	for want: String in [
		"@export var plain := 3.5",
		"@export_range(0.0, 10.0, 0.1) var ranged := 7.25:",
		"@export_range(0, 30000, 1) var counted := 120",
		"		ranged = v",          # the setter body is untouched
		"var not_exported := 5.0",
	]:
		if not text.contains(want):
			_fail("after apply, the file is missing: %s" % want)


## The project's files are CRLF on Windows, so a writer that normalised line
## endings would rewrite every line of a file as a side effect of changing one
## number - a one-line tweak arriving as a whole-file diff.
func _check_apply_preserves_crlf() -> void:
	var source := crlf(SCRIPT_TEXT)
	_put(SCRIPT_FIXTURE, source)

	var edit := TuningWriter.Edit.new()
	_writer._locate_export(edit, SCRIPT_FIXTURE, "plain", 3.5)
	if not edit.ok():
		_fail("CRLF: could not resolve 'plain': %s" % edit.problem)
		return
	if edit.before.contains("\r"):
		_fail("CRLF: the line was read with its separator still attached")

	var edits: Array[TuningWriter.Edit] = [edit]
	if int(_writer.apply(edits)["written"]) != 1:
		_fail("CRLF: apply wrote nothing")
		return

	var after := FileAccess.get_file_as_string(SCRIPT_FIXTURE)
	if after.contains("\n") and not after.contains("\r\n"):
		_fail("CRLF: the file came back with LF endings")
	if after.count("\r\n") != source.count("\r\n"):
		_fail("CRLF: separator count changed, %d -> %d"
			% [source.count("\r\n"), after.count("\r\n")])
	if not after.contains("@export var plain := 3.5\r\n"):
		_fail("CRLF: the value was not written")


## A plan holds line numbers. If the file moved under it, the write must not
## happen - the panel throws a plan away on any slider move, but the editor
## saving the same file is outside its knowledge.
func _check_apply_refuses_a_stale_plan() -> void:
	_put(SCRIPT_FIXTURE, lf(SCRIPT_TEXT))
	var edit := TuningWriter.Edit.new()
	_writer._locate_export(edit, SCRIPT_FIXTURE, "plain", 3.5)

	# Something else edits the file after the plan was made. The separator has to
	# match the fixture's, or the line numbering does not actually shift and the
	# check passes for the wrong reason.
	_put(SCRIPT_FIXTURE, "# a new first line\n" + lf(SCRIPT_TEXT))
	var edits: Array[TuningWriter.Edit] = [edit]
	var result := _writer.apply(edits)

	if int(result["written"]) != 0:
		_fail("a stale plan was written anyway")
	if result["failed"].is_empty():
		_fail("a stale plan reported no problem")
	if FileAccess.get_file_as_string(SCRIPT_FIXTURE).contains("plain := 3.5"):
		_fail("a stale plan changed the file")


# --- Resolution, against the real project (read-only) -------------------

## The distinction the whole feature turns on, checked against the real files:
## `Terrain.size` is overridden in the world scene, `Terrain.height_span` is not
## and is therefore the script's default. Getting these two the wrong way round
## would either write a world value into every terrain in the project, or write
## a project-wide default when one scene was meant.
func _check_real_project_resolution() -> void:
	if not OS.has_feature("editor"):
		_fail("test must run from a non-exported build; resolution is untested")
		return

	var world := (load("res://scenes/world/test_world.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	var terrain := world.get_node("Terrain")
	var rover := get_tree().get_first_node_in_group("rover") as Node
	var wheels: Array[Node] = []
	_collect(rover, "VehicleWheel3D", wheels)

	_expect_home(terrain, "size", "res://scenes/world/test_world.tscn",
		"authored as a node override in the world scene")
	_expect_home(terrain, "height_span", "res://scripts/world/terrain.gd",
		"left at the script default")
	_expect_home(World, "surface_gravity", "res://scripts/core/world_constants.gd",
		"a script autoload has no scene to be overridden in")
	# A wheel's owner is the Rover, not the world, so its built-in suspension
	# properties resolve into rover.tscn and never into the scene that placed it.
	if not wheels.is_empty():
		_expect_home(wheels[0], "suspension_stiffness",
			"res://scenes/vehicle/rover.tscn", "a wheel belongs to the rover scene")

	world.queue_free()


func _expect_home(obj: Object, prop: String, file: String, why: String) -> void:
	var edit := _writer._plan_one(obj, prop, "%s.%s" % [obj, prop])
	if not edit.ok():
		_fail("%s.%s did not resolve (%s): %s" % [obj, prop, why, edit.problem])
		return
	if edit.file != file:
		_fail("%s.%s resolved to %s, expected %s - %s"
			% [obj, prop, edit.file, file, why])
		return
	# The plan is only as good as the line it points at. Split the way the
	# writer does: these files are CRLF on this machine, and splitting on "\n"
	# alone leaves a stray "\r" on every line that never compares equal.
	var text := FileAccess.get_file_as_string(edit.file)
	var lines := text.split("\r\n" if text.contains("\r\n") else "\n")
	if edit.line >= lines.size() or lines[edit.line] != edit.before:
		_fail("%s.%s points at %s:%d, which does not hold what the plan read"
			% [obj, prop, edit.file, edit.line + 1])


func _collect(n: Node, klass: String, out: Array[Node]) -> void:
	if n.is_class(klass):
		out.append(n)
	for c in n.get_children():
		_collect(c, klass, out)


# --- Fixtures -----------------------------------------------------------

func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("could not write the fixture %s" % path)
		return
	f.store_string(text)
	f.close()


func _cleanup() -> void:
	for path: String in [SCRIPT_FIXTURE, SCENE_FIXTURE, RESOURCE_FIXTURE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
