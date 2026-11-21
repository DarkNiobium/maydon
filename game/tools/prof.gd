extends SceneTree
## Micro-profile sim functions: godot --headless --path . --script res://tools/prof.gd -- <per_side>
func _initialize():
	var args := OS.get_cmdline_user_args()
	var cfg := MatchConfig.new()
	cfg.per_side = int(args[0]) if args.size() > 0 else 5
	cfg.rules = MatchConfig.Rules.FULL if cfg.per_side >= 9 else MatchConfig.Rules.ARENA
	cfg.duration = 300.0
	cfg.difficulty = 2
	var m := MatchSim.new(cfg)
	for i in 600:
		m.step()
	var t0 := Time.get_ticks_usec()
	var n := 1800
	MatchSim.prof_on = true
	for i in n:
		m.step()
	MatchSim.prof_on = false
	var tot := (Time.get_ticks_usec() - t0) / float(n)
	var parts := ""
	for k in MatchSim.prof:
		parts += "%s=%.0f " % [k, MatchSim.prof[k] / float(n)]
	print("sections (us/tick): ", parts)
	# isolate parts
	t0 = Time.get_ticks_usec()
	for i in 200:
		m.ai[0]._compute_intercepts(m.prediction())
	var ic := (Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		m.ball.predict(75, m.pred_dt)
	var pr := (Time.get_ticks_usec() - t0) / 200.0
	var c := m.team_players(0)[3]
	t0 = Time.get_ticks_usec()
	for i in 100:
		m.ai[0]._decide(c)
	var dc := (Time.get_ticks_usec() - t0) / 100.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		m.ai[0]._plan()
	var pl := (Time.get_ticks_usec() - t0) / 200.0
	print("per tick %.0f us | intercepts %.0f us | predict %.0f us | decide %.0f us | plan %.0f us" % [tot, ic, pr, dc, pl])
	quit()
