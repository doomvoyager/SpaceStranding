extends Node3D
## Regression test for how the F1 panel is laid out and navigated: folding,
## search, cluster headings, enum dropdowns, and which controls take focus.
##
## `test_debug_panel.tscn` proves the rows exist and write where they should.
## This proves they can be found - which is what the panel was missing when it
## was one two-hundred-row scroll. Everything here fails quietly if it breaks:
## a filter that matches nothing and a fold that never opens both just leave a
## tidy, useless panel.
##
## Runs as a scene rather than via --script so autoloads exist.
## Run: engine/Godot.app/Contents/MacOS/Godot --headless --path game \
##        res://tests/test_debug_panel_ui.tscn

const WORLD := preload("res://scenes/world/test_world.tscn")
const SETTLE := 90
const CLUSTERS := ["DRIVING", "ON FOOT", "WORLD", "NETWORK", "ORDERS AND ROUTES", "INTERFACE"]

var _failures: Array[String] = []
var _frames := 0


func _ready() -> void:
	add_child(WORLD.instantiate())


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames != SETTLE:
		return
	Debug.set_open(true)
	_test_titles_are_stable()
	_test_starts_folded()
	_test_clusters()
	_test_fold_survives_reopen()
	_test_fold_all()
	_test_search()
	_test_search_reads_context()
	_test_heading_click_clears_search()
	_test_enum_dropdown()
	_test_only_text_fields_take_focus()
	_test_closing_releases_the_keyboard()
	_test_readout()
	Debug.set_open(false)
	_finish()


## Titles key the fold state, the session file and every remembered value, so a
## count or a usage note in one would reset all three when a crate spawned.
func _test_titles_are_stable() -> void:
	var bad := PackedStringArray()
	var digits := RegEx.create_from_string("\\d")
	for t in Debug._targets:
		if t.title.contains("—") or t.title.contains(" - ") or digits.search(t.title) != null:
			bad.append(t.title)
	_expect(bad.is_empty(), "titles carrying notes or counts: %s" % ", ".join(bad))


func _test_starts_folded() -> void:
	_expect(Debug._sections.size() >= 20,
		"only %d sections built" % Debug._sections.size())
	var open := 0
	var miscounted := PackedStringArray()
	for section in Debug._sections:
		if section.body.visible or not section.header.text.begins_with(">"):
			open += 1
		var rows := 0
		for child in section.body.get_children():
			if child is HBoxContainer:
				rows += 1
		if rows != section.total or not section.header.text.ends_with("·  %d" % rows):
			miscounted.append("%s (%d rows, header \"%s\")"
				% [section.title, rows, section.header.text])
	_expect(open == 0, "%d section(s) open on first sight; every one should start folded" % open)
	_expect(miscounted.is_empty(), "header counts disagree with the rows: %s"
		% "; ".join(miscounted))
	_expect(Debug._status.text == "%d sections, %d tunables"
		% [Debug._sections.size(), Debug._total_tunables()],
		"status line reads \"%s\"" % Debug._status.text)
	print("%d sections, %d tunables, all folded" % [Debug._sections.size(), Debug._total_tunables()])


func _test_clusters() -> void:
	var names := PackedStringArray()
	for label in Debug._cluster_labels:
		names.append(label.text)
	print("clusters: %s" % ", ".join(names))
	_expect(names == PackedStringArray(CLUSTERS),
		"cluster headings read %s, expected %s" % [names, CLUSTERS])
	# The list opens on the rover: a heading, then its first section.
	var first := Debug._rows.get_child(0) as Label
	var second := Debug._rows.get_child(1) as Button
	_expect(first != null and first.text == "DRIVING" and second != null
		and second.text.contains("ROVER"),
		"the list does not open on DRIVING then ROVER")


func _test_fold_survives_reopen() -> void:
	var rover = _section("Rover")
	if rover == null:
		_expect(false, "no Rover section")
		return
	Debug._toggle_section(rover)
	_expect(rover.body.visible and rover.header.text.begins_with("v"),
		"clicking the Rover heading did not unfold it")
	Debug.set_open(false)
	Debug.set_open(true)
	rover = _section("Rover")
	_expect(rover.body.visible, "the Rover section folded itself again on reopening")
	Debug._toggle_section(rover)
	_expect(not rover.body.visible, "clicking an open heading did not fold it")


func _test_fold_all() -> void:
	Debug._unfold_all()
	var closed := 0
	for section in Debug._sections:
		if not section.body.visible:
			closed += 1
	_expect(closed == 0, "Unfold all left %d section(s) folded" % closed)
	Debug._fold_all()
	var open := 0
	for section in Debug._sections:
		if section.body.visible:
			open += 1
	_expect(open == 0, "Fold all left %d section(s) open" % open)


func _test_search() -> void:
	# Setting LineEdit.text from code does not emit text_changed (GrimdarkTank
	# measured it), so the test drives the filter the way the signal would.
	Debug._filter.text = "jolt"
	Debug._apply_filter()

	var shown_sections := 0
	var wrong_rows := 0
	var shown_rows := 0
	var crates = _section("Crates")
	for section in Debug._sections:
		if not section.header.visible:
			continue
		shown_sections += 1
		var children := section.body.get_children()
		for i in children.size():
			var c := children[i] as Control
			if not c.visible:
				continue
			if not section.is_row[i]:
				wrong_rows += 1
			elif not section.haystacks[i].contains("jolt"):
				wrong_rows += 1
			else:
				shown_rows += 1
	print("\"jolt\": %d row(s) in %d section(s); status \"%s\""
		% [shown_rows, shown_sections, Debug._status.text])
	_expect(shown_rows >= 2, "\"jolt\" found %d rows; the crates alone carry two" % shown_rows)
	_expect(wrong_rows == 0, "%d row(s) or headings visible that do not match \"jolt\"" % wrong_rows)
	_expect(crates != null and crates.body.visible,
		"the Crates section carries jolt_floor but was not opened by the search")
	_expect(Debug._status.text.begins_with("%d of %d tunables" % [shown_rows, Debug._total_tunables()]),
		"status under a filter reads \"%s\"" % Debug._status.text)
	for label in Debug._cluster_labels:
		_expect(not label.visible, "cluster heading %s still showing under a filter" % label.text)

	Debug._filter.text = ""
	Debug._apply_filter()
	_expect(crates != null and not crates.body.visible,
		"clearing the search left Crates open, though it was folded before")
	_expect(Debug._status.text.ends_with("tunables") and not Debug._status.text.contains("match"),
		"clearing the search left the status reading \"%s\"" % Debug._status.text)


## A search reads a row's surroundings, not just its name: the section's note
## and the headings above it.
func _test_search_reads_context() -> void:
	Debug._filter.text = "levelling"
	Debug._apply_filter()
	var rover = _section("Rover")
	var found := 0
	if rover != null:
		for i in rover.body.get_child_count():
			var c := rover.body.get_child(i) as Control
			if c.visible and rover.is_row[i]:
				found += 1
	_expect(found == 3, "\"levelling\" showed %d of the rover's 3 camera levelling rows" % found)

	Debug._filter.text = "rebuilds on release"
	Debug._apply_filter()
	var terrain = _section("Terrain")
	_expect(terrain != null and terrain.header.visible,
		"searching a section's note did not find the section")
	Debug._filter.text = ""
	Debug._apply_filter()


func _test_heading_click_clears_search() -> void:
	var crates = _section("Crates")
	if crates == null:
		return
	Debug._filter.text = "jolt"
	Debug._apply_filter()
	Debug._toggle_section(crates)
	_expect(Debug._filter.text == "", "clicking a heading under a search left the search in place")
	_expect(crates.body.visible, "the clicked heading did not end up open")
	Debug._fold_all()


func _test_enum_dropdown() -> void:
	var crates = _section("Crates")
	var target = null
	for t in Debug._targets:
		if t.title == "Crates":
			target = t
	if crates == null or target == null:
		_expect(false, "no Crates section to find cargo_owner in")
		return
	var option: OptionButton = null
	for row in crates.body.get_children():
		if row is HBoxContainer and (row.get_child(0) as Label).text == "cargo_owner":
			option = row.get_child(1) as OptionButton
	_expect(option != null, "cargo_owner is not a dropdown")
	if option == null:
		return
	_expect(option.item_count == Crate.Owner.size(),
		"cargo_owner offers %d choices for a %d-value enum" % [option.item_count, Crate.Owner.size()])

	var owners := {}
	for c in get_tree().get_nodes_in_group("cargo"):
		owners[c.get_instance_id()] = c.cargo_owner
	option.select(Crate.Owner.FACILITY)
	option.item_selected.emit(Crate.Owner.FACILITY)
	var set := 0
	for c in get_tree().get_nodes_in_group("cargo"):
		if c.cargo_owner == Crate.Owner.FACILITY:
			set += 1
	_expect(set == owners.size(), "choosing Facility reached %d of %d crates" % [set, owners.size()])
	Debug._reset_all()
	var restored := 0
	for c in get_tree().get_nodes_in_group("cargo"):
		if c.cargo_owner == owners[c.get_instance_id()]:
			restored += 1
	_expect(restored == owners.size(), "Reset put %d of %d crate owners back" % [restored, owners.size()])


## The panel is used while driving, and a focused control hears keys and sticks
## that gameplay reads too - see `_button()` in the panel.
func _test_only_text_fields_take_focus() -> void:
	var offenders := PackedStringArray()
	var fields := 0
	var panel_window := Debug._root.get_window()
	for node in Debug._root.find_children("*", "Control", true, false):
		# Each dropdown builds its own PopupMenu, and Godot puts a search
		# LineEdit inside that. The popup is a separate Window that holds input
		# only while its list is open, so it is not a control play can reach.
		if (node as Control).get_window() != panel_window:
			continue
		if node is LineEdit:
			fields += 1
			if (node as Control).focus_mode != Control.FOCUS_CLICK:
				offenders.append("a LineEdit with focus_mode %d" % node.focus_mode)
		elif node is BaseButton or node is Range:
			if (node as Control).focus_mode != Control.FOCUS_NONE:
				offenders.append("%s \"%s\"" % [node.get_class(),
					node.text if node is Button else node.name])
	print("%d text fields; %d focusable non-text control(s)" % [fields, offenders.size()])
	_expect(offenders.is_empty(), "controls that take keyboard focus: %s"
		% ", ".join(offenders.slice(0, 6)))


func _test_closing_releases_the_keyboard() -> void:
	var astronaut := get_tree().get_first_node_in_group("player") as Astronaut
	Debug._filter.grab_focus()
	_expect(astronaut.is_typing(), "the astronaut does not know the search box has the keyboard")
	Debug.set_open(false)
	_expect(not astronaut.is_typing(), "closing F1 left the search box holding the keyboard")
	Debug.set_open(true)


func _test_readout() -> void:
	var text := Debug._readout_text()
	print("readout:\n%s" % text)
	_expect(text.count("\n") >= 2, "the readout is not one subject to a line")
	_expect(text.contains("Hz physics") and text.contains("wheels down"),
		"the readout is missing the tick rate or the wheel contact count")


# --- helpers ------------------------------------------------------------

func _section(title: String):
	for s in Debug._sections:
		if s.title == title:
			return s
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: the panel folds, searches, groups, drops down and keeps its hands off the keyboard.")
		get_tree().quit(0)
		return
	for f in _failures:
		printerr("FAIL: " + f)
	get_tree().quit(1)
