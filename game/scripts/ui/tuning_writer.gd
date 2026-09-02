class_name TuningWriter
extends RefCounted
## Writes a tuned value back into the file it was authored in.
##
## One rule, and everything here serves it: **a value goes home to where it
## already lives.** If a scene carries a line for it, that line is updated. If
## nothing does, it is the script's own `@export` default and the `.gd` is
## updated. A shader uniform goes to its material. Nothing is ever *inserted* —
## no new overrides are invented — so the shape of every file is exactly what it
## was, one number different.
##
## That rule is what keeps [[Debug-Panel]] from becoming the second source of
## truth its decision explicitly rejected. The panel still does not hold values;
## it puts them in the inspector, which is where hard rule 3 says they belong.
## The only thing that changed is that you no longer transcribe them by hand.
##
## **Most tunables turn out to be script defaults, not scene values.**
## `rover.tscn`'s root node carries exactly one override — `mass` — and every
## other rover number is a `:=` in `rover.gd`. `World`, `Lattice` and `Orders`
## are script autoloads with no scene anywhere. So the `.gd` writer below is the
## common path and the `.tscn` writer is the exception, which is the opposite of
## what it looks like from the panel.
##
## Planning and applying are separate on purpose. `plan()` reads the files and
## reports exactly which line will change, so the panel can show it before
## anything is written; `apply()` re-checks that each line still says what the
## plan saw, so a plan left sitting while you keep dragging cannot write to a
## line that has moved underneath it.

## One line of one file, and what it will become.
class Edit extends RefCounted:
	## Human-readable "Rover.max_speed", for the report.
	var label := ""
	var file := ""
	## 0-based index into the file's lines. -1 until resolved.
	var line := -1
	var before := ""
	var after := ""
	## Non-empty means this value has nowhere to go, and why.
	var problem := ""

	func ok() -> bool:
		return problem == "" and line >= 0

	func describe() -> String:
		if not ok():
			return "%-34s  --  %s" % [label, problem]
		return "%-34s  %s:%d\n%s    - %s\n%s    + %s" % [
			label, file.trim_prefix("res://"), line + 1,
			"".lpad(34), before.strip_edges(),
			"".lpad(34), after.strip_edges(),
		]


## Resolve `entries` to concrete file edits without touching anything.
##
## Each entry is `{ "obj": Object, "prop": String, "label": String }`. The value
## is read off the object at plan time, so the plan always reflects what the
## sliders currently say.
##
## Edits are deduplicated by file and line. Six wheels tuned together resolve to
## six different lines in `rover.tscn` and all six are kept; seven crates that
## all fall back to the same `@export` default resolve to one line, and one edit
## survives. They cannot disagree — a panel write broadcasts the same value to
## every node in the target before any of this runs.
func plan(entries: Array) -> Array[Edit]:
	var out: Array[Edit] = []
	var seen := {}
	for entry: Dictionary in entries:
		var edit := _plan_one(entry["obj"], entry["prop"], entry["label"])
		if edit.ok():
			var key := "%s:%d" % [edit.file, edit.line]
			if seen.has(key):
				continue
			seen[key] = true
		out.append(edit)
	return out


## Write the plan. Returns `{ "written": int, "files": Array, "failed": Array }`.
func apply(edits: Array[Edit]) -> Dictionary:
	var by_file := {}
	for edit in edits:
		if not edit.ok():
			continue
		if not by_file.has(edit.file):
			by_file[edit.file] = []
		by_file[edit.file].append(edit)

	var written := 0
	var files: Array[String] = []
	var failed: Array[String] = []

	for file: String in by_file:
		var text := _read(file)
		if text == "":
			failed.append("could not read %s" % file)
			continue
		# Godot writes \n, but git and a passing editor can both leave \r\n. Keep
		# whatever is already there rather than rewriting every line of the file
		# as a side effect of changing one number.
		var sep := "\r\n" if text.contains("\r\n") else "\n"
		var lines := text.split(sep)

		var staged := 0
		for edit: Edit in by_file[file]:
			# The plan may be minutes old and the file may have been saved from
			# the editor since. Only write a line that still says what we read.
			if edit.line >= lines.size() or lines[edit.line] != edit.before:
				failed.append("%s:%d changed since the plan was made"
					% [file, edit.line + 1])
				continue
			lines[edit.line] = edit.after
			staged += 1
		if staged == 0:
			continue
		if not _write(file, sep.join(lines)):
			failed.append("could not write %s" % file)
			continue
		written += staged
		files.append(file)

	return {"written": written, "files": files, "failed": failed}


# --- Resolution ---------------------------------------------------------

func _plan_one(obj: Object, prop: String, label: String) -> Edit:
	var edit := Edit.new()
	edit.label = label
	if obj == null:
		edit.problem = "the object is gone"
		return edit
	# An exported build has res:// inside the pack, and nothing below can work.
	# Worth saying plainly rather than failing at the write with a file error.
	if not OS.has_feature("editor"):
		edit.problem = "exported build - res:// is read-only"
		return edit

	var value = obj.get(prop)
	if value == null:
		edit.problem = "no such property"
		return edit

	# A shader uniform lives on the material and nowhere else - there is no
	# script default behind it to fall back to.
	if prop.begins_with("shader_parameter/"):
		var res := obj as Resource
		if res == null or res.resource_path == "":
			edit.problem = "the material has no file of its own"
			return edit
		if res.resource_path.contains("::"):
			edit.problem = "the material is embedded in a scene, not a .tres"
			return edit
		_locate_in_section(edit, res.resource_path, "[resource]", prop, value)
		return edit

	# A scene that already carries a line for this property owns it.
	for candidate: Dictionary in _scene_candidates(obj):
		_locate_in_node(edit, candidate["file"], candidate["path"], prop, value)
		if edit.ok():
			return edit
		edit.problem = ""
		edit.line = -1

	# Otherwise it is the script's own default, which is the common case.
	var script := obj.get_script() as Script
	if script != null and script.resource_path != "":
		_locate_export(edit, script.resource_path, prop, value)
		return edit

	edit.problem = "no scene line and no script default to write to"
	return edit


## Where a node's value could be authored, outermost first.
##
## The order is the one the engine itself uses: an instance override in the
## scene that placed the node beats the value inside the node's own scene, so it
## is tried first. Measured in a probe rather than assumed - a wheel's `owner`
## is the Rover, not the world, so wheels resolve into `rover.tscn` and never
## into `test_world.tscn`.
func _scene_candidates(obj: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var node := obj as Node
	if node == null:
		return out
	if node.owner != null and node.owner.scene_file_path != "":
		out.append({
			"file": node.owner.scene_file_path,
			"path": str(node.owner.get_path_to(node)),
		})
	if node.scene_file_path != "":
		out.append({"file": node.scene_file_path, "path": "."})
	return out


# --- Finding the line ---------------------------------------------------

## A `prop = value` line inside the `[node ...]` block for `path`.
func _locate_in_node(edit: Edit, file: String, path: String,
		prop: String, value: Variant) -> void:
	var lines := _lines(file)
	if lines.is_empty():
		edit.problem = "could not read %s" % file
		return
	for i in lines.size():
		if not lines[i].begins_with("[node "):
			continue
		if _node_path_of(lines[i]) != path:
			continue
		_locate_between(edit, file, lines, i + 1, _section_end(lines, i), prop, value)
		return
	edit.problem = "no node '%s' in %s" % [path, file]


## The same, for a `[resource]` or `[sub_resource]` header given verbatim.
func _locate_in_section(edit: Edit, file: String, header: String,
		prop: String, value: Variant) -> void:
	var lines := _lines(file)
	if lines.is_empty():
		edit.problem = "could not read %s" % file
		return
	for i in lines.size():
		if lines[i].strip_edges() == header:
			_locate_between(edit, file, lines, i + 1, _section_end(lines, i), prop, value)
			return
	edit.problem = "no %s section in %s" % [header, file]


func _locate_between(edit: Edit, file: String, lines: PackedStringArray,
		from: int, to: int, prop: String, value: Variant) -> void:
	var needle := prop + " = "
	for i in range(from, to):
		if not lines[i].begins_with(needle):
			continue
		edit.file = file
		edit.line = i
		edit.before = lines[i]
		edit.after = needle + literal(value)
		return
	edit.problem = "not authored here"


## The `@export ... var <prop> := <value>` line in a script.
##
## The value runs to the end of the line, minus the trailing `:` that opens a
## setter - `@export var height_span := 210.0:` is the common shape in this
## project and losing that colon would take the setter with it.
func _locate_export(edit: Edit, file: String, prop: String, value: Variant) -> void:
	var lines := _lines(file)
	if lines.is_empty():
		edit.problem = "could not read %s" % file
		return
	# The assignment operator is required immediately after the name, so `size`
	# cannot match the declaration of `size_min`.
	var re := RegEx.create_from_string(
		"^(\\s*@export[^\\n]*?\\bvar\\s+" + prop
		+ "\\s*(?::=|:\\s*[A-Za-z_][A-Za-z0-9_.]*\\s*=|=)\\s*)(.*)$")
	if re == null:
		edit.problem = "could not build a matcher for %s" % prop
		return
	for i in lines.size():
		var m := re.search(lines[i])
		if m == null:
			continue
		var rest := m.get_string(2)
		# A trailing comment would be eaten by the rewrite. Refuse rather than
		# quietly delete something someone wrote down on purpose.
		if rest.contains("#"):
			edit.problem = "the declaration carries a comment; set it by hand"
			return
		var tail := ""
		if rest.ends_with(":"):
			tail = ":"
		edit.file = file
		edit.line = i
		edit.before = lines[i]
		edit.after = m.get_string(1) + literal(value) + tail
		return
	edit.problem = "no @export declaration in %s" % file.get_file()


# --- Text helpers -------------------------------------------------------

## Full path of the node a `[node ...]` header declares, within its own scene.
## The scene root is ".", matching what `get_path_to` reports for it.
func _node_path_of(header: String) -> String:
	var name := _attribute(header, "name")
	var parent := _attribute(header, "parent")
	if parent == "":
		return "."
	if parent == ".":
		return name
	return parent + "/" + name


func _attribute(header: String, key: String) -> String:
	var needle := key + "=\""
	var at := header.find(needle)
	if at < 0:
		return ""
	var from := at + needle.length()
	var to := header.find("\"", from)
	return header.substr(from, to - from) if to > from else ""


## Where the section opened at `header` ends: the next line starting a new one.
func _section_end(lines: PackedStringArray, header: int) -> int:
	for i in range(header + 1, lines.size()):
		if lines[i].begins_with("["):
			return i
	return lines.size()


func _lines(file: String) -> PackedStringArray:
	var text := _read(file)
	if text == "":
		return PackedStringArray()
	return text.split("\r\n" if text.contains("\r\n") else "\n")


func _read(file: String) -> String:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _write(file: String, text: String) -> bool:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


# --- Literals -----------------------------------------------------------

## A value as GDScript and `.tscn` both spell it - the two agree for every type
## the panel supports, so there is one function rather than two.
static func literal(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return number(v)
		TYPE_VECTOR3:
			var vec: Vector3 = v
			return "Vector3(%s, %s, %s)" % [number(vec.x), number(vec.y), number(vec.z)]
		TYPE_COLOR:
			var c: Color = v
			return "Color(%s, %s, %s, %s)" % [
				number(c.r), number(c.g), number(c.b), number(c.a)]
	return str(v)


## A float, always with a decimal point.
##
## `var x := 3` declares an **int**. Writing a whole-numbered float back without
## the `.0` silently changes the property's type, and everything downstream that
## divides by it starts doing integer division. `String.num` rather than a
## format string, because GDScript's `%` has no `%g`.
static func number(v: float) -> String:
	var s := String.num(v, 6)
	if not s.contains(".") and not s.contains("e"):
		s += ".0"
	return s
