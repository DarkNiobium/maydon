extends Node
## Renders white silhouette icons of the emote poses → assets/gen/emotes/<clip>.png

const POSES := {"emote_wave": 1.0, "clap": 0.51, "emote_point_sky": 1.0, "emote_flex": 1.0,
	"emote_arms_crossed": 1.0, "celebrate_3": 0.5, "dejected": 1.7, "celebrate_2": 2.05}

func _ready() -> void:
	CharacterView.load_shared()
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.15
	cam.position = Vector3(0, 0.98, 4)
	vp.add_child(cam)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/gen/emotes"))
	for clip in POSES:
		var m: Node3D = (CharacterView._variants[2] as PackedScene).instantiate()
		vp.add_child(m)
		var sk := CharacterView._find(m, "Skeleton3D") as Skeleton3D
		sk.name = "SKEL"
		for mi in _meshes(m):
			(mi as MeshInstance3D).material_override = white
		var ap := AnimationPlayer.new()
		sk.get_parent().add_child(ap)
		ap.root_node = NodePath("..")
		ap.add_animation_library("", CharacterView._lib)
		ap.play(clip)
		ap.seek(POSES[clip], true)
		ap.pause()
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png("res://assets/gen/emotes/%s.png" % clip)
		print("icon ", clip)
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
