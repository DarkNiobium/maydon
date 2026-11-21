class_name Officials
extends Node3D
## Match officials for full-size games (view only): the referee runs the
## diagonal system around the ball, the two assistants patrol the touchlines
## level with the second-last defender (offside line).

var sim: MatchSim
var _views: Array = []
var _ps: Array = []      # Footballer stand-ins (kinematics only)
var _pos: Array = []


func setup(m: MatchSim) -> void:
	sim = m
	var kit := {"shirt": Color(0.07, 0.07, 0.08), "shorts": Color(0.05, 0.05, 0.06), "socks": Color(0.06, 0.06, 0.07),
		"num": Color(0.07, 0.07, 0.08), "pattern": 0}
	var hw := sim.pitch.hw()
	var starts := [Vector3(-6, 0, 8), Vector3(10, 0, hw + 0.8), Vector3(-10, 0, -hw - 0.8)]
	for i in 3:
		var p := Footballer.new()
		p.id = 90 + i
		p.number = 0
		p.pos = starts[i]
		p.face = Vector3(0, 0, -1) if i == 1 else (Vector3(0, 0, 1) if i == 2 else Vector3(1, 0, 0))
		var v := CharacterView.new()
		add_child(v)
		v.setup(p, kit)
		_views.append(v)
		_ps.append(p)
		_pos.append(starts[i])


func update(dt: float) -> void:
	if sim == null or dt <= 0.0:
		return
	var b := sim.ball.pos
	var hl := sim.pitch.hl()
	var hw := sim.pitch.hw()
	for i in 3:
		var p: Footballer = _ps[i]
		var tgt: Vector3
		var face_ball := true
		if i == 0:
			# diagonal system: stay ~12-18 m from the ball, on the left diagonal
			var side := 1.0 if b.x >= 0.0 else -1.0
			tgt = b + Vector3(-side * 9.0, 0, side * 9.0)
			tgt.x = clampf(tgt.x, -hl + 8.0, hl - 8.0)
			tgt.z = clampf(tgt.z, -hw + 4.0, hw - 4.0)
		else:
			# AR on +z covers the +x half, AR on -z covers the -x half
			var sgn := 1.0 if i == 1 else -1.0
			var line := _offside_line(sgn)
			var x := line
			if b.x * sgn > line * sgn:
				x = b.x
			x = clampf(x * sgn, 0.0, hl) * sgn
			tgt = Vector3(x, 0, sgn * (hw + 0.9))
		if sim.phase in [MatchSim.Phase.HALFTIME, MatchSim.Phase.FULLTIME]:
			face_ball = false
		var pos: Vector3 = _pos[i]
		if dt > 0.5:
			pos = tgt          # long jump in time (capture / resume): just be there
			p.vel = Vector3.ZERO
		var to := tgt - pos
		to.y = 0.0
		var d := to.length()
		var want := Vector3.ZERO
		if d > 0.6:
			var spd := clampf(d * 0.9, 0.0, 6.8 if i == 0 else 6.0)
			want = to / d * spd
		var sdt := minf(dt, 0.1)
		p.vel = p.vel.move_toward(want, 5.5 * sdt)
		pos += p.vel * sdt
		_pos[i] = pos
		var look := (b - pos) if face_ball else p.vel
		look.y = 0.0
		if i > 0:
			# assistants face across the pitch and shuffle sideways
			look = Vector3(0, 0, -signf(pos.z))
			if p.vel.length() > 4.0:
				look = look.lerp(p.vel.normalized(), 0.6)
		if look.length() > 0.1:
			var ang := p.face.signed_angle_to(look.normalized(), Vector3.UP)
			p.face = p.face.rotated(Vector3.UP, clampf(ang, -7.0 * dt, 7.0 * dt)).normalized()
		(_views[i] as CharacterView).sync(p, pos, p.face, dt)


## x of the second-last defender in the half on side `sgn` (+1 / -1).
func _offside_line(sgn: float) -> float:
	var xs: Array = []
	for q in sim.players:
		if q.sent_off:
			continue
		if q.pos.x * sgn > 0.0 and sim.side_of(q.team) == -int(sgn):
			xs.append(q.pos.x * sgn)
	xs.sort()
	if xs.size() >= 2:
		return xs[xs.size() - 2] * sgn
	return sgn * 10.0
