extends Node
## Offline screenshot / frame-sequence harness (works at any render speed):
## godot --path . res://tools/shot.tscn -- <out_dir> <scenario> <t1> <t2> ...   (sim seconds)
## godot --path . res://tools/shot.tscn -- <out_dir> <scenario> seq <start> <secs> <fps>
## scenarios: arena5, arena5tv, arena3, stadium (TV), stadiumpro, *human (keeps human slot)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/shots"
	var sc := args[1] if args.size() > 1 else "arena5"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1600, 900)
	Game.settings["camera"] = 0
	Game.settings["quality"] = int(OS.get_environment("MQ")) if OS.get_environment("MQ") != "" else 2
	if sc.begins_with("scene:"):
		# capture an arbitrary scene: scene:<res path> [frames] [profile=fresh|demo] [action]
		var path := sc.substr(6)
		if args.size() > 3 and args[3] == "demo":
			Game.profile["created"] = true
			Game.profile["name"] = "Karimov"
			Game.profile["level"] = 7
			Game.profile["coins"] = 1240
		elif args.size() > 3 and args[3] == "fresh":
			Game.profile["created"] = false
		if path.contains("results"):
			var cfg := Game.quick_match(5, Footballer.Role.FWD, 1)
			cfg.duration = 90.0
			var m := MatchSim.new(cfg)
			var hid := -1
			for p in m.players:
				if p.human == 0:
					hid = p.id
			while m.phase != MatchSim.Phase.FULLTIME:
				m.step()
			var ratings := []
			for p in m.players:
				ratings.append({"id": p.id, "team": p.team, "name": p.pname, "num": p.number, "role": p.role,
					"rating": m.rating(p), "stats": p.stats.duplicate(), "human": p.human})
			Game.last_result = {"score": [m.teams[0]["score"], m.teams[1]["score"]], "names": cfg.team_names,
				"short": cfg.team_short, "goals": m.goals, "shots": m.shots_n, "poss": m.poss_time,
				"corners": m.corners_n, "fouls": m.fouls_n, "ratings": ratings, "human_id": hid, "meta": {"mode": "quick"}}
		var node: Node = load(path).instantiate()
		add_child(node)
		var frames := int(args[2]) if args.size() > 2 else 30
		for i in frames:
			await get_tree().process_frame
		if args.size() > 4 and node.has_method(args[4]):
			node.call(args[4])
			for i in 20:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var fn := "%s/%s.png" % [out, path.get_file().get_basename() + ("_" + args[4] if args.size() > 4 else "")]
		get_viewport().get_texture().get_image().save_png(fn)
		print("shot ", fn)
		var df := FileAccess.open(out + "/.shot_done", FileAccess.WRITE)
		if df:
			df.store_string("ok")
			df.close()
		get_tree().quit()
		return
	var cfg: MatchConfig
	var meta := {}
	var day := sc.contains("day")
	sc = sc.replace("day", "")
	match sc.trim_suffix("human").trim_suffix("tv"):
		"arena3":
			cfg = Game.quick_match(3, Footballer.Role.FWD, 1)
		"stadium", "stadiumpro":
			cfg = Game.quick_match(11, Footballer.Role.MID, 1)
		_:
			cfg = Game.quick_match(5, Footballer.Role.FWD, 1)
	cfg.seed = 11
	cfg.night = not day
	if not sc.ends_with("human"):
		cfg.humans = []
		meta["follow"] = 3 if cfg.per_side == 5 else (1 if cfg.per_side == 3 else 9)
	if sc.contains("tv") or sc == "stadium":
		meta["cam"] = CameraRig.Mode.TV
	Game.next_match = cfg
	Game.next_match_meta = meta
	var view: MatchView = load("res://scenes/match.tscn").instantiate()
	view.manual_step = true
	add_child(view)
	for i in 3:
		await get_tree().process_frame
	var sim_t := 0.0
	var idx := 0
	if args.size() > 2 and args[2] == "seq":
		var start := float(args[3])
		var secs := float(args[4])
		var fps := int(args[5]) if args.size() > 5 else 15
		var per := int(60 / fps)
		view.advance(int(start * 60.0))
		var close := OS.get_environment("CLOSECAM") != ""
		var cpos := Vector3.ZERO
		for f in int(secs * fps):
			view.advance(per, 1.0 / fps)
			if close:
				# low touchline-style close-up that tracks the ball (foot/ball contact checks)
				var b: Vector3 = view.ball_mi.global_position
				var want := b + Vector3(0.0, 1.3, 4.2)
				cpos = want if f == 0 else cpos.lerp(want, 0.25)
				view.cam.global_position = cpos
				view.cam.look_at(Vector3(b.x, 0.45, b.z), Vector3.UP)
				view.cam.fov = 50.0
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("%s/f_%04d.jpg" % [out, f], 0.85)
		print("seq done ", int(secs * fps), " frames")
	else:
		for i in range(2, args.size()):
			var t := float(args[i])
			var n := int((t - sim_t) * 60.0)
			if n > 0:
				view.advance(n)
			sim_t = t
			# let interpolated visuals settle for a couple of frames
			for k in 2:
				view.advance(1)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var fn := "%s/%s_%02d.png" % [out, sc, idx]
			get_viewport().get_texture().get_image().save_png(fn)
			print("shot ", fn)
			idx += 1
	# Forward+ can hang on exit under Xvfb (background shader compiles): shot.sh kills us on this marker
	var f := FileAccess.open(out + "/.shot_done", FileAccess.WRITE)
	if f:
		f.store_string("ok")
		f.close()
	get_tree().quit()
