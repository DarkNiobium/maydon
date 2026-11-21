class_name PitchBuilder
extends RefCounted
## Builds the playable surface, goals, walls and floodlights for a Pitch.
## Venue art (stands, city backdrop) is added separately by VenueBuilder.

const PITCH_SHADER := preload("res://src/view/shaders/pitch.gdshader")
const NET_SHADER := preload("res://src/view/shaders/net.gdshader")


static func build(pitch: Pitch, root: Node3D) -> void:
	_ground(pitch, root)
	for side: int in [-1, 1]:
		_goal(pitch, root, side)
	if pitch.walls:
		_arena_walls(pitch, root)
	else:
		_ad_boards(pitch, root)


static func _mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _ground(pitch: Pitch, root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var pm := PlaneMesh.new()
	var ext := 30.0 if not pitch.walls else 6.0
	pm.size = Vector2(pitch.length + pitch.runoff_x * 2.0 + ext * 2.0, pitch.width + pitch.runoff_z * 2.0 + ext * 2.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = PITCH_SHADER
	sm.set_shader_parameter("hl", pitch.hl())
	sm.set_shader_parameter("hw", pitch.hw())
	sm.set_shader_parameter("box_d", pitch.box_depth)
	sm.set_shader_parameter("box_w", pitch.box_width)
	sm.set_shader_parameter("six_d", pitch.six_depth)
	sm.set_shader_parameter("six_w", pitch.six_width)
	sm.set_shader_parameter("circle_r", pitch.circle_radius)
	sm.set_shader_parameter("pen_spot", pitch.penalty_spot)
	sm.set_shader_parameter("arc_r", pitch.circle_radius if pitch.walls else 9.15)
	sm.set_shader_parameter("cross_mow", not pitch.walls and pitch.surface == Pitch.Surface.GRASS)
	if pitch.surface == Pitch.Surface.TURF:
		sm.set_shader_parameter("turf", true)
		sm.set_shader_parameter("grass_a", Color(0.21, 0.37, 0.15))
		sm.set_shader_parameter("grass_b", Color(0.19, 0.34, 0.14))
		sm.set_shader_parameter("stripes", 10.0)
	var tex_dir := "res://assets/tex/grass/" if pitch.surface == Pitch.Surface.GRASS else "res://assets/tex/turf/"
	if ResourceLoader.exists(tex_dir + "albedo.jpg"):
		sm.set_shader_parameter("detail_tex", load(tex_dir + "albedo.jpg"))
		sm.set_shader_parameter("detail_nrm", load(tex_dir + "normal.jpg"))
		sm.set_shader_parameter("macro_tex", load("res://assets/tex/grass/macro.jpg"))
		sm.set_shader_parameter("has_detail", true)
		sm.set_shader_parameter("detail_scale", 0.45 if pitch.surface == Pitch.Surface.GRASS else 0.9)
	mi.material_override = sm
	root.add_child(mi)


static func _cyl(root: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	var mid := (a + b) * 0.5
	var up := (b - a).normalized()
	var basis := Basis()
	if absf(up.dot(Vector3.UP)) > 0.999:
		basis = Basis.IDENTITY
	else:
		var x := up.cross(Vector3.UP).normalized()
		var z := x.cross(up).normalized()
		basis = Basis(x, up, z)
	mi.transform = Transform3D(basis, mid)
	root.add_child(mi)
	return mi


static func _quad(root: Node3D, center: Vector3, size: Vector2, rot: Basis, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = mat
	mi.transform = Transform3D(rot, center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _net_mat(size: Vector2, cell := 0.11) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = NET_SHADER
	sm.set_shader_parameter("size", size)
	sm.set_shader_parameter("cell", cell)
	sm.set_shader_parameter("thick", 0.13)
	sm.set_shader_parameter("opacity", 0.92)
	return sm


static func _goal(pitch: Pitch, root: Node3D, side: int) -> void:
	var g := Node3D.new()
	g.name = "Goal%d" % side
	root.add_child(g)
	var white := _mat(Color(0.96, 0.96, 0.96), 0.35)
	var dark := _mat(Color(0.25, 0.27, 0.3), 0.5, 0.6)
	var x := pitch.hl() * side
	var gw2 := pitch.goal_width * 0.5 + pitch.post_radius
	var gh := pitch.goal_height + pitch.post_radius
	var r := pitch.post_radius
	var depth := pitch.goal_depth
	_cyl(g, Vector3(x, 0, -gw2), Vector3(x, gh + r, -gw2), r, white)
	_cyl(g, Vector3(x, 0, gw2), Vector3(x, gh + r, gw2), r, white)
	_cyl(g, Vector3(x, gh, -gw2 - r), Vector3(x, gh, gw2 + r), r, white)
	var bx := x + depth * side
	_cyl(g, Vector3(bx, 0, -gw2), Vector3(bx, gh * 0.95, -gw2), 0.03, dark)
	_cyl(g, Vector3(bx, 0, gw2), Vector3(bx, gh * 0.95, gw2), 0.03, dark)
	_cyl(g, Vector3(bx, gh * 0.95, -gw2), Vector3(bx, gh * 0.95, gw2), 0.03, dark)
	_cyl(g, Vector3(x, gh, -gw2), Vector3(bx, gh * 0.95, -gw2), 0.025, dark)
	_cyl(g, Vector3(x, gh, gw2), Vector3(bx, gh * 0.95, gw2), 0.025, dark)
	_cyl(g, Vector3(x, 0.02, -gw2), Vector3(bx, 0.02, -gw2), 0.02, dark)
	_cyl(g, Vector3(x, 0.02, gw2), Vector3(bx, 0.02, gw2), 0.02, dark)
	_cyl(g, Vector3(bx, 0.02, -gw2), Vector3(bx, 0.02, gw2), 0.02, dark)
	# nets
	var back_size := Vector2(gw2 * 2.0, gh)
	_quad(g, Vector3(bx, gh * 0.5, 0), back_size, Basis(Vector3.UP, PI * 0.5), _net_mat(back_size))
	var side_size := Vector2(depth, gh)
	for zs: float in [-1.0, 1.0]:
		_quad(g, Vector3(x + depth * 0.5 * side, gh * 0.5, gw2 * zs), side_size, Basis.IDENTITY, _net_mat(side_size))
	var top_size := Vector2(depth, gw2 * 2.0)
	_quad(g, Vector3(x + depth * 0.5 * side, gh * 0.97, 0), top_size, Basis(Vector3.RIGHT, -PI * 0.5), _net_mat(top_size))


static func _arena_walls(pitch: Pitch, root: Node3D) -> void:
	var w := Node3D.new()
	w.name = "Walls"
	root.add_child(w)
	var hl := pitch.hl()
	var hw := pitch.hw()
	var c := pitch.wall_chamfer
	var board_h := 1.0
	var glass_h := 3.2
	var board := VenueBuilder.pbr("metal_painted", 3.0, Color(0.1, 0.11, 0.14), 0.3)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.85, 0.95, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rail := VenueBuilder.pbr("metal_brushed", 4.0, Color(0.75, 0.77, 0.8), 0.95)
	var gw2 := pitch.goal_width * 0.5 + 0.12
	# wall segments as (a, b) in XZ, skipping the goal openings
	var segs := []
	segs.append([Vector2(-hl + c, -hw), Vector2(hl - c, -hw)])
	segs.append([Vector2(-hl + c, hw), Vector2(hl - c, hw)])
	for s: float in [-1.0, 1.0]:
		segs.append([Vector2(hl * s, -hw + c), Vector2(hl * s, -gw2)])
		segs.append([Vector2(hl * s, gw2), Vector2(hl * s, hw - c)])
		segs.append([Vector2(hl * s - c * s, -hw), Vector2(hl * s, -hw + c)])
		segs.append([Vector2(hl * s - c * s, hw), Vector2(hl * s, hw - c)])
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		var ang := atan2(b.y - a.y, b.x - a.x)
		var basis := Basis(Vector3.UP, -ang)
		var bm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, board_h, 0.12)
		bm.mesh = box
		bm.material_override = board
		bm.transform = Transform3D(basis, Vector3(mid.x, board_h * 0.5, mid.y))
		w.add_child(bm)
		_ad_strip(w, mid, length, basis, board_h, a, b, pitch)
		var gm := MeshInstance3D.new()
		var gq := BoxMesh.new()
		gq.size = Vector3(length, glass_h - board_h, 0.04)
		gm.mesh = gq
		gm.material_override = glass
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gm.transform = Transform3D(basis, Vector3(mid.x, (glass_h + board_h) * 0.5, mid.y))
		w.add_child(gm)
		var rm := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(length, 0.08, 0.16)
		rm.mesh = rb
		rm.material_override = rail
		rm.transform = Transform3D(basis, Vector3(mid.x, glass_h, mid.y))
		w.add_child(rm)
		# steel posts holding the glass + fence
		var n_posts := maxi(int(length / 3.6), 1)
		for k in n_posts + 1:
			var pt := a.lerp(b, float(k) / float(n_posts))
			var post := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = Vector3(0.09, glass_h + 3.5, 0.09)
			post.mesh = pbm
			post.material_override = rail
			post.position = Vector3(pt.x, (glass_h + 3.5) * 0.5, pt.y)
			post.rotation.y = -ang
			w.add_child(post)
		# fence above the glass
		var fsize := Vector2(length, 3.5)
		var fm := _net_mat(fsize, 0.09)
		fm.set_shader_parameter("diamond", true)
		fm.set_shader_parameter("col", Color(0.55, 0.58, 0.6))
		fm.set_shader_parameter("thick", 0.09)
		fm.set_shader_parameter("metal", 0.8)
		_quad(w, Vector3(mid.x, glass_h + 1.75, mid.y), fsize, basis, fm)
	# goal back-walls (the goal is recessed into the wall)
	for s: float in [-1.0, 1.0]:
		var bx := (hl + pitch.goal_depth + 0.15) * s
		var bm2 := MeshInstance3D.new()
		var box2 := BoxMesh.new()
		box2.size = Vector3(0.12, glass_h, gw2 * 2.0 + 0.3)
		bm2.mesh = box2
		bm2.material_override = board
		bm2.transform = Transform3D(Basis.IDENTITY, Vector3(bx, glass_h * 0.5, 0))
		w.add_child(bm2)
		for zs: float in [-1.0, 1.0]:
			var sm2 := MeshInstance3D.new()
			var box3 := BoxMesh.new()
			box3.size = Vector3(pitch.goal_depth + 0.2, glass_h, 0.12)
			sm2.mesh = box3
			sm2.material_override = board
			sm2.transform = Transform3D(Basis.IDENTITY, Vector3((hl + pitch.goal_depth * 0.5) * s, glass_h * 0.5, (gw2 + 0.15) * zs))
			w.add_child(sm2)
		# lintel above the goal
		var lm := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.12, glass_h - pitch.goal_height - 0.1, gw2 * 2.0)
		lm.mesh = lb
		lm.material_override = board
		lm.transform = Transform3D(Basis.IDENTITY, Vector3(hl * s + 0.06 * s, (glass_h + pitch.goal_height + 0.1) * 0.5, 0))
		w.add_child(lm)


static func _ad_strip(w: Node3D, mid: Vector2, length: float, basis: Basis, h: float, a: Vector2, b: Vector2, pitch: Pitch, thick := 0.12) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(length - 0.1, h * 0.8)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	var tex := AdTextures.board_texture()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 0.9
	m.uv1_scale = Vector3(length / 32.0, 1, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# face toward the pitch centre
	var n := Vector3(0, 0, 1)
	var inward := -Vector3(mid.x, 0, mid.y).normalized()
	var face_basis := basis
	if (face_basis * n).dot(inward) < 0.0:
		face_basis = basis * Basis(Vector3.UP, PI)
	var off := (face_basis * n) * (thick * 0.5 + 0.006)
	mi.transform = Transform3D(face_basis, Vector3(mid.x, h * 0.5, mid.y) + off)
	w.add_child(mi)


static func _ad_boards(pitch: Pitch, root: Node3D) -> void:
	var w := Node3D.new()
	w.name = "AdBoards"
	root.add_child(w)
	var bx := pitch.hl() + pitch.runoff_x
	var bz := pitch.hw() + pitch.runoff_z
	var h := 0.9
	var board := _mat(Color(0.05, 0.05, 0.07), 0.5)
	var segs := [[Vector2(-bx, -bz), Vector2(bx, -bz)], [Vector2(-bx, bz), Vector2(bx, bz)],
		[Vector2(-bx, -bz), Vector2(-bx, bz)], [Vector2(bx, -bz), Vector2(bx, bz)]]
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		var ang := atan2(b.y - a.y, b.x - a.x)
		var basis := Basis(Vector3.UP, -ang)
		var bm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, h, 0.2)
		bm.mesh = box
		bm.material_override = board
		bm.transform = Transform3D(basis, Vector3(mid.x, h * 0.5, mid.y))
		w.add_child(bm)
		_ad_strip(w, mid, length, basis, h, a, b, pitch, 0.2)
