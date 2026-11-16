extends Node
## Text trace of an AI match: `godot --headless --path . res://tools/trace.tscn -- <per_side> <seconds> <every>`

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var per_side := int(args[0]) if args.size() > 0 else 5
	var secs := float(args[1]) if args.size() > 1 else 20.0
	var every := int(args[2]) if args.size() > 2 else 15
	var cfg := MatchConfig.new()
	cfg.per_side = per_side
	cfg.rules = MatchConfig.Rules.FULL if per_side >= 9 else MatchConfig.Rules.ARENA
	cfg.duration = 300.0
	cfg.seed = int(args[3]) if args.size() > 3 else 7
	cfg.difficulty = 2
	var m := MatchSim.new(cfg)
	var n := int(secs * 60.0)
	for i in n:
		m.step()
		for e in m.events:
			if e["t"] in ["bounce", "dribble"]:
				continue
			var s := "   ev %s" % e["t"]
			if e.has("id"):
				var p: Footballer = m.players[e["id"]]
				s += " %d(t%d %s)" % [p.id, p.team, Formations.role_name(p.role)]
			for k in e:
				if k not in ["t", "id", "p"]:
					s += " %s=%s" % [k, str(e[k]).substr(0, 24)]
			print(s)
		if i % every == 0:
			var o := m.owner
			var os := "-" if o < 0 else "%d(t%d %s %s)" % [o, m.players[o].team, Formations.role_name(m.players[o].role), m.ai[m.players[o].team].carrier_plan.get("kind", "")]
			print("%6.2f ph=%d own=%s ball=(%.1f,%.1f,%.1f) v=%.1f poss=%d" % [m.clock, m.phase, os, m.ball.pos.x, m.ball.pos.y, m.ball.pos.z, m.ball.speed(), m.poss_team])
	get_tree().quit()
