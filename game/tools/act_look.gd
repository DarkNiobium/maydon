extends Node3D
## Action contact sheet on the in-game character (same clip choice + timing as a match):
## args: out.png action [speed]   action = slide | fall | dive_l | dive_r | block_l | block_r | shot | pass
## Footballer timing mirrors MatchSim (_slide_step, _dive_step, FALL -> GETUP).

var cam: Camera3D

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "/tmp/act_look.png"
	var act := a[1] if a.size() > 1 else "slide"
	var sp := float(a[2]) if a.size() > 2 else 5.0
	CharacterView.load_shared()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color(0.3, 0.5, 0.25) if ((x / 8 + y / 8) % 2 == 0) else Color(0.26, 0.44, 0.22))
	gm.albedo_texture = ImageTexture.create_from_image(img)
	gm.uv1_scale = Vector3(100, 100, 1)
	g.material_override = gm
	add_child(g)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BallSim.R
	sm.height = BallSim.R * 2.0
	ball.mesh = sm
	add_child(ball)
	CharacterView.ball_node = ball
	var p := Footballer.new()
	p.id = 3
	p.number = 7
	p.face = Vector3(0, 0, 1)
	if act.begins_with("dive") or act.begins_with("block"):
		p.role = Footballer.Role.GK
	var v := CharacterView.new()
	add_child(v)
	v.setup(p, Game.team_kit(0))
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	var t := 0.0
	var pos := Vector3.ZERO
	var t_act := 1.0
	var dur := 1.45
	var shots: Array[Image] = []
	var started := false
	var getup_t := -1.0
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var bpos := Vector3(0, BallSim.R, 99)
	var cap_every := 0.12
	var next_cap := t_act - 0.1
	while shots.size() < 18 and t < 8.0:
		var run := not started and not (act.begins_with("dive") or act.begins_with("block"))
		if run:
			p.vel = Vector3(0, 0, sp)
		elif not started:
			p.vel = Vector3.ZERO
		if not started and t >= t_act:
			started = true
			p.act_t = 0.0
			match act:
				"slide":
					dur = 1.45
					p.start_action(Footballer.A.SLIDE, dur, 0.12, {"dir": Vector3(0, 0, 1), "v": sp + 1.0, "hit": false, "ball": false})
				"fall":
					dur = 1.0
					p.start_action(Footballer.A.FALL, dur, 0.0, {"dir": Vector3(0, 0, 1)})
				"shot", "pass":
					dur = 0.5
					bpos = pos + Vector3(0.1, BallSim.R, 0.36 + sp * 0.18)
					p.start_action(Footballer.A.SHOT if act == "shot" else Footballer.A.PASS, dur, 0.18,
						{"target": pos + Vector3(0, 0, 30), "power": 0.8, "foot": 1})
				_:
					var side := 1.0 if act.ends_with("_l") else -1.0     # +x = character left (face +z)
					dur = 1.25 + 2.5 * 0.08
					from = pos
					to = pos + Vector3(2.5 * side, 0, 0)
					p.start_action(Footballer.A.GK_DIVE, dur, 0.1, {"from": from, "to": to,
						"h": 0.3 if act.begins_with("block") else 1.2, "dir": Vector3(side, 0, 0), "lat": 2.5})
		if started:
			p.act_t += dt
			match p.action:
				Footballer.A.SLIDE:
					var k := maxf(1.0 - p.act_t / 0.75, 0.0)
					p.vel = Vector3(0, 0, (sp + 1.0) * k)
				Footballer.A.FALL:
					p.vel *= 0.9
				Footballer.A.GK_DIVE:
					var k2 := clampf((p.act_t - 0.06) / 0.42, 0.0, 1.0)
					pos = from.lerp(to, 1.0 - pow(1.0 - k2, 2.0))
					p.vel = Vector3.ZERO
				Footballer.A.SHOT, Footballer.A.PASS:
					p.vel = p.vel.move_toward(Vector3(0, 0, 1.5), 12.0 * dt)
					if p.act_t >= p.act_contact and not p.act_done:
						p.act_done = true
				Footballer.A.GETUP:
					p.vel = Vector3.ZERO
			if p.action != Footballer.A.NONE and p.act_t >= p.act_dur:
				if p.action in [Footballer.A.SLIDE, Footballer.A.GK_DIVE]:
					p.start_action(Footballer.A.GETUP, 0.7, 0.0)
				elif p.action == Footballer.A.FALL:
					p.start_action(Footballer.A.GETUP, 1.0, 0.0)
				else:
					p.end_action()
		if p.action != Footballer.A.GK_DIVE:
			pos += p.vel * dt
		if p.vel.length() > 0.3:
			p._gait_step(dt)
		if p.act_done and act in ["shot", "pass"]:
			bpos += Vector3(0, 0, 20.0 * dt)
		ball.position = bpos
		CharacterView.ball_pos = bpos
		CharacterView.ball_vel = Vector3.ZERO
		CharacterView.sim_time = t
		CharacterView.sim_clock = t
		CharacterView.sim_owner = -1
		CharacterView.cam_pos = pos
		v.sync(p, pos, p.face, dt)
		var off := Vector3(5.0, 1.1, 1.0) if not (act.begins_with("dive") or act.begins_with("block")) else Vector3(0.0, 1.3, 6.5)
		cam.position = pos + off
		cam.look_at(pos + Vector3(0, 0.7, 0), Vector3.UP)
		await get_tree().process_frame
		t += dt
		if t >= next_cap:
			next_cap += cap_every
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.resize(im.get_width() / 3, im.get_height() / 3)
			var w := im.get_width()
			im = im.get_region(Rect2i(w / 2 - 130, 20, 260, im.get_height() - 40))
			shots.append(im)
	var W := shots[0].get_width()
	var H := shots[0].get_height()
	var sheet := Image.create(W * 6, H * 3, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, W, H), Vector2i((i % 6) * W, (i / 6) * H))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
