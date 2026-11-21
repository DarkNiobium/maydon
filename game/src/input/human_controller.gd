class_name HumanController
extends RefCounted
## Turns a human's InputState into a Cmd for their footballer, with the
## assistance a phone game needs: receiver picking, auto pass power, shot aim.

var m: MatchSim
var pid := -1
var inp := InputState.new()
var aim_assist := 1.0
var gk_assist := true
var called_t := -10.0
var called_through := false
var aim_origin := Vector3.ZERO      # camera aim ray (set by the view when inp.aim_mode)
var aim_dir := Vector3.FORWARD
var last_ctx := ""
var _emote_t := -99.0


func _init(sim: MatchSim, player_id: int) -> void:
	m = sim
	pid = player_id


func player() -> Footballer:
	return m.players[pid]


## Context for the HUD: "attack" (I have the ball), "support" (team has it),
## "defend", "gk_hold", "setpiece".
func context() -> String:
	var p := player()
	if m.ball.in_hands == p.id:
		return "gk_hold" if m.phase == MatchSim.Phase.PLAY or not _throwin() else "throw"
	if (m.phase == MatchSim.Phase.RESTART or m.phase == MatchSim.Phase.KICKOFF) and m.restart.get("taker", -1) == pid:
		return "throw" if _throwin() else "setpiece"
	if _has_ball(p):
		return "attack"
	var c := m.carrier()
	if c and c.team == p.team:
		return "support"
	if c == null and m.poss_team == p.team and not m.last_pass.is_empty():
		return "support"
	return "defend"


func _throwin() -> bool:
	return m.restart.get("type", -1) == MatchSim.Restart.THROW_IN


func _has_ball(p: Footballer) -> bool:
	if m.owner == p.id:
		return true
	if m.owner < 0 and m.ball.in_hands < 0:
		var d := Vector2(m.ball.pos.x - p.pos.x, m.ball.pos.z - p.pos.z).length()
		return d < 1.4 and m.ball.pos.y < 0.9
	return false


func update(now: float, cam_fwd: Vector3, cam_right: Vector3) -> void:
	var p := player()
	if inp.emote >= 0 and inp.emote < Emotes.LIST.size() and now - _emote_t > Emotes.COOLDOWN:
		_emote_t = now
		m.emit_later({"t": "emote", "id": p.id, "e": inp.emote})
	var c := p.cmd
	c.act = Cmd.Act.NONE
	c.look = Vector3.INF
	c.jockey = false
	var s := inp.stick
	var mv := cam_right * s.x + cam_fwd * s.y
	mv.y = 0.0
	if mv.length() > 1.0:
		mv = mv.normalized()
	c.move = mv
	c.sprint = inp.held[InputState.B.SPRINT]
	var ctx := context()
	last_ctx = ctx
	var dir := mv.normalized() if mv.length() > 0.2 else p.face
	var B := InputState.B
	var aim := inp.aim_mode
	if aim:
		dir = _aim_flat()
	# explicit PC actions work in any context
	if inp.pressed[B.CALL]:
		m.ai[p.team].request_pass(p.id, false)
		if now - called_t > 1.0:
			Sfx.call_for_ball(p.pos + Vector3(0, 1.6, 0))
		called_t = now
		called_through = false
	elif inp.pressed[B.RUNREQ]:
		m.ai[p.team].request_pass(p.id, true)
		if now - called_t > 1.0:
			Sfx.call_for_ball(p.pos + Vector3(0, 1.6, 0))
		called_t = now
		called_through = true
	if ctx != "attack" and ctx != "setpiece" and ctx != "gk_hold" and ctx != "throw":
		if inp.pressed[B.TACKLE]:
			c.act = Cmd.Act.TACKLE
			return
		if inp.pressed[B.SLIDE]:
			c.act = Cmd.Act.SLIDE
			c.target = m.ball.pos
			return

	match ctx:
		"attack", "setpiece":
			if inp.released[B.A]:
				if inp.hold_time[B.A] < 0.28:
					_pass(p, dir, Cmd.Act.PASS)
				else:
					_pass(p, dir, Cmd.Act.LOB)
			elif inp.released[B.C]:
				_pass(p, dir, Cmd.Act.THROUGH)
			elif inp.released[B.B]:
				var pw := clampf(inp.hold_time[B.B] / 0.85, 0.15, 1.0)
				if aim:
					_shoot_aim(p, pw)
				else:
					_shoot(p, mv, pw)
			elif inp.pressed[B.D] and ctx == "attack":
				_skill(p, mv)
		"throw":
			if inp.released[B.A] or inp.released[B.C] or inp.released[B.B]:
				var q := pick_receiver(p, dir, false)
				c.act = Cmd.Act.THROW_IN if m.phase != MatchSim.Phase.PLAY else Cmd.Act.GK_THROW
				c.target = q.pos + q.vel * 0.5 if q else p.pos + dir * 12.0
				c.receiver = q.id if q else -1
		"gk_hold":
			if inp.released[B.A] or inp.released[B.C]:
				var q2 := pick_receiver(p, dir, false)
				c.act = Cmd.Act.GK_THROW
				c.target = q2.pos + q2.vel * 0.6 if q2 else p.pos + dir * 15.0
				c.receiver = q2.id if q2 else -1
			elif inp.released[B.B]:
				var q3 := pick_receiver(p, dir, false)
				c.act = Cmd.Act.GK_KICK
				c.target = q3.pos + dir * 3.0 if q3 else p.pos + dir * 45.0
				c.receiver = q3.id if q3 else -1
		"support":
			if inp.pressed[B.A]:
				m.ai[p.team].request_pass(p.id, false)
				called_t = now
				called_through = false
			elif inp.pressed[B.C]:
				m.ai[p.team].request_pass(p.id, true)
				called_t = now
				called_through = true
			if inp.released[B.B]:
				# first-time shot when the ball arrives
				var pw2 := clampf(inp.hold_time[B.B] / 0.85, 0.3, 1.0)
				if aim:
					_shoot_aim(p, pw2)
				else:
					_shoot(p, mv, pw2)
		"defend":
			if p.is_gk():
				last_ctx = "gk_defend"
				_gk_defend(p, mv)
				return
			if aim:
				# PC: LMB tackle, RMB (hold) contain; Ctrl slides (explicit)
				if inp.pressed[B.B]:
					c.act = Cmd.Act.TACKLE
			elif inp.pressed[B.A]:
				c.act = Cmd.Act.TACKLE
			elif inp.pressed[B.B]:
				c.act = Cmd.Act.SLIDE
				c.target = m.ball.pos
			if inp.held[B.C] or (aim and inp.held[B.A]):
				var car := m.carrier()
				var ref := car.pos if car else m.ball.pos
				c.jockey = true
				c.look = ref
				if mv.length() < 0.2:
					# auto-contain: hold a goal-side position
					var goal := m.own_goal(p.team)
					var contain := ref + (goal - ref).normalized() * 1.6
					var to := contain - p.pos
					to.y = 0
					c.move = to.normalized() * clampf(to.length() / 2.0, 0.0, 1.0)
	if p.is_gk() and ctx != "gk_hold" and ctx != "setpiece" and ctx != "throw" and gk_assist and mv.length() < 0.2:
		m.ai[p.team]._gk(p)


func _gk_defend(p: Footballer, mv: Vector3) -> void:
	var c := p.cmd
	var B := InputState.B
	if gk_assist and mv.length() < 0.2 and not inp.pressed[B.B] and not inp.held[B.A] and not inp.aim_mode:
		m.ai[p.team]._gk(p)
		return
	if inp.pressed[B.B]:
		var dir := mv.normalized() if mv.length() > 0.2 else p.face.cross(Vector3.UP)
		c.act = Cmd.Act.GK_DIVE
		c.target = p.pos + dir * 2.6 + Vector3(0, 0.8 + inp.stick.y * 0.8, 0)
		if inp.aim_mode and mv.length() < 0.2:
			# dive to where the camera points along the goal mouth
			var gx := m.pitch.goal_x(-m.side_of(p.team))
			var hit := _ray_plane_x(gx + m.side_of(p.team) * 0.8)
			if hit != Vector3.INF:
				c.target = Vector3(hit.x, clampf(hit.y, 0.2, 2.4), clampf(hit.z, -m.pitch.goal_width * 0.6, m.pitch.goal_width * 0.6))
	if inp.held[B.A]:
		# rush out at the ball
		var to := m.ball.pos - p.pos
		to.y = 0
		c.move = to.normalized()
		c.sprint = true


func pick_receiver(p: Footballer, dir: Vector3, through: bool, cone := 0.85) -> Footballer:
	var best: Footballer = null
	var best_s := -99.0
	for q in m.team_players(p.team):
		if q.id == p.id:
			continue
		var v := q.pos - p.pos
		v.y = 0
		var d := v.length()
		if d < 2.0:
			continue
		var ang := absf(dir.angle_to(v))
		if ang > cone:
			continue
		var open: float = m.ai[p.team].nearest_opponent_dist(q.pos)
		var s := cos(ang) * 2.2 - d / 45.0 + minf(open, 6.0) * 0.06
		if through and q.vel.dot(Vector3(m.side_of(p.team), 0, 0)) > 2.0:
			s += 0.3
		if s > best_s:
			best_s = s
			best = q
	return best


func _pass(p: Footballer, dir: Vector3, kind: int) -> void:
	var c := p.cmd
	var q := pick_receiver(p, dir, kind == Cmd.Act.THROUGH, 0.42 if inp.aim_mode else 0.85)
	var tgt := p.pos + dir * 16.0
	if inp.aim_mode:
		# no teammate under the crosshair → play it into the space you aim at
		var g := _ray_ground()
		if g != Vector3.INF:
			var off := g - p.pos
			off.y = 0
			tgt = p.pos + off.normalized() * clampf(off.length(), 6.0, 38.0)
	if q:
		var d := p.pos.distance_to(q.pos)
		if kind == Cmd.Act.THROUGH:
			var run := q.vel.normalized() if q.vel.length() > 1.5 else Vector3(m.side_of(p.team), 0, 0)
			tgt = q.pos + run * clampf(d * 0.28, 3.5, 10.0)
		else:
			tgt = q.pos + q.vel * clampf(d / 14.0, 0.15, 1.1)
		c.receiver = q.id
		if kind == Cmd.Act.LOB and m.pitch.in_box(tgt, m.side_of(p.team)) and absf(p.pos.z) > m.pitch.hw() * 0.4:
			kind = Cmd.Act.CROSS
	else:
		c.receiver = -1
		if kind == Cmd.Act.LOB and not inp.aim_mode:
			tgt = p.pos + dir * 28.0
	c.act = kind
	c.target = m.pitch.clamp_player(tgt)
	c.power = clampf(inp.hold_time[InputState.B.A] / 1.0, 0.3, 1.0)


func _shoot(p: Footballer, mv: Vector3, power: float) -> void:
	var c := p.cmd
	var side := m.side_of(p.team)
	var goal := m.opp_goal(p.team)
	var gw := m.pitch.goal_width
	var to_goal := goal - p.pos
	to_goal.y = 0
	var dist := to_goal.length()
	var gdir := to_goal / maxf(dist, 0.01)
	var z := 0.0
	var max_z := gw * 0.5 - 0.32
	if mv.length() < 0.2:
		z = -signf(p.pos.z + 0.01) * max_z * 0.8   # far post
	else:
		var ang := gdir.signed_angle_to(mv.normalized(), Vector3.UP)
		var max_ang := atan2(gw * 0.5, maxf(dist, 1.0)) * 1.6
		var k := clampf(ang / max_ang, -1.0, 1.0)
		# rotating +ang about +Y turns +X toward −Z
		z = -k * max_z * side
		if aim_assist > 0.5 and absf(k) > 0.35:
			z = signf(z) * max_z
	var y := clampf(0.3 + power * 1.45, 0.25, 2.15)
	c.act = Cmd.Act.SHOT
	c.target = Vector3(goal.x, y, z)
	c.power = power
	if power < 0.62 and dist > 11.0:
		# placed finesse shot: curl toward the far post
		c.spin = Vector3(0, -signf(z - p.pos.z) * side * 30.0, 0)
	else:
		c.spin = Vector3.ZERO


# --- camera aim helpers (PC / gamepad) ------------------------------------------

func _aim_flat() -> Vector3:
	var d := Vector3(aim_dir.x, 0, aim_dir.z)
	return d.normalized() if d.length() > 0.01 else player().face


func _ray_ground() -> Vector3:
	if aim_dir.y > -0.02:
		return Vector3.INF
	var t := -aim_origin.y / aim_dir.y
	return aim_origin + aim_dir * t if t < 80.0 else Vector3.INF


func _ray_plane_x(x: float) -> Vector3:
	if absf(aim_dir.x) < 0.02:
		return Vector3.INF
	var t := (x - aim_origin.x) / aim_dir.x
	return aim_origin + aim_dir * t if t > 0.0 else Vector3.INF


## Shoot exactly where the crosshair points (REMATCH-style): the aim ray meets
## the goal plane; misses are possible — no auto-aim on PC.
func _shoot_aim(p: Footballer, power: float) -> void:
	var c := p.cmd
	var side := m.side_of(p.team)
	var gx := m.pitch.goal_x(side)
	var gw := m.pitch.goal_width
	var tgt := Vector3.INF
	if signf(aim_dir.x) == float(side):
		tgt = _ray_plane_x(gx)
	if tgt == Vector3.INF:
		tgt = p.pos + _aim_flat() * 25.0 + Vector3(0, 1.0, 0)
	else:
		tgt.z = clampf(tgt.z, -gw * 0.5 - 2.0, gw * 0.5 + 2.0)
		tgt.y = clampf(tgt.y, 0.15, m.pitch.goal_height + 1.5)
	c.act = Cmd.Act.SHOT
	c.target = tgt
	c.power = power
	var d := p.pos.distance_to(Vector3(gx, 0, 0))
	if power < 0.55 and d > 12.0:
		c.spin = Vector3(0, -signf(tgt.z - p.pos.z) * side * 26.0, 0)
	else:
		c.spin = Vector3.ZERO


func _skill(p: Footballer, mv: Vector3) -> void:
	var c := p.cmd
	c.act = Cmd.Act.SKILL
	if mv.length() < 0.2:
		c.skill = 1 if randf() < 0.5 else 2
		return
	var ang := p.face.signed_angle_to(mv.normalized(), Vector3.UP)
	if absf(ang) > 2.2:
		c.skill = 3
	else:
		c.skill = 1 if ang > 0.0 else 2
