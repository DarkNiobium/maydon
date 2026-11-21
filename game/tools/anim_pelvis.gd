extends Node
func _ready() -> void:
	CharacterView.load_shared()
	var lib: AnimationLibrary = CharacterView._lib
	for clip in ["kick_shot", "kick_pass", "kick_long", "tackle", "slide", "getup", "fall", "jog", "stepover_r", "trap_chest", "header", "gk_dive_r", "celebrate_2"]:
		var a := lib.get_animation(clip)
		var ti := a.find_track(NodePath("SKEL:pelvis"), Animation.TYPE_POSITION_3D)
		if ti < 0:
			print(clip, " no pelvis pos track")
			continue
		var s := ""
		for k in 6:
			var t := a.length * k / 5.0
			var v: Vector3 = a.position_track_interpolate(ti, t)
			s += " (%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
		print(clip, " len %.2f" % a.length, s)
	get_tree().quit()
