extends SceneTree
func _initialize():
	var inst: Node = load("res://assets/chars/anims.glb").instantiate()
	var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
	print("libs: ", ap.get_animation_library_list(), " anims: ", ap.get_animation_list())
	var a := ap.get_animation(ap.get_animation_list()[0])
	var types := {}
	var pos_bones := []
	for i in a.get_track_count():
		var tt := a.track_get_type(i)
		types[tt] = types.get(tt, 0) + 1
		if tt == Animation.TYPE_POSITION_3D:
			pos_bones.append(String(a.track_get_path(i)))
	print("track types (0=val,1=pos,2=rot,3=scale): ", types)
	print("position tracks: ", pos_bones.slice(0, 6))
	var sk := _find(inst, "Skeleton3D") as Skeleton3D
	print("skeleton path: ", inst.get_path_to(sk), " bones: ", sk.get_bone_count())
	var v: Node = load("res://assets/chars/variants/p01.glb").instantiate()
	var sk2 := _find(v, "Skeleton3D") as Skeleton3D
	print("variant skeleton path: ", v.get_path_to(sk2), " bones: ", sk2.get_bone_count())
	var miss := []
	for b in sk.get_bone_count():
		if sk2.find_bone(sk.get_bone_name(b)) < 0:
			miss.append(sk.get_bone_name(b))
	print("bones missing in variant: ", miss)
	quit()
func _find(n: Node, c: String) -> Node:
	if n.is_class(c):
		return n
	for ch in n.get_children():
		var r := _find(ch, c)
		if r:
			return r
	return null
