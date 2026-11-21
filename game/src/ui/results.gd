extends Control
## Full-time screen: score, scorers, team stats, your rating, MOTM, XP/level.

var res: Dictionary
var prog: Dictionary


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	res = Game.last_result
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(UiKit.ACCENT, 0.12)
	stripe.position = Vector2(0, 0)
	stripe.size = Vector2(4000, 330)
	add_child(stripe)
	if res.is_empty():
		Game.goto("res://scenes/menu.tscn")
		return
	var meta: Dictionary = res.get("meta", {})
	var hid: int = res.get("human_id", -1)
	var my_team := 0
	for r in res["ratings"]:
		if r["id"] == hid:
			my_team = r["team"]
	var gf: int = res["score"][my_team]
	var ga: int = res["score"][1 - my_team]
	prog = League.apply_result(res)
	# headline
	var head := UiKit.label(tr("WIN") if gf > ga else (tr("DRAW") if gf == ga else tr("LOSS")), 54,
		UiKit.ACCENT if gf > ga else (Color.WHITE if gf == ga else Color(1, 0.45, 0.4)))
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.position = Vector2(-300, 24)
	head.size = Vector2(600, 70)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(head)
	var score := HBoxContainer.new()
	score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score.position = Vector2(-700, 100)
	score.custom_minimum_size = Vector2(1400, 140)
	score.alignment = BoxContainer.ALIGNMENT_CENTER
	score.add_theme_constant_override("separation", 40)
	add_child(score)
	var n0 := UiKit.label(str(res["names"][0]).to_upper(), 46)
	n0.custom_minimum_size = Vector2(480, 0)
	n0.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.add_child(n0)
	score.add_child(UiKit.label("%d  -  %d" % [res["score"][0], res["score"][1]], 110))
	var n1 := UiKit.label(str(res["names"][1]).to_upper(), 46)
	n1.custom_minimum_size = Vector2(480, 0)
	score.add_child(n1)
	# scorers
	var sc_l := VBoxContainer.new()
	sc_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sc_l.position = Vector2(-700, 240)
	sc_l.custom_minimum_size = Vector2(560, 0)
	add_child(sc_l)
	var sc_r := VBoxContainer.new()
	sc_r.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sc_r.position = Vector2(140, 240)
	add_child(sc_r)
	var names := {}
	for r in res["ratings"]:
		names[r["id"]] = r["name"]
	for g in res["goals"]:
		var txt := "⚽ %s  %d'" % [names.get(g["scorer"], "?"), int(g.get("minute", 0))]
		if g.get("own", false):
			txt += " (" + tr("OWN_GOAL") + ")"
		var l := UiKit.label(txt, 22, Color(1, 1, 1, 0.8), false)
		if int(g["team"]) == 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size = Vector2(560, 0)
			sc_l.add_child(l)
		else:
			sc_r.add_child(l)
	# team stats
	var stats := VBoxContainer.new()
	stats.position = Vector2(80, 390)
	stats.add_theme_constant_override("separation", 10)
	add_child(stats)
	var poss: Array = res["poss"]
	var pt: float = maxf(poss[0] + poss[1], 0.01)
	_stat_bar(stats, tr("POSSESSION"), int(round(100.0 * poss[0] / pt)), int(round(100.0 * poss[1] / pt)), "%")
	_stat_bar(stats, tr("SHOTS"), res["shots"][0], res["shots"][1])
	_stat_bar(stats, tr("CORNERS"), res["corners"][0], res["corners"][1])
	_stat_bar(stats, tr("FOULS"), res["fouls"][0], res["fouls"][1])
	# your performance
	if hid >= 0:
		var me: Dictionary = {}
		for r in res["ratings"]:
			if r["id"] == hid:
				me = r
		var card := PanelContainer.new()
		card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		card.position = Vector2(-640, 345)
		card.custom_minimum_size = Vector2(580, 330)
		card.add_theme_stylebox_override("panel", UiKit.style(Color(1, 1, 1, 0.05), 16, UiKit.GOLD if prog.get("motm", false) else Color(1, 1, 1, 0.15), 2))
		add_child(card)
		var v := VBoxContainer.new()
		card.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 22)
		v.add_child(top)
		var rating: float = me.get("rating", 6.0)
		var rc := Color(0.3, 0.9, 0.45) if rating >= 7.5 else (Color(1, 0.8, 0.3) if rating >= 6.5 else Color(1, 0.5, 0.4))
		top.add_child(UiKit.label("%.1f" % rating, 90, rc))
		var tv := VBoxContainer.new()
		top.add_child(tv)
		tv.add_child(UiKit.label(tr("YOUR_RATING"), 26, Color(1, 1, 1, 0.65)))
		tv.add_child(UiKit.label(str(me.get("name", "")).to_upper(), 36))
		if prog.get("motm", false):
			tv.add_child(UiKit.label("★ " + tr("MOTM"), 26, UiKit.GOLD))
		var st: Dictionary = me.get("stats", {})
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 24)
		v.add_child(grid)
		var items := [["S_GOALS", st.get("goals", 0)], ["S_ASSISTS", st.get("assists", 0)], ["S_SHOTS", st.get("shots", 0)],
			["S_PASSES", "%d/%d" % [st.get("passes_ok", 0), st.get("passes", 0)]], ["S_TACKLES", st.get("tackles_won", 0)],
			["S_INTERCEPT", st.get("interceptions", 0)], ["S_SAVES", st.get("saves", 0)]]
		for it in items:
			var cv := VBoxContainer.new()
			cv.add_child(UiKit.label(str(it[1]), 34))
			cv.add_child(UiKit.label(tr(it[0]), 18, Color(1, 1, 1, 0.55), false))
			grid.add_child(cv)
		var xp := UiKit.label("+%d %s    +%d %s" % [prog.get("xp", 0), tr("XP"), prog.get("coins", 0), tr("COINS")], 26, UiKit.ACCENT)
		v.add_child(xp)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(520, 14)
		bar.max_value = float(prog.get("xp_need", 1))
		bar.value = 0.0
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color(1, 1, 1, 0.1)
		var fgs := StyleBoxFlat.new()
		fgs.bg_color = UiKit.ACCENT
		bar.add_theme_stylebox_override("background", bgs)
		bar.add_theme_stylebox_override("fill", fgs)
		v.add_child(bar)
		create_tween().tween_property(bar, "value", float(prog.get("xp_now", 0)), 1.2).set_delay(0.4)
		v.add_child(UiKit.label("%s %d" % [tr("LEVEL"), prog.get("level", 1)] + ("   " + tr("LEVEL_UP") if prog.get("level_up", false) else ""), 24, UiKit.GOLD if prog.get("level_up", false) else Color.WHITE))
	var cont := UiKit.big_button(tr("CONTINUE") + "  ›", true, 36)
	cont.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cont.position = Vector2(-440, -96)
	cont.pressed.connect(func() -> void:
		Game.next_match = null
		Game.goto("res://scenes/menu.tscn"))
	add_child(cont)
	if gf > ga:
		Sfx.play("crowd_applause", 0.7)


func _stat_bar(parent: Control, name: String, a: int, b: int, suffix := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var la := UiKit.label(str(a) + suffix, 30)
	la.custom_minimum_size = Vector2(70, 0)
	la.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(la)
	var mid := VBoxContainer.new()
	row.add_child(mid)
	var nl := UiKit.label(name, 20, Color(1, 1, 1, 0.6), false)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.custom_minimum_size = Vector2(380, 0)
	mid.add_child(nl)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	mid.add_child(bars)
	var tot := maxf(a + b, 1)
	var ra := ColorRect.new()
	ra.color = UiKit.ACCENT
	ra.custom_minimum_size = Vector2(376.0 * a / tot, 10)
	bars.add_child(ra)
	var rb := ColorRect.new()
	rb.color = Color(1, 1, 1, 0.35)
	rb.custom_minimum_size = Vector2(376.0 * b / tot, 10)
	bars.add_child(rb)
	var lb := UiKit.label(str(b) + suffix, 30)
	lb.custom_minimum_size = Vector2(70, 0)
	row.add_child(lb)
