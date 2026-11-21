extends Node3D
## Visual animation check: one footballer doing a scripted motion, captured as a
## contact sheet. args: out.png mode speed [turn] ; modes: line, circle, diag, side, turn, stopgo, ab
## (ab: two players side by side, left without foot IK)

var chars: Array = []
var players: Array = []
var cam: Camera3D

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "/tmp/anim_look.png"
	var mode := a[1] if a.size() > 1 else "line"
	var sp := float(a[2]) if a.size() > 2 else 5.0
	var turn := float(a[3]) if a.size() > 3 else 1.5
	var view := a[4] if a.size() > 4 else "side"
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
	sun.light_energy = 1.4
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.42, 0.2)
	gm.uv1_scale = Vector3(100, 100, 1)
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color(0.3, 0.5, 0.25) if ((x / 8 + y / 8) % 2 == 0) else Color(0.26, 0.44, 0.22))
	gm.albedo_texture = ImageTexture.create_from_image(img)
	g.material_override = gm
	add_child(g)
	var n := 2 if mode == "ab" else 1
	for i in n:
		var p := Footballer.new()
		p.id = i
		p.number = 7 + i
		p.face = Vector3(0, 0, 1)
		var v := CharacterView.new()
		add_child(v)
		v.setup(p, Game.team_kit(i))
		chars.append(v)
		players.append(p)
	cam = Camera3D.new()
	cam.fov = 35
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	var dt := 1.0 / 60.0
	var shots: Array[Image] = []
	var t := 0.0
	var pos: Array = [Vector3(-0.9, 0, 0), Vector3(0.9, 0, 0)] if n == 2 else [Vector3.ZERO]
	var total := 3.0
	var cap_start := 2.0
	var cap_every := 0.05
	var next_cap := cap_start
	while t < total:
		for i in n:
			var p: Footballer = players[i]
			var dir := Vector3(0, 0, 1)
			var s := sp
			match mode:
				"circle":
					p.face = p.face.rotated(Vector3.UP, turn * dt)
					dir = p.face
				"diag":
					dir = Vector3(0.7071, 0, 0.7071)
				"side":
					dir = Vector3(1, 0, 0)
				"turn":
					s = 0.0
					p.face = p.face.rotated(Vector3.UP, turn * dt)
				"stopgo":
					var ph := fmod(t, 1.6)
					s = sp if ph < 0.8 else 0.0
			p.vel = p.vel.move_toward(dir * s, 9.0 * dt) if mode == "stopgo" else dir * s
			if mode != "circle" and mode != "turn" and p.vel.length() > 0.6:
				p.face = p.vel.normalized()
			pos[i] += p.vel * dt
			CharacterView.cam_pos = pos[i]
			if mode == "ab" and i == 0:
				CharacterView.cam_pos = Vector3(1e4, 0, 0)   # force LOD → no foot IK on the left one
			(chars[i] as CharacterView).sync(p, pos[i], p.face, dt)
		var c: Vector3 = pos[0] if n == 1 else (pos[0] + pos[1]) * 0.5
		var off := Vector3(5.5, 1.0, 0) if view == "side" else (Vector3(0, 1.0, 6.0) if view == "front" else Vector3(3.6, 1.6, 4.2))
		cam.position = c + off
		cam.look_at(c + Vector3(0, 0.85, 0), Vector3.UP)
		await get_tree().process_frame
		t += dt
		if t >= next_cap and shots.size() < 12:
			next_cap += cap_every
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.resize(im.get_width() / 3, im.get_height() / 3)
			var w := im.get_width()
			im = im.get_region(Rect2i(w / 2 - 110, 0, 220, im.get_height()))
			shots.append(im)
	var W := shots[0].get_width()
	var H := shots[0].get_height()
	var sheet := Image.create(W * 6, H * 2, false, shots[0].get_format())
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, W, H), Vector2i((i % 6) * W, (i / 6) * H))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
