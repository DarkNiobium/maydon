extends Node
## 11v11 team-control smoke test through MatchView (headless, manual stepping).
func _ready() -> void:
	Game.settings["control"] = "team"
	var cfg := Game.quick_match(11, Footballer.Role.MID, 1)
	cfg.duration = 600.0
	Game.next_match = cfg
	Game.next_match_meta = {"mode": "quick"}
	var view: MatchView = load("res://scenes/match.tscn").instantiate()
	view.manual_step = true
	add_child(view)
	await get_tree().process_frame
	view.intro_t = 0.0
	print("team_mode ", view.team_mode, " officials ", view.officials != null, " cam ", view.cam.mode)
	var switches := 0
	var last := view.human_id
	var ids := {}
	var t0 := Time.get_ticks_usec()
	var tview := 0
	for f in 30 * 20:
		# simple scripted human: run at the ball, pass when owning it
		var me: Footballer = view.sim.players[view.human_id]
		var to := view.sim.ball.pos - me.pos
		view.human.inp.stick = Vector2(to.x, to.z).normalized() if to.length() > 1.0 else Vector2.ZERO
		view.human.inp.set_button(InputState.B.A, view.sim.owner == view.human_id and f % 40 < 3, view.now)
		var a := Time.get_ticks_usec()
		view.advance(2, 1.0 / 30.0)
		tview += Time.get_ticks_usec() - a
		await get_tree().process_frame
		if view.human_id != last:
			switches += 1
			last = view.human_id
		ids[view.human_id] = true
	for i in 3:
		print("official ", i, " pos ", view.officials._pos[i], " view ", (view.officials._views[i] as Node3D).global_position, " vis ", (view.officials._views[i] as Node3D).visible)
	print("ball ", view.sim.ball.pos)
	var ts := Time.get_ticks_usec()
	for k in 600:
		view.sim.step()
	print("sim step: %.2f ms" % ((Time.get_ticks_usec() - ts) / 600.0 / 1000.0))
	var tt := Time.get_ticks_usec()
	for k in 600:
		view._tick(1.0 / 60.0)
	print("view tick: %.2f ms" % ((Time.get_ticks_usec() - tt) / 600.0 / 1000.0))
	var t3 := Time.get_ticks_usec()
	for k in 600:
		view._snapshot()
	print("snapshot: %.3f ms" % ((Time.get_ticks_usec() - t3) / 600.0 / 1000.0))
	var t4 := Time.get_ticks_usec()
	for k in 600:
		view.replay.record()
	print("replay rec: %.3f ms" % ((Time.get_ticks_usec() - t4) / 600.0 / 1000.0))
	var t5 := Time.get_ticks_usec()
	for k in 600:
		view._team_control()
	print("team ctl: %.3f ms" % ((Time.get_ticks_usec() - t5) / 600.0 / 1000.0))
	var tr := Time.get_ticks_usec()
	for k in 300:
		view._render(1.0 / 30.0, 1.0)
	print("render sync: %.2f ms" % ((Time.get_ticks_usec() - tr) / 300.0 / 1000.0))
	print("avg frame (2 ticks + render sync + modifiers): %.2f ms" % (tview / 600.0 / 1000.0))
	print("switches %d distinct %d score %s" % [switches, ids.size(), str([view.sim.teams[0]["score"], view.sim.teams[1]["score"]])])
	get_tree().quit()
