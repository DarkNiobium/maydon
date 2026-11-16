class_name ReplayBuffer
extends RefCounted
## Ring buffer of compact match snapshots (30 Hz) for goal replays.

const RATE := 30
const SECONDS := 10.0

var m: MatchSim
var frames: Array = []
var _acc := 0
var _ghosts: Array = []


func _init(sim: MatchSim) -> void:
	m = sim
	for p in sim.players:
		var g := Footballer.new()
		g.id = p.id
		g.team = p.team
		g.role = p.role
		g.number = p.number
		_ghosts.append(g)


func record() -> void:
	_acc += 1
	if _acc % 2 != 0:
		return
	var ps := []
	for p in m.players:
		ps.append([p.pos, p.face, p.vel, p.gait, p.action, p.act_t, p.act_contact, p.act_data.duplicate(), p.act_seq, p.stun])
	frames.append({"ball": m.ball.pos, "spin": m.ball.spin, "p": ps})
	if frames.size() > int(RATE * SECONDS):
		frames.pop_front()


func last_seconds(s: float) -> Array:
	var n := mini(frames.size(), int(s * RATE))
	return frames.slice(frames.size() - n)


func ghost(i: int, f0: Dictionary, f1: Dictionary, a: float) -> Footballer:
	var g: Footballer = _ghosts[i]
	var p0: Array = f0["p"][i]
	var p1: Array = f1["p"][i]
	g.pos = (p0[0] as Vector3).lerp(p1[0], a)
	g.face = (p0[1] as Vector3).slerp(p1[1], a).normalized() if (p0[1] as Vector3).length() > 0.5 else p1[1]
	g.vel = p0[2]
	g.gait = p0[3]
	g.action = p0[4]
	g.act_t = lerpf(p0[5], p1[5], a) if p0[4] == p1[4] else p0[5]
	g.act_contact = p0[6]
	g.act_data = p0[7]
	g.act_seq = p0[8]
	g.stun = p0[9]
	return g
