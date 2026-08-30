extends Node
## Compiles every post shader on the real backend and reports what the driver
## says about it.
##
## The headless dummy renderer does catch outright syntax errors - it is what
## surfaced the missing include - but it is not the compiler that will run on
## Mac's machine. Anything backend-specific only shows on Vulkan, so this runs
## windowed.
##
##   engine/Godot_v4.7.1-stable_win64_console.exe --path game \
##     res://tests/probe_post_shaders.tscn

const SHADERS := [
	"res://shaders/post/lens.gdshader",
	"res://shaders/post/glow.gdshader",
	"res://shaders/post/halation.gdshader",
	"res://shaders/post/grain.gdshader",
	"res://shaders/post/film.gdshader",
	"res://shaders/painterly.gdshader",
]
const MATERIALS := [
	"res://shaders/post/film_material.tres",
]
const SCENES := [
	"res://scenes/postprocessing_effects.tscn",
]


func _ready() -> void:
	print("--- post shader probe ---")

	for path in SHADERS:
		if not ResourceLoader.exists(path):
			print("  MISSING  %s" % path)
			continue
		var shader: Shader = load(path)
		if shader == null:
			print("  FAILED   %s (did not load)" % path)
			continue
		# A shader that failed to compile still loads; ask it what it exposes.
		# A working post shader always has at least one uniform.
		var uniforms := shader.get_shader_uniform_list(true)
		print("  ok       %-42s %2d uniforms" % [path.get_file(), uniforms.size()])

	for path in MATERIALS:
		if not ResourceLoader.exists(path):
			print("  MISSING  %s" % path)
			continue
		var mat: ShaderMaterial = load(path)
		print("  ok       %-42s shader=%s"
			% [path.get_file(), "yes" if mat != null and mat.shader != null else "NO"])

	for path in SCENES:
		if not ResourceLoader.exists(path):
			print("  MISSING  %s" % path)
			continue
		var packed: PackedScene = load(path)
		var node := packed.instantiate()
		add_child(node)
		var rects := 0
		var hidden := 0
		for child in node.get_children():
			var rect := child as ColorRect
			if rect == null:
				continue
			rects += 1
			if not rect.visible:
				hidden += 1
		print("  ok       %-42s %d effect rects, %d hidden"
			% [path.get_file(), rects, hidden])

	# Give the driver a few frames to actually compile and draw them.
	for i in 20:
		await get_tree().process_frame
	print("--- end probe ---")
	get_tree().quit(0)
