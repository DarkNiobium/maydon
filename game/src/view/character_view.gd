class_name CharacterView
extends Node3D
## Skinned footballer: MPFB character + retargeted mocap library.
## Locomotion = BlendSpace2D over local velocity (clips normalised to a 1 s
## cycle so blends stay phase-locked; TimeScale = real cadence → no foot
## sliding). Actions = OneShot whose clip is time-scaled so the foot/head/hand
## contact frame lands exactly on the simulation's contact time.

const KIT_SHADER := preload("res://src/view/shaders/kit.gdshader")
const SKIN_SHADER := preload("res://src/view/shaders/skin_variant.gdshader")
const HAIR_SHADER := preload("res://src/view/shaders/hair_variant.gdshader")
const LOCO_FWD := ["walk", "jog", "run", "sprint"]

static var _skin_nrm: Texture2D = preload("res://assets/tex/skin_normal.png")
static var _fabric_nrm: Texture2D = preload("res://assets/tex/fabric_normal.png")

static var _lib: AnimationLibrary
static var _meta := {}
static var _variants: Array = []
static var _fwd_table: Array = []      # [[speed, freq], ...] sorted
static var _team_mats := {}            # key -> ShaderMaterial (shared per kit)
static var _ref_hip := 1.0              # reference rig pelvis rest height
static var cam_pos := Vector3.ZERO      # set by MatchView each frame (animation LOD)
static var frame := 0
static var ball_node: Node3D            # set by MatchView: heads track the ball
static var ball_pos := Vector3.ZERO     # rendered ball position this frame (set by MatchView before sync)
static var sim_time := 0.0              # simulation clock at the rendered instant
static var sim_owner := -1              # ball carrier id
static var ball_vel := Vector3.ZERO     # simulation ball velocity
static var sim_clock := 0.0             # simulation clock of the latest tick (sim_time <= sim_clock)
static var m1_off := OS.get_environment("MAYDON_NO_M1") != ""   # A/B switch for audits
const TOUCH_IN := 0.2                   # s: foot starts reaching for a planned dribble touch
const TOUCH_OUT := 0.12                 # s: and lets go after it
static var _tris: Array = []            # blend-space triangles: [a, b, c, stride_a, stride_b, stride_c]
static var _pt_pos := {}                # clip -> blend position (local velocity, +x = character left)
static var _pt_stride := {}             # clip -> metres per normalised cycle (vector)
const NEAR_LOD := 24.0                  # m: foot IK + head tracking inside this radius

var pid := -1
var _model: Node3D
var _skel: Skeleton3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _act_node: AnimationNodeAnimation        # current action slot
var _act_slots: Array = []                  # two AnimationNodeAnimation slots (chained actions cross-fade)
var _act_slot := 0
var _in_action := false
var _prev_act := ""         # last action clip fired (kept after it ends; GETUP looks at it)
var _last_seq := -1
var _yaw := 0.0
var _act_clip := ""
var _act_end := 0.0
var _t := 0.0
var _lean := 0.0
var _acc := 0.0
var _leg_k := 1.0
var _planter: FootPlanter
var _look: LookAtModifier3D
var _prev_vel := Vector3.ZERO
var _acc_f := Vector3.ZERO
var _pitch := 0.0
var _roll := 0.0
var _emo_node: AnimationNodeAnimation
var _emo_end := -1.0
var _phase := 0.0          # locomotion cycle phase shown (0 = right foot strike), locked to Footballer.gait
var _cad := 1.0
var _snap_t := -9.0
var _touch_foot := 1
var _touch_pending := false
var _touch_rel_t := -9.0
var _warp := Vector3.ZERO  # visual root offset (world, horizontal) that brings the kicking leg to the ball
var _kick_pending := false
var _kick_rel_t := -9.0
var _kick_leg := 1
var _kick_tgt := Vector3.ZERO
var _leg_len := 0.9
var _dt := 0.016
var _thighs := [-1, -1]   # bone ids thigh_l, thigh_r
var _recv_w := 0.0
var _recv_leg := 1
var _recv_tgt := Vector3.ZERO
static var _web := OS.has_feature("web")   # browser: skip GDScript foot IK / head tracking (CPU)
const UPPER := ["spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
const FINGERS := ["index", "middle", "pinky", "ring", "thumb"]


static func load_shared() -> bool:
	if _lib != null:
		return true
	if not ResourceLoader.exists("res://assets/chars/anims.glb"):
		return false
	var f := FileAccess.open("res://assets/chars/anims.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			_meta = d.get("clips", d)
	var scn: PackedScene = load("res://assets/chars/anims.glb")
	var inst := scn.instantiate()
	var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		inst.free()
		return false
	var rsk := _find(inst, "Skeleton3D") as Skeleton3D
	if rsk:
		_ref_hip = _hip_height(rsk)
	_lib = AnimationLibrary.new()
	for lib_name in ap.get_animation_library_list():
		var src := ap.get_animation_library(lib_name)
		for an in src.get_animation_list():
			var a: Animation = src.get_animation(an).duplicate(true)
			_retarget_paths(a)
			var clip := String(an).get_slice("|", String(an).get_slice_count("|") - 1)
			if clip in LOCO_FWD or clip in ["backpedal", "strafe_l", "strafe_r", "dribble"]:
				_normalise(a, clip)
				a.loop_mode = Animation.LOOP_LINEAR
			elif clip in ["idle", "idle_ready", "lobby_idle"]:
				a.loop_mode = Animation.LOOP_LINEAR
			_lib.add_animation(clip, a)
	inst.free()
	_fwd_table = []
	for c in LOCO_FWD:
		var m: Dictionary = _meta.get(c, {})
		var sp := float(m.get("speed", {"walk": 1.4, "jog": 3.6, "run": 5.5, "sprint": 7.0}[c]))
		var cyc := float(m.get("cycle", {"walk": 1.1, "jog": 0.72, "run": 0.62, "sprint": 0.53}[c]))
		_fwd_table.append([sp, 1.0 / maxf(cyc, 0.2)])
	_fwd_table.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var dir := DirAccess.open("res://assets/chars/variants")
	if dir:
		var files := []
		for fn in dir.get_files():
			var n := fn.trim_suffix(".import")
			if n.ends_with(".glb") and not files.has(n):
				files.append(n)
		files.sort()
		for n in files:
			_variants.append(load("res://assets/chars/variants/" + n))
	return not _variants.is_empty()


static func _hip_height(sk: Skeleton3D) -> float:
	var b := sk.find_bone("pelvis")
	if b < 0:
		return 1.0
	return maxf(sk.get_bone_global_rest(b).origin.y, 0.3)


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


static func _retarget_paths(a: Animation) -> void:
	for i in a.get_track_count():
		var p := a.track_get_path(i)
		if p.get_subname_count() > 0:
			a.track_set_path(i, NodePath("SKEL:" + String(p.get_subname(0))))


static func _normalise(a: Animation, clip: String) -> void:
	var m: Dictionary = _meta.get(clip, {})
	var cyc := float(m.get("cycle", a.length))
	if cyc <= 0.05:
		cyc = a.length
	var k := 1.0 / cyc
	for i in a.get_track_count():
		for j in range(a.track_get_key_count(i) - 1, -1, -1):
			a.track_set_key_time(i, j, a.track_get_key_time(i, j) * k)
	a.length = 1.0


static func cadence(speed: float) -> float:
	if _fwd_table.is_empty():
		return 0.75 + 0.18 * speed
	if speed <= _fwd_table[0][0]:
		return _fwd_table[0][1] * maxf(speed / _fwd_table[0][0], 0.35)
	for i in range(1, _fwd_table.size()):
		if speed <= _fwd_table[i][0]:
			var a: Array = _fwd_table[i - 1]
			var b: Array = _fwd_table[i]
			var w: float = (speed - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(a[1], b[1], w)
	var last: Array = _fwd_table[-1]
	return last[1] * (speed / last[0])


func setup(p: Footballer, kit: Dictionary, other_look := {}) -> void:
	pid = p.id
	var vi := (p.id * 7 + p.number) % _variants.size()
	var look := {}
	if not other_look.is_empty() and CustomCharacter.available():
		# another real player's customised footballer (online rooms)
		look = Look.default_look()
		for k in other_look:
			look[k] = other_look[k]
		_model = CustomCharacter.instantiate_look(look)
	elif p.human == 0 and CustomCharacter.available():
		look = Look.get_look()
		_model = CustomCharacter.instantiate_look(look)
	else:
		if p.human >= 0:
			vi = int(Game.profile.get("face", vi)) % _variants.size()
		_model = (_variants[vi] as PackedScene).instantiate()
	add_child(_model)
	_model.position.y = 0.017   # boot soles sit 1.7 cm below the bare-foot origin
	_skel = _find(_model, "Skeleton3D") as Skeleton3D
	_skel.name = "SKEL"
	# pelvis translation comes from the reference rig: scale it to this body's leg length
	_skel.motion_scale = _hip_height(_skel) / _ref_hip
	_apply_kit(p, kit)
	if not look.is_empty():
		for mi in _meshes(_model):
			(mi as MeshInstance3D).set_instance_shader_parameter("boot_tint", Color.html(str(look.get("boot_color", "#101010"))))
	_player = AnimationPlayer.new()
	_skel.get_parent().add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library("", _lib)
	_build_tree()
	_leg_k = _skel.motion_scale
	_thighs = [_skel.find_bone("thigh_l"), _skel.find_bone("thigh_r")]
	var th := _skel.find_bone("thigh_r")
	var ca := _skel.find_bone("calf_r")
	var ft := _skel.find_bone("foot_r")
	if th >= 0 and ca >= 0 and ft >= 0:
		_leg_len = _skel.get_bone_global_rest(th).origin.distance_to(_skel.get_bone_global_rest(ca).origin) \
			+ _skel.get_bone_global_rest(ca).origin.distance_to(_skel.get_bone_global_rest(ft).origin)
	_add_modifiers()
	_yaw = atan2(p.face.x, p.face.z)


## Foot locking IK + head tracking the ball (skeleton modifiers, near players only).
func _add_modifiers() -> void:
	_planter = FootPlanter.new()
	_planter.name = "FootPlanter"
	_planter.active = false
	_skel.add_child(_planter)
	var head := _skel.find_bone("head")
	if head < 0 or not is_instance_valid(ball_node):
		return
	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	_look.bone_name = "head"
	# pick the head bone's local axes that point forward / up in character space
	var hb := _skel.get_bone_global_rest(head).basis.orthonormalized()
	var sk_fwd := (_skel.global_transform.basis.inverse() * global_transform.basis.z).normalized() if is_inside_tree() else Vector3(0, 0, 1)
	var sk_up := (_skel.global_transform.basis.inverse() * Vector3.UP).normalized() if is_inside_tree() else Vector3.UP
	var lf := hb.inverse() * sk_fwd
	var lu := hb.inverse() * sk_up
	_look.forward_axis = _axis_enum(lf)
	var ua := absf(lu.x)
	_look.primary_rotation_axis = Vector3.AXIS_X
	if absf(lu.y) > ua:
		_look.primary_rotation_axis = Vector3.AXIS_Y
		ua = absf(lu.y)
	if absf(lu.z) > ua:
		_look.primary_rotation_axis = Vector3.AXIS_Z
	_look.use_secondary_rotation = true
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(130.0)
	_look.primary_damp_threshold = 0.7
	_look.secondary_limit_angle = deg_to_rad(70.0)
	_look.secondary_damp_threshold = 0.7
	_look.duration = 0.18
	_look.transition_type = Tween.TRANS_SINE
	_look.influence = 0.0
	_look.active = false
	_skel.add_child(_look)
	_look.target_node = _look.get_path_to(ball_node)


static func _axis_enum(v: Vector3) -> int:
	var ax := v.abs()
	if ax.x >= ax.y and ax.x >= ax.z:
		return SkeletonModifier3D.BONE_AXIS_PLUS_X if v.x > 0 else SkeletonModifier3D.BONE_AXIS_MINUS_X
	if ax.y >= ax.z:
		return SkeletonModifier3D.BONE_AXIS_PLUS_Y if v.y > 0 else SkeletonModifier3D.BONE_AXIS_MINUS_Y
	return SkeletonModifier3D.BONE_AXIS_PLUS_Z if v.z > 0 else SkeletonModifier3D.BONE_AXIS_MINUS_Z


func _apply_kit(p: Footballer, kit: Dictionary) -> void:
	var key := "%s_%s_%s_%d" % [str(kit.get("shirt", "")), str(kit.get("shorts", "")), str(kit.get("socks", "")), int(kit.get("pattern", 0))]
	var mat: ShaderMaterial = _team_mats.get(key)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = KIT_SHADER
		mat.set_shader_parameter("shirt_col", kit.get("shirt", Color.RED))
		mat.set_shader_parameter("shorts_col", kit.get("shorts", Color.WHITE))
		mat.set_shader_parameter("socks_col", kit.get("socks", kit.get("shirt", Color.RED)))
		mat.set_shader_parameter("num_col", kit.get("num", Color.WHITE))
		var sh: Color = kit.get("shirt", Color.RED)
		mat.set_shader_parameter("trim_col", Color.WHITE if sh.get_luminance() < 0.6 else Color(0.1, 0.1, 0.12))
		mat.set_shader_parameter("shirt2_col", (kit.get("shorts", Color.WHITE) as Color))
		mat.set_shader_parameter("pattern", int(kit.get("pattern", 0)) if int(kit.get("pattern", 0)) <= 2 else 0)
		mat.set_shader_parameter("digits", load("res://assets/gen/numbers.png"))
		mat.set_shader_parameter("fabric_nrm", _fabric_nrm)
		mat.set_shader_parameter("has_fabric", true)
		_team_mats[key] = mat
	for mi_v in _meshes(_model):
		var mi := mi_v as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var nm: String = m.resource_name.to_lower() if m else ""
			if nm.begins_with("kit"):
				if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
					mat.set_shader_parameter("base_tex", (m as BaseMaterial3D).albedo_texture)
				mi.set_surface_override_material(s, mat)
			elif nm.begins_with("skin") and m is BaseMaterial3D and mi.get_surface_override_material(s) == null:
				# variants: one shared pore normal for all players, custom skins stay on their own shader
				var sm := ShaderMaterial.new()
				sm.shader = SKIN_SHADER
				if (m as BaseMaterial3D).albedo_texture:
					sm.set_shader_parameter("base_tex", (m as BaseMaterial3D).albedo_texture)
				sm.set_shader_parameter("skin_nrm", _skin_nrm)
				mi.set_surface_override_material(s, sm)
			elif nm.begins_with("hair") and m is BaseMaterial3D and mi.get_surface_override_material(s) == null:
				var hm := ShaderMaterial.new()
				hm.shader = HAIR_SHADER
				if (m as BaseMaterial3D).albedo_texture:
					hm.set_shader_parameter("hair_tex", (m as BaseMaterial3D).albedo_texture)
				mi.set_surface_override_material(s, hm)
		mi.set_instance_shader_parameter("number", p.number)
		var boots := [Color(0.06, 0.06, 0.06), Color(0.95, 0.95, 0.95), Color(1.0, 0.45, 0.05), Color(0.1, 0.35, 0.95), Color(0.9, 0.1, 0.4)]
		mi.set_instance_shader_parameter("boot_tint", boots[(p.id * 3 + p.number) % boots.size()])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-4.0, -4.0)
	bs.max_space = Vector2(4.0, 9.0)
	bs.sync = true
	if _pt_pos.is_empty():
		_init_points()
	bs.auto_triangles = false
	var idx := {}
	for c in _pt_pos:
		var an := AnimationNodeAnimation.new()
		an.animation = c
		idx[c] = bs.get_blend_point_count()
		bs.add_blend_point(an, _pt_pos[c], -1, StringName(c))
	# explicit triangulation (fans around the forward axis), shared with stride_at()
	var tris := [["idle", "strafe_l", "walk"], ["walk", "strafe_l", "jog"], ["jog", "strafe_l", "run"], ["run", "strafe_l", "sprint"],
		["idle", "walk", "strafe_r"], ["walk", "jog", "strafe_r"], ["jog", "run", "strafe_r"], ["run", "sprint", "strafe_r"],
		["idle", "backpedal", "strafe_l"], ["idle", "strafe_r", "backpedal"]]
	var build := _tris.is_empty()
	for t: Array in tris:
		if not (idx.has(t[0]) and idx.has(t[1]) and idx.has(t[2])):
			continue
		bs.add_triangle(idx[t[0]], idx[t[1]], idx[t[2]])
		if build:
			_tris.append([_pt_pos[t[0]], _pt_pos[t[1]], _pt_pos[t[2]], _pt_stride[t[0]], _pt_stride[t[1]], _pt_stride[t[2]]])
	bt.add_node("loco", bs, Vector2(0, 0))
	var seek := AnimationNodeTimeSeek.new()
	bt.add_node("seek", seek, Vector2(100, 0))
	bt.connect_node("seek", 0, "loco")
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("ts", ts, Vector2(200, 0))
	bt.connect_node("ts", 0, "seek")
	# main = transition loco | action slot 0 | action slot 1. An action that follows another
	# (fall -> get-up, kick -> kick) cross-fades pose to pose instead of through the running pose;
	# the view ends actions itself at the clip end (_act_end) with a 0.18 s blend back to locomotion.
	var main := AnimationNodeTransition.new()
	main.input_count = 3
	main.set_input_name(0, "loco")
	main.set_input_name(1, "s0")
	main.set_input_name(2, "s1")
	main.set_input_reset(0, false)
	main.set_input_reset(1, true)
	main.set_input_reset(2, true)
	main.xfade_time = 0.07
	bt.add_node("main", main, Vector2(400, 100))
	bt.connect_node("main", 0, "ts")
	_act_slots.clear()
	for i in 2:
		var an := AnimationNodeAnimation.new()
		an.animation = "idle"
		bt.add_node("act%d" % i, an, Vector2(0, 160 + 90 * i))
		var ats := AnimationNodeTimeScale.new()
		bt.add_node("act_ts%d" % i, ats, Vector2(150, 160 + 90 * i))
		bt.connect_node("act_ts%d" % i, 0, "act%d" % i)
		bt.connect_node("main", i + 1, "act_ts%d" % i)
		_act_slots.append(an)
	_act_node = _act_slots[0]
	# upper-body emote layer (wave, clap, ... also while running)
	_emo_node = AnimationNodeAnimation.new()
	_emo_node.animation = "idle"
	bt.add_node("emo", _emo_node, Vector2(400, 300))
	var eos := AnimationNodeOneShot.new()
	eos.fadein_time = 0.2
	eos.fadeout_time = 0.3
	eos.filter_enabled = true
	for b in UPPER:
		eos.set_filter_path(NodePath("SKEL:" + b), true)
	for side in ["l", "r"]:
		for f in FINGERS:
			for k in ["01", "02", "03"]:
				eos.set_filter_path(NodePath("SKEL:%s_%s_%s" % [f, k, side]), true)
	bt.add_node("emote_os", eos, Vector2(600, 150))
	bt.connect_node("emote_os", 0, "main")
	bt.connect_node("emote_os", 1, "emo")
	bt.connect_node("output", 0, "emote_os")
	_tree = AnimationTree.new()
	_tree.tree_root = bt
	_tree.anim_player = _tree.get_path_to(_player) if _tree.is_inside_tree() else NodePath("")
	_skel.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.active = true


## Blend points at each clip's measured velocity (character space: +x = left,
## +y = forward) and the distance its feet cover per normalised cycle.
static func _init_points() -> void:
	var defs := {"idle": Vector2.ZERO, "walk": Vector2(0, 1.75), "jog": Vector2(0, 3.35), "run": Vector2(0, 5.19),
		"sprint": Vector2(0, 6.9), "backpedal": Vector2(0, -3.25), "strafe_l": Vector2(3.0, 0), "strafe_r": Vector2(-3.0, 0)}
	for c in defs:
		if not _lib.has_animation(c):
			continue
		var m: Dictionary = _meta.get(c, {})
		var pos: Vector2 = defs[c]
		if m.has("velocity") and c != "idle":
			var v: Array = m["velocity"]
			# metadata velocity is Blender space (x = left, -y = forward)
			pos = Vector2(float(v[0]), -float(v[1]))
			if c in LOCO_FWD or c == "backpedal":
				pos.x = 0.0
			else:
				pos.y = 0.0
		_pt_pos[c] = pos
		var cyc := float(m.get("cycle", 1.0))
		_pt_stride[c] = Vector2.ZERO if c == "idle" else pos * cyc


## Stride (m per cycle, vector) of the locomotion blend at local velocity `p`,
## replicating the blend space's barycentric weights → exact cadence.
static func stride_at(p: Vector2) -> Vector2:
	var best_d := INF
	var best := Vector2.ZERO
	for tri: Array in _tris:
		var a: Vector2 = tri[0]
		var b: Vector2 = tri[1]
		var c: Vector2 = tri[2]
		var v0 := b - a
		var v1 := c - a
		var v2 := p - a
		var d00 := v0.dot(v0)
		var d01 := v0.dot(v1)
		var d11 := v1.dot(v1)
		var d20 := v2.dot(v0)
		var d21 := v2.dot(v1)
		var den := d00 * d11 - d01 * d01
		if absf(den) < 1e-9:
			continue
		var wv := (d11 * d20 - d01 * d21) / den
		var ww := (d00 * d21 - d01 * d20) / den
		var wu := 1.0 - wv - ww
		if wu >= -1e-4 and wv >= -1e-4 and ww >= -1e-4:
			return (tri[3] as Vector2) * wu + (tri[4] as Vector2) * wv + (tri[5] as Vector2) * ww
		# outside: remember the closest edge point
		for e in 3:
			var pa: Vector2 = tri[e]
			var pb: Vector2 = tri[(e + 1) % 3]
			var ab := pb - pa
			var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var d := p.distance_squared_to(pa + ab * t)
			if d < best_d:
				best_d = d
				best = (tri[3 + e] as Vector2).lerp(tri[3 + (e + 1) % 3] as Vector2, t)
	return best


## Clip + time scale for a simulation action.
func _action_clip(p: Footballer) -> Array:
	var A := Footballer.A
	var fast := p.vel.length() > 3.2 and _lib.has_animation("kick_run")
	var m := "_m" if int(p.act_data.get("foot", 1)) == -1 else ""
	match p.action:
		A.PASS:
			return [_foot_clip("kick_run" if p.vel.length() > 4.5 and _lib.has_animation("kick_run") else "kick_pass", m), "contact"]
		A.SHOT:
			return [_foot_clip("kick_run" if fast else "kick_shot", m), "contact"]
		A.VOLLEY:
			return [_foot_clip("volley" if _lib.has_animation("volley") else "kick_shot", m), "contact"]
		A.LOB, A.CHIP:
			return [_foot_clip("kick_run" if fast and p.action == A.LOB else "kick_long", m), "contact"]
		A.GK_KICK:
			return ["gk_kick" if _lib.has_animation("gk_kick") else "kick_long", "contact"]
		A.HEADER:
			return ["header", "contact"]
		A.TACKLE:
			return ["tackle", "contact"]
		A.SLIDE:
			if _lib.has_animation("slide_mx"):
				return [_foot_clip("slide_mx", "_m" if p.strong_foot() == -1 else ""), "fit"]
			return ["slide", "fit"]
		A.TRAP:
			if float(p.act_data.get("h", 0.0)) > 0.7:
				return ["trap_chest", "fit"]
			return ["", ""]
		A.GK_DIVE:
			var dir: Vector3 = p.act_data.get("dir", Vector3.RIGHT)
			# local +x of a +z-facing character is its LEFT (clips: root_motion +x = left)
			var left := Vector3(cos(_yaw), 0, -sin(_yaw))
			var side := "l" if dir.dot(left) > 0.0 else "r"
			var low: bool = float(p.act_data.get("h", 1.0)) < 0.6
			var lat: float = p.act_data.get("lat", 1.0)
			if lat < 0.6:
				return ["gk_catch", "contact"]
			var mx := ("gk_block_mx_" if low else "gk_dive_mx_") + side
			if _lib.has_animation(mx):
				return [mx, "dive"]
			return ["gk_dive_low_" + side if low and _lib.has_animation("gk_dive_low_" + side) else "gk_dive_" + side, "contact"]
		A.GK_THROW:
			return ["gk_throw", "contact"]
		A.THROW_IN:
			return ["throw_in", "contact"]
		A.FALL:
			return ["fall_mx", "fit"] if _lib.has_animation("fall_mx") else ["fall", "natural"]
		A.GETUP:
			if _prev_act.begins_with("slide_mx") or _prev_act.begins_with("gk_dive_mx") or _prev_act.begins_with("gk_block_mx"):
				return ["", ""]          # these clips already get back up
			if _prev_act == "fall_mx" and _lib.has_animation("getup_mx"):
				return ["getup_mx", "fit"]
			return ["getup", "fit"]
		A.CELEBRATE:
			var st := int(p.act_data.get("style", 0)) % 3
			return ["celebrate_%d" % (st + 1), "natural"]
		A.SKILL:
			var sk := int(p.act_data.get("skill", 1))
			return [["stepover_l", "stepover_r", "drag_back"][clampi(sk - 1, 0, 2)], "contact"]
	return ["", ""]


static func _foot_clip(clip: String, m: String) -> String:
	return clip + m if m != "" and _lib.has_animation(clip + m) else clip


## Player emote (Emotes.LIST index): upper-body layer, or full body when standing.
func emote(i: int) -> void:
	if i < 0 or i >= Emotes.LIST.size():
		return
	var d: Dictionary = Emotes.LIST[i]
	var clip: String = d["clip"]
	if not _lib.has_animation(clip):
		return
	if not d["upper"]:
		if _prev_vel.length() < 1.0:
			play_emote(clip)
		return
	_emo_node.animation = clip
	_tree.set("parameters/emote_os/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_emo_end = _t + _lib.get_animation(clip).length


## View-only reactions (no gameplay effect): "dejected", "clap", ...
func play_emote(clip: String, delay := 0.0) -> void:
	if not _lib.has_animation(clip) or _act_clip != "":
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree() or _act_clip != "":
			return
	var a := _lib.get_animation(clip)
	_fire_action(clip, 1.0, 0.0, a.length, 0.07)
	_act_clip = "emote"
	_act_end = _t + a.length


func sync(p: Footballer, pos: Vector3, face: Vector3, dt: float) -> void:
	_t += dt
	_dt = dt
	position = pos
	if p.action == Footballer.A.HEADER:
		pass
	var tgt := atan2(face.x, face.z)
	_yaw = lerp_angle(_yaw, tgt, clampf(dt * 16.0, 0.0, 1.0))
	rotation = Vector3(0, _yaw, 0)
	# locomotion
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var v := p.vel
	var local := Vector2(v.dot(right), v.dot(fwd))   # x = character left
	var sp := v.length()
	_tree.set("parameters/loco/blend_position", local)
	# cadence = speed / stride of the current blend → planted feet don't skate
	var cad := 1.0
	if sp > 0.2:
		var st := stride_at(local).length() * _leg_k
		cad = clampf(sp / st, 0.55, 3.0) if st > 0.05 else 1.0
	# phase lock: the shown step cycle follows the simulation's gait (dribble touches are planned
	# on it), small error -> nudge the cadence, big error (after an action) -> jump
	if sp > 0.3 and Footballer.gait_freq(sp) > 0.0 and not m1_off:
		var e := wrapf(p.gait - _phase, -0.5, 0.5)
		if absf(e) > 0.3 and _act_clip == "" and _t - _snap_t > 0.6:
			_tree.set("parameters/seek/seek_request", p.gait)
			_phase = p.gait
			_snap_t = _t
		else:
			cad *= clampf(1.0 + 2.5 * e, 0.7, 1.3)
	_cad = cad
	_tree.set("parameters/ts/scale", cad)
	# body lean: forward with speed/acceleration, banked into curves
	if dt > 0.0:
		var acc := (v - _prev_vel) / dt
		_acc_f = _acc_f.lerp(acc, clampf(dt * 7.0, 0.0, 1.0))
	_prev_vel = v
	var a_fwd := _acc_f.dot(fwd)
	var a_left := _acc_f.dot(right)
	var floor_act := p.action in [Footballer.A.SLIDE, Footballer.A.FALL, Footballer.A.GETUP, Footballer.A.GK_DIVE]
	var pt := clampf(sp / 9.0 * 0.07 + a_fwd / 9.81 * 0.3, -0.08, 0.17)
	var rl := 0.0
	if sp > 2.0 and not floor_act:
		rl = clampf(-atan(a_left / 9.81) * 0.55, -0.2, 0.2)
	if floor_act or p.action == Footballer.A.CELEBRATE:
		pt = 0.0
	var lk := clampf(dt * 6.0, 0.0, 1.0)
	_pitch = lerpf(_pitch, pt, lk)
	_roll = lerpf(_roll, rl, lk)
	_model.rotation = Vector3(0.0, 0.0, _roll)   # pitch goes into the spine (planter)
	# near-camera detail: foot locking + head tracking
	var near := position.distance_squared_to(cam_pos) < NEAR_LOD * NEAR_LOD and not _web
	if _planter:
		_planter.body_speed = sp
		_planter.body_vel = v
		_planter.frame_dt = dt
		_planter.frame_id += 1
		_planter.spine_pitch = _pitch
		_planter.left_world = global_transform.basis.x
		_planter.unlean = global_transform * Transform3D(Basis(), _model.position) * _model.transform.affine_inverse() * global_transform.affine_inverse()
		_planter.force_pin = p.action in KICKS or p.action in [Footballer.A.TRAP, Footballer.A.THROW_IN, Footballer.A.GK_THROW, Footballer.A.GK_KICK]
		_planter.weight = 1.0 if near and not floor_act and p.action not in [Footballer.A.HEADER, Footballer.A.SKILL, Footballer.A.CELEBRATE] else 0.0
		_planter.active = _planter.weight > 0.0 or _planter._w > 0.0
	if _planter and not m1_off:
		_update_touch(p, near)
	if _look:
		var lw := 0.0
		if near and p.action in [Footballer.A.NONE, Footballer.A.TRAP] and _t > _emo_end and _act_clip != "emote":
			lw = 0.75
		_look.influence = move_toward(_look.influence, lw, dt * 3.0)
		_look.active = _look.influence > 0.0
	# actions
	if p.act_seq != _last_seq:
		_last_seq = p.act_seq
		var ac := _action_clip(p)
		var clip: String = ac[0]
		if clip != "" and _lib.has_animation(clip):
			var a := _lib.get_animation(clip)
			var m: Dictionary = _meta.get(clip, {})
			var scale := 1.0
			var off := 0.0
			match ac[1]:
				"contact":
					# skip the clip's run-up so the strike lands on the sim's contact time
					# while playing at a natural speed (≈1.3×)
					var cc := float(m.get("contact", a.length * 0.4))
					var sc := maxf(p.act_contact, 0.05)
					off = clampf(cc - sc * 1.3, 0.0, cc - 0.05)
					scale = clampf((cc - off) / sc, 0.6, 2.2)
				"fit":
					scale = clampf(a.length / maxf(p.act_dur, 0.1), 0.5, 2.5)
				"dive":
					# start at the push-off so full stretch lands when the simulated body is fully
					# out (~0.45 s, MatchSim._dive_step); the clip's own get-up plays through GETUP
					var cd := float(m.get("contact", a.length * 0.4))
					off = clampf(cd - 0.45, 0.0, cd - 0.05)
			var a_len := a.length - off
			# strikes blend in a bit longer (the swing starts from the running pose)
			_fire_action(clip, scale, off, a.length, 0.11 if p.action in KICKS else 0.07)
			_act_clip = clip
			_act_end = _t + a_len / scale
	# animation LOD: far players are evaluated at half rate
	_acc += dt
	var far := position.distance_squared_to(cam_pos) > (400.0 if _web else 900.0)
	if not far or (frame + pid) % 2 == 0:
		_tree.advance(_acc)
		_phase = fposmod(_phase + _cad * _acc, 1.0)
		_acc = 0.0
	# a finished clip blends back only once the simulation is done too (FALL -> GETUP etc. chain directly)
	if _in_action and _t >= _act_end - 0.18 and p.action == Footballer.A.NONE:
		_end_action()
		if _act_clip != "emote":
			_act_clip = ""
	if _act_clip == "emote":
		if _t > _act_end or p.vel.length() > 2.0:
			if p.vel.length() > 2.0:
				_end_action()
			_act_clip = ""
	elif _act_clip != "" and p.action == Footballer.A.NONE and _act_end - _t > 0.3 and _act_clip not in ["celebrate_1", "celebrate_2", "celebrate_3", "fall", "getup", "fall_mx", "getup_mx"]:
		_end_action()
		_act_clip = ""


## Dribble touch: the foot planned by the simulation (Footballer.touch_at / touch_foot) is pulled
## onto the ball over the last TOUCH_IN seconds, then lets go — the ball is pushed by a real foot.
func _update_touch(p: Footballer, near: bool) -> void:
	# fast path: nothing to reach for (most players, most frames)
	if sim_owner != pid and _recv_w <= 0.0 and not _kick_pending and _warp == Vector3.ZERO \
			and position.distance_squared_to(ball_pos) > 9.0 and not (p.action in KICKS):
		if _planter.reach_leg != -1:
			_planter.reach_leg = -1
			_planter.reach_w = 0.0
		return
	if p.action in KICKS:
		_update_strike(p, near)
		return
	if _kick_pending or _t - _kick_rel_t < KICK_OUT or _warp.length_squared() > 1e-6:
		_kick_pending = false
		_update_strike(p, near)
		if _t - _kick_rel_t < KICK_OUT:
			return
	if (sim_owner != pid or (_recv_w > 0.0 and p.touch_at < 0.0)) and _update_receive(p, near):
		return
	var w := 0.0
	var mine := sim_owner == pid and near and p.action == Footballer.A.NONE
	if mine and p.touch_at >= 0.0:
		var rem := p.touch_at - sim_time
		_touch_foot = p.touch_foot
		_touch_pending = true
		w = 1.0 - smoothstep(0.0, TOUCH_IN, rem)
	elif _touch_pending:
		_touch_pending = false
		_touch_rel_t = _t
	if not _touch_pending and _t - _touch_rel_t < TOUCH_OUT:
		w = 1.0 - (_t - _touch_rel_t) / TOUCH_OUT
	if w <= 0.001:
		_planter.reach_leg = -1
		_planter.reach_w = 0.0
		return
	var n := ball_pos - _warp - position
	n.y = 0.0
	if n.length() < 0.05:
		n = Vector3(sin(_yaw), 0, cos(_yaw))
	n = n.normalized()
	# metatarsal joint just behind the ball (instep / inside of the foot on the ball's back)
	var t := ball_pos - n * 0.14
	t.y = clampf(ball_pos.y - 0.07, 0.04, 0.5)
	_planter.reach_leg = 1 if _touch_foot == 1 else 0
	_planter.reach_w = w
	_planter.reach_target = t
	_planter.reach_yaw = 0.0
	# ball a little too far ahead for the leg: lean the body into the touch (<= 0.2 m)
	var want := _reach_shift(_planter.reach_leg, t, 0.2) * w if _touch_pending else Vector3.ZERO
	_warp = _warp.lerp(want, 1.0 - exp(-_dt * (25.0 if _touch_pending else 7.0)))
	_model.position = global_transform.basis.inverse() * _warp + Vector3(0, 0.017, 0)


const KICKS := [Footballer.A.PASS, Footballer.A.SHOT, Footballer.A.LOB, Footballer.A.CHIP, Footballer.A.VOLLEY]
const KICK_IN := 0.12      # s: kicking foot homes in on the ball before contact
const KICK_OUT := 0.08     # s: and is released after it


## Horizontal body shift that brings `leg`'s hip within reach of `tgt` (0 if already reachable).
static var _no_warp := OS.get_environment("MAYDON_NO_WARP") != ""
func _reach_shift(leg: int, tgt: Vector3, cap: float) -> Vector3:
	if _no_warp:
		return Vector3.ZERO
	var th: int = _thighs[1 if leg == 1 else 0]
	if th < 0:
		return Vector3.ZERO
	var hip := _skel.global_transform * _skel.get_bone_global_pose(th).origin - _warp
	var d := Vector3(tgt.x - hip.x, 0.0, tgt.z - hip.z)
	var dv := maxf(hip.y - tgt.y, 0.0)
	var lmax := _leg_len * 0.98
	var dh_max := sqrt(maxf(lmax * lmax - dv * dv, 0.01)) + 0.15   # pelvis drop + lean
	if d.length() <= dh_max:
		return Vector3.ZERO
	return d.normalized() * minf(d.length() - dh_max, cap)


## Strike: the kicking foot meets the ball at the simulation's contact time. If the hip is too far
## for the leg to reach, the whole body is shifted (visual root warp, <= 0.45 m) during the wind-up.
func _update_strike(p: Footballer, near: bool) -> void:
	var w := 0.0
	var want := Vector3.ZERO
	if p.action in KICKS and near:
		var act_t := p.act_t - (sim_clock - sim_time)
		var rem := p.act_contact - act_t
		if rem >= 0.0 and not p.act_done:
			_kick_leg = 1 if int(p.act_data.get("foot", 1)) == 1 else 0
			var tgt: Vector3 = p.act_data.get("target", ball_pos + Vector3(sin(_yaw), 0, cos(_yaw)))
			var kdir := tgt - ball_pos
			kdir.y = 0.0
			kdir = kdir.normalized() if kdir.length() > 0.1 else Vector3(sin(_yaw), 0, cos(_yaw))
			_kick_tgt = ball_pos - kdir * 0.13
			_kick_tgt.y = clampf(ball_pos.y - 0.05, 0.04, 1.3)
			w = 1.0 - smoothstep(0.0, KICK_IN, rem)
			_kick_pending = true
			want = _reach_shift(_kick_leg, _kick_tgt, 0.45) * clampf(1.0 - rem / maxf(p.act_contact, 0.05), 0.0, 1.0)
		elif _kick_pending:
			_kick_pending = false
			_kick_rel_t = _t
	elif _kick_pending:
		_kick_pending = false
		_kick_rel_t = _t
	if not _kick_pending and _t - _kick_rel_t < KICK_OUT:
		w = 1.0 - (_t - _kick_rel_t) / KICK_OUT
	if _kick_pending:
		_warp = _warp.lerp(want, 1.0 - exp(-_dt * 25.0))
	else:
		_warp = _warp.lerp(Vector3.ZERO, 1.0 - exp(-_dt * 7.0))
		if _warp.length_squared() < 1e-6:
			_warp = Vector3.ZERO
	_model.position = global_transform.basis.inverse() * _warp + Vector3(0, 0.017, 0)
	_planter.reach_leg = _kick_leg if w > 0.001 else -1
	_planter.reach_w = w
	_planter.reach_target = _kick_tgt
	_planter.reach_yaw = 0.0


const RECV_IN := 0.22      # s: receiving foot goes to meet an incoming ground ball


## Receiving: a ground ball about to reach this player (its path passes close by) is met by the
## nearer foot, so the first touch / trap happens on a foot instead of on thin air.
func _update_receive(p: Footballer, near: bool) -> bool:
	var want := 0.0
	if near and p.action in [Footballer.A.NONE, Footballer.A.TRAP] and ball_pos.y < 0.5:
		var rel := ball_pos - position
		rel.y = 0.0
		var bv := Vector3(ball_vel.x, 0.0, ball_vel.z)
		var bs := bv.length()
		if bs <= 1.5 and rel.length() < 0.95 and rel.length() > 0.05 and p.vel.length() > 0.5 and rel.dot(p.vel) > 0.0:
			# slow / loose ball the player runs onto: step onto it with the nearer foot
			want = clampf((0.95 - rel.length()) / 0.3, 0.0, 1.0)
			var lft := Vector3(cos(_yaw), 0, -sin(_yaw))     # local +x = character left
			_recv_leg = 0 if rel.dot(lft) > 0.05 else 1
			_recv_tgt = ball_pos - rel.normalized() * 0.14
			_recv_tgt.y = clampf(ball_pos.y - 0.06, 0.04, 0.45)
		elif bs > 1.5 and rel.length() < 3.0:
			var u := bv / bs
			var along := -rel.dot(u)                       # distance the ball still travels to us
			var miss := (rel + u * along).length()        # closest approach of the ball path
			# the simulation collects the ball as soon as it is within ~0.72 m (MatchSim reach)
			var reach := sqrt(maxf(0.68 * 0.68 - miss * miss, 0.0))
			if along > 0.05 and miss < 0.7:
				var tti := maxf(along - reach, 0.0) / bs
				if tti < RECV_IN:
					want = 1.0 - tti / RECV_IN
					var hit := ball_pos + u * maxf(along - reach, 0.0)
					var lft2 := Vector3(cos(_yaw), 0, -sin(_yaw))
					_recv_leg = 0 if (hit - position).dot(lft2) > 0.05 else 1
					_recv_tgt = hit + u * 0.12
					_recv_tgt.y = clampf(ball_pos.y - 0.06, 0.04, 0.45)
	if p.action == Footballer.A.TRAP:
		want = maxf(want, 0.0)
	_recv_w = move_toward(_recv_w, want, _dt * (14.0 if want > _recv_w else 8.0))
	if _recv_w <= 0.001:
		return false
	_planter.reach_leg = _recv_leg
	_planter.reach_w = _recv_w
	_planter.reach_target = _recv_tgt
	_planter.reach_yaw = 0.0
	var shift := _reach_shift(_recv_leg, _recv_tgt, 0.25) * _recv_w if want > 0.0 else Vector3.ZERO
	_warp = _warp.lerp(shift, 1.0 - exp(-_dt * (20.0 if want > 0.0 else 7.0)))
	_model.position = global_transform.basis.inverse() * _warp + Vector3(0, 0.017, 0)
	return true


## Start an action clip. If another action is still on screen, cross-fade slot to slot (0.15 s);
## otherwise blend over from locomotion in `fade_in`.
func _fire_action(clip: String, scale: float, off: float, length: float, fade_in: float) -> void:
	var chained := _in_action and _act_clip != "" and _t < _act_end + 0.05
	_act_slot = 1 - _act_slot
	_act_node = _act_slots[_act_slot]
	_act_node.animation = clip
	_act_node.use_custom_timeline = off > 0.0
	if off > 0.0:
		_act_node.start_offset = off
		_act_node.timeline_length = length - off
		_act_node.stretch_time_scale = false
	_tree.set("parameters/act_ts%d/scale" % _act_slot, scale)
	var main := (_tree.tree_root as AnimationNodeBlendTree).get_node("main") as AnimationNodeTransition
	main.xfade_time = 0.15 if chained else fade_in
	_tree.set("parameters/main/transition_request", "s%d" % _act_slot)
	_in_action = true
	_prev_act = clip


## Blend back to locomotion.
func _end_action(fade := 0.18) -> void:
	if not _in_action:
		return
	var main := (_tree.tree_root as AnimationNodeBlendTree).get_node("main") as AnimationNodeTransition
	main.xfade_time = fade
	_tree.set("parameters/main/transition_request", "loco")
	_in_action = false
