extends Node3D
## Render character variants with the kit shader (no animation): front + back.
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.65)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	var many := OS.get_cmdline_user_args().has("all")
	cam.position = Vector3(0, 1.0, 4.6) if not many else Vector3(0, 1.0, 9.5)
	cam.fov = 40
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	var dir := DirAccess.open("res://assets/chars/variants")
	var files := []
	for f in dir.get_files():
		var n := f.trim_suffix(".import")
		if n.ends_with(".glb") and not files.has(n):
			files.append(n)
	files.sort()
	var kit := Game.kit(1)
	if many:
		kit = Game.kit(2)
	var i := 0
	for n in files:
		var inst: Node3D = load("res://assets/chars/variants/" + n).instantiate()
		add_child(inst)
		inst.position = Vector3((i % 2) * 1.0 - 0.5, 0, 0)
		inst.rotation.y = 0.0 if i % 2 == 0 else PI
		if many:
			inst.position = Vector3((i - 5.5) * 0.95, 0, 0)
			inst.rotation.y = 0.0
		var fake := Footballer.new()
		fake.number = 10 + i
		fake.id = i
		var cv := CharacterView.new()
		cv._model = inst
		cv._apply_kit(fake, kit)
		cv.free()
		i += 1
		if i >= 2 and not many:
			break
	if files.size() == 1:
		var inst2: Node3D = load("res://assets/chars/variants/" + files[0]).instantiate()
		add_child(inst2)
		inst2.position = Vector3(0.5, 0, 0)
		inst2.rotation.y = PI
		var fake2 := Footballer.new()
		fake2.number = 7
		var cv2 := CharacterView.new()
		cv2._model = inst2
		cv2._apply_kit(fake2, Game.kit(2))
		cv2.free()
