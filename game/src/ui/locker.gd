extends Control
## Locker room: full character customisation with a live 3D preview
## (face sliders, hair, facial hair, skin, body, gear) and "create from selfie".

const TABS := ["C_PRESETS", "C_FACE", "C_HAIR", "C_BEARD", "C_SKIN", "C_BODY", "C_GEAR"]

var look: Dictionary
var tab := 1
var _vp: SubViewport
var _pivot: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _cam: Camera3D
var _cam_target := Vector3(0, 1.0, 0)
var _cam_dist := 3.4
var _yaw := 0.0
var _drag := false
var _content: VBoxContainer
var _tabs_box: HBoxContainer
var _status: Label
var _ai: AiFace
var _rebuild_t := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	look = Look.get_look()
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.05)
	add_child(bg)
	_build_preview()
	_build_panel()
	var back := UiKit.big_button("‹  " + tr("BACK"), false, 26)
	back.custom_minimum_size = Vector2(190, 64)
	back.position = Vector2(24 + UiKit.safe_left(), 22)
	back.pressed.connect(_leave)
	add_child(back)
	_rebuild_model()
	_show_tab(tab)


# ---------------------------------------------------------------------------
# 3D preview
# ---------------------------------------------------------------------------

func _build_preview() -> void:
	var cont := SubViewportContainer.new()
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.offset_right = -720 - UiKit.safe_right()
	cont.stretch = true
	cont.mouse_filter = Control.MOUSE_FILTER_PASS
	cont.gui_input.connect(_on_preview_input)
	add_child(cont)
	_vp = SubViewport.new()
	_vp.size = Vector2i(900, 900)
	_vp.msaa_3d = Viewport.MSAA_DISABLED if Game.is_web() else (Viewport.MSAA_4X if not Game.is_phone() else Viewport.MSAA_2X)
	_vp.own_world_3d = true
	cont.add_child(_vp)
	var world := Node3D.new()
	_vp.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.3
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 30, 0)
	key.light_energy = 1.15
	key.shadow_enabled = true
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.85, 1.0)
	world.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 1.6, 2.5)
	fill.light_energy = 0.9
	fill.omni_range = 8.0
	world.add_child(fill)
	# floor disc
	var floor := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1
	cm.bottom_radius = 1.15
	cm.height = 0.06
	floor.mesh = cm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.09, 0.1, 0.12)
	fm.roughness = 0.35
	fm.metallic = 0.4
	floor.material_override = fm
	floor.position.y = -0.03
	world.add_child(floor)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.12
	tm.outer_radius = 1.16
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.emission_enabled = true
	rm.emission = UiKit.ACCENT
	rm.emission_energy_multiplier = 2.5
	rm.albedo_color = UiKit.ACCENT
	ring.material_override = rm
	ring.scale = Vector3(1, 0.4, 1)
	world.add_child(ring)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	world.add_child(_cam)
	_cam.current = true


func _on_preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = maxf(1.0, _cam_dist - 0.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(4.5, _cam_dist + 0.25)
	elif e is InputEventMouseMotion and _drag:
		_yaw += (e as InputEventMouseMotion).relative.x * 0.01
	elif e is InputEventScreenDrag:
		_yaw += (e as InputEventScreenDrag).relative.x * 0.01


func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _yaw, clampf(delta * 10.0, 0.0, 1.0))
	var face_tab := tab in [1, 2, 3, 4]
	var tgt := Vector3(0, 1.6, 0) if face_tab else Vector3(0, 1.0, 0)
	if face_tab and _model:
		var sk := CharacterView._find(_model, "Skeleton3D") as Skeleton3D
		if sk:
			var hb := sk.find_bone("head")
			if hb >= 0:
				tgt = sk.global_transform * sk.get_bone_global_pose(hb).origin + Vector3(0, 0.06, 0)
	var dist := (1.45 if face_tab else 3.6) * (_cam_dist / 3.4)
	_cam_target = _cam_target.lerp(tgt, clampf(delta * 5.0, 0.0, 1.0))
	var cp := _cam_target + Vector3(0, 0.05 if face_tab else 0.25, dist)
	_cam.position = _cam.position.lerp(cp, clampf(delta * 5.0, 0.0, 1.0))
	_cam.look_at(_cam_target, Vector3.UP)
	if _rebuild_t > 0.0:
		_rebuild_t -= delta
		if _rebuild_t <= 0.0:
			_rebuild_model()


func _schedule_rebuild() -> void:
	# sliders call this often; re-apply in place when possible
	if _model and CustomCharacter.available():
		CustomCharacter.apply(_model, look)
		_apply_kit_preview()
	else:
		_rebuild_t = 0.05


func _rebuild_model() -> void:
	if _model:
		_model.queue_free()
		_model = null
	if CustomCharacter.available():
		_model = CustomCharacter.instantiate_look(look)
	else:
		CharacterView.load_shared()
		var v: Array = CharacterView._variants
		if v.is_empty():
			return
		_model = (v[int(Game.profile.get("face", 0)) % v.size()] as PackedScene).instantiate()
	_pivot.add_child(_model)
	_model.position.y = 0.017
	_apply_kit_preview()
	# idle animation from the shared library
	if CharacterView.load_shared():
		var sk := CharacterView._find(_model, "Skeleton3D") as Skeleton3D
		if sk:
			sk.name = "SKEL"
			_anim = AnimationPlayer.new()
			sk.get_parent().add_child(_anim)
			_anim.root_node = NodePath("..")
			_anim.add_animation_library("", CharacterView._lib)
			_anim.play(Lobby3D._idle_clip())


func _apply_kit_preview() -> void:
	if _model == null:
		return
	var fake := Footballer.new()
	fake.number = int(Game.profile.get("number", 10))
	var cv := CharacterView.new()
	cv._model = _model
	cv._apply_kit(fake, Game.team_kit(0))
	cv.free()
	for mi in CustomCharacter_meshes(_model):
		(mi as MeshInstance3D).set_instance_shader_parameter("boot_tint", Color.html(str(look.get("boot_color", "#101010"))))
	if CustomCharacter.available():
		CustomCharacter.apply(_model, look)


func CustomCharacter_meshes(n: Node) -> Array:
	var out := []
	CustomCharacter._meshes(n, out)
	return out


# ---------------------------------------------------------------------------
# Panel
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -720 - UiKit.safe_right()
	panel.offset_right = -UiKit.safe_right()
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.add_theme_stylebox_override("panel", UiKit.style(Color(0.06, 0.07, 0.09, 0.97), 0))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := UiKit.label(tr("LOCKER"), 44)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var selfie := UiKit.big_button("📷  " + tr("SELFIE"), true, 24)
	selfie.custom_minimum_size = Vector2(230, 60)
	selfie.add_theme_stylebox_override("normal", UiKit.style(UiKit.GOLD, 12))
	selfie.add_theme_stylebox_override("hover", UiKit.style(UiKit.GOLD.lightened(0.1), 12))
	selfie.pressed.connect(_selfie_start)
	selfie.visible = not OS.has_feature("web")   # no file picker / key in the browser build
	top.add_child(selfie)
	_status = UiKit.label("", 20, Color(1, 1, 1, 0.7), false)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(640, 0)
	v.add_child(_status)
	var tsc := ScrollContainer.new()
	tsc.custom_minimum_size = Vector2(660, 64)
	tsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(tsc)
	_tabs_box = HBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", 6)
	tsc.add_child(_tabs_box)
	for i in TABS.size():
		var b := Button.new()
		b.text = tr(TABS[i])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(90, 56)
		b.add_theme_font_override("font", UiKit.font())
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", UiKit.style(Color(1, 1, 1, 0.06), 10))
		b.add_theme_stylebox_override("hover", UiKit.style(Color(1, 1, 1, 0.12), 10))
		b.add_theme_stylebox_override("pressed", UiKit.style(UiKit.ACCENT, 10))
		b.add_theme_stylebox_override("hover_pressed", UiKit.style(UiKit.ACCENT, 10))
		b.add_theme_color_override("font_pressed_color", UiKit.DARK)
		b.add_theme_color_override("font_hover_pressed_color", UiKit.DARK)
		var idx := i
		b.pressed.connect(func() -> void: _show_tab(idx))
		_tabs_box.add_child(b)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(650, 0)
	_content.add_theme_constant_override("separation", 10)
	sc.add_child(_content)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	var back := UiKit.big_button("‹  " + tr("BACK"), false, 24)
	back.custom_minimum_size = Vector2(160, 64)
	back.pressed.connect(_leave)
	bottom.add_child(back)
	var rnd := UiKit.big_button(tr("RANDOMIZE"), false, 24)
	rnd.custom_minimum_size = Vector2(200, 64)
	rnd.pressed.connect(func() -> void:
		var keep := {"boots": look.get("boots"), "boot_color": look.get("boot_color"), "sleeves": look.get("sleeves"), "socks": look.get("socks"), "acc": look.get("acc")}
		look = Look.random_look(_rng)
		for k in keep:
			look[k] = keep[k]
		_rebuild_model()
		_show_tab(tab))
	bottom.add_child(rnd)
	var save := UiKit.big_button(tr("SAVE"), true, 26)
	save.custom_minimum_size = Vector2(250, 64)
	save.pressed.connect(_save)
	bottom.add_child(save)


## Save the look; paid items that aren't owned yet are bought (or removed if
## the player can't afford them).
func _save() -> void:
	var need := Look.unowned(look)
	var total := 0
	for k in need:
		total += Look.price(k)
	if total == 0:
		Game.profile["look"] = look
		Game.save_game()
		_leave()
		return
	var coins := int(Game.profile.get("coins", 0))
	var dlg := ConfirmationDialog.new()
	dlg.dialog_autowrap = true
	dlg.size = Vector2i(700, 260)
	if coins >= total:
		dlg.title = tr("BUY")
		dlg.dialog_text = tr("BUY_Q").replace("{n}", str(need.size())).replace("{c}", str(total))
		dlg.ok_button_text = tr("BUY") + "  ● %d" % total
		dlg.confirmed.connect(func() -> void:
			Game.profile["coins"] = coins - total
			var own: Array = Game.profile.get("owned", [])
			own.append_array(need)
			Game.profile["owned"] = own
			Game.profile["look"] = look
			Sfx.ui("ok")
			Game.save_game()
			_leave())
	else:
		dlg.title = tr("NO_COINS")
		dlg.dialog_text = tr("NO_COINS_Q").replace("{c}", str(total)).replace("{have}", str(coins))
		dlg.ok_button_text = tr("SAVE_FREE")
		dlg.confirmed.connect(func() -> void:
			Look.strip_unowned(look)
			Game.profile["look"] = look
			Game.save_game()
			_leave())
	dlg.cancel_button_text = tr("BACK")
	add_child(dlg)
	dlg.popup_centered()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_leave()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		_leave()


func _leave() -> void:
	Net.party.push_profile()
	if Game.profile.get("onboarding_locker", false):
		Game.profile["onboarding_locker"] = false
		Game.profile["look"] = look
		Game.save_game()
		if not bool(Game.profile.get("tutorial_done", false)):
			var cfg := Game.quick_match(3, Footballer.Role.FWD, 0, true)
			cfg.duration = 600.0
			cfg.team_strength = [0.65, 0.4]
			Game.next_match = cfg
			Game.next_match_meta = {"mode": "training", "tutorial": true}
			Game.goto("res://scenes/match.tscn")
			return
	Game.goto("res://scenes/menu.tscn")




func show_body() -> void:
	_show_tab(5)


func base_look() -> void:
	# capture/test helper: the clean default look (no accessories)
	look = Look.default_look()
	_rebuild_model()
	_show_tab(2)



func demo_look() -> void:
	# capture/test helper: a distinctive look
	look = Look.default_look()
	look["morphs"] = {"jaw_wide": 0.6, "nose_hump": 0.5, "eyes_monolid": 0.4, "cheekbones_high": 0.6, "brow_heavy": 0.4}
	look["skin_tone"] = 0.7
	look["hair"] = "hair_curly"
	look["hair_color"] = "#3a271a"
	look["beard"] = "beard_short"
	look["beard_color"] = "#2a1d14"
	look["brows"] = "brows_thick"
	look["eye_color"] = "#4f6b3a"
	look["acc"] = {"headband": true, "wristbands": true, "gloves": false, "armband": true}
	look["socks"] = "low"
	look["boots"] = 2
	look["boot_color"] = "#ff6a00"
	_rebuild_model()
	_show_tab(2)


func _show_tab(i: int) -> void:
	tab = i
	for k in _tabs_box.get_child_count():
		(_tabs_box.get_child(k) as Button).button_pressed = k == i
	for c in _content.get_children():
		c.queue_free()
	match TABS[i]:
		"C_PRESETS":
			_presets()
		"C_FACE":
			for sl in Look.FACE_SLIDERS:
				_slider(tr(sl[0]), Look.slider_value(look, sl), -1.0 if sl[1] != "" else 0.0, 1.0, func(v: float) -> void:
					Look.set_slider(look, sl, v)
					_schedule_rebuild())
		"C_HAIR":
			_grid(tr("C_HAIR"), Look.HAIR, str(look.get("hair")), func(id: String) -> void:
				look["hair"] = id
				_schedule_rebuild())
			_swatches(tr("HAIR_COLOR"), Look.HAIR_COLORS, str(look.get("hair_color")), func(c: String) -> void:
				look["hair_color"] = c
				_schedule_rebuild())
		"C_BEARD":
			_grid(tr("C_BEARD"), Look.BEARD, str(look.get("beard")), func(id: String) -> void:
				look["beard"] = id
				_schedule_rebuild())
			_swatches(tr("BEARD_COLOR"), Look.HAIR_COLORS, str(look.get("beard_color")), func(c: String) -> void:
				look["beard_color"] = c
				_schedule_rebuild())
			_grid(tr("BROWS"), Look.BROWS, str(look.get("brows")), func(id: String) -> void:
				look["brows"] = id
				_schedule_rebuild())
		"C_SKIN":
			_slider(tr("SKIN_TONE"), float(look.get("skin_tone", 0.45)), 0.0, 1.0, func(v: float) -> void:
				look["skin_tone"] = v
				_schedule_rebuild(), true)
			_slider(tr("WARMTH"), float(look.get("skin_warmth", 0.2)), -1.0, 1.0, func(v: float) -> void:
				look["skin_warmth"] = v
				_schedule_rebuild())
			_swatches(tr("EYE_COLOR"), Look.EYE_COLORS, str(look.get("eye_color")), func(c: String) -> void:
				look["eye_color"] = c
				_schedule_rebuild())
		"C_BODY":
			_slider(tr("HEIGHT"), float(look.get("height", 0.5)), 0.0, 1.0, func(v: float) -> void:
				look["height"] = v
				_schedule_rebuild())
			var b: Dictionary = look.get("build", {})
			for pair in [["B_MUSCLE", "body_muscular"], ["B_HEAVY", "body_heavy"], ["B_SLIM", "body_slim"]]:
				var key: String = pair[1]
				_slider(tr(pair[0]), float(b.get(key, 0.0)), 0.0, 1.0, func(v: float) -> void:
					var bb: Dictionary = look.get("build", {})
					bb[key] = v
					look["build"] = bb
					_schedule_rebuild())
		"C_GEAR":
			_coins_line()
			_grid(tr("BOOTS"), ["1", "2", "3", "4"], str(look.get("boots", 1)), func(id: String) -> void:
				look["boots"] = int(id)
				_schedule_rebuild(), {"1": tr("BOOT_1"), "2": tr("BOOT_2"), "3": tr("BOOT_3"), "4": tr("BOOT_4")}, "boots:")
			_swatches(tr("BOOT_COLOR"), Look.BOOT_COLORS, str(look.get("boot_color")), func(c: String) -> void:
				look["boot_color"] = c
				_schedule_rebuild(), "bootcol:")
			_grid(tr("SLEEVES"), ["short", "long"], str(look.get("sleeves", "short")), func(id: String) -> void:
				look["sleeves"] = id
				_schedule_rebuild(), {"short": tr("SHORT"), "long": tr("LONG")}, "sleeves:")
			_grid(tr("SOCKS"), ["high", "low"], str(look.get("socks", "high")), func(id: String) -> void:
				look["socks"] = id
				_schedule_rebuild(), {"high": tr("HIGH"), "low": tr("LOW_S")}, "socks:")
			_swatches(tr("ACC_COLOR"), Look.ACC_COLORS, str(look.get("acc_color", "#f2f2f2")), func(c: String) -> void:
				look["acc_color"] = c
				_schedule_rebuild(), "acccol:")
			var acc: Dictionary = look.get("acc", {})
			for pair in [["HEADBAND", "headband"], ["WRISTBANDS", "wristbands"], ["GLOVES", "gloves"], ["ARMBAND", "armband"]]:
				var key2: String = pair[1]
				var cb := CheckButton.new()
				var pr := Look.price("acc:" + key2)
				cb.text = tr(pair[0]) + ("    ● %d" % pr if pr > 0 else "")
				cb.button_pressed = bool(acc.get(key2, false))
				cb.add_theme_font_override("font", UiKit.font())
				cb.add_theme_font_size_override("font_size", 24)
				cb.toggled.connect(func(on: bool) -> void:
					var a: Dictionary = look.get("acc", {})
					a[key2] = on
					look["acc"] = a
					_schedule_rebuild())
				_content.add_child(cb)


func _presets() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	var seeds := [11, 23, 37, 41, 58, 64, 79, 83, 97, 105, 118, 131]
	for i in seeds.size():
		var b := UiKit.big_button("%d" % (i + 1), false, 28)
		b.custom_minimum_size = Vector2(150, 90)
		var sd: int = seeds[i]
		b.pressed.connect(func() -> void:
			var r := RandomNumberGenerator.new()
			r.seed = sd
			var keep := {"boots": look.get("boots"), "boot_color": look.get("boot_color"), "sleeves": look.get("sleeves"), "socks": look.get("socks"), "acc": look.get("acc")}
			look = Look.random_look(r)
			for k in keep:
				look[k] = keep[k]
			_rebuild_model())
		grid.add_child(b)
	var rs := UiKit.big_button(tr("RESET"), false, 24)
	rs.pressed.connect(func() -> void:
		look = Look.default_look()
		_rebuild_model())
	_content.add_child(rs)


func _slider(label: String, val: float, mn: float, mx: float, cb: Callable, tone_bar := false) -> void:
	var l := UiKit.label(label, 22, Color(1, 1, 1, 0.75), false)
	_content.add_child(l)
	var h := HSlider.new()
	h.min_value = mn
	h.max_value = mx
	h.step = 0.01
	h.value = val
	h.custom_minimum_size = Vector2(620, 40)
	h.value_changed.connect(cb)
	_content.add_child(h)
	if tone_bar:
		var g := TextureRect.new()
		var gt := GradientTexture2D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(0.95, 0.8, 0.7))
		gr.set_color(1, Color(0.3, 0.2, 0.14))
		gr.add_point(0.5, Color(0.78, 0.6, 0.45))
		gt.gradient = gr
		gt.width = 256
		gt.height = 8
		g.texture = gt
		g.custom_minimum_size = Vector2(620, 8)
		g.stretch_mode = TextureRect.STRETCH_SCALE
		_content.add_child(g)


func _coins_line() -> void:
	var l := UiKit.label("● %d  %s" % [int(Game.profile.get("coins", 0)), tr("COINS")], 24, UiKit.GOLD)
	_content.add_child(l)


func _grid(label: String, ids: Array, current: String, cb: Callable, names := {}, price_kind := "") -> void:
	_content.add_child(UiKit.label(label, 22, Color(1, 1, 1, 0.75), false))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	var btns := []
	for id in ids:
		var b := Button.new()
		var txt: String = names.get(id, str(id).replace("hair_", "").replace("beard_", "").replace("brows_", "").replace("_", " ").to_upper())
		if id == "none" or id == "bald":
			txt = tr("NONE")
		if price_kind != "":
			var pr := Look.price(price_kind + str(id))
			if pr > 0:
				txt += "   ● %d" % pr
		b.text = txt
		b.toggle_mode = true
		b.button_pressed = str(id) == current
		b.custom_minimum_size = Vector2(205, 58)
		b.add_theme_font_override("font", UiKit.font())
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_stylebox_override("normal", UiKit.style(Color(1, 1, 1, 0.06), 10))
		b.add_theme_stylebox_override("hover", UiKit.style(Color(1, 1, 1, 0.12), 10))
		b.add_theme_stylebox_override("pressed", UiKit.style(UiKit.ACCENT, 10))
		b.add_theme_stylebox_override("hover_pressed", UiKit.style(UiKit.ACCENT, 10))
		b.add_theme_color_override("font_pressed_color", UiKit.DARK)
		var sid := str(id)
		b.pressed.connect(func() -> void:
			for bb in btns:
				bb.button_pressed = false
			b.button_pressed = true
			Sfx.ui("click")
			cb.call(sid))
		btns.append(b)
		grid.add_child(b)


func _swatches(label: String, cols: Array, current: String, cb: Callable, price_kind := "") -> void:
	_content.add_child(UiKit.label(label, 22, Color(1, 1, 1, 0.75), false))
	var flow := HFlowContainer.new()
	flow.custom_minimum_size = Vector2(640, 0)
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	_content.add_child(flow)
	for c in cols:
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		var col := Color.html(c)
		var sel: bool = str(c).to_lower() == current.to_lower()
		b.add_theme_stylebox_override("normal", UiKit.style(col, 28, UiKit.GOLD if sel else Color(1, 1, 1, 0.25), 4 if sel else 2))
		b.add_theme_stylebox_override("hover", UiKit.style(col.lightened(0.1), 28, Color.WHITE, 3))
		b.add_theme_stylebox_override("pressed", UiKit.style(col, 28, UiKit.GOLD, 4))
		var cc: String = c
		b.pressed.connect(func() -> void:
			cb.call(cc)
			_show_tab(tab))
		if price_kind != "" and Look.price(price_kind + c) > 0:
			b.text = str(Look.price(price_kind + c))
			b.add_theme_font_override("font", UiKit.font())
			b.add_theme_font_size_override("font_size", 15)
			b.add_theme_color_override("font_color", Color.WHITE if col.get_luminance() < 0.6 else UiKit.DARK)
		flow.add_child(b)


# ---------------------------------------------------------------------------
# Selfie → AI
# ---------------------------------------------------------------------------

func _selfie_start() -> void:
	if not bool(Game.profile.get("selfie_consent", false)):
		var dlg := ConfirmationDialog.new()
		dlg.title = tr("SELFIE_TITLE")
		dlg.dialog_text = tr("SELFIE_HINT") + "\n\n" + tr("SELFIE_CONSENT")
		dlg.dialog_autowrap = true
		dlg.size = Vector2i(760, 360)
		dlg.ok_button_text = tr("SELFIE_PICK")
		dlg.cancel_button_text = tr("BACK")
		add_child(dlg)
		dlg.confirmed.connect(func() -> void:
			Game.profile["selfie_consent"] = true
			Game.save_game()
			_pick_photo())
		dlg.popup_centered()
		return
	_pick_photo()


func _pick_photo() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show(tr("SELFIE_PICK"), OS.get_system_dir(OS.SYSTEM_DIR_PICTURES), "",
			false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.jpg,*.jpeg,*.png,*.webp;Images"]),
			func(ok: bool, paths: PackedStringArray, _f: int) -> void:
				if ok and not paths.is_empty():
					_load_and_send(paths[0]))
	else:
		var fd := FileDialog.new()
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.filters = PackedStringArray(["*.jpg,*.jpeg,*.png,*.webp;Images"])
		fd.size = Vector2i(1100, 700)
		add_child(fd)
		fd.file_selected.connect(_load_and_send)
		fd.popup_centered()


func _load_and_send(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = tr("SELFIE_FAIL")
		return
	_status.text = tr("SELFIE_WORKING")
	if _ai == null:
		_ai = AiFace.new()
		add_child(_ai)
		_ai.done.connect(_on_ai)
	_ai.analyze(img)


func _on_ai(ok: bool, data: Dictionary, err: String) -> void:
	if not ok:
		_status.text = tr("SELFIE_NET") if err.begins_with("net") or err == "no_key" or err.begins_with("http") else tr("SELFIE_FAIL")
		return
	look = Look.from_ai(data, look)
	_status.text = tr("SELFIE_DONE")
	_rebuild_model()
	_show_tab(1)
