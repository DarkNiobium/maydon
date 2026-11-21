extends SceneTree
## Where do ball carriers make decisions (11v11)? Histogram of progress and chosen kind per zone.
func _initialize():
	var cfg := MatchConfig.new()
	cfg.per_side = 11
	cfg.rules = MatchConfig.Rules.FULL
	cfg.duration = 360.0
	cfg.seed = 5
	cfg.difficulty = 2
	var m := MatchSim.new(cfg)
	TeamAI.dbg_on = true
	var zones := {}
	var last_owner := -1
	var owner_time := [0.0, 0.0, 0.0, 0.0, 0.0]
	while m.phase != MatchSim.Phase.FULLTIME:
		m.step()
		if m.owner >= 0:
			var p: Footballer = m.players[m.owner]
			var prog := (p.pos.x * m.side_of(p.team) / m.pitch.hl() + 1.0) * 0.5
			var z := clampi(int(prog * 5.0), 0, 4)
			owner_time[z] += MatchSim.DT
			for t in 2:
				var dec: Dictionary = m.ai[t].carrier_plan
				pass
	print("possession time by fifth of pitch (own goal → opp goal): ", owner_time)
	var shots := 0
	for p in m.players:
		shots += p.stats["shots"]
	for l in TeamAI.dbg_samples.slice(0, 25):
		print("  ", l)
	print("shots: ", shots, "  score ", m.teams[0]["score"], "-", m.teams[1]["score"])
	quit()
