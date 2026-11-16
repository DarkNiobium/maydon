extends Node
## Headless AI-vs-AI benchmark: `godot --headless --path . res://tools/bench.tscn -- <per_side> <matches> <duration>`

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var per_side := int(args[0]) if args.size() > 0 else 5
	var n := int(args[1]) if args.size() > 1 else 4
	var dur := float(args[2]) if args.size() > 2 else 300.0
	var tot := {}
	var t0 := Time.get_ticks_msec()
	var ticks := 0
	for i in n:
		var cfg := MatchConfig.new()
		cfg.per_side = per_side
		cfg.rules = MatchConfig.Rules.FULL if per_side >= 9 or (args.size() > 3 and args[3] == "full") else MatchConfig.Rules.ARENA
		cfg.duration = dur
		cfg.seed = 1000 + i
		cfg.ai_only = true
		cfg.difficulty = 2
		var m := MatchSim.new(cfg)
		var ev_count := {}
		while m.phase != MatchSim.Phase.FULLTIME and ticks < 10000000:
			m.step()
			ticks += 1
			for e in m.events:
				var k: String = e["t"]
				if k == "kick":
					k = "kick_" + str(e["kind"])
				ev_count[k] = ev_count.get(k, 0) + 1
		var s := {"goals": 0, "shots": 0, "on_target": 0, "passes": 0, "passes_ok": 0,
			"tackles": 0, "tackles_won": 0, "interceptions": 0, "saves": 0, "fouls": 0, "lost": 0}
		for p in m.players:
			for k in s:
				s[k] += p.stats[k]
		var line := "match %d: %d-%d  " % [i, m.teams[0]["score"], m.teams[1]["score"]]
		for k in s:
			line += "%s=%d " % [k, s[k]]
			tot[k] = tot.get(k, 0) + s[k]
		line += " poss=%.0f%%" % (100.0 * m.poss_time[0] / maxf(m.poss_time[0] + m.poss_time[1], 1.0))
		print(line)
		print("   events: ", ev_count)
	var ms := Time.get_ticks_msec() - t0
	print("--- avg per match:")
	for k in tot:
		print("  %s: %.1f" % [k, float(tot[k]) / n])
	if tot.get("passes", 0) > 0:
		print("  pass completion: %.1f%%" % (100.0 * tot["passes_ok"] / tot["passes"]))
	print("  sim speed: %.3f ms/tick (%d ticks)" % [float(ms) / ticks, ticks])
	print("decisions: ", TeamAI.hist)
	for l in TeamAI.dbg_samples:
		print("  ", l)
	get_tree().quit()
