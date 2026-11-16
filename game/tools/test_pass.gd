extends SceneTree
func _initialize():
	var cfg := MatchConfig.new()
	cfg.per_side = 5
	var m := MatchSim.new(cfg)
	var b := m.ball
	for v0 in [6.0, 10.0, 14.0]:
		print("v0=", v0, " t(5)=", b.roll_time(v0, 5.0), " t(10)=", b.roll_time(v0, 10.0), " dist(v0->3)=", b.roll_distance(v0, 3.0))
	print("speed for 12m arrive 4: ", b.ground_pass_speed(12.0, 4.0))
	# place: passer at origin, receiver 12 m ahead, opponent far away
	for p in m.players:
		p.pos = Vector3(0, 0, 100 + p.id * 3)
	var a: Footballer = m.players[3]
	var r: Footballer = m.players[4]
	a.pos = Vector3(0, 0, 0)
	r.pos = Vector3(12, 0, 0)
	b.reset(Vector3(0.4, 0, 0))
	var ai: TeamAI = m.ai[0]
	var v := b.ground_pass_speed(12.0, 4.0)
	print("safety (no opp) = ", ai.pass_safety(b.pos, r.pos, v))
	var o: Footballer = m.players[8]
	o.pos = Vector3(6, 0, 4)
	print("safety (opp 4m off lane) = ", ai.pass_safety(b.pos, r.pos, v), " t_o=", o.time_to(Vector3(6,0,0), true, 0.72))
	o.pos = Vector3(6, 0, 2)
	print("safety (opp 2m off lane) = ", ai.pass_safety(b.pos, r.pos, v))
	quit()
