extends Node
## Ball-contact audit: runs an AI match through MatchView (manual stepping, 60 fps renders) and
## measures, at every planned dribble touch and every kick contact of a near player, how far the
## touching foot is from the ball. godot --headless --path . res://tools/contact_audit.tscn -- [per_side] [seconds]

var view: MatchView
var touch_err: Array = []     # IK error: metatarsal joint vs. its target (m)
var touch_gap: Array = []     # gap between foot (metatarsal joint + 0.07 m toe) and ball surface (m)
var kick_gap: Array = []
var missed := 0               # planned touches of near players with the foot not reaching (weight < 0.9)
var kick_seen := {}
var recv_gap: Array = []
var recv_none := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var per := int(args[0]) if args.size() > 0 else 5
	var secs := float(args[1]) if args.size() > 1 else 60.0
	Game.settings["quality"] = 2
	var cfg := Game.quick_match(per, Footballer.Role.FWD, 1)
	cfg.humans = []
	cfg.duration = 600.0
	Game.next_match = cfg
	Game.next_match_meta = {"follow": 3}
	view = load("res://scenes/match.tscn").instantiate()
	view.manual_step = true
	add_child(view)
	await get_tree().process_frame
	view.intro_t = 0.0
	for f in int(secs * 60.0):
		view.advance(1, 1.0 / 60.0)
		await get_tree().process_frame
		_measure()
	_report()
	get_tree().quit()


func _foot_gap(v: Node3D, leg: int, b := CharacterView.ball_pos) -> float:
	var pl: FootPlanter = v.get("_planter")
	var sk: Skeleton3D = v.get("_skel")
	var side := "l" if leg == 0 else "r"
	var bj: Vector3 = pl.final_ball[leg] if pl._w > 0.5 else sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ball_" + side)).origin
	var fwd := Vector3(sin(v.rotation.y), 0, cos(v.rotation.y))
	var toe := bj + fwd * 0.07
	# closest point of the foot segment (metatarsal joint .. toe tip) to the ball centre
	var ab := toe - bj
	var t := clampf((b - bj).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (bj + ab * t).distance_to(b) - BallSim.R


func _measure() -> void:
	var s := view.sim
	for e in s.events:
		if str(e.get("t", "")) in ["touch", "trap"] and e.has("id"):
			var rid := int(e["id"])
			var rv: Node3D = view.views[rid]
			var rpl: FootPlanter = rv.get("_planter")
			if rpl == null or rv.position.distance_to(CharacterView.cam_pos) > CharacterView.NEAR_LOD or s.players[rid].is_gk():
				continue
			rpl.debug = true
			if rpl.reach_w > 0.5 and rpl.reach_leg >= 0:
				recv_gap.append(_foot_gap(rv, rpl.reach_leg, view.prev_ball))
			else:
				recv_none += 1
	for i in view.views.size():
		var v: Node3D = view.views[i]
		var p: Footballer = s.players[i]
		var pl: FootPlanter = v.get("_planter")
		if pl == null or v.position.distance_to(CharacterView.cam_pos) > CharacterView.NEAR_LOD:
			continue
		pl.debug = true
		if s.owner == i and p.touch_at >= 0.0 and p.action == Footballer.A.NONE:
			var rem := p.touch_at - CharacterView.sim_time
			if rem >= -0.001 and rem < MatchSim.DT:
				var leg := 1 if p.touch_foot == 1 else 0
				if pl.reach_w < 0.9 or pl.reach_leg != leg:
					missed += 1
				else:
					touch_err.append(Vector2(pl.final_ball[leg].x - pl.reach_target.x, pl.final_ball[leg].z - pl.reach_target.z).length())
					touch_gap.append(_foot_gap(v, leg))
		if p.action in [Footballer.A.PASS, Footballer.A.SHOT, Footballer.A.LOB, Footballer.A.CHIP, Footballer.A.VOLLEY]:
			var key := "%d_%d" % [i, p.act_seq]
			if not kick_seen.has(key) and p.act_t >= p.act_contact - 0.001:
				kick_seen[key] = true
				var leg2 := 1 if int(p.act_data.get("foot", 1)) == 1 else 0
				# the strike tick already moved the ball: compare with where it was struck
				kick_gap.append(_foot_gap(v, leg2, view.prev_ball))


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(q * (b.size() - 1)), 0, b.size() - 1)]


func _report() -> void:
	print("touches: n=%d  missed(weight<0.9)=%d" % [touch_err.size(), missed])
	print("  IK error   p50 %.3f  p90 %.3f m" % [_pct(touch_err, 0.5), _pct(touch_err, 0.9)])
	print("  foot-ball gap p50 %.3f  p90 %.3f  (|gap| p90 %.3f) m" % [_pct(touch_gap, 0.5), _pct(touch_gap, 0.9), _pct(touch_gap.map(func(x): return absf(x)), 0.9)])
	print("receives: n=%d (no foot out: %d)  foot-ball gap p50 %.3f  |gap| p90 %.3f m" % [recv_gap.size(), recv_none, _pct(recv_gap, 0.5), _pct(recv_gap.map(func(x): return absf(x)), 0.9)])
	print("kicks: n=%d  foot-ball gap p50 %.3f  p90 %.3f  (|gap| p90 %.3f) m" % [kick_gap.size(), _pct(kick_gap, 0.5), _pct(kick_gap, 0.9), _pct(kick_gap.map(func(x): return absf(x)), 0.9)])
