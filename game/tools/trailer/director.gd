extends Node
## Trailer director: renders one shot with Godot Movie Maker.
##   godot --write-movie out/shot.png --fixed-fps 30 --resolution 1920x1080 \
##         res://tools/trailer/director.tscn -- <shot name>
## The sim is deterministic, so a look-ahead copy records the whole future
## (ball, players, owner) and the camera is planned with that knowledge:
## non-causal smoothing, anticipation, framing of the shot before it happens.
## WARM frames are rendered muted before the in-point (cut away later).

const Cfg := preload("res://tools/trailer/cfg.gd")
const Shots := preload("res://tools/trailer/shots.gd")

const FPS := 30.0
const WARM := 45

var view: MatchView
var spec: Dictionary
var cs: Dictionary
var f := -WARM
var total := 0
var tps: PackedFloat64Array = []     # sim tick position per frame (index f + WARM)
var rec_t0 := 0
var rec_ball: PackedVector3Array = []
var rec_owner: PackedInt32Array = []
var rec_pl: Array = []               # PackedVector3Array per tick
var c_pos := Vector3.ZERO
var c_look := Vector3.ZERO
var c_init := false
var _goal_frames := 0
var _last_carrier := -1
var out_dir := ""
var _cur := -999
var _tasks: Array = []
var _p0 := -1
var gs := 1.0
var pitch_hl := 22.0
var la_pitch: Pitch
var _frozen := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var shot_name := args[0] if args.size() > 0 else "test"
	out_dir = args[1] if args.size() > 1 else "/tmp/trailer_frames"
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.frame_post_draw.connect(_grab)
	spec = Shots.get_shot(shot_name)
	cs = spec.get("cam", {"type": "rig", "mode": "TV"})
	Game.settings["quality"] = 2
	Game.settings["camera"] = 0
	print("[director] window ", get_window().size, " screen ", DisplayServer.screen_get_size())
	var want := DisplayServer.screen_get_size()
	if get_window().size != want:
		get_window().size = want
	var kind: String = spec["kind"]
	var seed := int(spec["seed"])
	total = int(round(float(spec["len"]) * FPS))
	var in_tick := float(spec.get("in", 0.0)) * 60.0
	if spec.has("sync"):
		# place sim tick sync[0] at output second sync[1] (through the slow-motion profile)
		var sy: Array = spec["sync"]
		var adv := 0.0
		for k in int(round(float(sy[1]) * FPS)):
			adv += 60.0 / FPS * _time_scale(float(k) / FPS)
		in_tick = float(sy[0]) - adv
	# --- frame -> sim tick map (slow motion profile)
	var tp := in_tick - 2.0 * WARM
	for i in WARM + total + 1:
		tps.append(tp)
		var t := float(i - WARM) / FPS
		tp += 60.0 / FPS * _time_scale(t)
	# --- look-ahead record
	var la := MatchSim.new(Cfg.make(kind, seed))
	rec_t0 = maxi(int(tps[0]) - 120, 0)
	var t_end := int(tps[tps.size() - 1]) + 240
	while la.tick < t_end:
		la.step()
		if la.tick >= rec_t0:
			rec_ball.append(la.ball.pos)
			rec_owner.append(la.owner)
			var pp := PackedVector3Array()
			for p in la.players:
				pp.append(p.pos)
			rec_pl.append(pp)
	rec_t0 = t_end - rec_ball.size() + 1
	# goal side (+1/-1) of the synced event, for goal-relative camera positions
	if spec.has("sync"):
		gs = 1.0 if _ball(float(spec["sync"][0])).x > 0.0 else -1.0
	elif cs.has("gs"):
		gs = float(cs["gs"])
	pitch_hl = la.pitch.hl()
	la_pitch = la.pitch
	# --- the rendered match
	Game.next_match = Cfg.make(kind, seed)
	var meta := {}
	if spec.has("follow"):
		meta["follow"] = int(spec["follow"])
	Game.next_match_meta = meta
	view = load("res://scenes/match.tscn").instantiate()
	view.manual_step = true
	add_child(view)
	view.intro_t = 0.0
	view.cam.snap()
	if cs["type"] == "rig":
		view.cam.mode = CameraRig.Mode.get(str(cs["mode"]))
		if spec.has("follow"):
			view.cam.follow_id = int(spec["follow"])
		view.cam.zoom = float(cs.get("zoom", 1.0))
	else:
		view.cam.mode = CameraRig.Mode.PRO
	view._prev_cam_mode = view.cam.mode
	view.hud.visible = bool(spec.get("hud", false))
	if spec.get("no_trail", false) and view.fx._trail:
		view.fx._trail.visible = false
	_apply_quality()
	# night pano (Shanghai Bund): turn its landmark tower to +Z, behind the usual camera side
	var sky_rot := float(spec.get("sky_rot", 38.0 if not kind.ends_with("day") else 0.0))
	var we := _find_env(view)
	if we and sky_rot != 0.0:
		we.environment.sky_rotation = Vector3(0, deg_to_rad(sky_rot), 0)
	AudioServer.set_bus_mute(0, true)
	var first := int(ceil(tps[0]))
	while view.sim.tick < first:
		view.replay_mode = false
		view._tick(1.0 / 60.0)
	# goals during the fast-forward queued replay tweens / fades: drop them
	for tw in get_tree().get_processed_tweens():
		tw.kill()
	view.replay.frames.clear()
	view._celebrate_id = -1
	view.hud._banner_t = 0.0
	view.hud._hint_t = 0.0
	view.hud.update_hud(0.0, view.now, "attack", -1.0)
	print("[director] %s kind=%s seed=%d in=%.1f frames=%d gs=%d check ball %s vs %s" % [shot_name, kind, seed, in_tick, total, int(gs),
		str(view.sim.ball.pos), str(_ball(float(view.sim.tick)))])


func _find_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var r := _find_env(c)
		if r:
			return r
	return null


func _apply_quality() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(spec.get("ss", 1.5))
	if OS.get_environment("TR_PREVIEW") != "":
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	view.cam.attributes = null
	if spec.has("dof"):
		var ca := CameraAttributesPractical.new()
		var d: Array = spec["dof"]
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = float(d[0])
		ca.dof_blur_far_transition = float(d[1])
		ca.dof_blur_amount = float(d[2]) if d.size() > 2 else 0.08
		view.cam.attributes = ca


## Slow-motion profile: spec "slow" = [[t0, t1, scale, ramp], ...] in output seconds from the in-point.
func _time_scale(t: float) -> float:
	var s := 1.0
	for seg: Array in spec.get("slow", []):
		var t0 := float(seg[0])
		var t1 := float(seg[1])
		var v := float(seg[2])
		var r := float(seg[3]) if seg.size() > 3 else 0.15
		var w := 0.0
		if t >= t0 and t <= t1:
			w = 1.0
		elif t > t0 - r and t < t0:
			w = smoothstep(t0 - r, t0, t)
		elif t > t1 and t < t1 + r:
			w = 1.0 - smoothstep(t1, t1 + r, t)
		s = lerpf(s, v, w)
	return s


## Save the frame that was just drawn (window resolution; Movie Maker itself only records audio).
func _grab() -> void:
	if OS.get_environment("TR_DEBUG") != "":
		print("[grab] cur=", _cur, " pf=", Engine.get_process_frames())
	if _cur < 0 or _cur >= total:
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/f_%04d.png" % [out_dir, _cur]
	# the lambda keeps the Image alive (a bound method callable does not hold a reference)
	_tasks.append(WorkerThreadPool.add_task(func() -> void: img.save_png(path)))
	_cur = -999


func _process(_d: float) -> void:
	var i := f + WARM
	if i >= tps.size():
		for id: int in _tasks:
			WorkerThreadPool.wait_for_task_completion(id)
		print("[director] done frames=%d p0=%d pend=%d" % [total, _p0, Engine.get_process_frames()])
		get_tree().quit()
		return
	if f == 0:
		AudioServer.set_bus_mute(0, false)
		_p0 = Engine.get_process_frames()
	# keep the PNG queue bounded
	while _tasks.size() > 12:
		WorkerThreadPool.wait_for_task_completion(_tasks.pop_front())
	var tp := tps[i]
	if OS.get_environment("TR_DEBUG") != "":
		print("[f] ", f, " tick=", view.sim.tick, " tp=", tp, " ms=", Time.get_ticks_msec())
	var target := int(ceil(tp - 1e-6))
	var ts := _time_scale(float(f) / FPS)
	var guard := 0
	while view.sim.tick < target and guard < 600:
		guard += 1
		view.replay_mode = false
		view._tick(1.0 / 60.0)
		for e in view.sim.events:
			if e["t"] == "goal":
				_goal_frames = 90
	if _goal_frames > 0:
		_goal_frames -= 1
		view.replay.frames.clear()     # no in-game replay inside a trailer shot
	view.replay_mode = false
	var alpha := clampf(1.0 - (float(target) - tp), 0.0, 1.0)
	view._render(ts / FPS, alpha)
	if cs["type"] != "rig":
		_camera(tp, float(f) / FPS)
	_cur = f
	f += 1


# ---------------------------------------------------------------- record access
func _idx(t: float) -> Array:
	var x := clampf(t - rec_t0, 0.0, rec_ball.size() - 1.001)
	return [int(x), x - floor(x)]


func _ball(t: float) -> Vector3:
	var ia := _idx(t)
	return rec_ball[ia[0]].lerp(rec_ball[ia[0] + 1], ia[1])


func _pl(id: int, t: float) -> Vector3:
	var ia := _idx(t)
	return (rec_pl[ia[0]] as PackedVector3Array)[id].lerp((rec_pl[ia[0] + 1] as PackedVector3Array)[id], ia[1])


func _owner(t: float) -> int:
	return rec_owner[_idx(t)[0]]


## Target point at sim tick t: "ball", "carrier" (owner, else ball), "mid" (ball/carrier blend) or a player id.
func _target(what: Variant, t: float) -> Vector3:
	if what is int or what is float:
		return _pl(int(what), t) + Vector3(0, 1.0, 0)
	var sw := str(what)
	if sw.begins_with("ball@"):
		return _ball(float(sw.substr(5)))
	if sw.begins_with("pl@"):     # pl@<id>@<tick>: a player frozen at a tick
		var pr := sw.split("@")
		return _pl(int(pr[1]), float(pr[2])) + Vector3(0, 1.0, 0)
	match sw:
		"ball":
			return _ball(t)
		"carrier":
			var o := _owner(t)
			if o >= 0:
				_last_carrier = o
				return _pl(o, t) + Vector3(0, 1.0, 0)
			return _ball(t) + Vector3(0, 0.5, 0)
	return _ball(t)


## Centred moving average over +-w seconds of sim time (look-ahead smoothing).
func _smooth(what: Variant, t: float, w: float) -> Vector3:
	if w <= 0.0:
		return _target(what, t)
	var acc := Vector3.ZERO
	var n := 0
	var step := maxf(w * 60.0 / 8.0, 1.0)
	var k := -w * 60.0
	while k <= w * 60.0 + 0.001:
		acc += _target(what, t + k)
		n += 1
		k += step
	return acc / n


func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	var v := Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if cs.get("goal_rel", false):
		# x measured from the goal line of the synced goal (+ = into the goal), z mirrored with it
		v = Vector3(gs * (pitch_hl + v.x), v.y, gs * v.z)
	return v


func _camera(tp: float, t: float) -> void:
	var cam := view.cam
	var pitch := view.sim.pitch
	var dur := maxf(float(spec["len"]), 0.01)
	var u := clampf(t / dur, 0.0, 1.0)
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := float(cs.get("fov", 45.0))
	if cs.has("fov_to"):
		fov = lerpf(fov, float(cs["fov_to"]), smoothstep(0.0, 1.0, u))
	var look_w := float(cs.get("look_w", 0.35))
	var look_what: Variant = cs.get("look", cs.get("target", "ball"))
	look = _smooth(look_what, tp, look_w) + Vector3(0, float(cs.get("look_h", 0.0)), 0)
	if cs.has("look_mix"):
		var lm: Array = cs["look_mix"]
		var other: Vector3 = _v3(lm[0]) if lm[0] is Array else _smooth(lm[0], tp, look_w)
		look = look.lerp(other, float(lm[1]))
	match str(cs["type"]):
		"track":
			# side-on tracking: offset from the (smoothed) target in a world direction
			var tgt := _smooth(cs.get("target", "carrier"), tp, float(cs.get("w", 0.6)))
			var yaw := deg_to_rad(float(cs.get("yaw", 0.0)) + float(cs.get("yaw_speed", 0.0)) * t)
			var dir := Vector3(sin(yaw), 0, cos(yaw))
			pos = tgt + dir * float(cs.get("dist", 7.0))
			pos.y = float(cs.get("h", 1.0))
		"fixed":
			if str(cs.get("pos", "")) == "auto_net":
				# inside the goal, top corner opposite to where the ball goes in
				var gt := float(spec["sync"][0])
				var zb := _ball(gt).z
				var side := -signf(zb) if absf(zb) > 0.05 else 1.0
				pos = Vector3(gs * (pitch_hl + float(cs.get("depth", 1.2))), la_pitch.goal_height - float(cs.get("drop", 0.35)),
					side * (la_pitch.goal_width * 0.5 - float(cs.get("inset", 0.35))))
			else:
				pos = _v3(cs["pos"])
		"orbit":
			var ctr: Vector3
			if cs.get("center") is Array:
				ctr = _v3(cs["center"])
			else:
				ctr = _smooth(cs.get("center", "ball"), tp, float(cs.get("w", 0.8)))
			var a := deg_to_rad(float(cs.get("a0", 0.0)) + float(cs.get("speed", 10.0)) * t)
			var r := lerpf(float(cs.get("r", 20.0)), float(cs.get("r_to", cs.get("r", 20.0))), smoothstep(0.0, 1.0, u))
			var h := lerpf(float(cs.get("h", 8.0)), float(cs.get("h_to", cs.get("h", 8.0))), smoothstep(0.0, 1.0, u))
			pos = Vector3(ctr.x, 0, ctr.z) + Vector3(cos(a), 0, sin(a)) * r + Vector3(0, h, 0)
			if not cs.has("look"):
				look = ctr + Vector3(0, float(cs.get("look_h", 1.0)), 0)
		"pan":
			pos = _v3(cs["pos"])
			var pa := deg_to_rad(float(cs.get("a0", 0.0)) + float(cs.get("speed", 120.0)) * t)
			look = pos + Vector3(cos(pa), float(cs.get("tilt", 0.0)), sin(pa))
		"dolly":
			var e := u
			if str(cs.get("ease", "inout")) == "inout":
				e = smoothstep(0.0, 1.0, u)
			elif str(cs.get("ease", "")) == "out":
				e = 1.0 - pow(1.0 - u, 2.0)
			pos = _v3(cs["from"]).lerp(_v3(cs["to"]), e)
			if cs.get("rel", false):
				pos += _smooth(cs.get("target", "ball"), tp, float(cs.get("w", 0.8))) * Vector3(1, 0, 1)
		"chase":
			# behind the target, along its smoothed direction of travel
			var tg := _smooth(cs.get("target", "carrier"), tp, float(cs.get("w", 0.5)))
			var ahead := _smooth(cs.get("target", "carrier"), tp + 20.0, float(cs.get("w", 0.5)))
			var d := ahead - tg
			d.y = 0.0
			if d.length() < 0.05:
				d = c_look - c_pos
				d.y = 0.0
			d = d.normalized()
			if str(cs.get("dir", "")) == "attack":
				var att := Vector3(gs, 0, 0)
				d = (att * float(cs.get("att_w", 0.7)) + d * (1.0 - float(cs.get("att_w", 0.7)))).normalized()
			pos = tg - d * float(cs.get("back", 4.5)) + Vector3(0, float(cs.get("h", 1.8)), 0)
			if str(cs.get("target", "")) == "ball":
				pos.y = maxf(pos.y, tg.y + float(cs.get("h", 0.6)))
			if cs.has("max_x"):     # stop short of the goal (goal-relative)
				var mx := float(cs["max_x"])
				var gx := gs * (pitch_hl + mx)
				pos.x = minf(pos.x, gx) if gs > 0 else maxf(pos.x, gx)
			pos += d.cross(Vector3.UP) * float(cs.get("side", 0.0))
			if not cs.has("look"):
				look = tg + d * 6.0 + Vector3(0, float(cs.get("look_h", -0.2)), 0)
	# keep inside the cage / bowl
	if cs.get("clamp", true):
		var lx := pitch.hl() - 0.4 + (pitch.runoff_x if not pitch.walls else 0.0)
		var lz := pitch.hw() - 0.4 + (pitch.runoff_z if not pitch.walls else 0.0)
		pos.x = clampf(pos.x, -lx, lx)
		pos.z = clampf(pos.z, -lz, lz)
	pos.y = maxf(pos.y, 0.25)
	if cs.has("freeze_at") and tp >= float(cs["freeze_at"]):
		if not _frozen:
			_frozen = true
		pos = c_pos
	# camera inertia (seconds); 0 = locked to the plan
	var lag := float(cs.get("lag", 0.0))
	if not c_init or lag <= 0.0:
		c_pos = pos
		c_look = look
		c_init = true
	else:
		var k := 1.0 - exp(-(1.0 / FPS) / lag)
		c_pos = c_pos.lerp(pos, k)
		c_look = c_look.lerp(look, 1.0 - exp(-(1.0 / FPS) / maxf(lag * 0.6, 0.01)))
	var hand := Vector3.ZERO
	if cs.has("hand"):     # subtle hand-held drift
		var hs := float(cs["hand"])
		hand = Vector3(sin(t * 1.3) * 0.6 + sin(t * 2.9) * 0.3, sin(t * 1.7 + 1.0) * 0.4, 0) * hs
	cam.global_position = c_pos + hand
	if c_pos.distance_to(c_look) > 0.01:
		cam.look_at(c_look, Vector3.UP)
	if cs.has("roll"):
		cam.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(float(cs["roll"])))
	cam.fov = fov
