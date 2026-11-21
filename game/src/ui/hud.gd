class_name Hud
extends CanvasLayer
## In-match HUD: broadcast score bug, banners, radar, pause button, touch controls.

signal pause_requested

var m: MatchSim
var human_id := -1
var touch: TouchControls
var _score_lbl: Label
var _time_lbl: Label
var _home_lbl: Label
var _away_lbl: Label
var _home_chip: ColorRect
var _away_chip: ColorRect
var _banner: Label
var _sub: Label
var _banner_t := 0.0
var _radar: Control
var _hint: Label
var _hint_t := 0.0
var _font: Font
var _font_text: Font
var _name_lbl: Label
var _stamina: ProgressBar
var crosshair := false
var emote_wheel: EmoteWheel
var emote_btn: Button
var _cross: Control
var _power := -1.0


func setup(sim: MatchSim, hid: int, show_touch: bool) -> void:
	m = sim
	human_id = hid
	layer = 10
	_font = load("res://assets/fonts/Oswald.ttf")
	_font_text = load("res://assets/fonts/Inter.ttf")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var inset := maxf(UiKit.safe_left(), UiKit.safe_right())
	root.offset_left = inset
	root.offset_right = -inset
	_build_scorebug(root)
	_build_banner(root)
	_radar = Control.new()
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.draw.connect(_draw_radar)
	root.add_child(_radar)
	_cross = Control.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	var pb := Button.new()
	pb.text = "II"
	pb.add_theme_font_override("font", _font)
	pb.add_theme_font_size_override("font_size", 30)
	pb.flat = false
	pb.custom_minimum_size = Vector2(70, 60)
	pb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pb.position = Vector2(-90, 18)
	pb.pressed.connect(func() -> void: pause_requested.emit())
	var sbx := StyleBoxFlat.new()
	sbx.bg_color = Color(0, 0, 0, 0.45)
	sbx.set_corner_radius_all(8)
	pb.add_theme_stylebox_override("normal", sbx)
	pb.add_theme_stylebox_override("hover", sbx)
	pb.add_theme_stylebox_override("pressed", sbx)
	pb.focus_mode = Control.FOCUS_NONE
	root.add_child(pb)
	_hint = Label.new()
	_hint.add_theme_font_override("font", _font)
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-300, -150)
	_hint.size = Vector2(600, 40)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate.a = 0.0
	root.add_child(_hint)
	if hid >= 0:
		var p: Footballer = m.players[hid]
		_name_lbl = Label.new()
		_name_lbl.text = "%d  %s  ·  %s" % [p.number, p.pname.to_upper(), Formations.role_name(p.role)]
		_name_lbl.add_theme_font_override("font", _font)
		_name_lbl.add_theme_font_size_override("font_size", 22)
		_name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_name_lbl.add_theme_constant_override("outline_size", 5)
		_name_lbl.position = Vector2(24, 92)
		root.add_child(_name_lbl)
		_stamina = ProgressBar.new()
		_stamina.show_percentage = false
		_stamina.max_value = 1.0
		_stamina.position = Vector2(24, 126)
		_stamina.size = Vector2(170, 8)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.45)
		var fg := StyleBoxFlat.new()
		fg.bg_color = Color(0.3, 0.95, 0.5)
		_stamina.add_theme_stylebox_override("background", bg)
		_stamina.add_theme_stylebox_override("fill", fg)
		root.add_child(_stamina)
	if hid >= 0:
		emote_btn = Button.new()
		emote_btn.custom_minimum_size = Vector2(70, 60)
		emote_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		emote_btn.position = Vector2(-172, 18)
		emote_btn.focus_mode = Control.FOCUS_NONE
		emote_btn.add_theme_stylebox_override("normal", sbx)
		emote_btn.add_theme_stylebox_override("hover", sbx)
		emote_btn.add_theme_stylebox_override("pressed", sbx)
		emote_btn.draw.connect(func() -> void:
			var c := emote_btn.size * 0.5
			emote_btn.draw_arc(c, 17.0, 0, TAU, 32, Color.WHITE, 3.0, true)
			emote_btn.draw_circle(c + Vector2(-6, -5), 2.6, Color.WHITE)
			emote_btn.draw_circle(c + Vector2(6, -5), 2.6, Color.WHITE)
			emote_btn.draw_arc(c + Vector2(0, 1), 9.0, 0.35, PI - 0.35, 12, Color.WHITE, 2.6, true)
			if not Game.is_phone():
				emote_btn.draw_string(_font, Vector2(emote_btn.size.x - 16, emote_btn.size.y - 4), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6)))
		root.add_child(emote_btn)
	if show_touch:
		touch = TouchControls.new()
		touch.btn_scale = float(Game.settings.get("btn_scale", 1.0))
		touch.btn_alpha = float(Game.settings.get("btn_alpha", 0.8))
		add_child(touch)   # full-screen layer (handles safe area itself)
	if hid >= 0:
		emote_wheel = EmoteWheel.new()
		add_child(emote_wheel)
		emote_btn.pressed.connect(emote_wheel.open)


func _panel(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(4)
	return s


func _build_scorebug(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(20, 20)
	bar.add_theme_constant_override("separation", 0)
	root.add_child(bar)
	var mk := func(txt: String, w: float, bg: Color, fs: int, col := Color.WHITE) -> Label:
		var l := Label.new()
		l.text = txt
		l.custom_minimum_size = Vector2(w, 56)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", col)
		l.add_theme_stylebox_override("normal", _panel(bg))
		return l
	_home_chip = ColorRect.new()
	_home_chip.custom_minimum_size = Vector2(8, 56)
	_home_chip.color = m.cfg.kits[0].get("shirt", Color.RED)
	bar.add_child(_home_chip)
	_home_lbl = mk.call(str(m.cfg.team_short[0]), 84, Color(0.04, 0.06, 0.09, 0.82), 28)
	bar.add_child(_home_lbl)
	_score_lbl = mk.call("0 - 0", 96, Color(0.96, 0.96, 0.96, 0.95), 32, Color(0.05, 0.05, 0.08))
	bar.add_child(_score_lbl)
	_away_lbl = mk.call(str(m.cfg.team_short[1]), 84, Color(0.04, 0.06, 0.09, 0.82), 28)
	bar.add_child(_away_lbl)
	_away_chip = ColorRect.new()
	_away_chip.custom_minimum_size = Vector2(8, 56)
	_away_chip.color = m.cfg.kits[1].get("shirt", Color.BLUE)
	bar.add_child(_away_chip)
	_time_lbl = mk.call("00:00", 96, Color(0.1, 0.75, 0.42, 0.92), 28)
	bar.add_child(_time_lbl)


func _build_banner(root: Control) -> void:
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-500, -170)
	_banner.size = Vector2(1000, 150)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_override("font", _font)
	_banner.add_theme_font_size_override("font_size", 120)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.position = Vector2(-500, -30)
	_sub.size = Vector2(1000, 60)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_override("font", _font)
	_sub.add_theme_font_size_override("font_size", 36)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_sub.add_theme_constant_override("outline_size", 8)
	_sub.modulate.a = 0.0
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sub)


func banner(text: String, sub := "", dur := 2.5, col := Color.WHITE, fs := 120) -> void:
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", fs)
	_banner.add_theme_color_override("font_color", col)
	_sub.text = sub
	_banner_t = dur
	_banner.scale = Vector2(1.4, 1.4)
	_banner.pivot_offset = _banner.size * 0.5
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hint(text: String, dur := 2.0) -> void:
	_hint.text = text
	_hint_t = dur


var _click_lbl: Label


func click_hint(on: bool) -> void:
	if _click_lbl == null:
		if not on:
			return
		_click_lbl = Label.new()
		_click_lbl.text = tr("CLICK_TO_PLAY")
		_click_lbl.add_theme_font_override("font", _font)
		_click_lbl.add_theme_font_size_override("font_size", 34)
		_click_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_click_lbl.add_theme_constant_override("outline_size", 10)
		_click_lbl.set_anchors_preset(Control.PRESET_CENTER)
		_click_lbl.offset_left = -500
		_click_lbl.offset_right = 500
		_click_lbl.offset_top = 60
		_click_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_click_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_click_lbl)
	_click_lbl.visible = on


func set_human(id: int) -> void:
	human_id = id
	if _name_lbl and id >= 0:
		var p: Footballer = m.players[id]
		_name_lbl.text = "%d  %s  ·  %s" % [p.number, p.pname.to_upper(), Formations.role_name(p.role)]


func update_hud(dt: float, now: float, ctx: String, power: float) -> void:
	_score_lbl.text = "%d - %d" % [m.teams[0]["score"], m.teams[1]["score"]]
	if m.is_full():
		var mins := m.minute()
		_time_lbl.text = "%d'" % mins
	else:
		var tl := m.time_left()
		_time_lbl.text = "%d:%02d" % [int(tl) / 60, int(tl) % 60]
	if _banner_t > 0.0:
		_banner_t -= dt
		_banner.modulate.a = minf(1.0, _banner_t * 3.0)
		_sub.modulate.a = _banner.modulate.a
	else:
		_banner.modulate.a = 0.0
		_sub.modulate.a = 0.0
	if _hint_t > 0.0:
		_hint_t -= dt
		_hint.modulate.a = minf(1.0, _hint_t * 2.5)
	else:
		_hint.modulate.a = 0.0
	_power = power
	_cross.queue_redraw()
	if touch:
		touch.set_context(ctx)
		touch.set_power(power)
		touch.tick(now, dt)
	if _stamina and human_id >= 0:
		_stamina.value = m.players[human_id].stamina
	_radar.queue_redraw()


func _draw_cross() -> void:
	if not crosshair:
		return
	var c := _cross.get_viewport_rect().size * 0.5
	var col := Color(1, 1, 1, 0.85)
	_cross.draw_arc(c, 9.0, 0, TAU, 32, Color(0, 0, 0, 0.35), 4.0, true)
	_cross.draw_arc(c, 9.0, 0, TAU, 32, col, 2.0, true)
	_cross.draw_circle(c, 1.8, col)
	if _power >= 0.0:
		var pc := Color(0.2, 0.95, 0.45).lerp(Color(1.0, 0.25, 0.15), clampf((_power - 0.6) / 0.4, 0.0, 1.0))
		_cross.draw_arc(c, 18.0, -PI * 0.5, -PI * 0.5 + TAU * _power, 48, pc, 4.0, true)


func _draw_radar() -> void:
	var vs := _radar.get_viewport_rect().size
	var w := 230.0
	var h := w * m.pitch.width / m.pitch.length
	var origin := Vector2(vs.x * 0.5 - w * 0.5, vs.y - h - 14.0)
	if touch:
		origin = Vector2(vs.x * 0.5 - w * 0.5, 14.0)
	_radar.draw_rect(Rect2(origin, Vector2(w, h)), Color(0.05, 0.25, 0.12, 0.45))
	_radar.draw_rect(Rect2(origin, Vector2(w, h)), Color(1, 1, 1, 0.5), false, 1.5)
	_radar.draw_line(origin + Vector2(w * 0.5, 0), origin + Vector2(w * 0.5, h), Color(1, 1, 1, 0.35), 1.0)
	var to2 := func(p: Vector3) -> Vector2:
		return origin + Vector2((p.x / m.pitch.length + 0.5) * w, (p.z / m.pitch.width + 0.5) * h)
	for p in m.players:
		if p.sent_off:
			continue
		var c: Color = m.cfg.kits[p.team].get("shirt", Color.WHITE)
		var r := 3.5
		if p.id == human_id:
			_radar.draw_circle(to2.call(p.pos), 6.5, Color(1, 1, 0.2))
			r = 4.5
		_radar.draw_circle(to2.call(p.pos), r, c)
	_radar.draw_circle(to2.call(m.ball.pos), 3.0, Color.WHITE)
