class_name MatchSim
extends RefCounted
## Authoritative match simulation. Fixed timestep, no scene-tree nodes:
## runs in the game, headless in tests/benchmarks, and on a host for LAN play.

enum Phase { KICKOFF, PLAY, RESTART, GOAL, HALFTIME, FULLTIME }
enum Restart { KICKOFF, THROW_IN, CORNER, GOAL_KICK, FREE_KICK, PENALTY }

const A := Footballer.A
const KICK_ACTS := [Footballer.A.PASS, Footballer.A.LOB, Footballer.A.SHOT, Footballer.A.CHIP,
		Footballer.A.VOLLEY, Footballer.A.GK_KICK, Footballer.A.THROW_IN, Footballer.A.GK_THROW]
const DT := 1.0 / 60.0

var cfg: MatchConfig
var pitch: Pitch
var ball := BallSim.new()
var players: Array[Footballer] = []
var teams: Array = []             # [{score, side, name, short, ids}]
var ai: Array = []                # TeamAI per team
var rng := RandomNumberGenerator.new()

var phase := Phase.KICKOFF
var phase_t := 0.0
var clock := 0.0
var half := 1
var added := 0.0
var tick := 0
var owner := -1
var last_touch := -1
var last_touch_team := -1
var last_touch_kind := ""
var poss_team := -1
var last_pass := {}
var last_shot := {}
var offside_marks: Array = []
var restart := {}
var goals: Array = []
var events: Array = []
var ball_pred := PackedVector3Array()
var pred_dt := 1.0 / 25.0
var pred_tick := -100
var kickoff_team := 0
var overtime := 0.0
var poss_time := [0.0, 0.0]
var shots_n := [0, 0]
var corners_n := [0, 0]
var fouls_n := [0, 0]


func _init(c: MatchConfig) -> void:
	cfg = c
	rng.seed = c.seed
	if c.rules == MatchConfig.Rules.FULL:
		pitch = Pitch.full() if c.per_side >= 9 else Pitch.arena(c.per_side)
		if c.per_side < 9:
			pitch.walls = false
			pitch.runoff_x = 3.0
			pitch.runoff_z = 2.5
	else:
		pitch = Pitch.arena(c.per_side)
	ball.setup(pitch)
	for t in 2:
		teams.append({"score": 0, "side": 1 if t == 0 else -1, "name": c.team_names[t],
			"short": c.team_short[t], "ids": []})
	_build_players()
	for t in 2:
		ai.append(TeamAI.new(self, t))
	kickoff_team = rng.randi() % 2
	_setup_kickoff(kickoff_team)


func is_full() -> bool:
	return cfg.rules == MatchConfig.Rules.FULL


func _build_players() -> void:
	var nid := 0
	for t in 2:
		var slots := Formations.get_slots(cfg.formation[t], cfg.per_side)
		var base: float = cfg.team_strength[t]
		var numbers := _numbers_for(slots)
		for si in slots.size():
			var s: Array = slots[si]
			var p := Footballer.new()
			p.id = nid
			p.team = t
			p.slot = si
			p.role = s[0]
			p.number = numbers[si]
			p.pname = Names.random_surname(rng)
			_roll_attrs(p, base)
			players.append(p)
			teams[t]["ids"].append(nid)
			nid += 1
	# assign humans to slots of their chosen role
	for h in cfg.humans:
		var t: int = h.get("team", 0)
		var role: int = h.get("role", Footballer.Role.FWD)
		var chosen: Footballer = null
		for id in teams[t]["ids"]:
			var p: Footballer = players[id]
			if p.human < 0 and p.role == role:
				chosen = p
				break
		if chosen == null:
			for id in teams[t]["ids"]:
				if players[id].human < 0 and players[id].role != Footballer.Role.GK:
					chosen = players[id]
					break
		if chosen:
			chosen.human = h.get("idx", 0)
			if h.has("name") and str(h["name"]) != "":
				chosen.pname = str(h["name"])
			if h.has("number"):
				chosen.number = int(h["number"])
			var lvl: float = h.get("level", 0.7)
			for attr in ["pace", "accel_attr", "stamina_attr", "shot_attr", "pass_attr",
					"dribble_attr", "tackle_attr", "gk_attr", "strength"]:
				chosen.set(attr, clampf(lvl + rng.randf_range(-0.04, 0.04), 0.3, 0.99))


func _numbers_for(slots: Array) -> Array:
	var out := []
	var used := {}
	var pref := {Footballer.Role.GK: [1, 12], Footballer.Role.DEF: [2, 5, 4, 3, 6, 15],
		Footballer.Role.MID: [8, 6, 10, 14, 16, 18], Footballer.Role.FWD: [9, 7, 11, 19, 17]}
	for s in slots:
		var n := 0
		for cand in pref[s[0]]:
			if not used.has(cand):
				n = cand
				break
		if n == 0:
			n = 20 + out.size()
		used[n] = true
		out.append(n)
	return out


func _roll_attrs(p: Footballer, base: float) -> void:
	var v := func(bias: float) -> float:
		return clampf(base + bias + rng.randfn(0.0, 0.07), 0.2, 0.97)
	match p.role:
		Footballer.Role.GK:
			p.gk_attr = v.call(0.08)
			p.pace = v.call(-0.2)
			p.shot_attr = v.call(-0.2)
			p.pass_attr = v.call(-0.1)
			p.dribble_attr = v.call(-0.25)
			p.tackle_attr = v.call(-0.2)
		Footballer.Role.DEF:
			p.tackle_attr = v.call(0.1)
			p.strength = v.call(0.08)
			p.pace = v.call(-0.02)
			p.shot_attr = v.call(-0.12)
			p.pass_attr = v.call(-0.03)
			p.dribble_attr = v.call(-0.08)
			p.gk_attr = 0.2
		Footballer.Role.MID:
			p.pass_attr = v.call(0.08)
			p.dribble_attr = v.call(0.04)
			p.stamina_attr = v.call(0.08)
			p.shot_attr = v.call(0.0)
			p.tackle_attr = v.call(-0.02)
			p.pace = v.call(0.0)
			p.gk_attr = 0.2
		Footballer.Role.FWD:
			p.shot_attr = v.call(0.1)
			p.pace = v.call(0.06)
			p.dribble_attr = v.call(0.06)
			p.pass_attr = v.call(-0.02)
			p.tackle_attr = v.call(-0.15)
			p.gk_attr = 0.2
	p.accel_attr = v.call(0.0)
	p.stamina_attr = maxf(p.stamina_attr, v.call(0.0))
	p.strength = maxf(p.strength, v.call(-0.03))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func side_of(team: int) -> int:
	return teams[team]["side"]


func own_goal(team: int) -> Vector3:
	return pitch.goal_center(-side_of(team))


func opp_goal(team: int) -> Vector3:
	return pitch.goal_center(side_of(team))


func team_players(team: int) -> Array[Footballer]:
	var out: Array[Footballer] = []
	for id in teams[team]["ids"]:
		var p: Footballer = players[id]
		if not p.sent_off:
			out.append(p)
	return out


func gk_of(team: int) -> Footballer:
	for id in teams[team]["ids"]:
		var p: Footballer = players[id]
		if p.role == Footballer.Role.GK and not p.sent_off:
			return p
	return null


func carrier() -> Footballer:
	return players[owner] if owner >= 0 else null


func emit(e: Dictionary) -> void:
	events.append(e)


func minute() -> int:
	var frac := clock / cfg.duration
	if is_full():
		return int(frac * 90.0) + 1 if half == 1 else int(frac * 90.0) + 1
	return int(frac * 90.0)


func time_left() -> float:
	return maxf(cfg.duration - clock, 0.0)


func half_len() -> float:
	return cfg.duration * 0.5 if is_full() else cfg.duration


## Shared ball prediction for AI (refreshed at most every 3 ticks).
func prediction() -> PackedVector3Array:
	if tick - pred_tick >= 3:
		pred_tick = tick
		if ball.in_hands >= 0:
			ball_pred = PackedVector3Array()
			ball_pred.resize(75)
			ball_pred.fill(ball.pos)
		else:
			ball_pred = ball.predict(75, pred_dt)
	return ball_pred


# ---------------------------------------------------------------------------
# Main step
# ---------------------------------------------------------------------------

func step() -> void:
	tick += 1
	events.clear()
	phase_t += DT
	match phase:
		Phase.KICKOFF, Phase.RESTART:
			_setpiece_step()
		Phase.PLAY:
			_play_step()
			_clock_step()
		Phase.GOAL:
			_idle_step(true)
			if phase_t > 4.2:
				if _time_over():
					_end_period()
				else:
					_setup_kickoff(kickoff_team)
		Phase.HALFTIME:
			_idle_step(false)
			if phase_t > 3.0:
				half = 2
				for t in 2:
					teams[t]["side"] = -teams[t]["side"]
				for p in players:
					p.stamina = minf(1.0, p.stamina + 0.35)
				_setup_kickoff(1 - kickoff_team_first)
		Phase.FULLTIME:
			_idle_step(false)


var kickoff_team_first := 0


func _clock_step() -> void:
	clock += DT
	if poss_team >= 0:
		poss_time[poss_team] += DT
	if _time_over():
		# let a dangerous attack finish (max 8 s)
		var danger := false
		if poss_team >= 0:
			var gx := pitch.goal_x(side_of(poss_team))
			danger = absf(ball.pos.x - gx) < pitch.length * 0.33
		overtime += DT
		if not danger or overtime > 8.0:
			_end_period()


func _time_over() -> bool:
	if is_full() and half == 1:
		return clock >= cfg.duration * 0.5 + added
	return clock >= cfg.duration + added


func _end_period() -> void:
	overtime = 0.0
	if is_full() and half == 1:
		phase = Phase.HALFTIME
		phase_t = 0.0
		clock = cfg.duration * 0.5
		added = 0.0
		emit({"t": "whistle", "k": "half"})
		emit({"t": "halftime"})
	else:
		phase = Phase.FULLTIME
		phase_t = 0.0
		emit({"t": "whistle", "k": "full"})
		emit({"t": "fulltime"})
	owner = -1


func _idle_step(celebrate: bool) -> void:
	# players walk around / celebrate, ball settles
	for p in players:
		if p.sent_off:
			continue
		p.cmd.move = p.vel * 0.0
		if p.action != A.NONE:
			p.act_t += DT
			if p.act_t >= p.act_dur:
				p.end_action()
		p.move_step(DT, false)
	ball.step(DT)
	ball.events.clear()


func _play_step() -> void:
	for t in 2:
		ai[t].think(DT)
	for p in players:
		if p.sent_off:
			continue
		if p.no_touch > 0.0:
			p.no_touch -= DT
		_try_start_action(p)
		_update_action(p)
		if p.action == A.NONE or p.action in [A.TRAP, A.CELEBRATE]:
			p.move_step(DT, p.id == owner)
		_zone_stat(p)
	_separate_players()
	_ball_control()
	_gk_hands()
	if ball.in_hands >= 0:
		var gk: Footballer = players[ball.in_hands]
		ball.pos = gk.pos + gk.face * 0.3 + Vector3(0, 1.05, 0)
		ball.vel = gk.vel
		ball.spin = Vector3.ZERO
	else:
		ball.step(DT)
		_ball_events()
		_ball_bodies()
	_check_goal()
	if is_full():
		_check_out()
	else:
		_check_stuck()


func _zone_stat(p: Footballer) -> void:
	p.stats["play_t"] += DT


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _ball_near_feet(p: Footballer, reach := 0.95) -> bool:
	var d := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length()
	return d < reach and ball.pos.y < 0.8 and ball.in_hands < 0


func _try_start_action(p: Footballer) -> void:
	var c := p.cmd
	if c.act == Cmd.Act.NONE:
		return
	var req := c.act
	var kick_req := req in [Cmd.Act.PASS, Cmd.Act.THROUGH, Cmd.Act.LOB, Cmd.Act.CROSS,
		Cmd.Act.SHOT, Cmd.Act.CHIP, Cmd.Act.CLEAR]
	if p.busy():
		if p.action == A.TRAP and p.act_t > 0.1 and p.stun <= 0.0:
			p.end_action()
		elif kick_req and p.stun <= 0.0:
			_queue_first_time(p, c)
			c.clear_action()
			return
		else:
			c.clear_action()
			return
	if p.action == A.TRAP:
		p.end_action()
	var data := {"target": c.target, "power": c.power, "spin": c.spin, "recv": c.receiver, "req": req}
	match req:
		Cmd.Act.PASS, Cmd.Act.THROUGH, Cmd.Act.LOB, Cmd.Act.CROSS, Cmd.Act.SHOT, Cmd.Act.CHIP, Cmd.Act.CLEAR:
			if ball.in_hands == p.id:
				_start_gk_release(p, req, data)
			elif _can_kick_now(p):
				_start_kick(p, req, data)
			elif _ball_header_range(p):
				_start_header(p, data)
			else:
				_queue_first_time(p, c)
		Cmd.Act.TACKLE:
			if owner != p.id:
				p.start_action(A.TACKLE, 0.55, 0.2, {"dir": p.face})
				emit({"t": "act", "id": p.id, "k": "tackle"})
		Cmd.Act.SLIDE:
			if owner != p.id:
				var sdir := p.face
				if c.target != Vector3.ZERO:
					var d := c.target - p.pos
					d.y = 0
					if d.length() > 0.5:
						sdir = d.normalized()
				p.face = sdir
				var spd := maxf(p.vel.length(), 5.5) + 1.0
				p.start_action(A.SLIDE, 1.45, 0.12, {"dir": sdir, "v": spd, "hit": false, "ball": false})
				emit({"t": "act", "id": p.id, "k": "slide"})
		Cmd.Act.GK_DIVE:
			if p.is_gk():
				_start_dive(p, c.target)
		Cmd.Act.GK_THROW, Cmd.Act.GK_KICK:
			if ball.in_hands == p.id:
				_start_gk_release(p, req, data)
		Cmd.Act.THROW_IN:
			pass
		Cmd.Act.SKILL:
			if owner == p.id:
				p.start_action(A.SKILL, 0.55, 0.12, {"skill": c.skill, "dir": c.target})
				emit({"t": "act", "id": p.id, "k": "skill", "s": c.skill})
	c.clear_action()


func _queue_first_time(p: Footballer, c: Cmd) -> void:
	p.queued.copy_from(c)
	p.queued.first_time = true
	p.act_data["queued_t"] = 0.0
	p.queued.power = c.power
	queued_until[p.id] = clock + 1.2


var queued_until := {}


func _can_kick_now(p: Footballer) -> bool:
	if ball.in_hands >= 0:
		return false
	var d := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length()
	if owner == p.id:
		return d < 1.6 and ball.pos.y < 0.9
	# ball reachable within the wind-up?
	var bv := Vector2(ball.vel.x, ball.vel.z)
	var rel := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z)
	var closing := -rel.normalized().dot(bv) if rel.length() > 0.01 else 0.0
	return (d < 1.25 or (d < 2.2 and closing > 1.0)) and ball.pos.y < 1.2


func _ball_header_range(p: Footballer) -> bool:
	var d := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length()
	return d < 2.5 and ball.pos.y > 1.1 and ball.pos.y < 3.4


func _start_kick(p: Footballer, req: int, data: Dictionary) -> void:
	var pw: float = data["power"]
	var kind := A.PASS
	var wind := 0.13
	var dur := 0.45
	var bh := ball.pos.y
	match req:
		Cmd.Act.PASS, Cmd.Act.THROUGH:
			kind = A.PASS
			wind = 0.12 + 0.1 * pw
			dur = wind + 0.24
		Cmd.Act.LOB, Cmd.Act.CROSS, Cmd.Act.CLEAR:
			kind = A.LOB
			wind = 0.2 + 0.05 * pw
			dur = wind + 0.3
		Cmd.Act.SHOT:
			kind = A.SHOT
			wind = 0.18 + 0.12 * pw
			dur = wind + 0.34
		Cmd.Act.CHIP:
			kind = A.CHIP
			wind = 0.2
			dur = wind + 0.3
	if bh > 0.42 and kind != A.LOB:
		kind = A.VOLLEY if req == Cmd.Act.SHOT else kind
	if owner != p.id and ball.ground_speed() > 3.0:
		wind = minf(wind, 0.12)   # first-time / moving ball: quick strike
	data["kind_req"] = req
	p.start_action(kind, dur, wind, data)
	emit({"t": "act", "id": p.id, "k": "kick", "kind": kind, "wind": wind})


func _start_header(p: Footballer, data: Dictionary) -> void:
	p.start_action(A.HEADER, 0.75, 0.22, data)
	emit({"t": "act", "id": p.id, "k": "header"})


func _start_dive(p: Footballer, target: Vector3) -> void:
	if p.action == A.GK_DIVE:
		return
	var d := target - p.pos
	d.y = 0.0
	var reach := 2.3 + p.gk_attr * 0.9
	var lat := d.length()
	if lat > reach:
		d = d / lat * reach
		lat = reach
	var h := clampf(target.y, 0.2, 2.6)
	var dur := 1.25 + lat * 0.08
	p.start_action(A.GK_DIVE, dur, 0.1, {"from": p.pos, "to": p.pos + d, "h": h,
		"dir": d.normalized() if lat > 0.05 else p.face, "lat": lat})
	emit({"t": "act", "id": p.id, "k": "dive", "lat": lat, "h": h})


func _start_gk_release(p: Footballer, req: int, data: Dictionary) -> void:
	var kind := A.GK_THROW
	if req in [Cmd.Act.GK_KICK, Cmd.Act.SHOT, Cmd.Act.LOB, Cmd.Act.CLEAR]:
		kind = A.GK_KICK
	data["kind_req"] = req
	if kind == A.GK_THROW:
		p.start_action(A.GK_THROW, 0.85, 0.42, data)
	else:
		p.start_action(A.GK_KICK, 1.0, 0.55, data)
	emit({"t": "act", "id": p.id, "k": "gk_release", "kind": kind})


func _update_action(p: Footballer) -> void:
	if p.action == A.NONE:
		return
	p.act_t += DT
	match p.action:
		A.PASS, A.LOB, A.SHOT, A.CHIP, A.VOLLEY:
			if not p.act_done:
				_approach_ball(p)
				if p.act_t >= p.act_contact:
					_kick_contact(p)
			else:
				_recover_move(p, 0.35)
		A.HEADER:
			_header_step(p)
		A.TACKLE:
			_tackle_step(p)
		A.SLIDE:
			_slide_step(p)
		A.GK_DIVE:
			_dive_step(p)
		A.GK_THROW, A.GK_KICK:
			p.vel *= 0.85
			if not p.act_done and p.act_t >= p.act_contact:
				_gk_release_contact(p)
		A.THROW_IN:
			p.vel = Vector3.ZERO
			if not p.act_done and p.act_t >= p.act_contact:
				_throw_in_contact(p)
		A.FALL:
			p.vel *= 0.9
			p.pos += p.vel * DT
			if p.act_t >= p.act_dur:
				p.start_action(A.GETUP, 0.75, 0.0)
				return
		A.GETUP:
			p.vel = Vector3.ZERO
		A.SKILL:
			_skill_step(p)
		A.TRAP:
			pass
		A.CELEBRATE:
			pass
	if p.action != A.NONE and p.act_t >= p.act_dur:
		if p.action == A.SLIDE or p.action == A.GK_DIVE:
			p.start_action(A.GETUP, 0.7, 0.0)
		else:
			p.end_action()


func _recover_move(p: Footballer, k: float) -> void:
	var want := p.cmd.move * p.top_speed(false) * k
	p.vel = p.vel.move_toward(want, 9.0 * DT)
	p.pos += p.vel * DT


## During a kick wind-up the player steps into the ball so the planted foot
## meets it at contact time (kick magnetism, like real footwork adjustments).
func _approach_ball(p: Footballer) -> void:
	var remain := maxf(p.act_contact - p.act_t, DT)
	var bp := ball.pos + ball.vel * remain
	if ball.on_ground():
		var gsp := ball.ground_speed()
		if gsp > 0.1:
			var dec := (ball.roll_c + ball.roll_k * gsp) * remain * remain * 0.5
			bp -= Vector3(ball.vel.x, 0, ball.vel.z).normalized() * minf(dec, gsp * remain)
	bp.y = 0.0
	var tgt: Vector3 = p.act_data.get("target", bp)
	var kdir := tgt - bp
	kdir.y = 0.0
	if kdir.length() < 0.1:
		kdir = p.face
	kdir = kdir.normalized()
	var stand := bp - kdir * 0.36 + kdir.cross(Vector3.UP) * 0.12
	var to := stand - p.pos
	to.y = 0.0
	var need := to / remain
	var maxv := 7.5
	if need.length() > maxv:
		need = need.normalized() * maxv
	p.vel = p.vel.lerp(need, 0.5)
	p.pos += p.vel * DT
	var ang := p.face.signed_angle_to(kdir, Vector3.UP)
	p.face = p.face.rotated(Vector3.UP, clampf(ang, -14.0 * DT, 14.0 * DT)).normalized()


func _kick_error_scale(p: Footballer, kdir: Vector3) -> float:
	var s := 1.0
	var body := p.face.dot(kdir)
	if body < 0.6:
		s += (0.6 - body) * 1.4
	var sp := p.vel.length()
	if sp > 5.5:
		s += (sp - 5.5) * 0.12
	if ball.pos.y > 0.3:
		s += 0.35
	var opp: float = ai[p.team].nearest_opponent_dist(p.pos)
	if opp < 1.6:
		s += (1.6 - opp) * 0.45
	if p.stamina < 0.4:
		s += (0.4 - p.stamina) * 1.2
	return s


func _kick_contact(p: Footballer) -> void:
	p.act_done = true
	var foot := p.pos + p.face * 0.36
	var d := Vector2(ball.pos.x - foot.x, ball.pos.z - foot.z).length()
	var ylim := 1.35 if p.action == A.VOLLEY else 0.85
	if d > 0.78 or ball.pos.y > ylim or ball.in_hands >= 0 or (owner >= 0 and owner != p.id
			and players[owner].team != p.team and _protected(players[owner])):
		emit({"t": "whiff", "id": p.id})
		return
	var data := p.act_data
	var tgt: Vector3 = data["target"]
	var pw: float = data["power"]
	var req: int = data.get("kind_req", Cmd.Act.PASS)
	var from := ball.pos
	var flat := Vector3(tgt.x - from.x, 0.0, tgt.z - from.z)
	if flat.length() < 0.3:
		flat = p.face
	var kdir := flat.normalized()
	var err := _kick_error_scale(p, kdir)
	var v := Vector3.ZERO
	var w := Vector3.ZERO
	var kind := "pass"
	match p.action:
		A.PASS:
			var dist := flat.length()
			var arrive := BallSim.pass_arrive_speed(dist, req == Cmd.Act.THROUGH)
			var v0 := minf(ball.ground_pass_speed(dist, arrive), 26.0 + p.pass_attr * 4.0)
			var sigma := lerpf(5.5, 1.3, p.pass_attr) * err * (0.7 + v0 / 30.0)
			var yaw := deg_to_rad(rng.randfn(0.0, sigma))
			var dir := kdir.rotated(Vector3.UP, yaw)
			v0 *= 1.0 + rng.randfn(0.0, 0.035 * err)
			v = dir * v0
			v.y = 0.25 + v0 * 0.015
			w = BallSim.rolling_spin(v) * 0.6
			kind = "through" if req == Cmd.Act.THROUGH else "pass"
		A.LOB, A.CHIP:
			var elev := 0.62 if p.action == A.CHIP else 0.48
			if req == Cmd.Act.CROSS:
				elev = 0.36
			elif req == Cmd.Act.CLEAR:
				elev = 0.66
			var dist2 := flat.length()
			if dist2 < 14.0:
				elev += 0.12
			var side_curl: float = data.get("spin", Vector3.ZERO).y
			w = kdir.cross(Vector3.UP) * 22.0   # backspin keeps lobs floating
			w.y = side_curl
			v = ball.lob_velocity(from, Vector3(tgt.x, 0, tgt.z), elev, w)
			var sigma2 := lerpf(6.5, 1.8, p.pass_attr) * err
			v = v.rotated(Vector3.UP, deg_to_rad(rng.randfn(0.0, sigma2)))
			v *= 1.0 + rng.randfn(0.0, 0.045 * err)
			kind = "cross" if req == Cmd.Act.CROSS else ("clear" if req == Cmd.Act.CLEAR else "lob")
		A.SHOT, A.VOLLEY:
			var spd := lerpf(15.0, 31.0 + p.shot_attr * 4.0, pw)
			if p.action == A.VOLLEY:
				spd *= 1.05
			w = data.get("spin", Vector3.ZERO)
			var aim := tgt
			var sigma3 := lerpf(4.6, 1.5, p.shot_attr) * err * (0.6 + pw * 0.8)
			if p.action == A.VOLLEY:
				sigma3 *= 1.5
			v = ball.shot_velocity(from, aim, spd, w)
			v = v.rotated(Vector3.UP, deg_to_rad(rng.randfn(0.0, sigma3)))
			var lift := rng.randfn(0.0, sigma3 * 0.7) + maxf(pw - 0.88, 0.0) * 16.0 * (1.2 - p.shot_attr)
			v = v.rotated(kdir.cross(Vector3.UP).normalized(), deg_to_rad(-lift))
			kind = "shot"
	_touch(p, v, w, kind)
	if kind == "shot":
		_register_shot(p, v)


func _protected(o: Footballer) -> bool:
	# ball tucked at the carrier's feet (close control) — needs a tackle
	if o.stun > 0.0 or o.on_floor():
		return false
	var foot := o.pos + o.face * 0.42
	return Vector2(ball.pos.x - foot.x, ball.pos.z - foot.z).length() < 0.55


func _register_shot(p: Footballer, v: Vector3) -> void:
	p.stats["shots"] += 1
	shots_n[p.team] += 1
	var side := side_of(p.team)
	var gx := pitch.goal_x(side)
	var on := false
	if v.x * side > 0.1:
		var preds := ball.predict(90, 1.0 / 40.0)
		for q in preds:
			if absf(q.x) >= pitch.hl() and signf(q.x) == side:
				on = absf(q.z) < pitch.goal_width * 0.5 and q.y < pitch.goal_height
				break
	last_shot = {"id": p.id, "team": p.team, "t": clock, "on": on,
		"xg": ai[p.team].xg(p.pos, p.team), "gx": gx}
	if on:
		p.stats["on_target"] += 1
	emit({"t": "shot", "id": p.id, "on": on, "s": v.length()})


func _header_step(p: Footballer) -> void:
	var c := p.act_contact
	_recover_move(p, 0.45)
	if p.act_done:
		return
	if p.act_t >= c - 0.06 and p.act_t <= c + 0.16:
		var head := p.pos + p.face * 0.12 + Vector3(0, 1.72 + 0.45 * sin(clampf(p.act_t / 0.4, 0, 1) * PI), 0)
		if ball.pos.distance_to(head) < 0.62 and ball.in_hands < 0:
			p.act_done = true
			var tgt: Vector3 = p.act_data["target"]
			var req: int = p.act_data.get("req", Cmd.Act.PASS)
			var dir := tgt - ball.pos
			var spd := 9.0 + ball.speed() * 0.25
			if req == Cmd.Act.SHOT:
				spd = 13.0 + ball.speed() * 0.3 + p.shot_attr * 4.0
				dir.y = minf(dir.y, 0.0) + (tgt.y - ball.pos.y)
			elif req == Cmd.Act.CLEAR:
				spd = 15.0
				dir.y = dir.length() * 0.55
			else:
				dir.y = dir.length() * 0.2
			var sigma := lerpf(9.0, 3.5, p.shot_attr) * _kick_error_scale(p, dir.normalized())
			var v := dir.normalized() * spd
			v = v.rotated(Vector3.UP, deg_to_rad(rng.randfn(0.0, sigma)))
			_touch(p, v, Vector3.ZERO, "header")
			if req == Cmd.Act.SHOT:
				_register_shot(p, v)
	elif p.act_t > c + 0.16:
		p.act_done = true


func _tackle_step(p: Footballer) -> void:
	var dir: Vector3 = p.act_data["dir"]
	if p.act_t < p.act_contact:
		# lunge toward the ball
		var to := ball.pos - p.pos
		to.y = 0
		if to.length() > 0.2:
			dir = dir.slerp(to.normalized(), 0.3).normalized()
			p.act_data["dir"] = dir
		p.face = dir
		p.vel = p.vel.lerp(dir * 4.5, 0.25)
		p.pos += p.vel * DT
		return
	if not p.act_done:
		p.act_done = true
		var foot := p.pos + dir * 0.8
		var d := Vector2(ball.pos.x - foot.x, ball.pos.z - foot.z).length()
		var victim: Footballer = carrier() if owner >= 0 and players[owner].team != p.team else null
		p.stats["tackles"] += 1
		var reach := 0.62 + p.tackle_attr * 0.18
		if d < reach and ball.pos.y < 0.6 and ball.in_hands < 0:
			var strength_edge := p.tackle_attr - (victim.dribble_attr * 0.6 + victim.strength * 0.4 if victim else 0.0)
			var won_clean := rng.randf() < 0.55 + strength_edge * 0.6
			p.stats["tackles_won"] += 1
			if victim:
				victim.stats["lost"] += 1
				victim.stun = 0.25
			if won_clean:
				ball.kick(p.vel * 0.9 + dir * 1.2, Vector3.ZERO)
				owner = p.id
				_first_touch(p, "tackle")
			else:
				var away := dir.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0))
				var v := away * rng.randf_range(4.0, 8.0)
				v.y = rng.randf_range(0.0, 1.5)
				owner = -1
				_touch(p, v, Vector3.ZERO, "poke")
			emit({"t": "tackle", "id": p.id, "won": true, "victim": victim.id if victim else -1})
		elif victim and victim.pos.distance_to(foot) < 0.75:
			emit({"t": "tackle", "id": p.id, "won": false, "victim": victim.id})
			_foul(p, victim, 0.45, false)
		else:
			emit({"t": "tackle", "id": p.id, "won": false, "victim": -1})
			p.act_dur = maxf(p.act_dur, 0.75)   # over-committed: slower recovery
	_recover_move(p, 0.2)


func _slide_step(p: Footballer) -> void:
	var dir: Vector3 = p.act_data["dir"]
	var v0: float = p.act_data["v"]
	var t := p.act_t
	var slide_len := 0.75
	if t < slide_len:
		var k := 1.0 - t / slide_len
		p.vel = dir * v0 * k
	else:
		p.vel = Vector3.ZERO
	p.pos += p.vel * DT
	p.face = dir
	if t >= p.act_contact and t < 0.62:
		var foot := p.pos + dir * 0.95
		var ball_hit: bool = p.act_data["ball"]
		var hit: bool = p.act_data["hit"]
		if not ball_hit and ball.in_hands < 0:
			var d := Vector2(ball.pos.x - foot.x, ball.pos.z - foot.z).length()
			var seg_d := _point_seg_dist2(Vector2(ball.pos.x, ball.pos.z),
				Vector2(p.pos.x, p.pos.z), Vector2(foot.x, foot.z))
			if (d < 0.6 or seg_d < 0.32) and ball.pos.y < 0.55:
				p.act_data["ball"] = true
				var victim: Footballer = carrier() if owner >= 0 and players[owner].team != p.team else null
				if victim:
					victim.stats["lost"] += 1
				p.stats["tackles"] += 1
				p.stats["tackles_won"] += 1
				var v := dir * rng.randf_range(7.0, 12.0) + dir.cross(Vector3.UP) * rng.randf_range(-3.0, 3.0)
				v.y = rng.randf_range(0.0, 2.0)
				owner = -1
				_touch(p, v, Vector3.ZERO, "slide")
				emit({"t": "tackle", "id": p.id, "won": true, "slide": true,
					"victim": victim.id if victim else -1})
		if not hit:
			for o in players:
				if o.team == p.team or o.sent_off or o.on_floor():
					continue
				var dd := _point_seg_dist2(Vector2(o.pos.x, o.pos.z), Vector2(p.pos.x, p.pos.z),
					Vector2(foot.x, foot.z))
				if dd < 0.42:
					p.act_data["hit"] = true
					var clean: bool = p.act_data["ball"]
					_trip(o, dir)
					if not clean:
						var from_behind := o.face.dot(dir) > 0.4
						_foul(p, o, 0.9 if from_behind else 0.6, true)
					break


func _point_seg_dist2(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return pt.distance_to(a + ab * t)


func _trip(o: Footballer, dir: Vector3) -> void:
	if o.id == owner:
		owner = -1
	o.vel = o.vel * 0.6 + dir * 1.5
	o.start_action(A.FALL, 1.0, 0.0, {"dir": dir})
	o.stun = 1.6
	if ball.in_hands == o.id:
		ball.in_hands = -1
	emit({"t": "fall", "id": o.id})


func _skill_step(p: Footballer) -> void:
	# simple feints: step-over (sideways burst) or drag-back (turn with the ball)
	var sk: int = p.act_data.get("skill", 1)
	var t := p.act_t
	if sk == 3:
		# drag back: ball pulled behind, player turns 180°
		if t < 0.3:
			p.vel *= 0.82
		elif not p.act_done:
			p.act_done = true
			p.face = -p.face
			if owner == p.id:
				ball.kick(p.face * 1.6, Vector3.ZERO)
	else:
		var side := -1.0 if sk == 1 else 1.0
		var lat := p.face.cross(Vector3.UP) * side
		if t < 0.25:
			p.vel *= 0.9
		elif not p.act_done:
			p.act_done = true
			if owner == p.id:
				var dir := (p.face * 0.55 + lat).normalized()
				ball.kick(dir * 4.2, Vector3.ZERO)
				p.vel = dir * 5.5
				p.stats["dribbles"] += 1
	p.pos += p.vel * DT


func _dive_step(p: Footballer) -> void:
	var from: Vector3 = p.act_data["from"]
	var to: Vector3 = p.act_data["to"]
	var t := p.act_t
	var fly := 0.42
	var k := clampf((t - 0.06) / fly, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	p.pos = from.lerp(to, e)
	p.vel = (to - from) / fly * (1.0 - k)
	var dir: Vector3 = p.act_data["dir"]
	if t < 0.06:
		return
	# hands sweep from shoulder height toward target height
	var h: float = p.act_data["h"]
	var lat: float = p.act_data["lat"]
	var hand := p.pos + dir * 0.55 + Vector3(0, lerpf(1.3, h, e) if lat > 0.6 else h, 0)
	if ball.in_hands >= 0 or p.act_done or t > fly + 0.35:
		return
	var body_d := _seg_dist3(ball.pos, p.pos + Vector3(0, 0.25, 0), hand)
	if ball.pos.distance_to(hand) < 0.55 or body_d < 0.38:
		p.act_done = true
		_gk_contact(p, ball.pos.distance_to(hand) < 0.4)


func _seg_dist3(pt: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return pt.distance_to(a + ab * t)


## Goalkeeper touches a ball with hands: catch or parry.
func _gk_contact(p: Footballer, clean_hands: bool) -> void:
	var spd := ball.speed()
	var can_hands := pitch.in_box(p.pos, -side_of(p.team))
	var back_pass := last_touch_team == p.team and last_touch_kind in ["pass", "through", "lob"]
	var was_shot: bool = not last_shot.is_empty() and last_shot["team"] != p.team and clock - last_shot["t"] < 3.0
	if not can_hands:
		return
	if back_pass and not was_shot:
		return
	var catch_lim := 13.0 + p.gk_attr * 11.0
	if not clean_hands:
		catch_lim *= 0.55
	if p.action == A.GK_DIVE and p.act_data.get("lat", 0.0) > 1.5:
		catch_lim *= 0.8
	var catch_it := spd < catch_lim and rng.randf() < 0.65 + p.gk_attr * 0.33
	if was_shot:
		p.stats["saves"] += 1
		last_shot["saved"] = true
	if catch_it:
		ball.in_hands = p.id
		ball.vel = Vector3.ZERO
		ball.spin = Vector3.ZERO
		owner = p.id
		gk_hold_t = 0.0
		_first_touch(p, "catch")
		emit({"t": "save" if was_shot else "catch", "id": p.id, "catch": true})
	else:
		# parry away from goal and wide
		var gside := -side_of(p.team)
		var away := Vector3(-gside, 0.0, signf(ball.pos.z - p.pos.z + 0.001))
		var v := ball.vel
		var nrm := (ball.pos - (p.pos + Vector3(0, 1.0, 0))).normalized()
		v = v - nrm * v.dot(nrm) * 1.6
		v = v * 0.45 + away.normalized() * spd * 0.25
		if v.y < 0.0:
			v.y = absf(v.y) * 0.3
		_touch(p, v, Vector3.ZERO, "parry")
		emit({"t": "save" if was_shot else "parry", "id": p.id, "catch": false})


var gk_hold_t := 0.0


func _gk_release_contact(p: Footballer) -> void:
	p.act_done = true
	if ball.in_hands != p.id:
		return
	var tgt: Vector3 = p.act_data["target"]
	ball.in_hands = -1
	owner = -1
	var from := p.pos + p.face * 0.5 + Vector3(0, 1.0 if p.action == A.GK_THROW else 0.5, 0)
	ball.pos = from
	var flat := Vector3(tgt.x - from.x, 0, tgt.z - from.z)
	var v := Vector3.ZERO
	if p.action == A.GK_THROW:
		var d := flat.length()
		if d < 22.0:
			# rolled/bowled throw along the ground
			ball.pos.y = 0.5
			var v0 := ball.ground_pass_speed(d, 4.0)
			v = flat.normalized() * minf(v0, 18.0)
			v.y = -0.5
		else:
			v = ball.lob_velocity(from, tgt, 0.42)
	else:
		v = ball.lob_velocity(from, tgt, 0.62, flat.normalized().cross(Vector3.UP) * 18.0)
		v = v.rotated(Vector3.UP, deg_to_rad(rng.randfn(0.0, 4.0)))
	p.no_touch = 0.4
	_touch(p, v, Vector3.ZERO, "gk_" + ("throw" if p.action == A.GK_THROW else "kick"))


func _throw_in_contact(p: Footballer) -> void:
	p.act_done = true
	var tgt: Vector3 = p.act_data["target"]
	var from := p.pos + p.face * 0.2 + Vector3(0, 2.1, 0)
	ball.pos = from
	ball.in_hands = -1
	var flat := Vector3(tgt.x - from.x, 0, tgt.z - from.z)
	var d := flat.length()
	var elev := 0.35 if d > 12.0 else 0.15
	var v := ball.lob_velocity(from, tgt, elev)
	if v.length() > 17.0:
		v = v.normalized() * 17.0
	p.no_touch = 0.35
	_touch(p, v, Vector3.ZERO, "throw_in")


# ---------------------------------------------------------------------------
# Ball control: dribbling, receiving, interceptions
# ---------------------------------------------------------------------------

func _touch(p: Footballer, v: Vector3, w: Vector3, kind: String) -> void:
	ball.kick(v, w)
	p.no_touch = maxf(p.no_touch, 0.22)
	p.stats["touches"] += 1
	if kind in ["pass", "through", "lob", "cross", "gk_throw", "gk_kick", "throw_in", "clear"]:
		owner = -1
		p.stats["passes"] += 1
		var recv := -1
		if p.act_data.has("recv"):
			recv = p.act_data["recv"]
		last_pass = {"from": p.id, "team": p.team, "t": clock, "recv": recv, "kind": kind,
			"pos": ball.pos}
		_mark_offside(p)
	elif kind in ["shot", "header", "parry", "slide", "poke"]:
		owner = -1
		if kind != "header":
			last_pass = {}
		else:
			last_pass = {"from": p.id, "team": p.team, "t": clock, "recv": -1, "kind": "header",
				"pos": ball.pos}
			_mark_offside(p)
	_set_last_touch(p, kind)
	emit({"t": "kick", "id": p.id, "kind": kind, "s": v.length(), "p": ball.pos})
	if phase == Phase.RESTART or phase == Phase.KICKOFF:
		phase = Phase.PLAY
		phase_t = 0.0
		emit({"t": "live"})


func _set_last_touch(p: Footballer, kind: String) -> void:
	if last_touch_team >= 0 and last_touch_team != p.team:
		pass
	last_touch = p.id
	last_touch_team = p.team
	last_touch_kind = kind
	if kind != "parry" and kind != "body":
		poss_team = p.team


## First touch by `p` after the ball was released by someone.
func _first_touch(p: Footballer, how: String) -> void:
	# offside?
	if is_full() and p.id in offside_marks and how != "catch" and phase == Phase.PLAY:
		offside_marks.clear()
		emit({"t": "offside", "id": p.id})
		_whistle_restart(Restart.FREE_KICK, 1 - p.team, p.pos, "offside")
		return
	offside_marks.clear()
	if not last_pass.is_empty():
		var passer: Footballer = players[last_pass["from"]]
		if last_pass["team"] == p.team and passer.id != p.id:
			passer.stats["passes_ok"] += 1
			assist_from = passer.id
			assist_t = clock
			var gx := pitch.goal_x(side_of(p.team))
			if absf(p.pos.x - gx) < pitch.box_depth * 1.4 and absf(p.pos.z) < pitch.box_width * 0.6:
				passer.stats["key_passes"] += 1
		elif last_pass["team"] != p.team:
			p.stats["interceptions"] += 1
			emit({"t": "pass_int", "id": p.id, "kind": last_pass.get("kind", ""), "dist": passer.pos.distance_to(p.pos)})
			passer.stats["lost"] += 1
			assist_from = -1
		last_pass = {}
	elif last_touch_team >= 0 and last_touch_team != p.team:
		assist_from = -1
	_set_last_touch(p, how)
	emit({"t": "touch", "id": p.id, "how": how})


var assist_from := -1
var assist_t := -100.0


func _ball_control() -> void:
	if ball.in_hands >= 0:
		return
	# --- carrier keeps / loses control ----------------------------------------
	if owner >= 0:
		var o: Footballer = players[owner]
		var dist := Vector2(ball.pos.x - o.pos.x, ball.pos.z - o.pos.z).length()
		var too_high := ball.pos.y > 1.0 and o.action != A.TRAP
		if o.stun > 0.0 or o.on_floor() or dist > 2.9 or too_high or o.sent_off:
			owner = -1
		elif not o.busy() or o.action == A.TRAP:
			_dribble(o)
	# --- others may collect / intercept ---------------------------------------
	var best: Footballer = null
	var best_d := 99.0
	for p in players:
		if p.sent_off or p.id == owner or p.no_touch > 0.0 or p.stun > 0.0 or p.on_floor():
			continue
		if p.action in [A.TACKLE, A.SLIDE, A.GK_DIVE, A.HEADER, A.SHOT, A.PASS, A.LOB, A.CHIP, A.VOLLEY]:
			continue
		var reach := 0.72 if not p.is_gk() else 0.8
		var d := Vector2(ball.pos.x - p.pos.x, ball.pos.z - p.pos.z).length()
		if d > reach + 0.35 or ball.pos.y > 1.9:
			continue
		if d > reach and ball.pos.y > 0.62:
			continue
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		return
	var reach2 := 0.72 if not best.is_gk() else 0.8
	if best_d > reach2:
		if not (ball.pos.y > 0.62):
			return
	if owner >= 0:
		var o2: Footballer = players[owner]
		if o2.team == best.team:
			return
		if _protected(o2):
			return
		# the carrier is still nearer to the ball → only a tackle can win it
		var dc := Vector2(ball.pos.x - o2.foot_point().x, ball.pos.z - o2.foot_point().z).length()
		if dc < 0.75 and dc < best_d:
			return
		# carrier's loose touch intercepted
		o2.stats["lost"] += 1
		best.stats["interceptions"] += 1
		emit({"t": "steal", "id": best.id, "from": o2.id, "d": Vector2(ball.pos.x - o2.pos.x, ball.pos.z - o2.pos.z).length(), "sp": o2.vel.length()})
	_collect(best)


func _collect(p: Footballer) -> void:
	# goalkeeper prefers hands in his box
	if p.is_gk() and pitch.in_box(p.pos, -side_of(p.team)):
		var back_pass := last_touch_team == p.team and last_touch_kind in ["pass", "through", "lob", "cross"]
		if not back_pass:
			_gk_contact(p, true)
			if ball.in_hands == p.id:
				return
	# queued first-time action?
	if p.queued.first_time and queued_until.get(p.id, -1.0) > clock:
		var q := p.queued
		p.queued = Cmd.new()
		_first_touch(p, "first_time")
		if phase != Phase.PLAY:
			return
		owner = p.id
		var data := {"target": q.target, "power": q.power, "spin": q.spin, "recv": q.receiver, "req": q.act}
		if ball.pos.y > 1.1 and q.act != Cmd.Act.LOB:
			_start_header(p, data)
		else:
			_start_kick(p, q.act, data)
			p.act_contact = minf(p.act_contact, 0.06)
		return
	var rel := ball.vel - p.vel
	var rs := rel.length()
	var high := ball.pos.y > 0.62
	_first_touch(p, "receive")
	if phase != Phase.PLAY:
		return
	var face_dir := p.face
	var mv := p.cmd.move
	if mv.length() > 0.3:
		face_dir = mv.normalized()
	if high:
		# chest / thigh control: ball drops to the feet
		p.start_action(A.TRAP, 0.4, 0.0, {"h": ball.pos.y})
		var q2 := clampf(1.1 - rs / 20.0 + p.dribble_attr * 0.3 - rng.randf() * 0.3, 0.0, 1.0)
		ball.vel = p.vel * 0.85 + face_dir * (0.6 + (1.0 - q2) * 3.0) + Vector3(0, -1.0, 0)
		ball.spin = Vector3.ZERO
		p.no_touch = 0.3
		owner = p.id if q2 > 0.35 else -1
		emit({"t": "trap", "id": p.id, "h": "chest", "q": q2})
		return
	if rs < 4.8:
		owner = p.id
		ball.vel = Vector3(p.vel.x, 0, p.vel.z)
		ball.spin = BallSim.rolling_spin(ball.vel)
		emit({"t": "trap", "id": p.id, "h": "soft", "q": 1.0})
		return
	var q := clampf(1.2 - rs / 24.0 + p.dribble_attr * 0.3 - rng.randf() * 0.35, 0.0, 1.0)
	var dev := (1.0 - q) * rng.randf_range(-1.6, 1.6)
	var out_dir := face_dir.rotated(Vector3.UP, dev)
	var bounce := (1.0 - q) * rs * 0.32
	ball.vel = Vector3(p.vel.x, 0, p.vel.z) * 0.9 + out_dir * (0.5 + bounce)
	ball.vel.y = (1.0 - q) * rng.randf_range(0.0, 2.0)
	ball.spin = BallSim.rolling_spin(ball.vel)
	owner = p.id if q > 0.45 else -1
	p.start_action(A.TRAP, 0.28, 0.0, {"h": 0.2})
	emit({"t": "trap", "id": p.id, "h": "foot", "q": q})


func _dribble(o: Footballer) -> void:
	var sp := o.vel.length()
	var mv := o.cmd.move
	var dir := o.face
	if mv.length() > 0.25:
		dir = mv.normalized()
	elif sp > 0.5:
		dir = o.vel / sp
	var rel := ball.pos - o.pos
	rel.y = 0.0
	o.touch_cd -= DT
	var pressured: bool = ai[o.team].nearest_opponent_dist(o.pos) < 2.6
	if (sp < 2.4 or (pressured and sp < 5.2)) and not o.cmd.sprint:
		# close control: ball kept just in front of the stronger foot
		var tgt := o.pos + o.face * 0.44 + o.face.cross(Vector3.UP) * 0.08 + o.vel * 0.08
		var corr := tgt - ball.pos
		corr.y = 0.0
		var nv := Vector3(o.vel.x, 0, o.vel.z) + corr * 10.0
		if nv.length() > 9.0:
			nv = nv.normalized() * 9.0
		if ball.pos.y > BallSim.R + 0.05:
			nv.y = ball.vel.y
		ball.vel = nv
		ball.spin = BallSim.rolling_spin(ball.vel)
		if o.touch_cd <= 0.0 and sp > 0.4:
			o.touch_cd = 0.42
			emit({"t": "dribble", "id": o.id, "soft": true})
		return
	var ahead := rel.dot(dir)
	var lat := (rel - dir * ahead).length()
	var bdir := Vector3(ball.vel.x, 0, ball.vel.z)
	var misdir := bdir.length() > 0.5 and bdir.normalized().dot(dir) < 0.9
	var need := ahead < 0.5 + 0.045 * sp or lat > 0.45 or misdir
	var foot_ok := absf(fmod(o.gait * 2.0, 1.0) - 0.15) < 0.2 or ahead < 0.25 or misdir
	if need and foot_ok and o.touch_cd <= 0.0 and rel.length() < 1.25 and ball.pos.y < 0.45:
		var push := 0.55 + 0.11 * sp - 0.25 * o.dribble_attr
		if o.cmd.sprint:
			push += 0.75
		var v := dir * (maxf(sp, 2.0) + push)
		# correct lateral offset so the ball ends up in the running line
		var lat_v := (o.pos + dir * maxf(ahead, 0.3)) - ball.pos
		lat_v.y = 0.0
		v += (lat_v - dir * lat_v.dot(dir)) * 3.0
		ball.kick(Vector3(v.x, 0.0, v.z), BallSim.rolling_spin(v))
		o.touch_cd = 0.24 + (0.12 if o.cmd.sprint else 0.0)
		o.stats["touches"] += 1
		emit({"t": "dribble", "id": o.id, "soft": false, "s": v.length()})


func _ball_bodies() -> void:
	if ball.in_hands >= 0:
		return
	for p in players:
		if p.sent_off or p.id == owner or p.no_touch > 0.0:
			continue
		var top := 1.0 if p.on_floor() else 1.78
		var h := clampf(ball.pos.y, 0.12, top)
		var c := Vector3(p.pos.x, h, p.pos.z)
		var d := ball.pos - c
		var dist := d.length()
		var rad := 0.24 if not p.on_floor() else 0.4
		if dist < rad + BallSim.R and dist > 0.0001:
			var rel := ball.vel - p.vel
			var n := d / dist
			var vn := rel.dot(n)
			if vn < 0.0 and rel.length() > 2.2:
				var vt := rel - n * vn
				var nv := vt * 0.55 - n * vn * 0.32 + p.vel
				ball.pos = c + n * (rad + BallSim.R + 0.01)
				ball.vel = nv
				ball.spin *= 0.3
				p.no_touch = 0.12
				var was_shot: bool = not last_shot.is_empty() and clock - last_shot["t"] < 2.0 and last_shot["team"] != p.team
				if last_touch_team != p.team:
					p.stats["blocks"] += 1 if was_shot else 0
				emit({"t": "block", "id": p.id, "s": rel.length(), "shot": was_shot})
				_set_last_touch(p, "body")
				if not last_pass.is_empty() and last_pass["team"] != p.team:
					last_pass = {}


func _ball_events() -> void:
	for e in ball.events:
		emit(e)
	ball.events.clear()


# ---------------------------------------------------------------------------
# Goalkeepers
# ---------------------------------------------------------------------------

func _gk_hands() -> void:
	for t in 2:
		var gk := gk_of(t)
		if gk == null:
			continue
		if ball.in_hands == gk.id:
			gk_hold_t += DT
			# can't carry the ball out of the box
			var gside := -side_of(t)
			var limit := pitch.hl() - pitch.box_depth + 0.6
			if gk.pos.x * gside < limit:
				gk.pos.x = limit * gside
			continue
		if ball.in_hands >= 0 or gk.busy() or gk.no_touch > 0.0:
			continue
		if not pitch.in_box(gk.pos, -side_of(t)):
			continue
		# keeper owns a loose ball at his feet inside the box → pick it up
		if owner == gk.id and pitch.in_box(ball.pos, -side_of(t)):
			var bp := last_touch_team == gk.team and last_touch != gk.id and last_touch_kind in ["pass", "through", "lob", "cross", "throw_in"]
			if not bp and gk.human < 0:
				ball.in_hands = gk.id
				ball.vel = Vector3.ZERO
				gk_hold_t = 0.0
				emit({"t": "catch", "id": gk.id, "catch": true})
				continue
		var hd := Vector2(ball.pos.x - gk.pos.x, ball.pos.z - gk.pos.z).length()
		if hd < 0.62 and ball.pos.y > 0.25 and ball.pos.y < 2.45 and ball.speed() > 1.0:
			var toward := ball.vel.dot(gk.pos - ball.pos) > 0.0 or hd < 0.4
			if toward:
				_gk_contact(gk, true)


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

func _check_goal() -> void:
	var gs := ball.goal_side()
	if gs == 0:
		return
	var scoring := 0 if side_of(0) == gs else 1
	teams[scoring]["score"] += 1
	var scorer := last_touch
	var own_goal_flag := last_touch_team >= 0 and last_touch_team != scoring
	var assist := -1
	if not own_goal_flag and assist_from >= 0 and assist_from != scorer and clock - assist_t < 12.0:
		if players[assist_from].team == scoring:
			assist = assist_from
	if scorer >= 0 and not own_goal_flag:
		players[scorer].stats["goals"] += 1
	if assist >= 0:
		players[assist].stats["assists"] += 1
	var gk := gk_of(1 - scoring)
	if gk:
		gk.stats["conceded"] += 1
	for p in team_players(1 - scoring):
		if p.role == Footballer.Role.DEF:
			p.stats["conceded"] += 1
	var g := {"team": scoring, "scorer": scorer, "assist": assist, "own": own_goal_flag,
		"minute": minute(), "clock": clock, "half": half}
	goals.append(g)
	var e := g.duplicate()
	e["t"] = "goal"
	emit(e)
	phase = Phase.GOAL
	phase_t = 0.0
	owner = -1
	kickoff_team = 1 - scoring
	if scorer >= 0 and not own_goal_flag:
		var sp: Footballer = players[scorer]
		sp.start_action(A.CELEBRATE, 4.0, 0.0, {"style": rng.randi() % 4})


func _check_out() -> void:
	if phase != Phase.PLAY or ball.in_goal != 0 or ball.in_hands >= 0:
		return
	var hl := pitch.hl()
	var hw := pitch.hw()
	var margin := pitch.line_half + BallSim.R
	if absf(ball.pos.z) > hw + margin:
		var team := 1 - maxi(last_touch_team, 0)
		var at := Vector3(clampf(ball.pos.x, -hl + 0.5, hl - 0.5), 0, signf(ball.pos.z) * (hw + 0.05))
		emit({"t": "out", "k": "throw"})
		_whistle_restart(Restart.THROW_IN, team, at, "throw")
	elif absf(ball.pos.x) > hl + margin:
		var side := int(signf(ball.pos.x))
		var defending := 0 if side_of(0) == -side else 1
		var attacking := 1 - defending
		if last_touch_team == defending:
			var cz := signf(ball.pos.z) * (hw - 0.3)
			emit({"t": "out", "k": "corner"})
			corners_n[attacking] += 1
			_whistle_restart(Restart.CORNER, attacking, Vector3(side * (hl - 0.3), 0, cz), "corner")
		else:
			var gz := signf(ball.pos.z) * minf(pitch.six_width * 0.3, 4.5)
			emit({"t": "out", "k": "goal_kick"})
			_whistle_restart(Restart.GOAL_KICK, defending,
				Vector3(side * (hl - pitch.six_depth + 0.5), 0, gz), "goal_kick")


## Arena: if the ball is dead in a corner with nobody near for a while → drop ball.
var stuck_t := 0.0


func _check_stuck() -> void:
	if ball.speed() < 0.3 and owner < 0 and ball.in_hands < 0:
		stuck_t += DT
	else:
		stuck_t = 0.0
	if stuck_t > 6.0:
		stuck_t = 0.0
		ball.reset(Vector3(clampf(ball.pos.x, -pitch.hl() + 3, pitch.hl() - 3), 0,
			clampf(ball.pos.z, -pitch.hw() + 3, pitch.hw() - 3)))


func _mark_offside(passer: Footballer) -> void:
	offside_marks.clear()
	if not is_full():
		return
	var side := side_of(passer.team)
	var bx := ball.pos.x * side
	# second-last defender line
	var dxs := []
	for o in team_players(1 - passer.team):
		dxs.append(o.pos.x * side)
	dxs.sort()
	if dxs.size() < 2:
		return
	var line: float = dxs[dxs.size() - 2]
	for q in team_players(passer.team):
		if q.id == passer.id:
			continue
		var qx: float = q.pos.x * side
		if qx > 0.0 and qx > line + 0.15 and qx > bx + 0.15:
			offside_marks.append(q.id)


func _foul(by: Footballer, victim: Footballer, severity: float, slide: bool) -> void:
	by.stats["fouls"] += 1
	fouls_n[by.team] += 1
	if not is_full():
		return   # arena: no fouls, the victim just falls (no stoppages)
	var at := victim.pos
	var own_side := -side_of(by.team)
	var pen := pitch.in_box(at, own_side)
	var card := 0
	if severity > 0.8 or (slide and rng.randf() < severity * 0.5):
		card = 1
	# denying an obvious goal-scoring opportunity
	var gx := pitch.goal_x(own_side)
	if absf(at.x - gx) < 28.0 and ai[victim.team].is_through_on_goal(victim):
		card = 2 if rng.randf() < 0.7 else 1
	if card == 1:
		by.yellow += 1
		if by.yellow >= 2:
			card = 2
	emit({"t": "foul", "id": by.id, "victim": victim.id, "pen": pen, "card": card})
	if card == 2:
		by.sent_off = true
		if owner == by.id:
			owner = -1
		emit({"t": "card", "id": by.id, "c": "red"})
	elif card == 1:
		emit({"t": "card", "id": by.id, "c": "yellow"})
	if pen:
		_whistle_restart(Restart.PENALTY, victim.team, pitch.penalty_point(own_side), "penalty")
	else:
		_whistle_restart(Restart.FREE_KICK, victim.team, at, "foul")


func _whistle_restart(type: int, team: int, at: Vector3, why: String) -> void:
	emit({"t": "whistle", "k": why})
	_setup_restart(type, team, at)


# ---------------------------------------------------------------------------
# Set pieces
# ---------------------------------------------------------------------------

func _setup_kickoff(team: int) -> void:
	if half == 1 and phase == Phase.KICKOFF and tick == 0:
		kickoff_team_first = team
	_setup_restart(Restart.KICKOFF, team, Vector3.ZERO)
	phase = Phase.KICKOFF
	emit({"t": "kickoff", "team": team})


func _setup_restart(type: int, team: int, at: Vector3) -> void:
	owner = -1
	last_pass = {}
	offside_marks.clear()
	queued_until.clear()
	for p in players:
		if p.sent_off:
			p.pos = Vector3(0, -50, 0)
			continue
		p.end_action()
		p.stun = 0.0
		p.vel = Vector3.ZERO
		p.cmd = Cmd.new()
		p.queued = Cmd.new()
	at.y = 0.0
	ball.reset(at)
	var taker := _choose_taker(type, team, at)
	var pos_map: Dictionary = ai[team].restart_positions(type, at, true, taker)
	var pos_map2: Dictionary = ai[1 - team].restart_positions(type, at, false, -1)
	for id in pos_map:
		players[id].pos = pitch.clamp_player(pos_map[id]) if type != Restart.THROW_IN or id != taker else pos_map[id]
	for id in pos_map2:
		players[id].pos = pitch.clamp_player(pos_map2[id])
	for p in players:
		if p.sent_off:
			continue
		var look := ball.pos - p.pos
		look.y = 0.0
		if look.length() > 0.3:
			p.face = look.normalized()
	if taker >= 0:
		var tk: Footballer = players[taker]
		var aim := opp_goal(team) - at
		aim.y = 0
		if type == Restart.THROW_IN:
			aim = Vector3(0, 0, -signf(at.z))
		tk.face = aim.normalized()
		if type != Restart.THROW_IN:
			tk.pos = at - tk.face * 0.55
		else:
			tk.pos = Vector3(at.x, 0, at.z)
			ball.in_hands = taker
			ball.pos = tk.pos + Vector3(0, 2.15, 0)
	if type == Restart.GOAL_KICK:
		pass
	restart = {"type": type, "team": team, "pos": at, "taker": taker}
	phase = Phase.RESTART if type != Restart.KICKOFF else Phase.KICKOFF
	phase_t = 0.0
	emit({"t": "restart", "type": type, "team": team, "taker": taker})


func _choose_taker(type: int, team: int, at: Vector3) -> int:
	var best := -1
	var best_score := -1e9
	for p in team_players(team):
		var s: float = -p.pos.distance_to(at)
		match type:
			Restart.GOAL_KICK:
				s = 100.0 if p.is_gk() else -100.0
			Restart.KICKOFF:
				s = (10.0 if p.role == Footballer.Role.FWD else 0.0) + (5.0 if p.human >= 0 and p.role != Footballer.Role.GK else 0.0) - absf(p.slot - 9)
			Restart.PENALTY:
				s = p.shot_attr * 10.0 + (20.0 if p.human >= 0 and not p.is_gk() else 0.0)
				if p.is_gk():
					s = -100.0
			Restart.FREE_KICK:
				var gd := at.distance_to(opp_goal(team))
				if gd < 32.0:
					s = p.shot_attr * 10.0 + (20.0 if p.human >= 0 and not p.is_gk() else 0.0)
				else:
					s = p.pass_attr * 5.0 - (0.0 if p.role != Footballer.Role.DEF else 0.0)
				if p.is_gk() and gd > 60.0:
					s = 50.0
				elif p.is_gk():
					s = -100.0
			Restart.CORNER:
				s = p.pass_attr * 10.0 + (3.0 if p.role == Footballer.Role.MID else 0.0)
				if p.is_gk() or p.role == Footballer.Role.DEF:
					s = -50.0 + p.pass_attr
			Restart.THROW_IN:
				s = -absf(p.pos.x - at.x) * 0.2 + (3.0 if p.role in [Footballer.Role.DEF, Footballer.Role.MID] else 0.0)
				if p.is_gk():
					s = -100.0
		if s > best_score:
			best_score = s
			best = p.id
	return best


func _setpiece_step() -> void:
	# taker waits; everyone else repositions (AI) or moves freely (human)
	for t in 2:
		ai[t].think(DT)
	var taker: int = restart.get("taker", -1)
	for p in players:
		if p.sent_off:
			continue
		if p.id == taker:
			_taker_step(p)
			continue
		if p.action != A.NONE:
			p.act_t += DT
			if p.act_t >= p.act_dur:
				p.end_action()
		p.cmd.act = Cmd.Act.NONE
		p.move_step(DT, false)
		_keep_distance(p)
	_separate_players()
	if ball.in_hands >= 0 and phase != Phase.PLAY:
		var h: Footballer = players[ball.in_hands]
		if restart.get("type", -1) == Restart.THROW_IN:
			ball.pos = h.pos + Vector3(0, 2.15, 0) + h.face * 0.1
		else:
			ball.pos = h.pos + h.face * 0.3 + Vector3(0, 1.05, 0)
	elif phase == Phase.PLAY:
		ball.step(DT)
		_ball_events()


func _keep_distance(p: Footballer) -> void:
	var type: int = restart.get("type", -1)
	var team: int = restart.get("team", 0)
	var at: Vector3 = restart.get("pos", Vector3.ZERO)
	if type == Restart.KICKOFF:
		# stay in own half, opponents outside the circle
		var side := side_of(p.team)
		if p.pos.x * side > -0.3 and p.id != restart.get("taker", -1):
			if not (p.team == team and p.pos.length() < 3.0):
				p.pos.x = -0.3 * side
		if p.team != team and p.pos.length() < pitch.circle_radius:
			p.pos = p.pos.normalized() * pitch.circle_radius if p.pos.length() > 0.1 else Vector3(-side * pitch.circle_radius, 0, 0)
		return
	if p.team == team:
		return
	var min_d := 9.15 if is_full() and per_side_big() else 4.0
	if type == Restart.THROW_IN:
		min_d = 2.0
	if type == Restart.PENALTY:
		if p.is_gk():
			var gx := pitch.goal_x(-side_of(p.team))
			p.pos.x = gx - side_of(p.team) * -0.1
			p.pos.z = clampf(p.pos.z, -pitch.goal_width * 0.5 + 0.3, pitch.goal_width * 0.5 - 0.3)
			return
		min_d = 9.15
	var d := p.pos - at
	d.y = 0.0
	if d.length() < min_d:
		p.pos = at + (d.normalized() if d.length() > 0.05 else Vector3(1, 0, 0)) * min_d


func per_side_big() -> bool:
	return cfg.per_side >= 9


func _taker_step(p: Footballer) -> void:
	var type: int = restart.get("type", -1)
	p.vel = Vector3.ZERO
	if p.action != A.NONE:
		_update_action(p)
		return
	var c := p.cmd
	if c.act == Cmd.Act.NONE:
		# rotate to aim while waiting
		if c.move.length() > 0.2:
			var ang := p.face.signed_angle_to(c.move.normalized(), Vector3.UP)
			p.face = p.face.rotated(Vector3.UP, clampf(ang, -3.0 * DT, 3.0 * DT))
			if type != Restart.THROW_IN:
				p.pos = ball.pos - p.face * 0.55
				p.pos.y = 0.0
		return
	var data := {"target": c.target, "power": c.power, "spin": c.spin, "recv": c.receiver, "req": c.act}
	if type == Restart.THROW_IN:
		var d := c.target - p.pos
		d.y = 0
		if d.length() > 0.5:
			p.face = d.normalized()
		p.start_action(A.THROW_IN, 0.9, 0.45, data)
		emit({"t": "act", "id": p.id, "k": "throw_in"})
	elif ball.in_hands == p.id:
		_start_gk_release(p, c.act, data)
	else:
		var req := c.act
		if req in [Cmd.Act.GK_KICK, Cmd.Act.GK_THROW]:
			req = Cmd.Act.LOB
		_start_kick(p, req, data)
	c.clear_action()


# ---------------------------------------------------------------------------
# Player separation (bodies don't overlap; stronger player wins the shove)
# ---------------------------------------------------------------------------

func _separate_players() -> void:
	var n := players.size()
	for i in n:
		var a: Footballer = players[i]
		if a.sent_off:
			continue
		for j in range(i + 1, n):
			var b: Footballer = players[j]
			if b.sent_off:
				continue
			var d := b.pos - a.pos
			d.y = 0.0
			var dl := d.length()
			var mind := 0.62
			if a.on_floor() or b.on_floor():
				mind = 0.4
			if dl < mind and dl > 0.0001:
				var push := (mind - dl)
				var nrm := d / dl
				var wa := 0.5 + (b.strength - a.strength) * 0.3
				if a.id == owner:
					wa -= 0.1
				if b.id == owner:
					wa += 0.1
				wa = clampf(wa, 0.15, 0.85)
				a.pos -= nrm * push * wa
				b.pos += nrm * push * (1.0 - wa)
				# kill closing velocity
				var rv := (b.vel - a.vel).dot(nrm)
				if rv < 0.0:
					a.vel += nrm * rv * wa * 0.5
					b.vel -= nrm * rv * (1.0 - wa) * 0.5
	for p in players:
		if not p.sent_off and p.action != A.GK_DIVE:
			p.pos = pitch.clamp_player(p.pos)


# ---------------------------------------------------------------------------
# Ratings (1..10, SofaScore-like)
# ---------------------------------------------------------------------------

func rating(p: Footballer) -> float:
	var s: Dictionary = p.stats
	var r := 6.0
	var won: bool = teams[p.team]["score"] > teams[1 - p.team]["score"]
	var lost: bool = teams[p.team]["score"] < teams[1 - p.team]["score"]
	var goal_w := 1.0
	if p.role == Footballer.Role.DEF:
		goal_w = 1.2
	r += s["goals"] * goal_w + s["assists"] * 0.7 + s["key_passes"] * 0.15
	r += s["on_target"] * 0.1 + (s["shots"] - s["on_target"]) * -0.03
	r += s["passes_ok"] * 0.02 - (s["passes"] - s["passes_ok"]) * 0.04
	r += s["tackles_won"] * 0.12 - (s["tackles"] - s["tackles_won"]) * 0.04
	r += s["interceptions"] * 0.1 + s["blocks"] * 0.12 + s["dribbles"] * 0.06
	r -= s["lost"] * 0.03 + s["fouls"] * 0.06 + p.yellow * 0.3
	if p.sent_off:
		r -= 1.5
	if p.role == Footballer.Role.GK:
		r += s["saves"] * 0.3 - s["conceded"] * 0.25
		if s["conceded"] == 0:
			r += 0.6
	elif p.role == Footballer.Role.DEF:
		r -= s["conceded"] * 0.1
		if s["conceded"] == 0:
			r += 0.3
	r += 0.25 if won else (-0.2 if lost else 0.0)
	return clampf(r, 3.0, 10.0)
