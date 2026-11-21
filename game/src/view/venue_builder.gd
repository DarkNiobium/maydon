class_name VenueBuilder
extends RefCounted
## Environment, lighting and surroundings: a mahalla cage arena among
## Tashkent panel blocks, or a floodlit stadium with terraces and crowd.

const BUILDING_SHADER := preload("res://src/view/shaders/building.gdshader")
const CROWD_SHADER := preload("res://src/view/shaders/crowd.gdshader")
const FAN_SHADER := preload("res://src/view/shaders/fan.gdshader")
const SKY_SHADER := preload("res://src/view/shaders/sky_dome.gdshader")
const SKY_DAY_ROT := 0.248   # puts the HDRI sun behind the KeyLight direction

static var _quality := 1

static var crowd_mats: Array = []
static var _roof_h := 0.0


static func build(pitch: Pitch, cfg: MatchConfig, root: Node3D, quality: int) -> void:
	crowd_mats.clear()
	_roof_h = 0.0
	_quality = quality
	_environment(cfg.night, root, quality)
	_lights(pitch, cfg.night, root, quality)
	if pitch.walls or cfg.venue == "arena":
		_arena_surroundings(pitch, cfg, root)
	else:
		_stadium(pitch, cfg, root)


static func set_excite(v: float) -> void:
	for m in crowd_mats:
		(m as ShaderMaterial).set_shader_parameter("excite", v)


## True when running the desktop Forward+ renderer (SSAO/SSIL/volumetric fog available).
static func forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


static func _environment(night: bool, root: Node3D, quality: int) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var fwd := forward_plus()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	if night:
		sm.set_shader_parameter("pano", load("res://assets/tex/sky/night.jpg"))
		sm.set_shader_parameter("tint", Color(0.42, 0.52, 0.85))
		sm.set_shader_parameter("energy", 0.55)
		sm.set_shader_parameter("rot", 0.5)
		sm.set_shader_parameter("ground_col", Color(0.035, 0.035, 0.04))
		sm.set_shader_parameter("glow_col", Color(0.32, 0.2, 0.1))   # sodium-lit city on the horizon
		sm.set_shader_parameter("glow_h", 0.10)
	else:
		sm.set_shader_parameter("pano", load("res://assets/tex/sky/day.jpg"))
		sm.set_shader_parameter("energy", 1.0)
		sm.set_shader_parameter("rot", SKY_DAY_ROT)
		sm.set_shader_parameter("ground_col", Color(0.16, 0.16, 0.13))
		sm.set_shader_parameter("haze", 0.25)
		sm.set_shader_parameter("haze_col", Color(0.78, 0.82, 0.88))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if quality == 0 else Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if fwd else Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.7 if night else 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if quality >= 1 else Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15 if night else 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if not fwd else Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0 if night else 0.96
	if quality >= 1 and ResourceLoader.exists("res://assets/tex/grade_%s.png" % ("night" if night else "day")):
		env.adjustment_color_correction = load("res://assets/tex/grade_%s.png" % ("night" if night else "day"))
	# Forward+ (desktop): screen-space AO / GI and volumetric floodlight haze
	env.ssao_enabled = fwd and quality >= 2
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = fwd and quality >= 3
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	if night:
		env.fog_enabled = quality >= 1
		env.fog_light_color = Color(0.07, 0.08, 0.11)
		env.fog_density = 0.0012
		env.fog_sky_affect = 0.0
		env.volumetric_fog_enabled = fwd and quality >= 3
		env.volumetric_fog_density = 0.0012
		env.volumetric_fog_albedo = Color(0.9, 0.92, 1.0)
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.0
	else:
		# aerial perspective: distant stands/blocks pick up a little sky haze
		env.fog_enabled = quality >= 1
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color(0.72, 0.78, 0.86)
		env.fog_depth_begin = 60.0
		env.fog_depth_end = 420.0
		env.fog_depth_curve = 1.6
		env.fog_sky_affect = 0.0
		env.fog_density = 0.35
	we.environment = env
	root.add_child(we)


static func _lights(pitch: Pitch, night: bool, root: Node3D, quality: int) -> void:
	var fwd := forward_plus()
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality == 0 else (DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if fwd and quality >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	sun.directional_shadow_max_distance = 80.0 if quality >= 1 else 40.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_blend_splits = quality >= 2
	sun.shadow_blur = 1.0
	sun.shadow_normal_bias = 1.2
	if fwd and quality >= 2:
		# soft contact-hardening shadows (PCSS) from the sun's angular size
		sun.light_angular_distance = 0.6 if not night else 1.5
	if night:
		sun.light_color = Color(0.97, 0.98, 1.0)
		sun.light_energy = 1.25
		sun.light_volumetric_fog_energy = 0.0
		sun.rotation_degrees = Vector3(-62, -35, 0)
	else:
		sun.light_color = Color(1.0, 0.95, 0.87)
		sun.light_energy = 2.2
		sun.rotation_degrees = Vector3(-48, -125, 0)
	root.add_child(sun)
	if night:
		# secondary floodlight from the opposite side (no shadows, cheap)
		var fill := DirectionalLight3D.new()
		fill.light_energy = 0.35
		fill.light_color = Color(1.0, 0.96, 0.9)
		fill.rotation_degrees = Vector3(-55, 145, 0)
		fill.shadow_enabled = false
		fill.light_volumetric_fog_energy = 0.0
		root.add_child(fill)
		_floodlight_towers(pitch, root)


static func _floodlight_towers(pitch: Pitch, root: Node3D) -> void:
	var pole_mat := pbr("metal_brushed", 2.0, Color(0.55, 0.57, 0.6), 0.9)
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
	var lit := 0
	for s in spots:
		var t := Node3D.new()
		t.position = Vector3(s.x, 0, s.y)
		root.add_child(t)
		if lit < 4 and absf(s.x) > 1.0:
			# floodlight: lights the pitch, not the city around it
			lit += 1
			var sl := SpotLight3D.new()
			sl.light_color = Color(1.0, 0.97, 0.92)
			sl.light_energy = 14.0 if big else 7.0
			sl.spot_range = 140.0 if big else 60.0
			sl.spot_angle = 38.0 if big else 50.0
			sl.spot_attenuation = 0.6
			sl.shadow_enabled = false
			sl.light_specular = 0.4
			sl.light_volumetric_fog_energy = 1.0
			root.add_child(sl)
			sl.position = Vector3(s.x, h + 1.0, s.y)
			var aim := Vector3(-s.x * 0.25, 0, -s.y * 0.25)
			sl.look_at(aim, Vector3.UP)
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


## PBR material from assets/tex/<name>/{albedo,normal,rough}.jpg
static func pbr(name: String, uv := 1.0, tint := Color.WHITE, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var d := "res://assets/tex/%s/" % name
	if ResourceLoader.exists(d + "albedo.jpg"):
		m.albedo_texture = load(d + "albedo.jpg")
	if ResourceLoader.exists(d + "normal.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(d + "normal.jpg")
	if ResourceLoader.exists(d + "rough.jpg"):
		m.roughness_texture = load(d + "rough.jpg")
		m.roughness = 1.0
	m.albedo_color = tint
	m.metallic = metal
	m.uv1_scale = Vector3(uv, uv, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


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
	# asphalt + a concrete apron around the cage; the skyline comes from the HDRI sky
	var hl := pitch.hl()
	var hw := pitch.hw()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 320)
	ground.mesh = pm
	ground.material_override = pbr("asphalt", 70.0, Color(0.32, 0.32, 0.34) if cfg.night else Color(0.75, 0.75, 0.75))
	ground.position.y = -0.03
	root.add_child(ground)
	var apron := MeshInstance3D.new()
	var am := PlaneMesh.new()
	am.size = Vector2(pitch.length + 16.0, pitch.width + 16.0)
	apron.mesh = am
	apron.material_override = pbr("concrete_smooth", 10.0, Color(0.62, 0.62, 0.64))
	apron.position.y = -0.015
	root.add_child(apron)
	# trees: crossed-quad impostors rendered from a CC0 Poly Haven tree
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_texture = load("res://assets/gen/tree_atlas.png")
	tree_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tree_mat.alpha_scissor_threshold = 0.4
	tree_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tree_mat.roughness = 0.95
	tree_mat.albedo_color = Color(0.32, 0.36, 0.34) if cfg.night else Color(1, 1, 1)
	tree_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var tm := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var u0 := 0.5 * k
		var ax := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var a := -ax * 0.5
		var b := ax * 0.5
		var verts := [a, b, b + Vector3.UP, a + Vector3.UP]
		var uvs := [Vector2(u0, 1), Vector2(u0 + 0.5, 1), Vector2(u0 + 0.5, 0), Vector2(u0, 0)]
		var nrm := ax.cross(Vector3.UP)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP.lerp(nrm, 0.3).normalized())
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
	tm = st.commit()
	mm.mesh = tm
	var spots := []
	for i in 26:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(maxf(hl, hw) + 14.0, maxf(hl, hw) + 40.0)
		spots.append(Vector3(cos(ang) * r * 1.2, 0, sin(ang) * r * 0.85))
	mm.instance_count = spots.size()
	for i in spots.size():
		var hgt := rng.randf_range(8.0, 13.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(hgt, hgt, hgt))
		mm.set_instance_transform(i, Transform3D(basis, spots[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = tree_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	# no spectators around a 3v3 / 5v5 cage: it's a pickup game, not a stadium


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
	mat.set_shader_parameter("fill", 0.0)
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
	_fans(node, length, rows, row_d, row_h, fill, cfg)
	# concrete under-structure
	var cm := pbr("concrete", 4.0, Color(0.6, 0.6, 0.62))
	_box(node, Vector3(length, height, 0.3), Vector3(0, height * 0.5, -depth - 0.15), cm)


static func _fans(node: Node3D, length: float, rows: int, row_d: float, row_h: float, fill: float, cfg: MatchConfig) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(length * 100.0) + rows
	var dens: float = [0.45, 0.8, 1.0][clampi(_quality, 0, 2)]
	var k0: Dictionary = cfg.kits[0] if cfg.kits.size() > 0 else {}
	var k1: Dictionary = cfg.kits[1] if cfg.kits.size() > 1 else {}
	var home: Color = k0.get("shirt", Color.RED)
	var away: Color = k1.get("shirt", Color.BLUE)
	var spots: Array = []
	var seat := 0.62
	var n_seats := int(length / seat)
	for r in rows:
		for i in n_seats:
			if rng.randf() > fill * dens:
				continue
			var x := -length * 0.5 + (i + 0.5) * seat + rng.randf_range(-0.08, 0.08)
			var y := r * row_h + 0.55
			var z := -(r + 0.55) * row_d
			spots.append(Vector3(x, y, z))
	if spots.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	var atlas := ResourceLoader.exists("res://assets/gen/fans.png")
	qm.size = Vector2(0.78, 1.56) if atlas else Vector2(0.56, 1.1)
	qm.center_offset = Vector3(0, 0.25 if atlas else 0.0, 0)
	mm.mesh = qm
	mm.instance_count = spots.size()
	for i in spots.size():
		var sc := rng.randf_range(0.9, 1.08)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(sc, sc, sc)), spots[i]))
		var roll := rng.randf()
		var c: Color
		if roll < 0.45:
			c = home.lerp(Color.WHITE, rng.randf() * 0.15)
		elif roll < 0.6:
			c = away
		else:
			c = Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.7), rng.randf_range(0.2, 0.9))
		c.a = rng.randf()
		mm.set_instance_custom_data(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = FAN_SHADER
	if ResourceLoader.exists("res://assets/gen/fans.png"):
		mat.set_shader_parameter("atlas", load("res://assets/gen/fans.png"))
		mat.set_shader_parameter("use_atlas", true)
	mat.set_shader_parameter("roof_h", _roof_h)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crowd_mats.append(mat)
	node.add_child(mmi)


static func _stadium(pitch: Pitch, cfg: MatchConfig, root: Node3D) -> void:
	var hl := pitch.hl() + pitch.runoff_x + 2.0
	var hw := pitch.hw() + pitch.runoff_z + 2.0
	var rows := 34
	var conc := pbr("concrete", 12.0, Color(0.55, 0.55, 0.57))
	# apron around the pitch
	var ap := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hl * 2.0 + 10.0, hw * 2.0 + 10.0)
	ap.mesh = pm
	ap.material_override = conc
	ap.position.y = -0.03
	root.add_child(ap)
	_roof_h = rows * 0.5 + 6.0
	# four terraces: long sides and ends (each built with its back away from the pitch)
	_terrace(root, Vector3(0, 0.6, -hw), hl * 2.0, rows, 0.0, cfg, 0.88, 0.85, 0.5)
	_terrace(root, Vector3(0, 0.6, hw), hl * 2.0, rows, PI, cfg, 0.88, 0.85, 0.5)
	_terrace(root, Vector3(-hl, 0.6, 0), hw * 2.0, rows - 6, PI * 0.5, cfg, 0.8, 0.85, 0.5)
	_terrace(root, Vector3(hl, 0.6, 0), hw * 2.0, rows - 6, -PI * 0.5, cfg, 0.8, 0.85, 0.5)
	# roofs
	var roof := pbr("metal_painted", 6.0, Color(0.22, 0.23, 0.26), 0.5)
	var rh := rows * 0.5 + 6.0
	var rd := rows * 0.85 * 0.8
	var rows_e := rows - 6
	var de := rows_e * 0.85
	var dl := rows * 0.85
	var rde := de * 0.8
	_box(root, Vector3(hl * 2.0 + 10.0, 0.6, rd), Vector3(0, rh, -hw - rd * 0.5), roof)
	_box(root, Vector3(hl * 2.0 + 10.0, 0.6, rd), Vector3(0, rh, hw + rd * 0.5), roof)
	_box(root, Vector3(rde, 0.6, hw * 2.0 + 10.0), Vector3(-hl - rde * 0.5, rh, 0), roof)
	_box(root, Vector3(rde, 0.6, hw * 2.0 + 10.0), Vector3(hl + rde * 0.5, rh, 0), roof)
	# roof fascia (front edge) and trusses: reads as a real cantilever roof
	var fascia := pbr("metal_painted", 4.0, Color(0.12, 0.12, 0.14), 0.4)
	for zs: float in [-1.0, 1.0]:
		_box(root, Vector3(hl * 2.0 + 10.0, 1.6, 0.4), Vector3(0, rh - 0.5, zs * (hw + 0.2)), fascia)
		for i in 13:
			var x := -hl + (i / 12.0) * hl * 2.0
			_box(root, Vector3(0.35, 1.2, rd), Vector3(x, rh - 0.9, zs * (hw + rd * 0.5)), fascia)
	for xs: float in [-1.0, 1.0]:
		_box(root, Vector3(0.4, 1.6, hw * 2.0 + 10.0), Vector3(xs * (hl + 0.2), rh - 0.5, 0), fascia)
	# back walls + corner blocks close the bowl (no void between stands)
	var wall := pbr("concrete", 10.0, Color(0.42, 0.42, 0.45))
	var top := rh + 0.3
	for zs: float in [-1.0, 1.0]:
		_box(root, Vector3(hl * 2.0 + 2.0 * de + 4.0, top, 0.6), Vector3(0, top * 0.5, zs * (hw + dl + 1.0)), wall)
	for xs: float in [-1.0, 1.0]:
		_box(root, Vector3(0.6, top, hw * 2.0 + 2.0 * dl + 4.0), Vector3(xs * (hl + de + 1.0), top * 0.5, 0), wall)
		for zs: float in [-1.0, 1.0]:
			var cb := _box(root, Vector3(de + 1.0, top, dl + 1.0), Vector3(xs * (hl + (de + 1.0) * 0.5), top * 0.5, zs * (hw + (dl + 1.0) * 0.5)), wall)
			cb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
