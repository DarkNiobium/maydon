class_name Lobby3D
extends Node3D
## 3D lobby behind the main menu: the player's own footballer on a lit plinth in
## a night stadium (floodlight beams, haze, goal, LED boards), squad pedestals
## for friends, idle + random emotes, drag to rotate, live face portrait.

var model: Node3D
var cam: Camera3D
var face_cam: Camera3D
var _pivot: Node3D
var _anim: AnimationPlayer
var _yaw := 0.35
var _yaw_target := 0.35
var _t := 0.0
var _next_emote := 6.0
var _slots: Array = []           # world positions of the squad pedestals
var _beams: Array = []
var look := {}
var _squad_root: Node3D
var _cam_base := Vector3(0.0, 1.5, 5.0)
var _squad_key := ""
var _mate_anims: Array = []      # AnimationPlayer per mate slot (null = empty)
var _cam_look := Vector3(0, 1.0, 0)
## pedestal layouts per room size: 3v3 = two beside me, 5v5 = a row of four
## behind, 11v11 = two rows of five behind (team-photo terraces), me in front
const LAYOUTS := {
	3: [Vector3(-1.75, 0, -0.9), Vector3(1.75, 0, -0.9)],
	5: [Vector3(-3.2, 0, -1.5), Vector3(-1.15, 0, -1.9), Vector3(1.15, 0, -1.9), Vector3(3.2, 0, -1.5)],
	11: [Vector3(-4.0, 0.3, -2.0), Vector3(-2.0, 0.3, -2.2), Vector3(0.0, 0.3, -2.3), Vector3(2.0, 0.3, -2.2), Vector3(4.0, 0.3, -2.0),
		Vector3(-4.8, 1.1, -4.6), Vector3(-2.4, 1.1, -4.8), Vector3(0.0, 1.1, -4.9), Vector3(2.4, 1.1, -4.8), Vector3(4.8, 1.1, -4.6)],
}

const EMOTES := ["emote_wave", "emote_flex", "emote_arms_crossed", "emote_point_sky", "clap"]


func _ready() -> void:
	_environment()
	_ground()
	_stadium()
	_plinth(Vector3.ZERO, 1.0, true)
	_squad_root = Node3D.new()
	add_child(_squad_root)
	set_squad(3, [])
	_pivot = Node3D.new()
	add_child(_pivot)
	rebuild_character()
	_ball()
	cam = Camera3D.new()
	cam.fov = 36.0
	cam.position = Vector3(0.0, 1.32, 5.0)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true
	_dust()


func slot_positions() -> Array:
	return _slots


## Team-mate pedestals: one per extra room slot (max 4 shown in 3D), with the
## member's own footballer standing on it or an empty hologram.
func set_squad(size: int, mates: Array) -> void:
	var key := str(size) + JSON.stringify(mates)
	if key == _squad_key:
		return
	_squad_key = key
	for c in _squad_root.get_children():
		c.queue_free()
	_slots.clear()
	_mate_anims.clear()
	# the stage grows with the people actually in the room (PUBG / Brawl Stars):
	# alone or with 1-2 mates → two slots beside me; 3-4 → a row behind;
	# 5+ → terraces (two rows of five). The room panel still shows every slot.
	var n_m := mates.size()
	var vis := 3 if n_m <= 2 else (5 if n_m <= 4 else 11)
	if size < vis:
		vis = size
	var layout: Array = LAYOUTS.get(vis, LAYOUTS[3])
	var shown := mini(size - 1, layout.size())
	if vis >= 11 and n_m <= 5:
		shown = mini(shown, 5)
	if vis >= 11:
		# terraces for the two back rows
		var step := StandardMaterial3D.new()
		step.albedo_color = Color(0.05, 0.06, 0.08)
		step.metallic = 0.5
		step.roughness = 0.35
		VenueBuilder._box(_squad_root, Vector3(10.5, 0.3, 1.6), Vector3(0, 0.15, -2.15), step)
		if shown > 5:
			VenueBuilder._box(_squad_root, Vector3(12.4, 1.1, 1.8), Vector3(0, 0.55, -4.75), step)
	for i in shown:
		var p: Vector3 = layout[i]
		var mate: Dictionary = mates[i] if i < mates.size() else {}
		_plinth(p, 0.7, false, _squad_root, not mate.is_empty())
		# empty slot: "+" floats over the pedestal; member: name plate in front of the pedestal
		_slots.append(p + (Vector3(0, 1.1 if vis < 11 else 0.55, 0) if mate.is_empty() else Vector3(0, 2.1, 0)))
		if not mate.is_empty() and CustomCharacter.available():
			var l := Look.default_look()
			var ml: Dictionary = mate.get("look", {}) if typeof(mate.get("look")) == TYPE_DICTIONARY else {}
			for k in ml:
				l[k] = ml[k]
			var m := CustomCharacter.instantiate_look(l)
			_squad_root.add_child(m)
			m.position = p + Vector3(0, 0.017 + 0.04, 0)
			m.rotation.y = -signf(p.x) * 0.35
			var fake := Footballer.new()
			fake.number = 7 + i
			var cv := CharacterView.new()
			cv._model = m
			cv._apply_kit(fake, Game.team_kit(0))
			cv.free()
			CustomCharacter.apply(m, l)
			var sk := CharacterView._find(m, "Skeleton3D") as Skeleton3D
			if sk and CharacterView.load_shared():
				sk.name = "SKEL"
				var ap := AnimationPlayer.new()
				sk.get_parent().add_child(ap)
				ap.root_node = NodePath("..")
				ap.add_animation_library("", CharacterView._lib)
				ap.play(_idle_clip())
				ap.seek(randf() * 3.0, true)
				ap.animation_finished.connect(func(_n: StringName) -> void: ap.play(_idle_clip(), 0.35))
				while _mate_anims.size() < i:
					_mate_anims.append(null)
				_mate_anims.append(ap)
	var fov := 36.0
	if vis >= 11:
		_cam_base = Vector3(0.0, 4.3, 8.8)
		_cam_look = Vector3(0, 1.0, -2.0)
		fov = 44.0
	elif vis >= 5:
		_cam_base = Vector3(0.0, 1.9, 6.6)
		_cam_look = Vector3(0, 1.0, -0.6)
		fov = 40.0
	else:
		_cam_base = Vector3(0.0, 1.5, 5.0)
		_cam_look = Vector3(0, 1.0, 0)
	if cam:
		cam.fov = fov


func rebuild_character() -> void:
	if model:
		model.queue_free()
		model = null
	look = Look.get_look()
	if CustomCharacter.available():
		model = CustomCharacter.instantiate_look(look)
	elif CharacterView.load_shared():
		var v: Array = CharacterView._variants
		model = (v[int(Game.profile.get("face", 0)) % v.size()] as PackedScene).instantiate()
	if model == null:
		return
	_pivot.add_child(model)
	model.position.y = 0.017 + 0.06
	var fake := Footballer.new()
	fake.number = int(Game.profile.get("number", 10))
	var cv := CharacterView.new()
	cv._model = model
	cv._apply_kit(fake, Game.team_kit(0))
	cv.free()
	if not look.is_empty():
		var mm := []
		CustomCharacter._meshes(model, mm)
		for mi in mm:
			(mi as MeshInstance3D).set_instance_shader_parameter("boot_tint", Color.html(str(look.get("boot_color", "#101010"))))
		if CustomCharacter.available():
			CustomCharacter.apply(model, look)
	if CharacterView.load_shared():
		var sk := CharacterView._find(model, "Skeleton3D") as Skeleton3D
		if sk:
			sk.name = "SKEL"
			_anim = AnimationPlayer.new()
			sk.get_parent().add_child(_anim)
			_anim.root_node = NodePath("..")
			_anim.add_animation_library("", CharacterView._lib)
			_anim.play(_idle_clip())
			_anim.animation_finished.connect(func(_n: StringName) -> void:
				_anim.play(_idle_clip(), 0.35))
			_add_face_cam(sk)


static func _idle_clip() -> String:
	return "lobby_idle" if CharacterView._lib.has_animation("lobby_idle") else "idle"


func play_emote(clip: String) -> void:
	if _anim and CharacterView._lib.has_animation(clip):
		_anim.play(clip, 0.3)
		_next_emote = _t + 12.0


func play_mate_emote(slot: int, clip: String) -> void:
	if slot >= 0 and slot < _mate_anims.size() and _mate_anims[slot] != null and CharacterView._lib.has_animation(clip):
		(_mate_anims[slot] as AnimationPlayer).play(clip, 0.3)


func rotate_by(dx: float) -> void:
	_yaw_target += dx * 0.01


func _add_face_cam(sk: Skeleton3D) -> void:
	# portrait camera for the profile avatar (rendered by a SubViewport sharing this world)
	if face_cam == null:
		face_cam = Camera3D.new()
		face_cam.fov = 22.0
		add_child(face_cam)
	var hb := sk.find_bone("head")
	if hb >= 0:
		face_cam.set_meta("head", hb)
		face_cam.set_meta("skel", sk)


func _process(delta: float) -> void:
	_t += delta
	_yaw = lerp_angle(_yaw, _yaw_target, clampf(delta * 6.0, 0.0, 1.0))
	if _pivot:
		_pivot.rotation.y = _yaw
	if cam:
		var sway := Vector3(sin(_t * 0.23) * 0.12, sin(_t * 0.31) * 0.04, 0)
		cam.position = _cam_base + sway
		cam.look_at(_cam_look + sway * 0.3)
	for i in _beams.size():
		var b: MeshInstance3D = _beams[i]
		b.rotation.z = sin(_t * 0.15 + i * 1.7) * 0.05
	if _anim and _t > _next_emote and _anim.current_animation == _idle_clip():
		_next_emote = _t + randf_range(10.0, 16.0)
		play_emote(EMOTES[randi() % EMOTES.size()])
	if face_cam and face_cam.has_meta("skel"):
		var sk: Skeleton3D = face_cam.get_meta("skel")
		if is_instance_valid(sk):
			var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(int(face_cam.get_meta("head"))).origin
			var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
			face_cam.global_position = hp + Vector3(0, 0.07, 0) + fwd * 0.85
			face_cam.look_at(hp + Vector3(0, 0.06, 0))


# ---------------------------------------------------------------------------

func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	if ResourceLoader.exists("res://assets/tex/sky_night.jpg"):
		pm.panorama = load("res://assets/tex/sky_night.jpg")
	pm.energy_multiplier = 0.45
	sky.sky_material = pm
	env.sky = sky
	env.sky_rotation = Vector3(0, 2.2, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.6)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.13, 0.19)
	env.fog_density = 0.035
	env.fog_sky_affect = 0.55
	env.fog_height = 1.5
	env.fog_height_density = 0.05
	we.environment = env
	add_child(we)
	# key light (front, high), rim lights (cool / warm), fill
	var key := SpotLight3D.new()
	key.position = Vector3(1.6, 4.5, 4.0)
	key.look_at_from_position(key.position, Vector3(0, 1.0, 0))
	key.spot_angle = 26.0
	key.spot_range = 14.0
	key.light_energy = 6.0
	key.shadow_enabled = true
	key.shadow_bias = 0.08
	key.shadow_normal_bias = 2.0
	add_child(key)
	for spec: Array in [[Vector3(-2.6, 3.2, -2.6), Color(0.45, 0.75, 1.0), 7.0], [Vector3(2.8, 2.6, -2.4), Color(1.0, 0.72, 0.4), 5.0]]:
		var rim := SpotLight3D.new()
		rim.position = spec[0]
		rim.look_at_from_position(rim.position, Vector3(0, 1.1, 0))
		rim.light_color = spec[1]
		rim.light_energy = spec[2]
		rim.spot_angle = 30.0
		rim.spot_range = 10.0
		add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 3.0, 3.5)
	fill.light_energy = 0.9
	fill.omni_range = 12.0
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)


func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(70, 70)
	g.mesh = pm
	var tex := "turf" if ResourceLoader.exists("res://assets/tex/turf/albedo.jpg") else "grass"
	var m := VenueBuilder.pbr(tex, 40.0, Color(0.55, 0.75, 0.5))
	g.material_override = m
	add_child(g)
	# mown stripes + centre circle markings, faint
	var lines := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 9.08
	tm.outer_radius = 9.15
	tm.rings = 96
	lines.mesh = tm
	lines.scale = Vector3(1, 0.02, 1)
	lines.position = Vector3(0, 0.01, -9.0)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.9, 0.92, 0.9)
	lm.roughness = 0.9
	lines.material_override = lm
	add_child(lines)
	var half := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 0.01, 0.12)
	half.mesh = bm
	half.position = Vector3(0, 0.006, -9.0)
	half.material_override = lm
	add_child(half)


func _plinth(at: Vector3, s: float, main: bool, parent: Node3D = null, occupied := false) -> void:
	if parent == null:
		parent = self
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.95 * s
	cm.bottom_radius = 1.0 * s
	cm.height = 0.06 if main else 0.04
	cm.radial_segments = 6 if main else 48
	base.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.07, 0.09)
	m.metallic = 0.6
	m.roughness = 0.28
	base.material_override = m
	base.position = at + Vector3(0, cm.height * 0.5, 0)
	parent.add_child(base)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.97 * s
	tm.outer_radius = 1.01 * s
	tm.ring_segments = 6
	tm.rings = 6 if main else 48
	ring.mesh = tm
	ring.scale = Vector3(1, 0.3, 1)
	ring.position = at + Vector3(0, cm.height, 0)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var col := UiKit.GOLD if main else Color(0.45, 0.8, 1.0)
	rm.albedo_color = Color(col.r * 2.2, col.g * 2.2, col.b * 2.2)
	ring.material_override = rm
	parent.add_child(ring)
	if not main and not occupied:
		# hologram column for an empty squad slot
		var holo := MeshInstance3D.new()
		var hc := CylinderMesh.new()
		hc.top_radius = 0.55 * s
		hc.bottom_radius = 0.7 * s
		hc.height = 2.2
		hc.cap_top = false
		hc.cap_bottom = false
		holo.mesh = hc
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.35, 0.7, 1.0, 0.0))
		g.set_color(1, Color(0.35, 0.7, 1.0, 0.07))
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		hm.albedo_texture = gt
		holo.material_override = hm
		holo.position = at + Vector3(0, 1.12, 0)
		holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(holo)


func _ball() -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BallSim.R
	sm.height = BallSim.R * 2.0
	b.mesh = sm
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/view/shaders/ball.gdshader")
	b.material_override = bm
	b.position = Vector3(0.42, 0.06 + BallSim.R, 0.38)
	add_child(b)


func _stadium() -> void:
	# goal behind the player
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	white.roughness = 0.35
	var gz := -16.0
	for x in [-3.66, 3.66]:
		VenueBuilder._box(self, Vector3(0.12, 2.44, 0.12), Vector3(x, 1.22, gz), white)
	VenueBuilder._box(self, Vector3(7.44, 0.12, 0.12), Vector3(0, 2.44, gz), white)
	var net := MeshInstance3D.new()
	var nq := QuadMesh.new()
	nq.size = Vector2(7.3, 2.4)
	net.mesh = nq
	var nm := StandardMaterial3D.new()
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	nm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 32:
		img.set_pixel(i, 0, Color(1, 1, 1, 1))
		img.set_pixel(0, i, Color(1, 1, 1, 1))
	nm.albedo_texture = ImageTexture.create_from_image(img)
	nm.uv1_scale = Vector3(40, 13, 1)
	nm.alpha_scissor_threshold = 0.5
	net.material_override = nm
	net.position = Vector3(0, 1.2, gz - 1.6)
	add_child(net)
	# stand silhouette with crowd specks + floodlight towers
	var stand := StandardMaterial3D.new()
	stand.albedo_color = Color(0.05, 0.055, 0.07)
	for k in 6:
		VenueBuilder._box(self, Vector3(60, 1.2, 2.2), Vector3(0, 1.2 + k * 1.15, gz - 6.0 - k * 1.6), stand)
	var crowd_tex := "res://assets/gen/fans.png"
	if ResourceLoader.exists(crowd_tex):
		var cm := StandardMaterial3D.new()
		cm.albedo_texture = load(crowd_tex)
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		cm.alpha_scissor_threshold = 0.5
		cm.albedo_color = Color(0.55, 0.55, 0.6)
		cm.uv1_scale = Vector3(30, 1, 1)
		for k in 5:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(60, 1.4)
			q.mesh = qm
			q.material_override = cm
			q.position = Vector3(0, 2.4 + k * 1.15, gz - 5.0 - k * 1.6)
			add_child(q)
	for x in [-22.0, 22.0]:
		var pole := StandardMaterial3D.new()
		pole.albedo_color = Color(0.12, 0.12, 0.14)
		pole.metallic = 0.8
		VenueBuilder._box(self, Vector3(0.6, 26, 0.6), Vector3(x, 13, gz - 12.0), pole)
		var lamp := StandardMaterial3D.new()
		lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lamp.albedo_color = Color(4.0, 3.9, 3.6)
		VenueBuilder._box(self, Vector3(5.0, 2.4, 0.3), Vector3(x, 26.5, gz - 11.6), lamp)
		pass


func _beam(from: Vector3, to: Vector3) -> void:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var length := from.distance_to(to)
	cm.top_radius = 1.6
	cm.bottom_radius = 9.0
	cm.height = length
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 24
	b.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.9, 0.92, 1.0, 0.0))
	g.set_color(1, Color(0.9, 0.92, 1.0, 0.09))
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	m.albedo_texture = gt
	b.material_override = m
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	add_child(holder)
	holder.position = (from + to) * 0.5
	holder.look_at_from_position(holder.position, to, Vector3.FORWARD if absf((to - from).normalized().y) > 0.99 else Vector3.UP)
	holder.add_child(b)
	b.rotation.x = -PI * 0.5
	_beams.append(b)


func _dust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.0, 1.6, 2.0)
	p.position = Vector3(0, 1.6, 0)
	p.direction = Vector3(0.2, 0.3, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.gravity = Vector3.ZERO
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.018)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.95, 0.85, 0.5)
	qm.material = m
	p.mesh = qm
	add_child(p)
