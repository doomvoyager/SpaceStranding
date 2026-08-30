extends Node
func _ready() -> void:
	var mat: ShaderMaterial = load("res://shaders/post/film_material.tres")
	print("=== ShaderMaterial property list (shader_parameter/*) ===")
	var n := 0
	for prop in mat.get_property_list():
		var name: String = prop["name"]
		if not name.begins_with("shader_parameter/"):
			continue
		n += 1
		print("  %-38s type=%-2d hint=%-2d hint_string=%-22s usage=%d get()=%s"
			% [name, prop["type"], prop["hint"], prop["hint_string"], prop["usage"], mat.get(name)])
	print("total: %d" % n)
	print("")
	print("=== round trip through get()/set() ===")
	var before = mat.get("shader_parameter/glow_intensity")
	mat.set("shader_parameter/glow_intensity", 1.234)
	print("  set via set():  %s -> %s (get_shader_parameter says %s)"
		% [before, mat.get("shader_parameter/glow_intensity"),
		   mat.get_shader_parameter("glow_intensity")])
	print("")
	print("=== usage flags on one entry ===")
	print("  EDITOR=%d SCRIPT_VARIABLE=%d GROUP=%d"
		% [PROPERTY_USAGE_EDITOR, PROPERTY_USAGE_SCRIPT_VARIABLE, PROPERTY_USAGE_GROUP])
	get_tree().quit(0)
