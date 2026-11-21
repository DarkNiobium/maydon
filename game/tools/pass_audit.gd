extends SceneTree
## Classify pass outcomes in AI matches: who touches the ball next and how.
func _initialize():
	var res := {}
	var dist_fail := []
	for seed in [1, 2]:
		var cfg := MatchConfig.new()
		cfg.per_side = 5
		cfg.duration = 240.0
		cfg.seed = seed
		cfg.difficulty = 2
		var m := MatchSim.new(cfg)
		var pend := {}
		while m.phase != MatchSim.Phase.FULLTIME:
			m.step()
			for e in m.events:
				var t: String = e["t"]
				if t == "kick" and e["kind"] in ["pass", "through", "lob", "cross"]:
					var p: Footballer = m.players[e["id"]]
					pend = {"kind": e["kind"], "team": p.team, "from": p.id, "pos": p.pos, "recv": m.last_pass.get("recv", -1), "t": m.clock}
				elif not pend.is_empty() and t in ["touch", "trap", "block", "catch", "save", "steal"]:
					if e.get("id", -1) == pend["from"] and t != "block":
						continue
					var who: Footballer = m.players[e["id"]]
					var outcome := "ok" if who.team == pend["team"] else ("blocked" if t == "block" else "intercepted")
					if outcome == "ok" and t == "block":
						outcome = "own_block"
					if outcome == "ok" and who.id != pend["recv"] and pend["recv"] >= 0:
						outcome = "ok_other"
					var k: String = pend["kind"] + ":" + outcome
					res[k] = res.get(k, 0) + 1
					if outcome != "ok" and outcome != "ok_other":
						dist_fail.append(snappedf(who.pos.distance_to(pend["pos"]), 0.1))
					pend = {}
				elif not pend.is_empty() and t in ["goal", "out", "restart"]:
					res[pend["kind"] + ":dead"] = res.get(pend["kind"] + ":dead", 0) + 1
					pend = {}
	var keys := res.keys()
	keys.sort()
	for k in keys:
		print(k, " ", res[k])
	dist_fail.sort()
	print("fail distance from passer (sorted): ", dist_fail.slice(0, 40))
	quit()
