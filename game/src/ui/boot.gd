extends Control
## Loading screen: logo, staged progress (engine → stadium → players → lobby),
## real background loading of the heavy assets, rotating tips. On the web it
## also drives the HTML loader overlay (window.maydonStage / maydonReady).

const STEPS := [
	["BOOT_STADIUM", ["res://assets/tex/sky_night.jpg", "res://assets/tex/turf/albedo.jpg", "res://assets/tex/turf/normal.jpg", "res://assets/gen/ads.png"]],
	["BOOT_PLAYERS", ["res://assets/chars/anims.glb", "res://assets/chars/custom/base.glb"]],
	["BOOT_KITS", ["res://assets/chars/variants/p01.glb", "res://assets/chars/variants/p02.glb", "res://assets/chars/variants/p03.glb"]],
]
const TIPS := ["TIP_1", "TIP_2", "TIP_3", "TIP_4", "TIP_5"]

var _step := 0
var _queue: Array = []
var _done := 0
var _total := 0
var _bar: Control
var _frac := 0.0
var _shown := 0.0
var _stage_l: Label
var _pct_l: Label
var _tip_l: Label
var _tip_t := 0.0
var _tip_i := 0
var _t := 0.0
var _finishing := false
var _dots: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip_i = randi() % TIPS.size()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.35)
	gt.fill_to = Vector2(1.1, 0.9)
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.35, 0.22, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	gt.gradient = g
	glow.texture = gt
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(glow)
	var logo := UiKit.label("MAYDON", 150)
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -500
	logo.offset_right = 500
	logo.offset_top = 90
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(logo)
	var tag := UiKit.label(tr("F3") + "  ·  " + tr("F5") + "  ·  " + tr("F11"), 24, Color(1, 1, 1, 0.6))
	tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tag.offset_left = -500
	tag.offset_right = 500
	tag.offset_top = 290
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)
	# spinning ball
	var ball := Control.new()
	ball.set_anchors_preset(Control.PRESET_CENTER)
	ball.offset_left = -30
	ball.offset_top = -40
	ball.custom_minimum_size = Vector2(60, 60)
	ball.draw.connect(func() -> void:
		var c := Vector2(30, 30 - absf(sin(_t * 5.5)) * 16.0)
		ball.draw_set_transform(c, _t * 5.0, Vector2.ONE)
		Icons.draw(ball, "ball", Rect2(Vector2(-26, -26), Vector2(52, 52)), Color.WHITE)
		ball.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	ball.set_meta("spin", true)
	add_child(ball)
	_dots.append(ball)
	# stage chips
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -400
	row.offset_right = 400
	row.offset_top = -280
	row.offset_bottom = -250
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for i in STEPS.size() + 1:
		var lbl := UiKit.label("%d · %s" % [i + 1, tr(STEPS[i][0] if i < STEPS.size() else "BOOT_LOBBY")], 17, Color(1, 1, 1, 0.35))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		_dots.append(lbl)
	_stage_l = UiKit.label("", 28)
	_stage_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stage_l.offset_left = -400
	_stage_l.offset_right = 200
	_stage_l.offset_top = -236
	_stage_l.offset_bottom = -196
	add_child(_stage_l)
	_pct_l = UiKit.label("0%", 32, UiKit.GOLD)
	_pct_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pct_l.offset_left = 200
	_pct_l.offset_right = 400
	_pct_l.offset_top = -238
	_pct_l.offset_bottom = -196
	_pct_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_pct_l)
	_bar = LobbyWidgets.bar(0.0, 800, 12, UiKit.GOLD)
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.offset_left = -400
	_bar.offset_right = 400
	_bar.offset_top = -146
	_bar.offset_bottom = -134
	add_child(_bar)
	_tip_l = UiKit.label("", 20, Color(1, 1, 1, 0.75), false)
	_tip_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tip_l.offset_left = -500
	_tip_l.offset_right = 500
	_tip_l.offset_top = -116
	_tip_l.offset_bottom = -60
	_tip_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_tip_l)
	_next_tip()
	for s in STEPS:
		_total += (s[1] as Array).size()
	_start_step(0)
	_js("window.maydonStage && window.maydonStage(3, 95)")


func _js(code: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(code, true)


func _next_tip() -> void:
	_tip_l.text = tr("TIP") + ": " + tr(TIPS[_tip_i % TIPS.size()]) if tr("TIP") != "TIP" else tr(TIPS[_tip_i % TIPS.size()])
	_tip_i += 1


func _start_step(i: int) -> void:
	_step = i
	_queue.clear()
	if i >= STEPS.size():
		return
	for p in STEPS[i][1]:
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
			_queue.append(p)
		else:
			_done += 1
	for k in _dots.size() - 1:
		var lbl: Label = _dots[k + 1]
		lbl.add_theme_color_override("font_color", UiKit.ACCENT if k < i else (UiKit.GOLD if k == i else Color(1, 1, 1, 0.35)))
	_stage_l.text = tr(STEPS[i][0]) + "…"


func _process(delta: float) -> void:
	_t += delta
	for d in _dots:
		if d.has_meta("spin"):
			(d as Control).queue_redraw()
	_tip_t += delta
	if _tip_t > 3.5:
		_tip_t = 0.0
		_next_tip()
	if _finishing:
		return
	# poll the current step
	var partial := 0.0
	for p in _queue.duplicate():
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(p, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(p)
			_queue.erase(p)
			_done += 1
		elif not prog.is_empty():
			partial += float(prog[0])
	if _queue.is_empty() and _step < STEPS.size():
		_start_step(_step + 1)
	_frac = (float(_done) + partial) / maxf(_total, 1) * 0.9
	if _step >= STEPS.size() and _queue.is_empty():
		_finish()
	_shown = lerpf(_shown, _frac, clampf(delta * 8.0, 0.0, 1.0))
	_update_bar(_shown)


func _update_bar(f: float) -> void:
	_bar.queue_redraw()
	var c := _bar
	for conn in c.draw.get_connections():
		c.draw.disconnect(conn["callable"])
	c.draw.connect(func() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.bg_color = Color(1, 1, 1, 0.12)
		c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size))
		var fb := StyleBoxFlat.new()
		fb.set_corner_radius_all(6)
		fb.bg_color = UiKit.GOLD
		c.draw_style_box(fb, Rect2(Vector2.ZERO, Vector2(maxf(c.size.x * f, 12.0), c.size.y))))
	_pct_l.text = "%d%%" % int(f * 100.0)


func _finish() -> void:
	_finishing = true
	for k in _dots.size() - 1:
		(_dots[k + 1] as Label).add_theme_color_override("font_color", UiKit.GOLD if k == STEPS.size() else UiKit.ACCENT)
	_stage_l.text = tr("BOOT_LOBBY") + "…"
	CharacterView.load_shared()
	CustomCharacter.available()
	_update_bar(0.96)
	await get_tree().process_frame
	Game.goto("res://scenes/menu.tscn")
