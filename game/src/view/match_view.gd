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
var manual_step := false        # tools advance the sim explicitly (offline capture)


func _ready() -> void:
	cfg = Game.next_match if Game.next_match else Game.quick_match(5, Footballer.Role.FWD, 1)
	quality = int(Game.settings.get("quality", 1))
	sim = MatchSim.new(cfg)
	replay = ReplayBuffer.new(sim)
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	VenueBuilder.build(sim.pitch, cfg, world, quality)
	PitchBuilder.build(sim.pitch, world)
	_spawn_views()
	_spawn_ball()
	for p in sim.players:
		if p.human == 0:
			human_id = p.id
	if human_id >= 0:
		human = HumanController.new(sim, human_id)
		human.gk_assist = cfg.gk_assist
		human.aim_assist = cfg.aim_assist
	cam = CameraRig.new()
	cam.setup(sim, human_id)
	cam.mode = CameraRig.Mode.TV if (human_id < 0 and not Game.next_match_meta.has("follow")) or int(Game.settings.get("camera", 0)) == 1 else CameraRig.Mode.PRO
	if Game.next_match_meta.has("cam"):
		cam.mode = int(Game.next_match_meta["cam"])
	add_child(cam)
	cam.current = true
	hud = Hud.new()
	add_child(hud)
	var touch_ui := OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch")
	hud.setup(sim, human_id, touch_ui and human_id >= 0)
	if hud.touch:
		hud.touch.inp = human.inp
	hud.pause_requested.connect(_toggle_pause)
	_snapshot()
	_snapshot()
	Sfx.match_start(cfg)


func _spawn_views() -> void:
	for p in sim.players:
		var kit: Dictionary = cfg.gk_kits[p.team] if p.is_gk() and cfg.gk_kits.size() > p.team and not cfg.gk_kits[p.team].is_empty() else cfg.kits[p.team]
		var v: Node3D
		if CharacterLibrary.available():
			v = CharacterView.new()
		else:
			v = PlayerViewScript.new()
		add_child(v)
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
	var keys := {
		InputState.B.A: Input.is_key_pressed(KEY_J) or Input.is_joy_button_pressed(0, JOY_BUTTON_A),
		InputState.B.B: Input.is_key_pressed(KEY_K) or Input.is_joy_button_pressed(0, JOY_BUTTON_B),
		InputState.B.C: Input.is_key_pressed(KEY_L) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y),
		InputState.B.D: Input.is_key_pressed(KEY_I) or Input.is_joy_button_pressed(0, JOY_BUTTON_X),
		InputState.B.SPRINT: Input.is_key_pressed(KEY_SHIFT) or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER),
	}
	for b in keys:
		var touch_held := hud.touch != null and hud.touch._btn_touch.values().has(b)
		if not touch_held:
			inp.set_button(b, keys[b], now)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_P:
			_toggle_pause()
		elif k.keycode == KEY_C:
			cam.mode = CameraRig.Mode.TV if cam.mode == CameraRig.Mode.PRO else CameraRig.Mode.PRO
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
		_render(render_dt, 1.0)


func _tick(delta: float) -> void:
	now += delta
	if replay_mode:
		return
	_read_devices()
	if human:
		var ax := cam.control_axes()
		human.update(now, ax[0], ax[1])
	sim.step()
	_snapshot()
	replay.record()
	for e in sim.events:
		_on_event(e)
	if human:
		human.inp.end_frame()


func _process(delta: float) -> void:
	if manual_step:
		return
	if replay_mode:
		_replay_process(delta)
		return
	_render(delta, Engine.get_physics_interpolation_fraction())


func _render(delta: float, alpha: float) -> void:
	for i in views.size():
		var p: Footballer = sim.players[i]
		var v: Node3D = views[i]
		if p.sent_off:
			v.visible = false
			continue
		var ip := prev_pos[i].lerp(cur_pos[i], alpha)
		v.call("sync", p, ip, p.face, delta)
	var bp := prev_ball.lerp(cur_ball, alpha)
	_update_ball(bp, sim.ball.spin, delta)
	if human_id >= 0:
		marker.visible = true
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
	cam.update_cam(delta, bp, focus, side)
	excite = maxf(excite - delta * 0.25, _danger() * 0.5)
	VenueBuilder.set_excite(excite)
	Sfx.crowd_level(excite)
	var power := -1.0
	var ctx := "attack"
	if human:
		ctx = human.last_ctx
		if human.inp.held[InputState.B.B] and ctx in ["attack", "setpiece", "support"]:
			power = clampf(human.inp.held_for(InputState.B.B, now) / 0.85, 0.0, 1.0)
	hud.update_hud(delta, now, ctx, power)
	if sim.phase == MatchSim.Phase.FULLTIME and not _ended and sim.phase_t > 2.5:
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
	match t:
		"kick":
			Sfx.kick(e.get("s", 10.0), e.get("kind", "pass"))
		"dribble":
			if not e.get("soft", true):
				Sfx.touch(0.4)
		"touch", "trap":
			Sfx.touch(0.6)
		"bounce":
			Sfx.bounce(e.get("s", 2.0))
		"post", "bar":
			Sfx.post(e.get("s", 10.0))
			excite = 1.0
			hud.hint("TO'SINQ!" if t == "bar" else "USTUN!")
			cam.shake = 0.4
		"net":
			Sfx.net(e.get("s", 5.0))
		"wall":
			Sfx.wall(e.get("s", 5.0))
		"whistle":
			Sfx.whistle(str(e.get("k", "")))
		"goal":
			_on_goal(e)
		"save":
			excite = 0.9
			Sfx.crowd_ooh()
			hud.hint("AJOYIB SEYV!")
		"shot":
			if not e.get("on", false):
				pass
		"tackle":
			if e.get("won", false):
				Sfx.tackle()
		"foul":
			var who: Footballer = sim.players[e["id"]]
			hud.banner("FOL", who.pname, 1.6, Color(1.0, 0.85, 0.3))
		"card":
			var who2: Footballer = sim.players[e["id"]]
			var red: bool = e.get("c", "") == "red"
			hud.banner("QIZIL KARTOCHKA" if red else "SARIQ KARTOCHKA", who2.pname, 2.2, Color(1, 0.2, 0.2) if red else Color(1, 0.9, 0.2))
		"offside":
			hud.banner("OFSAYD", "", 1.5, Color(1, 0.9, 0.4))
		"out":
			var k: String = e.get("k", "")
			if k == "corner":
				hud.hint("BURCHAK")
			elif k == "goal_kick":
				hud.hint("DARVOZADAN ZARBA")
			else:
				hud.hint("AUT")
		"restart":
			cam.snap()
			if int(e.get("type", -1)) == MatchSim.Restart.PENALTY:
				hud.banner("PENALTI!", "", 1.8, Color(1, 0.4, 0.3))
		"kickoff":
			cam.snap()
		"halftime":
			hud.banner("TANAFFUS", "%d - %d" % [sim.teams[0]["score"], sim.teams[1]["score"]], 3.0)
		"fulltime":
			hud.banner("O'YIN TUGADI", "%d - %d" % [sim.teams[0]["score"], sim.teams[1]["score"]], 3.0)
		"fall":
			Sfx.grunt()


func _on_goal(e: Dictionary) -> void:
	excite = 1.0
	cam.shake = 0.8
	var scorer_id: int = e.get("scorer", -1)
	var name := ""
	if scorer_id >= 0:
		var sp: Footballer = sim.players[scorer_id]
		name = sp.pname
		if e.get("own", false):
			name += " (o.g.)"
	var assist_id: int = e.get("assist", -1)
	var sub := name
	if assist_id >= 0:
		sub += "   ·   " + sim.players[assist_id].pname
	var mine: bool = human_id >= 0 and int(e["team"]) == sim.players[human_id].team
	hud.banner("GOL!", sub, 3.6, Color(0.35, 1.0, 0.55) if mine or human_id < 0 else Color(1.0, 0.45, 0.4))
	Sfx.goal(mine or human_id < 0)
	# replay after the celebration starts
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(_start_replay)


func _start_replay() -> void:
	replay_frames = replay.last_seconds(5.0)
	if replay_frames.size() < 30:
		return
	replay_mode = true
	replay_t = 0.0
	Game.fade_flash()
	cam.mode = CameraRig.Mode.CINE if false else cam.mode
	_replay_cam_mode = cam.mode
	cam.mode = CameraRig.Mode.TV
	cam.snap()
	hud.hint("TAKRORLASH", 3.0)


var _replay_cam_mode := CameraRig.Mode.PRO


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
	cam.zoom = 0.62
	cam.update_cam(delta, bp, bp, 1)
	cam.zoom = 1.0
	hud.update_hud(delta, now, "attack", -1.0)


func _finish() -> void:
	var res := {"score": [sim.teams[0]["score"], sim.teams[1]["score"]],
		"names": cfg.team_names, "short": cfg.team_short, "goals": sim.goals,
		"shots": sim.shots_n, "poss": sim.poss_time, "corners": sim.corners_n, "fouls": sim.fouls_n}
	var ratings := []
	for p in sim.players:
		ratings.append({"id": p.id, "team": p.team, "name": p.pname, "num": p.number,
			"role": p.role, "rating": sim.rating(p), "stats": p.stats.duplicate(), "human": p.human})
	res["ratings"] = ratings
	res["human_id"] = human_id
	res["meta"] = Game.next_match_meta
	Game.last_result = res
	Game.goto("res://scenes/results.tscn")
