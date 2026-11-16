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
	var cfg: MatchConfig
	var meta := {}
	match sc.trim_suffix("human").trim_suffix("tv"):
		"arena3":
			cfg = Game.quick_match(3, Footballer.Role.FWD, 1)
		"stadium", "stadiumpro":
			cfg = Game.quick_match(11, Footballer.Role.MID, 1)
		_:
			cfg = Game.quick_match(5, Footballer.Role.FWD, 1)
	cfg.seed = 11
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
		for f in int(secs * fps):
			view.advance(per, 1.0 / fps)
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
	get_tree().quit()
