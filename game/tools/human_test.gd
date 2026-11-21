extends Node
## Scripted "human" playing through InputState → HumanController (tests the real control path).
## godot --headless --path . res://tools/human_test.tscn -- <per_side> <role> <seconds>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ps := int(args[0]) if args.size() > 0 else 5
	var role := int(args[1]) if args.size() > 1 else 3
	var secs := float(args[2]) if args.size() > 2 else 240.0
	var cfg := Game.quick_match(ps, role, 1)
	cfg.duration = secs
	cfg.seed = 99
	var m := MatchSim.new(cfg)
	var hid := -1
	for p in m.players:
		if p.human == 0:
			hid = p.id
	var hc := HumanController.new(m, hid)
	var now := 0.0
	var hold_b := -1.0
	var ctx_count := {}
	var acts := {}
	while m.phase != MatchSim.Phase.FULLTIME:
		now += MatchSim.DT
		var me: Footballer = m.players[hid]
		var side := m.side_of(me.team)
		var fwd := Vector3(side, 0, 0)
		var right := fwd.cross(Vector3.UP)
		var inp := hc.inp
		var ctx := hc.context()
		ctx_count[ctx] = ctx_count.get(ctx, 0) + 1
		var goal := m.opp_goal(me.team)
		var target := m.ball.pos
		var press := []
		var release := []
		match ctx:
			"attack", "setpiece":
				target = goal
				var dg := me.pos.distance_to(goal)
				if hold_b < 0.0 and dg < 15.0 and randf() < 0.05:
					hold_b = now
					press.append(InputState.B.B)
				elif hold_b >= 0.0 and now - hold_b > 0.45:
					release.append(InputState.B.B)
					hold_b = -1.0
				elif hold_b < 0.0 and m.ai[me.team].nearest_opponent_dist(me.pos) < 2.2 and randf() < 0.08:
					press.append(InputState.B.A)
					release.append(InputState.B.A)
			"support":
				target = me.pos + fwd * 6.0
				if randf() < 0.01:
					press.append(InputState.B.A)
			"defend":
				target = m.ball.pos
				if me.pos.distance_to(m.ball.pos) < 1.6 and randf() < 0.1:
					press.append(InputState.B.A)
			"throw", "gk_hold":
				press.append(InputState.B.A)
				release.append(InputState.B.A)
		var d := target - me.pos
		d.y = 0
		var w := d.normalized() if d.length() > 0.5 else Vector3.ZERO
		inp.stick = Vector2(w.dot(right), w.dot(fwd))
		inp.set_button(InputState.B.SPRINT, d.length() > 6.0, now)
		for b in press:
			inp.set_button(b, true, now)
		if not release.is_empty():
			# release on the same tick → a tap; edges are kept until end_frame
			for b in release:
				inp.held[b] = true
				inp.set_button(b, false, now)
		hc.update(now, fwd, right)
		if me.cmd.act != Cmd.Act.NONE:
			acts[me.cmd.act] = acts.get(me.cmd.act, 0) + 1
		m.step()
		inp.end_frame()
	var me2: Footballer = m.players[hid]
	print("score %d-%d | my stats: %s" % [m.teams[0]["score"], m.teams[1]["score"], str(me2.stats)])
	print("rating %.1f | contexts %s | cmd acts %s" % [m.rating(me2), str(ctx_count), str(acts)])
	get_tree().quit()
