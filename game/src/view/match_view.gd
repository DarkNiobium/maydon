class_name MatchView
extends Node3D
## Match scene: owns the simulation, renders it with interpolation, routes
## input (touch / keyboard / gamepad), drives camera, HUD, audio and replays.

const PlayerViewScript := preload("res://src/view/player_view_simple.gd")

var sim: MatchSim
var cfg: MatchConfig
var views: Array = []
var ball_mi: MeshInstance3D
var ball_shadow: MeshInstance3D
var cam: CameraRig
var hud: Hud
var human: HumanController
var human_id := -1
var profile_id := -1             # the player's own footballer (results/career)
var team_mode := false           # 11v11 "real football" control: switch between teammates
var _switch_t := -9.0
var officials: Officials
var prev_pos: PackedVector3Array
var cur_pos: PackedVector3Array
var prev_ball := Vector3.ZERO
var cur_ball := Vector3.ZERO
var marker: MeshInstance3D
var now := 0.0
var paused := false
var excite := 0.0
var quality := 1
var replay: ReplayBuffer
var replay_mode := false
var replay_t := 0.0
var replay_frames: Array = []
var _ball_rot := Basis.IDENTITY
var _ended := false
var external_input := false     # tools drive input directly
var attract := false            # menu background: no HUD, no sounds, loops forever
var meta := {}
var tutorial: Node = null
var tv_hide: Array = []
var intro_t := 0.0
var _last_steps := -1
var call_label: Label3D
var fx: MatchFx
var _wheel_block_t := 0.0
var _t_down := 0.0
var _opt_rings: Array = []
var _opt_t := 0.0
var net: NetMatch = null
var _tv_hidden := false
var manual_step := false        # tools advance the sim explicitly (offline capture)


func _ready() -> void:
	cfg = Game.next_match if Game.next_match else Game.quick_match(5, Footballer.Role.FWD, 1)
	quality = int(Game.settings.get("quality", 1))
	sim = MatchSim.new(cfg)
	replay = ReplayBuffer.new(sim)
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	if not Net.dedicated:      # headless match server: no visuals (saves ~150 MB RAM)
		VenueBuilder.build(sim.pitch, cfg, world, quality)
		PitchBuilder.build(sim.pitch, world)
	_collect_tv_hide(world)
	_apply_quality()
	_spawn_ball()
	CharacterView.ball_node = ball_mi
	_spawn_views()
	if sim.is_full() and CharacterLibrary.available() and not Net.dedicated:
		officials = Officials.new()
		add_child(officials)
		officials.setup(sim)
	_spawn_call_label()
	for p in sim.players:
		if p.human == 0:
			human_id = p.id
	profile_id = human_id
	if human_id >= 0:
		human = HumanController.new(sim, human_id)
		human.gk_assist = cfg.gk_assist
		human.aim_assist = cfg.aim_assist
		team_mode = cfg.per_side >= 9 and str(Game.settings.get("control", "team")) == "team" \
			and not Game.next_match_meta.has("net") and not bool(Game.next_match_meta.get("tutorial", false))
	cam = CameraRig.new()
	cam.setup(sim, human_id)
	cam.mode = CameraRig.Mode.TV if (human_id < 0 and not Game.next_match_meta.has("follow")) or int(Game.settings.get("camera", 0)) == 1 else CameraRig.Mode.SHOULDER
	if human_id < 0 and Game.next_match_meta.has("follow"):
		cam.mode = CameraRig.Mode.PRO
	if human_id >= 0 and not Game.is_phone() and not attract and not OS.get_cmdline_user_args().has("--touch") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if team_mode and int(Game.settings.get("camera", 0)) != 2:
		cam.mode = CameraRig.Mode.TV      # broadcast camera, like a real football game
	if Game.next_match_meta.has("cam"):
		cam.mode = int(Game.next_match_meta["cam"])
	add_child(cam)
	cam.current = true
	fx = MatchFx.new()
	add_child(fx)
	fx.setup(cam, sim.pitch.surface == Pitch.Surface.TURF)
	attract = bool(Game.next_match_meta.get("attract", false))
	meta = Game.next_match_meta.duplicate()
	hud = Hud.new()
	add_child(hud)
	var touch_ui := Game.is_phone() or OS.get_cmdline_user_args().has("--touch")
	hud.setup(sim, human_id, touch_ui and human_id >= 0)
	if hud.touch:
		hud.touch.inp = human.inp
		hud.touch.team_mode = team_mode
	hud.pause_requested.connect(_toggle_pause)
	if hud.emote_wheel:
		hud.emote_wheel.chosen.connect(func(i: int) -> void:
			_wheel_block_t = now + 0.3
			if human:
				human.inp.emote = i)
	if attract:
		hud.visible = false
		hud.layer = -10
		for c in hud.get_children():
			c.queue_free()
	_snapshot()
	_snapshot()
	if not attract:
		Sfx.match_start(cfg)
		if not meta.has("net") and not meta.get("tutorial", false):
			intro_t = 2.8
			_prev_cam_mode = cam.mode
			cam.mode = CameraRig.Mode.CINE
			cam.cine_center = Vector3.ZERO
			cam.cine_t = 0.0
			hud.banner(str(cfg.team_names[0]).to_upper() + "  ·  " + str(cfg.team_names[1]).to_upper(),
				tr("F%d" % cfg.per_side) if cfg.per_side in [3, 5, 11] else "", 2.6, Color.WHITE, 72)
	if meta.has("net"):
		net = NetMatch.new(self, meta["net"] == "host")
		add_child(net)
	if meta.get("tutorial", false):
		tutorial = Tutorial.new(self)
		add_child(tutorial)


## Objects on the near (+Z) side block the broadcast camera: cut them away in TV mode.
func _collect_tv_hide(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.name != "Ground":
			var mi := c as MeshInstance3D
			var ab := mi.global_transform * mi.get_aabb()
			var cz := ab.get_center().z
			if cz > sim.pitch.hw() - 0.3 and ab.size.x < 400.0:
				tv_hide.append(mi)
		_collect_tv_hide(c)


func _update_cutaway() -> void:
	var want := cam.mode == CameraRig.Mode.TV
	if want == _tv_hidden:
		return
	_tv_hidden = want
	for mi in tv_hide:
		(mi as Node3D).visible = not want


func _spawn_views() -> void:
	for p in sim.players:
		var kit: Dictionary = cfg.gk_kits[p.team] if p.is_gk() and cfg.gk_kits.size() > p.team and not cfg.gk_kits[p.team].is_empty() else cfg.kits[p.team]
		var v: Node3D
		if CharacterLibrary.available() and not Net.dedicated:
			v = CharacterView.new()
		else:
			v = PlayerViewScript.new()
		add_child(v)
		var hl := {}
		if p.human > 0:
			for h in cfg.humans:
				if int(h.get("idx", -9)) == p.human and typeof(h.get("look")) == TYPE_DICTIONARY:
					hl = h["look"]
		if v is CharacterView:
			v.call("setup", p, kit, hl)
		else:
			v.call("setup", p, kit)
		views.append(v)
	marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	tm.rings = 24
	tm.ring_segments = 6
	marker.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.9, 0.15)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.85, 0.1)
	mm.emission_energy_multiplier = 1.5
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mm
	marker.scale = Vector3(1, 0.15, 1)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)


## Subtle rings under teammates who are open for a pass (helps reading play).
func _update_pass_options(delta: float) -> void:
	if human_id < 0 or _opt_rings.is_empty():
		return
	_opt_t -= delta
	var me: Footballer = sim.players[human_id]
	var have := sim.owner == human_id
	if _opt_t <= 0.0:
		_opt_t = 0.15
		var picks := []
		if have and sim.phase == MatchSim.Phase.PLAY:
			var ai_t: TeamAI = sim.ai[me.team]
			for q in sim.team_players(me.team):
				if q.id == me.id or q.is_gk():
					continue
				var d := me.pos.distance_to(q.pos)
				if d < 4.0 or d > 35.0:
					continue
				var v0 := sim.ball.ground_pass_speed(d, BallSim.pass_arrive_speed(d))
				var ps := ai_t.pass_safety(sim.ball.pos, q.pos, v0)
				if ps > 0.6:
					picks.append([ps, q.id])
			picks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		for i in _opt_rings.size():
			var r: MeshInstance3D = _opt_rings[i]
			r.set_meta("pid", picks[i][1] if i < picks.size() else -1)
	for r in _opt_rings:
		var pid: int = r.get_meta("pid", -1)
		r.visible = pid >= 0
		if pid >= 0:
			var vp: Vector3 = (views[pid] as Node3D).position
			r.position = Vector3(vp.x, 0.03, vp.z)


## Real-football control: the human always plays the ball carrier of their team;
## when defending, control moves to the best-placed teammate (auto, with
## hysteresis) or on demand (SWITCH: Tab / LB / touch).
func _team_control() -> void:
	var me: Footballer = sim.players[human_id]
	var team := me.team
	var manual: bool = human.inp.pressed[InputState.B.SWITCH] or (human.inp.pressed[InputState.B.D] and human.context() in ["defend", "support"])
	var owner := sim.owner
	if owner >= 0 and sim.players[owner].team == team:
		if owner != human_id:
			_switch_to(owner)
		return
	# a pass to a teammate: take over the receiver as the ball arrives
	var lp: Dictionary = sim.last_pass
	if owner < 0 and not lp.is_empty() and int(lp.get("team", -1)) == team and sim.clock - float(lp.get("t", -9.0)) < 3.0:
		var rid := int(lp.get("recv", -1))
		if rid >= 0 and rid != human_id and not sim.players[rid].is_gk() and sim.players[rid].pos.distance_to(sim.ball.pos) < 9.0:
			_switch_to(rid)
			return
	if me.busy() and not manual:
		return
	if sim.phase != MatchSim.Phase.PLAY and not manual:
		return
	# defending / loose ball: best interceptor
	var best := -1
	var best_t := INF
	var second := -1
	var second_t := INF
	for q in sim.team_players(team):
		if q.is_gk() or q.sent_off:
			continue
		var t := q.time_to(sim.ball.pos, true, 0.6)
		if t < best_t:
			second = best
			second_t = best_t
			best = q.id
			best_t = t
		elif t < second_t:
			second = q.id
			second_t = t
	if manual:
		var pick := best if best != human_id else second
		if pick >= 0:
			_switch_to(pick)
		return
	if best < 0 or best == human_id or now - _switch_t < 1.1:
		return
	var cur_t := me.time_to(sim.ball.pos, true, 0.6)
	# only switch when the current player is clearly worse and the human isn't steering hard
	var steering := human.inp.stick.length() > 0.5
	if cur_t - best_t > (1.2 if steering else 0.6):
		_switch_to(best)


func _switch_to(id: int) -> void:
	if id == human_id or id < 0:
		return
	var old: Footballer = sim.players[human_id]
	old.human = -1
	old.queued = Cmd.new()
	var nw: Footballer = sim.players[id]
	nw.human = 0
	human_id = id
	human.pid = id
	cam.follow_id = id
	hud.set_human(id)
	_switch_t = now


func _spawn_call_label() -> void:
	for i in 2:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.45
		tm.outer_radius = 0.52
		tm.rings = 24
		tm.ring_segments = 4
		r.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.35, 0.75, 1.0, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r.material_override = m
		r.scale = Vector3(1, 0.1, 1)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		add_child(r)
		_opt_rings.append(r)
	call_label = Label3D.new()
	call_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	call_label.font = load("res://assets/fonts/Oswald.ttf")
	call_label.font_size = 96
	call_label.outline_size = 18
	call_label.pixel_size = 0.004
	call_label.modulate = Color(1.0, 0.92, 0.2)
	call_label.no_depth_test = true
	call_label.visible = false
	add_child(call_label)


func _spawn_ball() -> void:
	ball_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BallSim.R
	sm.height = BallSim.R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	ball_mi.mesh = sm
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/view/shaders/ball.gdshader")
	ball_mi.material_override = bm
	add_child(ball_mi)
	ball_shadow = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	qm.orientation = PlaneMesh.FACE_Y
	ball_shadow.mesh = qm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	gt.gradient = g
	shm.albedo_texture = gt
	ball_shadow.material_override = shm
	ball_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball_shadow)


func _apply_quality() -> void:
	var vp := get_viewport()
	if attract:
		return
	match quality:
		0:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.62
			vp.msaa_3d = Viewport.MSAA_DISABLED
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		1:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.8
			vp.msaa_3d = Viewport.MSAA_DISABLED
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		2:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		_:
			# Ultra (desktop Forward+): TAA + MSAA for clean nets/lines, big shadow atlas
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
	vp.use_taa = VenueBuilder.forward_plus() and quality >= 2
	if VenueBuilder.forward_plus():
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if quality >= 3 else (RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality >= 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW))
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality >= 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if not Game.is_phone() and quality >= 2:
		vp.scaling_3d_scale = 1.0
	if Game.is_web():
		# WebGL2 (Compatibility renderer): no FSR, keep the GPU load low
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = minf(vp.scaling_3d_scale, 0.6 if Game.is_phone() else 0.8)
		vp.msaa_3d = Viewport.MSAA_DISABLED
		RenderingServer.directional_shadow_atlas_set_size(1024 if quality < 2 else 2048, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not paused and not attract and not (net != null):
			_toggle_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not attract:
			_toggle_pause()


func _snapshot() -> void:
	var n := sim.players.size()
	if cur_pos.size() != n:
		cur_pos.resize(n)
		prev_pos.resize(n)
		for i in n:
			cur_pos[i] = sim.players[i].pos
	prev_pos = cur_pos.duplicate()
	for i in n:
		cur_pos[i] = sim.players[i].pos
	prev_ball = cur_ball
	cur_ball = sim.ball.pos


func _toggle_pause() -> void:
	paused = not paused
	PauseMenu.toggle(self, paused)


func set_paused(v: bool) -> void:
	paused = v


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _pc_mode() -> bool:
	return not Game.is_phone() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _read_devices() -> void:
	if human == null or external_input:
		return
	var inp := human.inp
	var kb := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)))
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length() < 0.18:
		pad = Vector2.ZERO
	var touch_active := hud.touch != null and inp.stick != Vector2.ZERO and kb == Vector2.ZERO and pad == Vector2.ZERO
	if not touch_active:
		var st := kb.normalized() if kb != Vector2.ZERO else pad
		if hud.touch == null or st != Vector2.ZERO:
			inp.stick = st
	# gamepad right stick orbits the shoulder camera
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.2:
		var inv := -1.0 if Game.settings.get("invert_y", false) else 1.0
		cam.look_input(rs.x * 2.6 * get_physics_process_delta_time(), rs.y * 1.6 * get_physics_process_delta_time() * inv)
		_pad_aim_t = now
	var pc := _pc_mode()
	inp.aim_mode = cam.mode == CameraRig.Mode.SHOULDER and (pc or now - _pad_aim_t < 4.0)
	var wheel := hud.emote_wheel != null and (hud.emote_wheel.visible or now < _wheel_block_t)
	var mb := func(b: int) -> bool: return pc and not wheel and Input.is_mouse_button_pressed(b)
	var keys := {
		# contextual buttons: J/K/L/I, mouse (PC), gamepad
		InputState.B.A: Input.is_key_pressed(KEY_J) or mb.call(MOUSE_BUTTON_RIGHT) or Input.is_joy_button_pressed(0, JOY_BUTTON_A),
		InputState.B.B: Input.is_key_pressed(KEY_K) or mb.call(MOUSE_BUTTON_LEFT) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4,
		InputState.B.C: Input.is_key_pressed(KEY_L) or Input.is_key_pressed(KEY_Q) or mb.call(MOUSE_BUTTON_MIDDLE) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y),
		InputState.B.D: Input.is_key_pressed(KEY_I) or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_STICK),
		InputState.B.SPRINT: Input.is_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER),
		# explicit actions
		InputState.B.TACKLE: Input.is_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_X),
		InputState.B.SLIDE: Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_B),
		InputState.B.CALL: Input.is_key_pressed(KEY_F) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER),
		InputState.B.RUNREQ: Input.is_key_pressed(KEY_R) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.4,
		InputState.B.SWITCH: Input.is_key_pressed(KEY_TAB) or (team_mode and Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)),
	}
	for b in keys:
		var touch_held := hud.touch != null and hud.touch._btn_touch.values().has(b)
		if not touch_held:
			inp.set_button(b, keys[b], now)
	if inp.aim_mode:
		var ray := cam.aim_ray()
		human.aim_origin = ray[0]
		human.aim_dir = ray[1]
	# touch-drag on the right side rotates the camera on phones
	if hud.touch:
		var ld: Vector2 = hud.touch.take_look_delta()
		if ld != Vector2.ZERO:
			cam.look_input(ld.x * 0.006, ld.y * 0.004)


var _pad_aim_t := -99.0


func _input(event: InputEvent) -> void:
	if paused or attract or human == null:
		return
	# emotes: hold T for the wheel (release / click picks), 1-8 direct, gamepad d-pad quick emotes
	if event is InputEventKey and not event.echo and hud.emote_wheel:
		var k := event as InputEventKey
		if k.keycode == KEY_T:
			if k.pressed:
				if hud.emote_wheel.visible:
					hud.emote_wheel.close()      # second tap closes
				else:
					hud.emote_wheel.open()
					_t_down = now
			elif now - _t_down > 0.3:
				hud.emote_wheel.confirm()        # hold, aim, release
			# quick tap: wheel stays open → move the mouse + click, or press 1-8
			get_viewport().set_input_as_handled()
			return
		if k.pressed and hud.emote_wheel.visible and k.keycode >= KEY_1 and k.keycode <= KEY_8:
			hud.emote_wheel.pick(k.keycode - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventJoypadButton and event.pressed and hud.emote_wheel:
		var quick := {JOY_BUTTON_DPAD_UP: 0, JOY_BUTTON_DPAD_RIGHT: 1, JOY_BUTTON_DPAD_LEFT: 2, JOY_BUTTON_DPAD_DOWN: 3}
		if quick.has(event.button_index):
			human.inp.emote = quick[event.button_index]
			return
	if hud.emote_wheel and hud.emote_wheel.visible:
		return
	# any button skips the goal replay (quick restarts, REMATCH-style)
	if replay_mode and ((event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed)):
		replay_t = 1e9
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens := float(Game.settings.get("mouse_sens", 0.5)) * 0.006
		var inv := -1.0 if Game.settings.get("invert_y", false) else 1.0
		cam.look_input(mm.relative.x * sens, mm.relative.y * sens * inv)
	elif event is InputEventMouseButton and event.pressed and not Game.is_phone() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_wheel_block_t = now + 0.35      # the capturing click must not shoot
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_P:
			_toggle_pause()
		elif k.keycode == KEY_V:
			cam.mode = CameraRig.Mode.TV if cam.mode == CameraRig.Mode.SHOULDER else CameraRig.Mode.SHOULDER
			cam.snap()


# ---------------------------------------------------------------------------
# Loop
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if paused or manual_step:
		return
	_tick(delta)


## Offline capture: advance `n` fixed ticks, then render state with alpha = 1.
func advance(n: int, render_dt := 1.0 / 30.0) -> void:
	for i in n:
		if replay_mode:
			_replay_process(1.0 / 60.0)
		else:
			_tick(1.0 / 60.0)
	if not replay_mode:
		_render(maxf(render_dt, n / 60.0), 1.0)


func _tick(delta: float) -> void:
	now += delta
	if replay_mode:
		return
	_read_devices()
	if net and not net.host:
		net.client_tick(now)
		return
	if intro_t > 0.0:
		intro_t -= delta
		if intro_t <= 0.0:
			cam.mode = _prev_cam_mode
			cam.snap()
			Sfx.whistle("kickoff")
		if human:
			human.inp.end_frame()
		return
	if human and team_mode:
		_team_control()
	if human:
		var ax := cam.control_axes()
		human.update(now, ax[0], ax[1])
	if net:
		net.host_pre(now)
	sim.step()
	_snapshot()
	replay.record()
	for e in sim.events:
		_on_event(e)
	if net:
		net.host_post(sim.events)
	if human:
		human.inp.end_frame()


func _process(delta: float) -> void:
	if manual_step:
		return
	if replay_mode:
		_replay_process(delta)
		return
	_render(delta, net.client_alpha() if net and not net.host else Engine.get_physics_interpolation_fraction())


func _render(delta: float, alpha: float) -> void:
	if Net.dedicated:
		return            # headless match server: simulation only
	CharacterView.cam_pos = cam.global_position
	CharacterView.frame += 1
	CharacterView.ball_pos = prev_ball.lerp(cur_ball, alpha)
	CharacterView.sim_time = sim.clock - (1.0 - alpha) * MatchSim.DT
	CharacterView.sim_owner = sim.owner
	CharacterView.sim_clock = sim.clock
	CharacterView.ball_vel = sim.ball.vel
	for i in views.size():
		var p: Footballer = sim.players[i]
		var v: Node3D = views[i]
		if p.sent_off:
			v.visible = false
			continue
		var ip := prev_pos[i].lerp(cur_pos[i], alpha)
		v.call("sync", p, ip, p.face, delta)
	if officials:
		officials.update(delta)
	# PC: the browser/OS only locks the mouse after a click — say so
	if hud and human and not Game.is_phone():
		hud.click_hint(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not paused and intro_t <= 0.0)
	var bp := prev_ball.lerp(cur_ball, alpha)
	_update_ball(bp, sim.ball.spin, delta)
	fx.update_trail(bp, sim.ball.speed())
	_update_pass_options(delta)
	if human_id >= 0:
		var hp_f: Footballer = sim.players[human_id]
		if hp_f.gait_steps != _last_steps:
			if _last_steps >= 0 and hp_f.vel.length() > 2.5 and cam.mode in [CameraRig.Mode.PRO, CameraRig.Mode.SHOULDER]:
				Sfx.footstep(clampf(hp_f.vel.length() / 8.0, 0.3, 1.0))
			_last_steps = hp_f.gait_steps
		marker.visible = true
		var since := now - human.called_t if human else 99.0
		call_label.visible = since < 1.1
		if call_label.visible:
			var hpv: Vector3 = (views[human_id] as Node3D).position
			call_label.position = hpv + Vector3(0, 2.35 + since * 0.25, 0)
			call_label.text = tr("B_RUN") if human.called_through else tr("B_CALL")
			call_label.modulate.a = clampf(1.6 - since * 1.4, 0.0, 1.0)
		var hp: Vector3 = (views[human_id] as Node3D).position
		marker.position = Vector3(hp.x, 0.03, hp.z)
	else:
		marker.visible = false
	var focus := sim.ball.pos
	var side := 1
	var fid := human_id if human_id >= 0 else int(Game.next_match_meta.get("follow", -1))
	if fid >= 0:
		focus = (views[fid] as Node3D).position
		side = sim.side_of(sim.players[fid].team)
	if cam.mode == CameraRig.Mode.CINE and _celebrate_id >= 0:
		cam.cine_center = (views[_celebrate_id] as Node3D).position
	elif cam.mode == CameraRig.Mode.CINE and sim.phase != MatchSim.Phase.GOAL and intro_t <= 0.0:
		cam.mode = _prev_cam_mode
	cam.update_cam(delta, bp, focus, side)
	_update_cutaway()
	excite = maxf(excite - delta * 0.25, _danger() * 0.5)
	VenueBuilder.set_excite(excite)
	if not attract:
		Sfx.crowd_level(excite)
	var power := -1.0
	var ctx := "attack"
	if human:
		ctx = human.last_ctx
		if human.inp.held[InputState.B.B] and ctx in ["attack", "setpiece", "support"]:
			power = clampf(human.inp.held_for(InputState.B.B, now) / 0.85, 0.0, 1.0)
	if attract:
		return
	if human_id >= 0:
		var hpv2: Footballer = sim.players[human_id]
		cam.fov_kick = 6.0 if hpv2.cmd.sprint and hpv2.vel.length() > 6.0 else 0.0
	hud.crosshair = human != null and human.inp.aim_mode and cam.mode == CameraRig.Mode.SHOULDER
	hud.update_hud(delta, now, ctx, power)
	if sim.phase == MatchSim.Phase.FULLTIME and not _ended and sim.phase_t > 2.5 and not (net and not net.host):
		_ended = true
		_finish()


func _update_ball(bp: Vector3, spin: Vector3, dt: float) -> void:
	ball_mi.position = bp
	if spin.length() > 0.01:
		_ball_rot = Basis(spin.normalized(), spin.length() * dt) * _ball_rot
		_ball_rot = _ball_rot.orthonormalized()
	ball_mi.basis = _ball_rot
	ball_shadow.position = Vector3(bp.x, 0.015, bp.z)
	var hgt := clampf(bp.y / 4.0, 0.0, 1.0)
	ball_shadow.scale = Vector3.ONE * (1.0 + hgt)
	(ball_shadow.material_override as StandardMaterial3D).albedo_color.a = 1.0 - hgt * 0.8


func _danger() -> float:
	if sim.poss_team < 0:
		return 0.0
	var gx := sim.pitch.goal_x(sim.side_of(sim.poss_team))
	var d := absf(sim.ball.pos.x - gx) / sim.pitch.length
	return clampf(1.0 - d * 3.0, 0.0, 1.0)


func _on_event(e: Dictionary) -> void:
	var t: String = e["t"]
	if tutorial:
		tutorial.call("on_event", e)
	if attract:
		if t == "goal":
			excite = 1.0
		return
	match t:
		"emote":
			var eid := int(e.get("id", -1))
			if eid >= 0 and eid < views.size() and views[eid].has_method("emote"):
				views[eid].call("emote", int(e.get("e", 0)))
		"kick":
			Sfx.kick(e.get("s", 10.0), e.get("kind", "pass"), e.get("p", sim.ball.pos))
			var ks: float = e.get("s", 10.0)
			if ks > 14.0 and e.has("p"):
				fx.flecks(e["p"], clampf(ks / 30.0, 0.3, 1.0))
			if e.get("kind", "") == "shot" and ks > 24.0 and human_id >= 0 and int(e.get("id", -1)) == human_id:
				cam.shake = maxf(cam.shake, 0.22)
		"dribble":
			if not e.get("soft", true):
				Sfx.touch(0.4, sim.ball.pos)
		"touch", "trap":
			Sfx.touch(0.6, sim.ball.pos)
		"bounce":
			Sfx.bounce(e.get("s", 2.0), e.get("p", sim.ball.pos))
		"post", "bar":
			Sfx.post(e.get("s", 10.0), e.get("p", sim.ball.pos))
			excite = 1.0
			hud.hint(tr("BAR") if t == "bar" else tr("POST"))
			cam.shake = 0.4
		"net":
			Sfx.net(e.get("s", 5.0), e.get("p", sim.ball.pos))
		"wall":
			Sfx.wall(e.get("s", 5.0), e.get("p", sim.ball.pos))
		"whistle":
			Sfx.whistle(str(e.get("k", "")))
		"goal":
			_on_goal(e)
		"save":
			excite = 0.9
			Sfx.crowd_ooh(sim.ball.pos)
			hud.hint(tr("GREAT_SAVE"))
		"shot":
			if not e.get("on", false):
				pass
		"tackle":
			if e.get("won", false):
				Sfx.tackle()
		"foul":
			var who: Footballer = sim.players[e["id"]]
			hud.banner(tr("FOUL"), who.pname, 1.6, Color(1.0, 0.85, 0.3))
		"card":
			var who2: Footballer = sim.players[e["id"]]
			var red: bool = e.get("c", "") == "red"
			hud.banner(tr("RED") if red else tr("YELLOW"), who2.pname, 2.2, Color(1, 0.2, 0.2) if red else Color(1, 0.9, 0.2))
		"offside":
			hud.banner(tr("OFFSIDE"), "", 1.5, Color(1, 0.9, 0.4))
		"out":
			var k: String = e.get("k", "")
			if k == "corner":
				hud.hint(tr("CORNER"))
			elif k == "goal_kick":
				hud.hint(tr("GOAL_KICK"))
			else:
				hud.hint(tr("THROW_IN"))
		"restart":
			cam.snap()
			if int(e.get("type", -1)) == MatchSim.Restart.PENALTY:
				hud.banner(tr("PENALTY"), "", 1.8, Color(1, 0.4, 0.3))
		"kickoff":
			cam.snap()
		"halftime":
			hud.banner(tr("HALFTIME"), "%d - %d" % [sim.teams[0]["score"], sim.teams[1]["score"]], 3.0)
		"fulltime":
			hud.banner(tr("FULLTIME"), "%d - %d" % [sim.teams[0]["score"], sim.teams[1]["score"]], 3.0)
		"fall":
			Sfx.grunt(sim.players[int(e["id"])].pos + Vector3(0, 1.0, 0) if e.has("id") else sim.ball.pos)


func _on_goal(e: Dictionary) -> void:
	excite = 1.0
	cam.shake = 0.8
	var scorer_id: int = e.get("scorer", -1)
	var name := ""
	if scorer_id >= 0:
		var sp: Footballer = sim.players[scorer_id]
		name = sp.pname
		if e.get("own", false):
			name += " (" + tr("OWN_GOAL") + ")"
	var assist_id: int = e.get("assist", -1)
	var sub := name
	if assist_id >= 0:
		sub += "   ·   " + sim.players[assist_id].pname
	var mine: bool = human_id >= 0 and int(e["team"]) == sim.players[human_id].team
	for p in sim.players:
		var v: Node = views[p.id]
		if p.id == scorer_id or p.sent_off or not v.has_method("play_emote"):
			continue
		if p.team == int(e["team"]):
			if randf() < 0.6:
				v.call("play_emote", "clap", randf() * 0.6)
		elif not p.is_gk() or randf() < 0.5:
			v.call("play_emote", "dejected", 0.3 + randf() * 0.8)
	hud.banner(tr("GOAL"), sub, 3.6, Color(0.35, 1.0, 0.55) if mine or human_id < 0 else Color(1.0, 0.45, 0.4))
	var spos: Vector3 = sim.players[scorer_id].pos + Vector3(0, 1.6, 0) if scorer_id >= 0 and scorer_id < sim.players.size() else sim.ball.pos
	Sfx.goal(mine or human_id < 0, spos)
	if mine and Game.settings.get("vibration", true) and Game.is_phone():
		Input.vibrate_handheld(220)
	# replay after the celebration starts
	# celebration close-up, then the replay
	if scorer_id >= 0 and not (net and not net.host):
		_celebrate_id = scorer_id
		_prev_cam_mode = cam.mode
		cam.mode = CameraRig.Mode.CINE
		cam.cine_t = randf() * TAU
		cam.snap()
	var tw := create_tween()
	tw.tween_interval(1.9)
	tw.tween_callback(_start_replay)


func _start_replay() -> void:
	if net and not net.host:
		return
	replay_frames = replay.last_seconds(5.0)
	if replay_frames.size() < 30:
		return
	replay_mode = true
	replay_t = 0.0
	Game.fade_flash()
	if _celebrate_id >= 0:
		cam.mode = _prev_cam_mode
		_celebrate_id = -1
	_replay_cam_mode = cam.mode
	cam.mode = CameraRig.Mode.TV
	cam.snap()
	hud.hint(tr("REPLAY"), 3.0)


var _replay_cam_mode := CameraRig.Mode.PRO
var _celebrate_id := -1
var _prev_cam_mode := CameraRig.Mode.PRO


func _replay_process(delta: float) -> void:
	replay_t += delta * 0.55
	var idx := int(replay_t * ReplayBuffer.RATE)
	if idx >= replay_frames.size() - 1:
		replay_mode = false
		cam.mode = _replay_cam_mode
		cam.snap()
		Game.fade_flash()
		return
	var a := fmod(replay_t * ReplayBuffer.RATE, 1.0)
	var f0: Dictionary = replay_frames[idx]
	var f1: Dictionary = replay_frames[idx + 1]
	var bp: Vector3 = (f0["ball"] as Vector3).lerp(f1["ball"], a)
	for i in views.size():
		var g: Footballer = replay.ghost(i, f0, f1, a)
		(views[i] as Node3D).call("sync", g, g.pos, g.face, delta * 0.55)
	_update_ball(bp, f0["spin"], delta * 0.55)
	cam.mode = CameraRig.Mode.TV
	_update_cutaway()
	cam.zoom = 0.62
	cam.update_cam(delta, bp, bp, 1)
	cam.zoom = 1.0
	hud.update_hud(delta, now, "attack", -1.0)


func _finish() -> void:
	Sfx.match_end()
	var res := {"score": [sim.teams[0]["score"], sim.teams[1]["score"]],
		"names": cfg.team_names, "short": cfg.team_short, "goals": sim.goals,
		"shots": sim.shots_n, "poss": sim.poss_time, "corners": sim.corners_n, "fouls": sim.fouls_n}
	var ratings := []
	for p in sim.players:
		ratings.append({"id": p.id, "team": p.team, "name": p.pname, "num": p.number,
			"role": p.role, "rating": sim.rating(p), "stats": p.stats.duplicate(), "human": p.human})
	res["ratings"] = ratings
	res["human_id"] = profile_id if profile_id >= 0 else human_id
	res["team_mode"] = team_mode
	res["meta"] = Game.next_match_meta
	Game.last_result = res
	if Net.dedicated:
		Net.send_end(res)
		print("[match] finished ", res["score"])
		get_tree().create_timer(1.5).timeout.connect(func() -> void: get_tree().quit())
		return
	if net and net.host:
		Net.send_end(res)
		Net.stop()
	Game.goto("res://scenes/results.tscn")


func _exit_tree() -> void:
	CharacterView.ball_node = null
