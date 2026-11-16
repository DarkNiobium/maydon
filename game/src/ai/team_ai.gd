class_name TeamAI
extends RefCounted
## Team + player AI. Team plan at 10 Hz (shape, roles, chaser, presser, runs),
## per-tick steering into Cmds. Bots use exactly the same Cmd interface as humans.

const R := Footballer.Role
const DIFF := [
	{"react": 0.34, "noise": 0.012, "press": 0.55, "tackle": 0.28, "gk_react": 0.27, "gk_err": 0.55, "shoot": 0.85, "slide": 0.02},
	{"react": 0.22, "noise": 0.007, "press": 0.8, "tackle": 0.45, "gk_react": 0.19, "gk_err": 0.35, "shoot": 1.0, "slide": 0.04},
	{"react": 0.14, "noise": 0.004, "press": 1.0, "tackle": 0.6, "gk_react": 0.13, "gk_err": 0.2, "shoot": 1.08, "slide": 0.06},
	{"react": 0.09, "noise": 0.002, "press": 1.15, "tackle": 0.72, "gk_react": 0.09, "gk_err": 0.12, "shoot": 1.12, "slide": 0.07},
]

var m: MatchSim
var team: int
var slots: Array
var d: Dictionary
var att := 0.5
var plan_t := 0.0
var targets := {}
var sprint := {}
var tasks := {}
var icpt := {}                  # id -> {"t": float, "p": Vector3}
var carrier_t := 0.0
var carrier_plan := {}
var carrier_id := -1
var carrier_since := 0.0
var request := {"id": -1, "t": -10.0, "through": false}
var runs := {}
var support_hold := {}
var gk_seen := -1.0
var gk_guess := 0
var setpiece_done := false
var rng := RandomNumberGenerator.new()
static var hist := {}
static var dbg_samples: Array = []


func _init(sim: MatchSim, t: int) -> void:
	m = sim
	team = t
	slots = Formations.get_slots(sim.cfg.formation[t], sim.cfg.per_side)
	var has_human := false
	for h in sim.cfg.humans:
		if int(h.get("team", 0)) == t:
			has_human = true
	var lvl: int = sim.cfg.difficulty
	if has_human:
		lvl = maxi(lvl, 2)       # teammates of humans are competent
	d = DIFF[clampi(lvl, 0, 3)]
	rng.seed = sim.cfg.seed * 7 + t * 131


func side() -> int:
	return m.side_of(team)


func hl() -> float:
	return m.pitch.hl()


func hw() -> float:
	return m.pitch.hw()


func mates() -> Array[Footballer]:
	return m.team_players(team)


func opps() -> Array[Footballer]:
	return m.team_players(1 - team)


func request_pass(id: int, through: bool) -> void:
	request = {"id": id, "t": m.clock, "through": through}


func nearest_opponent_dist(pos: Vector3) -> float:
	var best := 99.0
	for o in opps():
		var dd := Vector2(o.pos.x - pos.x, o.pos.z - pos.z).length()
		if dd < best:
			best = dd
	return best


func is_through_on_goal(p: Footballer) -> bool:
	var goal := m.opp_goal(p.team)
	var cnt := 0
	for o in m.team_players(1 - p.team):
		if o.is_gk():
			continue
		if (o.pos.x - p.pos.x) * side_for(p.team) > -0.5 and o.pos.distance_to(goal) < p.pos.distance_to(goal) + 1.0:
			cnt += 1
	return cnt == 0


func side_for(t: int) -> int:
	return m.side_of(t)


# ---------------------------------------------------------------------------
# Evaluation helpers
# ---------------------------------------------------------------------------

func xg_raw(pos: Vector3, t: int) -> float:
	var s := m.side_of(t)
	var goal := m.pitch.goal_center(s)
	if (goal.x - pos.x) * s < 0.2:
		return 0.0
	var gw := m.pitch.goal_width
	var a1 := Vector2(goal.x - pos.x, -gw * 0.5 - pos.z)
	var a2 := Vector2(goal.x - pos.x, gw * 0.5 - pos.z)
	var theta := absf(a1.angle_to(a2))
	var dist := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	var z := -0.65 - 0.13 * dist + 1.65 * theta
	return 1.0 / (1.0 + exp(-z))


func xg(pos: Vector3, t: int) -> float:
	var base := xg_raw(pos, t)
	if base <= 0.0:
		return 0.0
	var goal := m.pitch.goal_center(m.side_of(t))
	var mult := 1.0
	for o in m.team_players(1 - t):
		var od := _seg_dist(Vector2(o.pos.x, o.pos.z), Vector2(pos.x, pos.z), Vector2(goal.x, goal.z))
		var along := Vector2(o.pos.x - pos.x, o.pos.z - pos.z).length()
		if o.is_gk():
			if od < 1.0:
				mult *= 0.8
			elif od > 2.5:
				mult *= 1.25
			continue
		if od < 0.6 + along * 0.06 and along < pos.distance_to(goal):
			mult *= 0.5 if along < 4.0 else 0.7
	return clampf(base * mult, 0.0, 0.95)


func value(pos: Vector3, t: int) -> float:
	var s := m.side_of(t)
	var prog := clampf((pos.x * s + hl()) / (2.0 * hl()), 0.0, 1.0)
	return 0.01 + 0.06 * prog * prog * prog + 0.7 * xg_raw(pos, t)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * tt)


func _sig(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


## Probability that a ground pass from→to at speed v0 is not intercepted.
func pass_safety(from: Vector3, to: Vector3, v0: float) -> float:
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var dist := flat.length()
	if dist < 0.5:
		return 1.0
	var dir := flat / dist
	var min_margin := 9.0
	var x := 0.8
	var react := 0.12
	while x < dist + 0.8:
		var s := minf(x, dist)
		var tb := m.ball.roll_time(v0, s)
		if tb == INF:
			tb = 8.0
		var pt := from + dir * s
		for o in opps():
			var to_t := o.time_to(pt, true, 0.72 if not o.is_gk() else 1.1) + react
			var mm := to_t - tb
			if mm < min_margin:
				min_margin = mm
		x += 1.5
	return _sig(min_margin * 6.5 - 0.05)


## Lob: only the landing zone is contestable.
func lob_safety(from: Vector3, to: Vector3) -> float:
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var tf := 0.55 + dist / 17.0
	var mm := 9.0
	var dir := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
	var block := 1.0
	for o in opps():
		var t2 := o.time_to(to, true, 1.2) + 0.25
		mm = minf(mm, t2 - tf)
		# a defender right in front can charge the lob down
		var rel := o.pos - from
		rel.y = 0
		if rel.length() < 2.2 and rel.normalized().dot(dir) > 0.5:
			block = 0.6
	return _sig(mm * 4.0) * 0.8 * block


func offside_line() -> float:
	# second-last opponent, in my attack direction (normalized x)
	var xs := []
	for o in opps():
		xs.append(o.pos.x * side())
	xs.sort()
	if xs.size() < 2:
		return 1.0
	return maxf(xs[xs.size() - 2], 0.0) / hl()


# ---------------------------------------------------------------------------
# Shape
# ---------------------------------------------------------------------------

func slot_target(p: Footballer, ball_pos: Vector3, att_level: float) -> Vector3:
	var s: Array = slots[p.slot]
	var b: Vector2 = (s[1] as Vector2).lerp(s[2], att_level)
	var bx := clampf(ball_pos.x * side() / hl(), -1.0, 1.0)
	var bz := clampf(ball_pos.z * side() / hw(), -1.0, 1.0)
	var xn := b.x
	var zn := b.y
	if p.role != R.GK:
		xn += bx * 0.3
		zn = b.y * (0.78 + 0.22 * att_level) + bz * 0.3
		if p.role == R.DEF and att_level < 0.5:
			xn = minf(xn, bx + 0.06)
		if m.is_full() and p.role != R.DEF:
			var line := offside_line()
			xn = minf(xn, maxf(line - 0.012, bx))
	else:
		zn = bz * 0.12
	xn = clampf(xn, -0.97, 0.92)
	zn = clampf(zn, -0.93, 0.93)
	return Vector3(xn * hl() * side(), 0.0, zn * hw() * side())


# ---------------------------------------------------------------------------
# Thinking
# ---------------------------------------------------------------------------

func think(dt: float) -> void:
	if m.phase == MatchSim.Phase.KICKOFF or m.phase == MatchSim.Phase.RESTART:
		_setpiece_think()
		return
	setpiece_done = false
	plan_t -= dt
	if plan_t <= 0.0:
		plan_t = 0.1
		_plan()
	for p in mates():
		if p.human >= 0:
			continue
		_steer(p, dt)


func _compute_intercepts(preds: PackedVector3Array) -> void:
	icpt.clear()
	for p in m.players:
		if p.sent_off:
			continue
		var best_t := 99.0
		var best_p := m.ball.pos
		if m.ball.in_hands >= 0:
			icpt[p.id] = {"t": 99.0, "p": m.ball.pos}
			continue
		var n := preds.size()
		for i in n:
			var q := preds[i]
			var tb := (i + 1) * m.pred_dt
			var hmax := 1.0 if not p.is_gk() else 2.3
			if q.y > hmax and i < n - 1:
				continue
			var tp := p.time_to(q, true, 0.55)
			if tp <= tb:
				best_t = tb
				best_p = q
				break
			if i == n - 1:
				best_t = maxf(tp, tb)
				best_p = q
		icpt[p.id] = {"t": best_t, "p": Vector3(best_p.x, 0, best_p.z)}


func _plan() -> void:
	var preds := m.prediction()
	_compute_intercepts(preds)
	var c := m.carrier()
	var have := c != null and c.team == team
	var opp_have := c != null and c.team != team
	var goal_att := 0.0
	if have:
		goal_att = 1.0
	elif c == null:
		goal_att = 0.75 if m.poss_team == team else 0.25
	var rate := 0.16 if goal_att > att else 0.24
	att = move_toward(att, goal_att, rate)
	tasks.clear()
	var my := mates()

	if c == null and m.ball.in_hands < 0:
		var best: Footballer = null
		var bt := 99.0
		var human_t := 99.0
		for p in my:
			var it: float = icpt[p.id]["t"]
			if p.human >= 0:
				human_t = minf(human_t, it)
				continue
			if p.is_gk() and not m.pitch.in_box(icpt[p.id]["p"], -side()):
				continue
			if it < bt:
				bt = it
				best = p
		if best and not (human_t < bt - 0.35):
			tasks[best.id] = "chase"
		# second man when the ball is contested near our goal
		var ot := 99.0
		for o in opps():
			ot = minf(ot, icpt[o.id]["t"])
		if best and ot < bt + 0.3 and m.ball.pos.distance_to(m.own_goal(team)) < hl() * 0.7:
			var second: Footballer = null
			var st := 99.0
			for p in my:
				if p == best or p.human >= 0 or p.is_gk():
					continue
				var it2: float = icpt[p.id]["t"]
				if it2 < st:
					st = it2
					second = p
			if second and st < bt + 1.2:
				tasks[second.id] = "cover"
	elif opp_have:
		var presser: Footballer = null
		var pt := 99.0
		for p in my:
			if p.human >= 0 or p.is_gk():
				continue
			var tt := p.time_to(c.pos, true, 1.0)
			if tt < pt:
				pt = tt
				presser = p
		if presser:
			tasks[presser.id] = "press"
			if d["press"] >= 0.8 and my.size() >= 5:
				var cov: Footballer = null
				var ct := 99.0
				for p in my:
					if p == presser or p.human >= 0 or p.is_gk():
						continue
					var tt2 := p.time_to(c.pos, true, 1.0)
					if tt2 < ct:
						ct = tt2
						cov = p
				if cov and ct < 2.5:
					tasks[cov.id] = "cover"
	elif have:
		if c.human < 0:
			tasks[c.id] = "carry"
		_plan_runs(c)

	for p in my:
		if p.human >= 0 or p.is_gk() or tasks.has(p.id):
			continue
		var base := slot_target(p, m.ball.pos, att)
		var tgt := base
		if have:
			if runs.has(p.id) and runs[p.id]["until"] > m.clock:
				tgt = runs[p.id]["target"]
				tasks[p.id] = "run"
			else:
				tgt = _support_spot(p, base, c)
		elif opp_have or (c == null and m.poss_team != team):
			tgt = _defend_spot(p, base, c)
		targets[p.id] = m.pitch.clamp_player(tgt)
		sprint[p.id] = p.pos.distance_to(tgt) > 7.0 and (absf(att - 0.5) > 0.3)


func _plan_runs(c: Footballer) -> void:
	for id in runs.keys():
		if runs[id]["until"] < m.clock:
			runs.erase(id)
	var line_n := offside_line() if m.is_full() else 0.8
	var line_x := line_n * hl()
	var space_behind := hl() - line_x
	if space_behind < 6.0:
		return
	var cx := c.pos.x * side()
	for p in mates():
		if p.human >= 0 or p.id == c.id or p.is_gk() or runs.has(p.id):
			continue
		if not (p.role == R.FWD or (p.role == R.MID and rng.randf() < 0.3)):
			continue
		var px := p.pos.x * side()
		if px < cx - 2.0:
			continue
		if rng.randf() > 0.035:
			continue
		var depth := clampf(space_behind * 0.6, 4.0, 14.0)
		var tz := clampf(p.pos.z * 0.75, -hw() * 0.8, hw() * 0.8)
		var tgt := Vector3((line_x + depth) * side(), 0, tz)
		runs[p.id] = {"target": tgt, "until": m.clock + 2.6}


func _support_spot(p: Footballer, base: Vector3, c: Footballer) -> Vector3:
	var hold: Dictionary = support_hold.get(p.id, {})
	if not hold.is_empty() and hold["until"] > m.clock:
		return hold["pos"]
	var best := base
	var best_s := -99.0
	var ideal_min := 5.0 if not m.is_full() else 8.0
	var ideal_max := 16.0 if not m.is_full() else 26.0
	var line_x := offside_line() * hl() if m.is_full() else 99.0
	for i in 11:
		var cand := base
		if i > 0 and i < 9:
			var ang := TAU * float(i) / 8.0
			cand = base + Vector3(cos(ang), 0, sin(ang)) * 5.0
		elif i == 9:
			cand = base + Vector3(side() * 8.0, 0, 0)
		elif i == 10:
			cand = p.pos
		cand = m.pitch.clamp_player(cand)
		var lane := 4.0
		var space := 7.0
		for o in opps():
			var ld := _seg_dist(Vector2(o.pos.x, o.pos.z), Vector2(c.pos.x, c.pos.z), Vector2(cand.x, cand.z))
			lane = minf(lane, ld)
			space = minf(space, Vector2(o.pos.x - cand.x, o.pos.z - cand.z).length())
		var crowd := 0
		for q in mates():
			if q.id != p.id and q.pos.distance_to(cand) < 5.0:
				crowd += 1
		var dc := cand.distance_to(c.pos)
		var rng_pen := 0.0
		if dc < ideal_min:
			rng_pen = (ideal_min - dc) * 0.05
		elif dc > ideal_max:
			rng_pen = (dc - ideal_max) * 0.02
		var off_pen := 0.0
		if cand.x * side() > line_x - 0.3:
			off_pen = 0.5
		var s := 0.35 * lane / 4.0 + 0.25 * space / 7.0 + 3.0 * value(cand, team) \
			- 0.15 * crowd - 0.03 * cand.distance_to(base) - rng_pen - off_pen
		if s > best_s:
			best_s = s
			best = cand
	support_hold[p.id] = {"pos": best, "until": m.clock + 0.9}
	return best


func _defend_spot(p: Footballer, base: Vector3, c: Footballer) -> Vector3:
	var goal := m.own_goal(team)
	var best: Footballer = null
	var best_s := 99.0
	for o in opps():
		if o.is_gk() or (c and o.id == c.id):
			continue
		var dd := o.pos.distance_to(base)
		if dd > 13.0:
			continue
		var danger := o.pos.distance_to(goal) * 0.4
		var s := dd + danger
		if s < best_s:
			best_s = s
			best = o
	if best == null:
		return base
	var to_goal := (goal - best.pos)
	to_goal.y = 0
	var mark := best.pos + to_goal.normalized() * 1.6
	var ball_ref := c.pos if c else m.ball.pos
	var tb := ball_ref - best.pos
	tb.y = 0
	if tb.length() > 0.5:
		mark += tb.normalized() * 0.9
	var in_half := best.pos.x * side() < 0.0
	var blend := 0.68 if in_half else 0.35
	var tgt := base.lerp(mark, blend)
	return tgt


# ---------------------------------------------------------------------------
# Steering (every tick)
# ---------------------------------------------------------------------------

func _go(p: Footballer, tgt: Vector3, spr: bool, arrive := 0.7) -> void:
	var dd := tgt - p.pos
	dd.y = 0.0
	var dist := dd.length()
	var c := p.cmd
	if dist < arrive:
		c.move = Vector3.ZERO
		c.sprint = false
		return
	var k := 1.0
	if dist < 3.0:
		k = clampf(dist / 3.0, 0.25, 1.0)
	c.move = dd / dist * k
	c.sprint = spr and dist > 3.5 and p.stamina > 0.25


func _steer(p: Footballer, dt: float) -> void:
	var c := p.cmd
	c.look = Vector3.INF
	c.jockey = false
	c.sprint = false
	if p.is_gk():
		if m.owner == p.id and m.ball.in_hands < 0:
			_carrier(p, dt)
		else:
			_gk(p)
		return
	var task: String = tasks.get(p.id, "")
	match task:
		"chase":
			var ic: Dictionary = icpt.get(p.id, {"p": m.ball.pos})
			var tgt: Vector3 = ic["p"]
			var dist := p.pos.distance_to(tgt)
			# if it's a pass to me, meet it and face the ball
			var to_ball := m.ball.pos - p.pos
			to_ball.y = 0
			var my_pass: bool = not m.last_pass.is_empty() and m.last_pass["team"] == team
			var urgent := not my_pass or nearest_opponent_dist(tgt) < 6.0
			_go(p, tgt, urgent or dist > 8.0, 0.15)
			if dist < 2.5:
				c.look = m.ball.pos
		"carry":
			_carrier(p, dt)
		"press":
			_press(p)
		"cover":
			var cc := m.carrier()
			var ref := cc.pos if cc else m.ball.pos
			var goal := m.own_goal(team)
			var tgt2 := ref + (goal - ref).normalized() * 6.0
			_go(p, tgt2, true, 0.8)
			c.look = ref
		_:
			var tgt3: Vector3 = targets.get(p.id, p.pos)
			_go(p, tgt3, sprint.get(p.id, false), 0.9)
			if c.move.length() < 0.3:
				c.look = m.ball.pos


func _press(p: Footballer) -> void:
	var cc := m.carrier()
	var c := p.cmd
	if cc == null:
		return
	var goal := m.own_goal(team)
	var tg := goal - cc.pos
	tg.y = 0
	var contain := cc.pos + tg.normalized() * 1.25 + cc.vel * 0.18
	var dist := p.pos.distance_to(cc.pos)
	_go(p, contain, dist > 2.5, 0.2)
	c.look = m.ball.pos
	if dist < 3.2:
		c.jockey = true
	# tackle decision at plan rate (10 Hz)
	if plan_t > 0.0 and plan_t < 0.1 - 0.0001:
		pass
	if fmod(float(m.tick + p.id * 3), 6.0) != 0.0:
		return
	var bd := Vector2(m.ball.pos.x - p.pos.x, m.ball.pos.z - p.pos.z).length()
	if bd < 1.55 and not cc.busy() and m.ball.pos.y < 0.5:
		var foot := cc.pos + cc.face * 0.42
		var exposure := clampf(Vector2(m.ball.pos.x - foot.x, m.ball.pos.z - foot.z).length() / 0.8, 0.0, 1.0)
		var facing_away := cc.face.dot((p.pos - cc.pos).normalized()) < -0.2
		var ch: float = d["tackle"] * (0.12 + exposure * 0.55 + (0.12 if facing_away else 0.0))
		if rng.randf() < ch * 0.6:
			var dir := m.ball.pos - p.pos
			dir.y = 0
			p.face = dir.normalized()
			c.act = Cmd.Act.TACKLE
			return
	if bd < 3.0 and bd > 1.2 and m.ball.pos.y < 0.4:
		var slide_ch: float = d["slide"] * (2.2 if not m.is_full() else 1.0)
		var ahead := (m.ball.pos - p.pos).normalized().dot(p.vel.normalized()) > 0.8 if p.vel.length() > 3.0 else false
		if ahead and rng.randf() < slide_ch:
			c.act = Cmd.Act.SLIDE
			c.target = m.ball.pos


# ---------------------------------------------------------------------------
# Ball carrier decisions
# ---------------------------------------------------------------------------

func _carrier(p: Footballer, dt: float) -> void:
	var c := p.cmd
	if carrier_id != p.id:
		carrier_id = p.id
		carrier_since = m.clock
		carrier_t = d["react"] + rng.randf() * 0.12
		carrier_plan = {"kind": "dribble", "dir": p.face}
	carrier_t -= dt
	var pressure := nearest_opponent_dist(p.pos)
	if carrier_t <= 0.0 or (pressure < 1.7 and carrier_plan.get("kind", "") == "dribble" and m.clock - carrier_since > d["react"]):
		carrier_t = 0.22 + rng.randf() * 0.18
		carrier_plan = _decide(p)
	var kind: String = carrier_plan.get("kind", "dribble")
	match kind:
		"shoot":
			c.act = Cmd.Act.SHOT
			c.target = carrier_plan["target"]
			c.power = carrier_plan["power"]
			c.spin = carrier_plan.get("spin", Vector3.ZERO)
			carrier_plan = {"kind": "wait"}
		"pass", "through", "lob", "cross", "clear":
			c.act = {"pass": Cmd.Act.PASS, "through": Cmd.Act.THROUGH, "lob": Cmd.Act.LOB,
				"cross": Cmd.Act.CROSS, "clear": Cmd.Act.CLEAR}[kind]
			c.target = carrier_plan["target"]
			c.receiver = carrier_plan.get("recv", -1)
			c.power = 0.6
			carrier_plan = {"kind": "wait"}
			if c.receiver >= 0 and request["id"] == c.receiver:
				request["id"] = -1
		"dribble":
			var dir: Vector3 = carrier_plan.get("dir", p.face)
			c.move = dir
			c.sprint = carrier_plan.get("sprint", false) and p.stamina > 0.3
		"hold":
			var away := Vector3.ZERO
			for o in opps():
				var dd := p.pos - o.pos
				dd.y = 0
				var l := dd.length()
				if l < 4.0 and l > 0.01:
					away += dd / l * (4.0 - l)
			c.move = away.normalized() * 0.45 if away.length() > 0.1 else Vector3.ZERO
			c.sprint = false
		"skill":
			c.act = Cmd.Act.SKILL
			c.skill = carrier_plan.get("skill", 1)
			carrier_plan = {"kind": "dribble", "dir": carrier_plan.get("dir", p.face), "sprint": true}
		"wait":
			c.move = Vector3.ZERO


func _decide(p: Footballer) -> Dictionary:
	var best := {"kind": "dribble", "dir": p.face, "u": -9.0}
	var goal := m.opp_goal(team)
	var gw := m.pitch.goal_width
	var my_value := value(p.pos, team)
	var lose_cost := value(p.pos, 1 - team) * 0.8
	var pressure := nearest_opponent_dist(p.pos)
	var noise: float = d["noise"]
	var cands: Array = []

	# --- shot -----------------------------------------------------------------
	var dg := p.pos.distance_to(goal)
	var max_range := 32.0 if m.is_full() and m.cfg.per_side >= 9 else m.pitch.length * 0.45
	if dg < max_range:
		var x := xg(p.pos, team)
		var gk := m.gk_of(1 - team)
		var aim_z := -signf(p.pos.z + 0.01) * (gw * 0.5 - 0.45)
		if gk:
			# aim away from the keeper
			aim_z = (gw * 0.5 - 0.45) * (-1.0 if gk.pos.z > 0.0 else 1.0)
			if absf(gk.pos.z) < 0.3:
				aim_z *= (1.0 if rng.randf() < 0.5 else -1.0)
		var aim_y := 0.35 + rng.randf() * 1.3
		var power := clampf(0.55 + dg / 40.0, 0.55, 0.95)
		var u: float = x * d["shoot"] * 1.05 - (1.0 - x) * lose_cost * 0.25
		if dg < 9.0:
			u += 0.08
		var curl := Vector3.ZERO
		if dg > 14.0 and rng.randf() < 0.4:
			curl = Vector3(0, -signf(aim_z - p.pos.z) * side() * 28.0, 0)
		cands.append({"kind": "shoot", "u": u, "target": Vector3(goal.x, aim_y, aim_z), "power": power, "spin": curl})

	# --- passes ---------------------------------------------------------------
	var max_pass := 38.0 if m.cfg.per_side >= 9 else m.pitch.length * 0.75
	for q in mates():
		if q.id == p.id or q.stun > 0.0 or q.on_floor():
			continue
		if q.is_gk() and pressure > 2.5:
			continue
		var leads := [0]
		if runs.has(q.id) or q.vel.length() > 4.0:
			leads.append(1)
		for lead in leads:
			var tgt := q.pos
			var dist0 := p.pos.distance_to(q.pos)
			var kind := "pass"
			if lead == 1:
				var run_dir := q.vel.normalized() if q.vel.length() > 1.0 else Vector3(side(), 0, 0)
				if runs.has(q.id):
					run_dir = (runs[q.id]["target"] - q.pos).normalized()
				tgt = q.pos + run_dir * clampf(dist0 * 0.25, 3.0, 9.0)
				kind = "through"
			else:
				tgt = q.pos + q.vel * clampf(dist0 / 14.0, 0.2, 1.2)
			tgt = m.pitch.clamp_player(tgt)
			var dist := p.pos.distance_to(tgt)
			if dist < 3.0 or dist > max_pass:
				continue
			var arrive := BallSim.pass_arrive_speed(dist, lead == 1)
			var v0 := m.ball.ground_pass_speed(dist, arrive)
			var ps := pass_safety(m.ball.pos, tgt, v0)
			var t_arr := m.ball.roll_time(v0, dist)
			if q.time_to(tgt, true, 0.6) > t_arr + 0.35:
				ps *= 0.45
			var val := value(tgt, team)
			var u2 := ps * val - (1.0 - ps) * value(tgt, 1 - team) * 0.75
			if q.human >= 0:
				u2 += 0.015
				if request["id"] == q.id and m.clock - request["t"] < 2.0:
					u2 += 0.25 if (lead == 1) == request["through"] else 0.12
			cands.append({"kind": kind, "u": u2, "target": tgt, "recv": q.id})
			# lob alternative over a blocked lane
			if ps < 0.55 and dist > 11.0:
				var ls := lob_safety(m.ball.pos, tgt)
				var u3 := ls * val * (0.92 if m.cfg.per_side >= 7 else 0.7) - (1.0 - ls) * value(tgt, 1 - team) * 0.75
				var in_box := m.pitch.in_box(tgt, side())
				var lk := "cross" if in_box and absf(p.pos.z) > hw() * 0.45 else "lob"
				if q.human >= 0 and request["id"] == q.id and m.clock - request["t"] < 2.0:
					u3 += 0.12
				cands.append({"kind": lk, "u": u3, "target": tgt, "recv": q.id})

	# --- dribble --------------------------------------------------------------
	var gdir := goal - p.pos
	gdir.y = 0
	gdir = gdir.normalized()
	var spd := p.top_speed(true) * 0.9
	for ang: float in [0.0, -0.55, 0.55, -1.1, 1.1, -1.6, 1.6]:
		var dir := gdir.rotated(Vector3.UP, ang)
		var end := p.pos + dir * 5.0
		if not m.pitch.in_field(end, -1.0):
			continue
		var my_t := 5.0 / spd
		var opp_t := 99.0
		for o in opps():
			opp_t = minf(opp_t, o.time_to(p.pos + dir * 2.5, true, 0.8))
			opp_t = minf(opp_t, o.time_to(end, true, 0.8) - 0.2)
		var keep := _sig((opp_t - my_t * 0.6) * 3.5 + 0.4) * (0.75 + 0.25 * p.dribble_attr)
		var u4 := keep * value(end, team) - (1.0 - keep) * lose_cost
		cands.append({"kind": "dribble", "u": u4, "dir": dir, "sprint": opp_t > 1.2})
		# beat the man with a feint when tight
		if pressure < 1.6 and ang != 0.0 and absf(ang) < 1.2 and rng.randf() < 0.07 * p.dribble_attr:
			var keep2 := keep * 0.9 + 0.1
			cands.append({"kind": "skill", "u": keep2 * value(end, team) - (1.0 - keep2) * lose_cost,
				"skill": 1 if ang < 0.0 else 2, "dir": dir})

	# --- hold / clear ---------------------------------------------------------
	var keep_hold := clampf(pressure / 3.0, 0.1, 1.0)
	cands.append({"kind": "hold", "u": keep_hold * my_value * 0.9 - (1.0 - keep_hold) * lose_cost})
	var own_third := p.pos.x * side() < -hl() * 0.45
	if own_third and pressure < 2.2:
		var up := Vector3(hl() * 0.35 * side(), 0, signf(p.pos.z + 0.01) * hw() * 0.7)
		cands.append({"kind": "clear", "u": 0.004 + (2.2 - pressure) * 0.006, "target": up})

	for cd in cands:
		var u: float = cd["u"] + rng.randfn(0.0, noise)
		if u > best["u"]:
			best = cd
			best["u"] = u
	hist[best["kind"]] = hist.get(best["kind"], 0) + 1
	if dbg_samples.size() < 12 and rng.randf() < 0.03:
		var line := "pos=(%.0f,%.0f) pr=%.1f |" % [p.pos.x * side(), p.pos.z, pressure]
		var by := {}
		for cd in cands:
			var k: String = cd["kind"]
			if not by.has(k) or cd["u"] > by[k]:
				by[k] = cd["u"]
		for k in by:
			line += " %s=%.3f" % [k, by[k]]
		dbg_samples.append(line + " -> " + str(best["kind"]))
	return best


# ---------------------------------------------------------------------------
# Goalkeeper
# ---------------------------------------------------------------------------

func _gk(p: Footballer) -> void:
	var c := p.cmd
	var gside := -side()
	var goal := m.pitch.goal_center(gside)
	var gw := m.pitch.goal_width
	if m.ball.in_hands == p.id:
		_gk_distribute(p)
		return
	if p.busy():
		return
	var threat := _ball_threat(p, gside)
	if not threat.is_empty():
		if gk_seen < 0.0:
			gk_seen = m.clock
		var react: float = d["gk_react"] * (1.25 - p.gk_attr * 0.5)
		if m.clock - gk_seen >= react:
			var pt: Vector3 = threat["p"]
			var lat := Vector2(pt.x - p.pos.x, pt.z - p.pos.z).length()
			if lat < 0.85 and pt.y < 2.1:
				_go(p, pt, true, 0.1)
				c.look = m.ball.pos
			else:
				var err: float = d["gk_err"] * (1.1 - p.gk_attr) * 0.7
				var tgt := pt + Vector3(0, rng.randfn(0.0, err * 0.5), rng.randfn(0.0, err))
				c.act = Cmd.Act.GK_DIVE
				c.target = tgt
		else:
			c.move = Vector3.ZERO
		return
	gk_seen = -1.0
	# claim loose balls in the box
	var cc := m.carrier()
	if cc == null and m.ball.in_hands < 0:
		var ic: Dictionary = icpt.get(p.id, {})
		if not ic.is_empty() and m.pitch.in_box(ic["p"], gside):
			var ot := 99.0
			for o in opps():
				ot = minf(ot, icpt.get(o.id, {"t": 99.0})["t"])
			if ic["t"] < ot - 0.1:
				_go(p, ic["p"], true, 0.1)
				return
	# 1v1: come out to narrow the angle, smother
	if cc and cc.team != team:
		var dgc := cc.pos.distance_to(goal)
		if dgc < 16.0 and m.pitch.in_box(cc.pos, gside) and is_through_on_goal(cc):
			var out := minf(dgc - 1.6, 6.0)
			var tgt2 := goal + (cc.pos - goal).normalized() * out
			_go(p, tgt2, true, 0.2)
			c.look = m.ball.pos
			if p.pos.distance_to(m.ball.pos) < 2.3 and rng.randf() < 0.25:
				c.act = Cmd.Act.GK_DIVE
				c.target = m.ball.pos
			return
	# positioning on the ball–goal line
	var to_ball := m.ball.pos - goal
	to_ball.y = 0
	var bd := to_ball.length()
	var max_out := 3.2 if m.cfg.per_side >= 9 else 2.0
	var dist_out := clampf(0.7 + bd * 0.06, 0.7, max_out)
	var tgt := goal + to_ball.normalized() * dist_out
	tgt.z = clampf(tgt.z, -gw * 0.5 + 0.35, gw * 0.5 - 0.35)
	_go(p, tgt, bd < 20.0, 0.2)
	c.look = m.ball.pos
	c.jockey = true


func _ball_threat(p: Footballer, gside: int) -> Dictionary:
	if m.ball.in_hands >= 0 or m.ball.speed() < 7.0:
		return {}
	if m.owner >= 0:
		return {}
	var goal := m.pitch.goal_center(gside)
	var to_goal := goal - m.ball.pos
	if m.ball.vel.dot(to_goal) < 0.0:
		return {}
	var preds := m.prediction()
	var hl2 := hl()
	var gk_x := p.pos.x * gside
	var at_gk := {}
	for i in preds.size():
		var q := preds[i]
		var tq := (i + 1) * m.pred_dt
		if at_gk.is_empty() and q.x * gside >= gk_x:
			at_gk = {"p": q, "t": tq}
		if q.x * gside >= hl2 - 0.05:
			if absf(q.z) < m.pitch.goal_width * 0.5 + 0.7 and q.y < m.pitch.goal_height + 0.45:
				if at_gk.is_empty():
					at_gk = {"p": q, "t": tq}
				return at_gk
			return {}
	return {}


func _gk_distribute(p: Footballer) -> void:
	var c := p.cmd
	c.move = Vector3.ZERO
	if m.gk_hold_t < 1.1 + rng.randf() * 0.6:
		return
	var best: Footballer = null
	var best_s := -99.0
	for q in mates():
		if q.id == p.id:
			continue
		var open := nearest_opponent_dist(q.pos)
		var dist := p.pos.distance_to(q.pos)
		var s := open * 0.6 - dist * 0.05 + value(q.pos, team) * 10.0
		if dist > 40.0:
			s -= 3.0
		if s > best_s:
			best_s = s
			best = q
	if best == null:
		return
	var dist2 := p.pos.distance_to(best.pos)
	if dist2 < 30.0 and nearest_opponent_dist(best.pos) > 3.5:
		c.act = Cmd.Act.GK_THROW
		c.target = best.pos + best.vel * 0.6
	else:
		var fwd: Footballer = best
		for q in mates():
			if q.role == R.FWD:
				fwd = q
		c.act = Cmd.Act.GK_KICK
		c.target = fwd.pos + Vector3(side() * 4.0, 0, 0)
	c.receiver = best.id


# ---------------------------------------------------------------------------
# Set pieces
# ---------------------------------------------------------------------------

func _setpiece_think() -> void:
	var rs: Dictionary = m.restart
	var taker: int = rs.get("taker", -1)
	var type: int = rs.get("type", -1)
	for p in mates():
		if p.human >= 0 or p.id == taker:
			continue
		p.cmd.move = Vector3.ZERO
		p.cmd.look = m.ball.pos
		if p.is_gk() and type == MatchSim.Restart.PENALTY and rs.get("team", 0) != team:
			_penalty_gk(p)
	if rs.get("team", -1) != team or taker < 0:
		return
	var tk: Footballer = m.players[taker]
	if tk.human >= 0 or setpiece_done or tk.busy():
		return
	var delay: float = {MatchSim.Restart.KICKOFF: 1.1, MatchSim.Restart.THROW_IN: 1.3,
		MatchSim.Restart.CORNER: 1.9, MatchSim.Restart.GOAL_KICK: 1.6,
		MatchSim.Restart.FREE_KICK: 1.7, MatchSim.Restart.PENALTY: 2.0}.get(type, 1.5)
	if m.phase_t < delay:
		return
	setpiece_done = true
	var c := tk.cmd
	match type:
		MatchSim.Restart.KICKOFF:
			var q := _nearest_mate(tk, 2.0, 25.0, true)
			c.act = Cmd.Act.PASS
			c.target = q.pos if q else tk.pos + Vector3(-side() * 6.0, 0, 3.0)
			c.receiver = q.id if q else -1
		MatchSim.Restart.THROW_IN:
			var q2 := _open_mate(tk, 18.0)
			c.act = Cmd.Act.THROW_IN
			c.target = q2.pos if q2 else tk.pos + Vector3(side() * 8.0, 0, -signf(tk.pos.z) * 6.0)
			c.receiver = q2.id if q2 else -1
		MatchSim.Restart.CORNER:
			var gx := m.pitch.goal_x(side())
			var spot := Vector3(gx - side() * rng.randf_range(5.0, 11.0), 0, rng.randf_range(-3.5, 3.5))
			var tgt_p: Footballer = null
			var bd := 99.0
			for q3 in mates():
				if q3.id == tk.id or q3.is_gk():
					continue
				var dd := q3.pos.distance_to(spot)
				if dd < bd:
					bd = dd
					tgt_p = q3
			c.act = Cmd.Act.CROSS
			c.target = tgt_p.pos if tgt_p else spot
			c.receiver = tgt_p.id if tgt_p else -1
		MatchSim.Restart.GOAL_KICK:
			var q4 := _open_mate(tk, 25.0 if m.cfg.per_side >= 9 else 18.0)
			if q4 and (m.cfg.per_side < 9 or rng.randf() < 0.55):
				c.act = Cmd.Act.PASS
				c.target = q4.pos
				c.receiver = q4.id
			else:
				var fw: Footballer = null
				for q5 in mates():
					if q5.role == R.FWD or (fw == null and q5.role == R.MID):
						fw = q5
				c.act = Cmd.Act.LOB
				c.target = (fw.pos if fw else Vector3.ZERO) + Vector3(side() * 3.0, 0, 0)
				c.receiver = fw.id if fw else -1
		MatchSim.Restart.FREE_KICK:
			var goal := m.opp_goal(team)
			var dg := tk.pos.distance_to(goal)
			if dg < 30.0 and absf(tk.pos.z) < 20.0:
				var aim_z := (m.pitch.goal_width * 0.5 - 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
				c.act = Cmd.Act.SHOT
				c.target = Vector3(goal.x, 1.9, aim_z)
				c.power = 0.78
				c.spin = Vector3(0, -signf(aim_z - tk.pos.z) * side() * 38.0, 0)
			else:
				var q6 := _open_mate(tk, 30.0)
				c.act = Cmd.Act.PASS
				c.target = q6.pos if q6 else tk.pos + Vector3(side() * 10.0, 0, 0)
				c.receiver = q6.id if q6 else -1
		MatchSim.Restart.PENALTY:
			var goal2 := m.opp_goal(team)
			var z := (m.pitch.goal_width * 0.5 - 0.55) * (1.0 if rng.randf() < 0.5 else -1.0)
			if rng.randf() < 0.15:
				z = 0.0
			c.act = Cmd.Act.SHOT
			c.target = Vector3(goal2.x, 0.3 + rng.randf() * 1.4, z)
			c.power = 0.82


func _penalty_gk(p: Footballer) -> void:
	# keepers guess on penalties: commit as the taker strikes
	var tk_id: int = m.restart.get("taker", -1)
	if tk_id < 0:
		return
	var tk: Footballer = m.players[tk_id]
	if tk.action in [Footballer.A.SHOT] and tk.act_t > tk.act_contact - 0.12 and not p.busy():
		if gk_guess == 0:
			gk_guess = 1 if rng.randf() < 0.5 else -1
			if rng.randf() < 0.12:
				gk_guess = 2
		var gw := m.pitch.goal_width
		var z := 0.0 if gk_guess == 2 else gk_guess * (gw * 0.5 - 0.6)
		var gx := m.pitch.goal_x(-side())
		p.cmd.act = Cmd.Act.GK_DIVE
		p.cmd.target = Vector3(gx, rng.randf_range(0.3, 1.6), z)
	elif tk.action == Footballer.A.NONE:
		gk_guess = 0


func _nearest_mate(tk: Footballer, min_d: float, max_d: float, back: bool) -> Footballer:
	var best: Footballer = null
	var bd := 99.0
	for q in mates():
		if q.id == tk.id or q.is_gk():
			continue
		var dd := q.pos.distance_to(tk.pos)
		if dd < min_d or dd > max_d:
			continue
		if dd < bd:
			bd = dd
			best = q
	return best


func _open_mate(tk: Footballer, max_d: float) -> Footballer:
	var best: Footballer = null
	var bs := -99.0
	for q in mates():
		if q.id == tk.id or q.is_gk():
			continue
		var dd := q.pos.distance_to(tk.pos)
		if dd > max_d or dd < 3.0:
			continue
		var s := nearest_opponent_dist(q.pos) - dd * 0.08 + value(q.pos, team) * 8.0
		if s > bs:
			bs = s
			best = q
	return best


## Positions for a restart. `taking` = this team takes it.
func restart_positions(type: int, at: Vector3, taking: bool, taker: int) -> Dictionary:
	var out := {}
	var my := mates()
	var gside := -side()
	var own := m.pitch.goal_center(gside)
	var opp_goal := m.pitch.goal_center(side())
	var box_spots := []
	var att_lvl := 0.62 if taking else 0.3
	if type == MatchSim.Restart.KICKOFF:
		att_lvl = 0.0
	for p in my:
		if p.id == taker:
			continue
		var pos := slot_target(p, at, att_lvl)
		if p.is_gk():
			pos = own + (at - own).normalized() * 1.0 if at.distance_to(own) > 1.0 else own
			pos.z = clampf(pos.z, -1.5, 1.5)
			pos.x = own.x - gside * 0.8
			if type == MatchSim.Restart.PENALTY and not taking:
				pos = Vector3(own.x - gside * 0.1, 0, 0)
			out[p.id] = pos
			continue
		match type:
			MatchSim.Restart.KICKOFF:
				var s: Array = slots[p.slot]
				var dv: Vector2 = s[1]
				var xn := minf(dv.x, -0.04)
				pos = Vector3(xn * hl() * side(), 0, dv.y * hw() * 0.9 * side())
				if taking and p.role != R.DEF and box_spots.is_empty():
					pos = Vector3(-side() * 1.2, 0, 2.5)
					box_spots.append(1)
				elif not taking and pos.length() < m.pitch.circle_radius + 0.5:
					pos = pos.normalized() * (m.pitch.circle_radius + 0.8) if pos.length() > 0.1 else Vector3(-side() * 10.0, 0, 0)
			MatchSim.Restart.CORNER, MatchSim.Restart.FREE_KICK:
				var near_goal := at.distance_to(opp_goal if taking else own) < 34.0
				if near_goal:
					if taking and p.role != R.GK:
						var gx := opp_goal.x
						var spots := [Vector3(gx - side() * 2.5, 0, -1.8), Vector3(gx - side() * 4.5, 0, 2.6),
							Vector3(gx - side() * 9.0, 0, 0.0), Vector3(gx - side() * 7.0, 0, -4.5),
							Vector3(gx - side() * 15.0, 0, 1.0), Vector3(gx - side() * 6.0, 0, 5.0)]
						if m.cfg.per_side < 9:
							for i in spots.size():
								spots[i] = Vector3(gx - (gx - spots[i].x) * 0.6, 0, spots[i].z * 0.6)
						if p.role != R.DEF or (p.slot in [2, 3] and m.cfg.per_side >= 9):
							var k := box_spots.size()
							if k < spots.size():
								pos = spots[k]
								box_spots.append(k)
					elif not taking:
						var wall_n := 0
						if type == MatchSim.Restart.FREE_KICK:
							wall_n = 4 if at.distance_to(own) < 24.0 else 3
							if m.cfg.per_side < 9:
								wall_n = 2
						var k2 := box_spots.size()
						if k2 < wall_n:
							var dirg := (own - at)
							dirg.y = 0
							dirg = dirg.normalized()
							var wall_d := 9.15 if m.cfg.per_side >= 9 else 4.0
							pos = at + dirg * wall_d + dirg.cross(Vector3.UP) * (float(k2) - (wall_n - 1) * 0.5) * 0.62
						else:
							var gx2 := own.x
							var zs := [-2.0, 2.0, 0.0, -4.5, 4.5, -1.0, 1.0, 3.0]
							var j := k2 - wall_n
							if j < zs.size():
								pos = Vector3(gx2 + side() * (3.5 + (j % 3) * 2.5), 0, zs[j])
						box_spots.append(k2)
			MatchSim.Restart.PENALTY:
				var gx3 := signf(at.x) * hl()
				pos.x = clampf(pos.x, -hl() + m.pitch.box_depth + 1.0, hl() - m.pitch.box_depth - 1.0)
				if absf(pos.x - gx3) < m.pitch.box_depth + 1.5:
					pos.x = gx3 - signf(gx3) * (m.pitch.box_depth + 1.5)
			MatchSim.Restart.GOAL_KICK:
				if not taking:
					var gx4 := m.pitch.goal_x(side())
					if absf(pos.x - gx4) < m.pitch.box_depth + 1.0 and absf(pos.z) < m.pitch.box_width * 0.5 + 1.0:
						pos.x = gx4 - side() * (m.pitch.box_depth + 1.5)
			MatchSim.Restart.THROW_IN:
				pass
		out[p.id] = pos
	return out
