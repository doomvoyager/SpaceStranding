extends Node3D
## Where the astronaut's eyes are, read off the rig rather than guessed.
##
## The first-person camera has to sit at the figure's eye line, and the figure
## is an imported Mixamo skeleton whose mesh AABB says nothing useful (see the
## FBX entries in CLAUDE.md). The skeleton's rest pose does: this prints the
## world-space rest position of every head and neck bone, and the standing
## height off the topmost bone, all relative to the astronaut's origin at its
## feet. Run as a scene; the astronaut reaches for `World`.

const ASTRONAUT := preload("res://scenes/player/astronaut.tscn")


func _ready() -> void:
	var astronaut: Astronaut = ASTRONAUT.instantiate()
	add_child(astronaut)
	# Two frames so the rig's _ready has run and the skeleton exists.
	await get_tree().process_frame
	await get_tree().process_frame
	var rig := astronaut.get_node("Body/Rig") as AstronautRig
	var skeleton := rig.skeleton()
	if skeleton == null:
		push_error("probe_eye_height: no Skeleton3D in the rig")
		get_tree().quit(1)
		return
	print("skeleton global scale %s, %d bones" % [skeleton.global_transform.basis.get_scale(), skeleton.get_bone_count()])
	var top := 0.0
	var top_name := ""
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		var world := skeleton.global_transform * skeleton.get_bone_global_rest(i).origin
		var local := astronaut.to_local(world)
		if local.y > top:
			top = local.y
			top_name = bone_name
		if "Head" in bone_name or "Neck" in bone_name or "Eye" in bone_name:
			print("%-28s rest at %s  (%.3f m above the feet)" % [bone_name, local, local.y])
	print("topmost bone %s at %.3f m" % [top_name, top])
	print("CamPivot authored at %.2f m" % astronaut.get_node("CamPivot").position.y)
	get_tree().quit(0)
