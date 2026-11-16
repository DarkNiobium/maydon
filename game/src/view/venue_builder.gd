class_name VenueBuilder
extends RefCounted
## Environment, lighting and surroundings: a mahalla cage arena among
## Tashkent panel blocks, or a floodlit stadium with terraces and crowd.

const BUILDING_SHADER := preload("res://src/view/shaders/building.gdshader")
const CROWD_SHADER := preload("res://src/view/shaders/crowd.gdshader")

static var crowd_mats: Array = []


static func build(pitch: Pitch, cfg: MatchConfig, root: Node3D, quality: int) -> void:
	crowd_mats.clear()
	_environment(cfg.night, root, quality)
	_lights(pitch, cfg.night, root, quality)
	if pitch.walls or cfg.venue == "arena":
		_arena_surroundings(pitch, cfg, root)
	else:
		_stadium(pitch, cfg, root)


static func set_excite(v: float) -> void:
	for m in crowd_mats:
		(m as ShaderMaterial).set_shader_parameter("excite", v)


static func _environment(night: bool, root: Node3D, quality: int) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	if night:
		psm.sky_top_color = Color(0.01, 0.015, 0.04)
		psm.sky_horizon_color = Color(0.09, 0.08, 0.1)
		psm.ground_bottom_color = Color(0.02, 0.02, 0.02)
		psm.ground_horizon_color = Color(0.08, 0.07, 0.08)
		psm.sun_angle_max = 0.0
		psm.sky_energy_multiplier = 1.0
	else:
		psm.sky_top_color = Color(0.22, 0.42, 0.75)
		psm.sky_horizon_color = Color(0.68, 0.76, 0.85)
		psm.ground_horizon_color = Color(0.6, 0.62, 0.6)
		psm.ground_bottom_color = Color(0.2, 0.2, 0.18)
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.6 if night else 0.9
	env.ambient_light_sky_contribution = 0.6 if night else 1.0
	env.ambient_light_color = Color(0.45, 0.5, 0.6) if night else Color(0.6, 0.65, 0.7)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if quality >= 1 else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	if night:
		env.fog_enabled = quality >= 1
		env.fog_light_color = Color(0.12, 0.13, 0.17)
		env.fog_density = 0.0016
		env.fog_sky_affect = 0.3
	we.environment = env
	root.add_child(we)


static func _lights(pitch: Pitch, night: bool, root: Node3D, quality: int) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0 if quality >= 1 else 40.0
	sun.shadow_blur = 1.2
	if night:
		sun.light_color = Color(0.95, 0.97, 1.0)
		sun.light_energy = 1.35
		sun.rotation_degrees = Vector3(-62, -35, 0)
	else:
		sun.light_color = Color(1.0, 0.95, 0.85)
		sun.light_energy = 1.7
		sun.rotation_degrees = Vector3(-48, -125, 0)
	root.add_child(sun)
	if night:
		# secondary floodlight from the opposite side (no shadows, cheap)
		var fill := DirectionalLight3D.new()
		fill.light_energy = 0.55
		fill.light_color = Color(1.0, 0.96, 0.9)
		fill.rotation_degrees = Vector3(-55, 145, 0)
		fill.shadow_enabled = false
		root.add_child(fill)
		_floodlight_towers(pitch, root)


static func _floodlight_towers(pitch: Pitch, root: Node3D) -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.35, 0.37, 0.4)
	pole_mat.metallic = 0.8
	pole_mat.roughness = 0.4
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1, 1, 1)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.97, 0.9)
	lamp_mat.emission_energy_multiplier = 9.0
	var big := not pitch.walls
	var h := 32.0 if big else 14.0
	var ox := pitch.hl() + (14.0 if big else 3.0)
	var oz := pitch.hw() + (12.0 if big else 3.0)
	var spots := [Vector2(ox, oz), Vector2(-ox, oz), Vector2(ox, -oz), Vector2(-ox, -oz)]
	if not big:
		spots.append(Vector2(0, oz))
		spots.append(Vector2(0, -oz))
	for s in spots:
		var t := Node3D.new()
		t.position = Vector3(s.x, 0, s.y)
		root.add_child(t)
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18 if not big else 0.5
		cm.bottom_radius = 0.28 if not big else 0.9
		cm.height = h
		cm.radial_segments = 10
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.position.y = h * 0.5
		t.add_child(pole)
		var head := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.2, 0.3) if not big else Vector3(7.0, 4.0, 0.6)
		head.mesh = bm
		head.material_override = lamp_mat
		head.position.y = h + bm.size.y * 0.5
		t.add_child(head)
		head.position = Vector3(0, h + bm.size.y * 0.5, 0)
		var to_c := (Vector3.ZERO - t.position)
		to_c.y = 0
		head.rotation.y = atan2(to_c.x, to_c.z)
		head.rotation.x = -0.35


static func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	root.add_child(mi)
	return mi


static func _arena_surroundings(pitch: Pitch, cfg: MatchConfig, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# asphalt / paving around the cage
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 260)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.18, 0.18, 0.19)
	gm.roughness = 0.95
	if ResourceLoader.exists("res://assets/tex/asphalt/albedo.jpg"):
		gm.albedo_texture = load("res://assets/tex/asphalt/albedo.jpg")
		gm.albedo_color = Color(0.7, 0.7, 0.7)
		gm.uv1_scale = Vector3(60, 60, 1)
	ground.material_override = gm
	ground.position.y = -0.02
	root.add_child(ground)
	# ring of 9-storey panel blocks
	var cols := [Color(0.66, 0.63, 0.57), Color(0.72, 0.7, 0.64), Color(0.6, 0.6, 0.62), Color(0.74, 0.66, 0.55)]
	var hl := pitch.hl()
	var hw := pitch.hw()
	var placements := [
		[Vector3(0, 0, -hw - 34.0), 0.0, 72.0], [Vector3(-hl - 40.0, 0, -12.0), PI * 0.5, 60.0],
		[Vector3(hl + 42.0, 0, 6.0), PI * 0.5, 64.0], [Vector3(-20.0, 0, hw + 46.0), 0.0, 60.0],
		[Vector3(48.0, 0, hw + 52.0), 0.35, 48.0], [Vector3(-hl - 34.0, 0, hw + 30.0), -0.6, 40.0],
		[Vector3(hl + 30.0, 0, -hw - 36.0), 0.7, 44.0],
	]
	for pl in placements:
		var floors := 9 if rng.randf() < 0.7 else 5
		var h := floors * 2.9
		var w: float = pl[2]
		var d := 12.0
		var mat := ShaderMaterial.new()
		mat.shader = BUILDING_SHADER
		mat.set_shader_parameter("wall", cols[rng.randi() % cols.size()])
		mat.set_shader_parameter("size", Vector2(w, h))
		mat.set_shader_parameter("floors", float(floors))
		mat.set_shader_parameter("night", 1.0 if cfg.night else 0.0)
		mat.set_shader_parameter("seed", rng.randf() * 10.0)
		var b := _box(root, Vector3(w, h, d), pl[0] + Vector3(0, h * 0.5, 0), mat, pl[1])
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# trees (simple, replaced by proper models when available)
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color(0.25, 0.18, 0.12)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.1, 0.22, 0.08) if cfg.night else Color(0.2, 0.38, 0.12)
	leaf.roughness = 0.95
	for i in 26:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(maxf(hl, hw) + 8.0, maxf(hl, hw) + 24.0)
		var p := Vector3(cos(ang) * r * 1.2, 0, sin(ang) * r * 0.8)
		var th := rng.randf_range(4.0, 8.0)
		var tr := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.2
		cm.height = th
		tr.mesh = cm
		tr.material_override = trunk
		tr.position = p + Vector3(0, th * 0.5, 0)
		root.add_child(tr)
		var cr := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var cr_r := rng.randf_range(2.0, 3.5)
		sm.radius = cr_r
		sm.height = cr_r * 2.2
		sm.radial_segments = 10
		sm.rings = 6
		cr.mesh = sm
		cr.material_override = leaf
		cr.position = p + Vector3(0, th + cr_r * 0.6, 0)
		root.add_child(cr)
	# small spectator stand along one side
	_terrace(root, Vector3(0, 0, -hw - 1.5), pitch.length * 0.7, 5, 0.0, cfg, 0.55)


static func _terrace(root: Node3D, at: Vector3, length: float, rows: int, rot_y: float, cfg: MatchConfig, fill: float, row_d := 0.8, row_h := 0.42) -> void:
	var node := Node3D.new()
	node.position = at
	node.rotation.y = rot_y
	root.add_child(node)
	var depth := rows * row_d
	var height := rows * row_h
	# sloped crowd surface
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var slope_len := sqrt(depth * depth + height * height)
	qm.size = Vector2(length, slope_len)
	mi.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = CROWD_SHADER
	mat.set_shader_parameter("size", Vector2(length, slope_len))
	mat.set_shader_parameter("rows", float(rows))
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("night", 1.0 if cfg.night else 0.0)
	var k0: Dictionary = cfg.kits[0] if cfg.kits.size() > 0 else {}
	var k1: Dictionary = cfg.kits[1] if cfg.kits.size() > 1 else {}
	mat.set_shader_parameter("home_col", k0.get("shirt", Color.RED))
	mat.set_shader_parameter("away_col", k1.get("shirt", Color.BLUE))
	crowd_mats.append(mat)
	mi.material_override = mat
	var ang := atan2(height, depth)
	mi.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + ang), Vector3(0, height * 0.5, -depth * 0.5))
	if at.z > 0.0:
		pass
	node.add_child(mi)
	# concrete under-structure
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.45, 0.45, 0.47)
	_box(node, Vector3(length, height, 0.3), Vector3(0, height * 0.5, -depth - 0.15), cm)


static func _stadium(pitch: Pitch, cfg: MatchConfig, root: Node3D) -> void:
	var hl := pitch.hl() + pitch.runoff_x + 2.0
	var hw := pitch.hw() + pitch.runoff_z + 2.0
	var rows := 34
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.36, 0.36, 0.38)
	conc.roughness = 0.9
	# apron around the pitch
	var ap := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hl * 2.0 + 10.0, hw * 2.0 + 10.0)
	ap.mesh = pm
	ap.material_override = conc
	ap.position.y = -0.03
	root.add_child(ap)
	# four terraces: long sides and ends (each built with its back away from the pitch)
	_terrace(root, Vector3(0, 0.6, -hw), hl * 2.0, rows, 0.0, cfg, 0.88, 0.85, 0.5)
	_terrace(root, Vector3(0, 0.6, hw), hl * 2.0, rows, PI, cfg, 0.88, 0.85, 0.5)
	_terrace(root, Vector3(-hl, 0.6, 0), hw * 2.0, rows - 6, PI * 0.5, cfg, 0.8, 0.85, 0.5)
	_terrace(root, Vector3(hl, 0.6, 0), hw * 2.0, rows - 6, -PI * 0.5, cfg, 0.8, 0.85, 0.5)
	# roofs
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.2, 0.21, 0.23)
	roof.metallic = 0.5
	roof.roughness = 0.5
	var rh := rows * 0.5 + 6.0
	var rd := rows * 0.85 * 0.8
	_box(root, Vector3(hl * 2.0 + 10.0, 0.6, rd), Vector3(0, rh, -hw - rd * 0.5), roof)
	_box(root, Vector3(hl * 2.0 + 10.0, 0.6, rd), Vector3(0, rh, hw + rd * 0.5), roof)
	# light rings under the roof edge
	var lamp := StandardMaterial3D.new()
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.97, 0.9)
	lamp.emission_energy_multiplier = 6.0 if cfg.night else 0.5
	for zs: float in [-1.0, 1.0]:
		_box(root, Vector3(hl * 2.0 - 10.0, 0.4, 0.6), Vector3(0, rh - 0.5, zs * (hw + 1.0)), lamp)
	# city glow / outside
	var outside := MeshInstance3D.new()
	var op := PlaneMesh.new()
	op.size = Vector2(500, 500)
	outside.mesh = op
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.1, 0.1, 0.1)
	outside.material_override = om
	outside.position.y = -0.2
	root.add_child(outside)
