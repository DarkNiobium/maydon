extends Node
## Foot-slide audit: runs an AI match through MatchView (manual stepping) and
## measures horizontal speed of planted feet per locomotion category.
## godot --headless --path . res://tools/anim_audit.tscn -- [per_side] [seconds]

var view: MatchView
var stats := {}
var prev := {}
var prev_yaw := {}

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
	var frames := int(secs * 30.0)
	for f in frames:
		view.advance(2, 1.0 / 30.0)
		await get_tree().process_frame
		_measure(1.0 / 30.0)
	_report()
	get_tree().quit()


func _cat(p: Footballer, v: Node3D, yaw_rate: float) -> String:
	if p.action != Footballer.A.NONE:
		var ph := ""
		if p.action in [Footballer.A.PASS, Footballer.A.SHOT, Footballer.A.LOB, Footballer.A.CHIP, Footballer.A.VOLLEY]:
			ph = "_post" if p.act_done else "_pre"
		return "act_" + Footballer.A.keys()[p.action].to_lower() + ph
	var sp := p.vel.length()
	if sp < 0.3:
		return "turn_inplace" if absf(yaw_rate) > 1.5 else "idle"
	var yaw: float = v.rotation.y
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var c := p.vel.normalized().dot(fwd)
	var dir := "fwd" if c > 0.7 else ("back" if c < -0.5 else "side")
	var band := "walk" if sp < 2.5 else ("jog" if sp < 4.5 else ("run" if sp < 6.5 else "sprint"))
	var t := "_turn" if absf(yaw_rate) > 2.0 else ""
	return band + "_" + dir + t


func _measure(dt: float) -> void:
	for i in view.views.size():
		var v: Node3D = view.views[i]
		var p: Footballer = view.sim.players[i]
		var sk: Skeleton3D = v.get("_skel")
		if sk == null:
			continue
		var pl: FootPlanter = v.get("_planter")
		pl.debug = true
		if v.position.distance_to(CharacterView.cam_pos) > CharacterView.NEAR_LOD:
			prev.erase("%dl" % i)
			prev.erase("%dr" % i)
			continue
		var yr := 0.0
		if prev_yaw.has(i):
			yr = angle_difference(prev_yaw[i], v.rotation.y) / dt
		prev_yaw[i] = v.rotation.y
		var cat := _cat(p, v, yr)
		for side in ["l", "r"]:
			var bi := sk.find_bone("foot_" + side)
			var bb := sk.find_bone("ball_" + side)
			var pa: Vector3 = sk.global_transform * sk.get_bone_global_pose(bi).origin
			var pb: Vector3 = pl.final_ball[0 if side == "l" else 1] if pl._w > 0.5 else sk.global_transform * sk.get_bone_global_pose(bb).origin
			var key := "%d%s" % [i, side]
			if prev.has(key):
				var o: Array = prev[key]
				var planted := pb.y < 0.032 and (o[1] as Vector3).y < 0.032
				if planted:
					var pt := pb
					var opt: Vector3 = o[1]
					var hs := Vector2(pt.x - opt.x, pt.z - opt.z).length() / dt
					if hs > 0.5:
						var lg = pl._legs[0 if side == "l" else 1]
						var why := "pinned" if lg.planted else ("step" if lg.step_t >= 0.0 else "free_" + str(pl.diag[0 if side == "l" else 1]).substr(0, 6))
						var wk := "why_" + why
						var ws: Array = stats.get(wk, [0, 0.0, 0])
						ws[0] += 1; ws[1] += hs; ws[2] += 1
						stats[wk] = ws
						if cat.begins_with("act_"):
							var wk2 := "w_" + cat + "_" + why + ("_r" if pl.reach_leg == (0 if side == "l" else 1) else "")
							var ws2: Array = stats.get(wk2, [0, 0.0, 0])
							ws2[0] += 1; ws2[1] += hs; ws2[2] += 1
							stats[wk2] = ws2
					var s: Array = stats.get(cat, [0, 0.0, 0])
					s[0] += 1
					s[1] += hs
					if hs > 0.5:
						s[2] += 1
					stats[cat] = s
			prev[key] = [pa, pb]


func _report() -> void:
	var bins := {}
	for e in FootPlanter.diag_samples:
		var b := int(e[0] / 1.5)
		if not bins.has(b):
			bins[b] = []
		bins[b].append(e[1])
	var ks := bins.keys()
	ks.sort()
	for b in ks:
		var arr: Array = bins[b]
		arr.sort()
		var n := arr.size()
		print("body %.1f-%.1f m/s: n=%d  foot-intended speed p25 %.2f p50 %.2f p75 %.2f p90 %.2f" % [b * 1.5, b * 1.5 + 1.5, n, arr[n / 4], arr[n / 2], arr[n * 3 / 4], arr[n * 9 / 10]])
	var keys := stats.keys()
	keys.sort_custom(func(a, b): return stats[a][0] > stats[b][0])
	var tot := [0, 0.0, 0]
	for k in keys:
		var s: Array = stats[k]
		tot[0] += s[0]; tot[1] += s[1]; tot[2] += s[2]
		print("%-22s n=%6d  slide=%.2f m/s  >0.5: %4.1f%%" % [k, s[0], s[1] / s[0], 100.0 * s[2] / s[0]])
	print("TOTAL n=%d slide=%.3f m/s  >0.5: %.1f%%" % [tot[0], tot[1] / tot[0], 100.0 * tot[2] / tot[0]])
