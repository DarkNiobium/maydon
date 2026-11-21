extends Control
## Main menu with a live floodlit match behind it. Screens are built in code:
## onboarding, main, quick match, league, profile, settings, training.

const TF := preload("res://src/ui/ui_kit.gd")

var bg_match: Node
var lobby: Lobby3D
var _bg_container: SubViewportContainer
var _bg_vp: SubViewport
var _slot_btns: Array = []
var _slot_tags: Array = []
var _mm_banner: PanelContainer
var _mm_label: Label
var _play_btn: Control
var _versus: Control
var _party_hooked := false
var _lobby_wheel: EmoteWheel
var _av_cam: Camera3D
var _shade: TextureRect
var screen: Control
var _quick := {"format": 5, "role": -1, "diff": -1, "night": true, "len": -1}
var _onb := {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_background()
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.02, 0.03, 0.94))
	g.set_color(1, Color(0.01, 0.02, 0.03, 0.25))
	g.add_point(0.45, Color(0.01, 0.02, 0.03, 0.75))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)
	_shade = shade
	Sfx.play_music()
	_hook_party()
	if OS.has_feature("web"):
		_web_ready()
	if not bool(Game.profile.get("created", false)):
		_show_onboarding(0)
	else:
		_show_main()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_show_main()


func _start_background() -> void:
	var vp := SubViewportContainer.new()
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.stretch = true
	vp.stretch_shrink = 1
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp)
	var sv := SubViewport.new()
	sv.size = Vector2i(1600, 900)
	sv.audio_listener_enable_3d = false
	sv.msaa_3d = Viewport.MSAA_DISABLED if Game.is_web() else (Viewport.MSAA_2X if Game.is_phone() else Viewport.MSAA_4X)
	vp.add_child(sv)
	lobby = Lobby3D.new()
	sv.add_child(lobby)
	_bg_container = vp
	_bg_vp = sv


func _process(_delta: float) -> void:
	if lobby == null or lobby.cam == null:
		return
	# squad "+" buttons follow the 3D pedestals
	if not _slot_btns.is_empty() and is_instance_valid(_slot_btns[0]):
		var k := _bg_container.size / Vector2(_bg_vp.size)
		var slots := lobby.slot_positions()
		for i in mini(_slot_btns.size(), slots.size()):
			var b: Control = _slot_btns[i]
			if not is_instance_valid(b):
				continue
			var sp := lobby.cam.unproject_position(slots[i]) * k - (screen.position if screen else Vector2.ZERO)
			b.position = sp - b.size * 0.5
	if _av_cam and is_instance_valid(_av_cam) and lobby.face_cam:
		_av_cam.global_transform = lobby.face_cam.global_transform


func _clear() -> void:
	if _shade:
		_shade.visible = true
	_slot_btns.clear()
	_av_cam = null
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var inset := maxf(UiKit.safe_left(), UiKit.safe_right())
	screen.offset_left = inset
	screen.offset_right = -inset
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.2)


func _vbox(parent: Control, pos: Vector2, sep := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _title(parent: Control, key: String, pos := Vector2(70, 50)) -> void:
	var l := UiKit.label(tr(key), 64)
	l.position = pos
	parent.add_child(l)
	var bar := ColorRect.new()
	bar.color = UiKit.ACCENT
	bar.position = pos + Vector2(2, 92)
	bar.size = Vector2(90, 6)
	parent.add_child(bar)


func _back_button(parent: Control, cb: Callable) -> void:
	var b := UiKit.big_button("‹  " + tr("BACK"), false, 28)
	b.custom_minimum_size = Vector2(220, 64)
	b.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	b.position = Vector2(60, -100)
	b.pressed.connect(cb)
	parent.add_child(b)


## Row of toggle chips; returns the HBox. `opts` = [[label, value], ...]
func _chips(parent: Control, label_key: String, opts: Array, current, cb: Callable, w := 150.0) -> HBoxContainer:
	var lab := UiKit.label(tr(label_key), 24, Color(1, 1, 1, 0.65))
	parent.add_child(lab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var btns := []
	for o in opts:
		var b := Button.new()
		b.text = str(o[0])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(w, 60)
		b.add_theme_font_override("font", UiKit.font())
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_stylebox_override("normal", UiKit.style(Color(1, 1, 1, 0.08), 10))
		b.add_theme_stylebox_override("hover", UiKit.style(Color(1, 1, 1, 0.14), 10))
		b.add_theme_stylebox_override("pressed", UiKit.style(UiKit.ACCENT, 10))
		b.add_theme_stylebox_override("hover_pressed", UiKit.style(UiKit.ACCENT.lightened(0.1), 10))
		b.add_theme_stylebox_override("focus", UiKit.style(Color(0, 0, 0, 0), 10))
		b.add_theme_color_override("font_pressed_color", UiKit.DARK)
		b.add_theme_color_override("font_hover_pressed_color", UiKit.DARK)
		b.button_pressed = o[1] == current
		var val = o[1]
		b.pressed.connect(func() -> void:
			for bb in btns:
				bb.button_pressed = false
			b.button_pressed = true
			Sfx.ui("click")
			cb.call(val))
		btns.append(b)
		row.add_child(b)
	return row


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

func _show_main() -> void:
	_clear()
	_shade.visible = false
	_slot_btns.clear()
	# drag on empty space rotates the footballer
	var drag := Control.new()
	drag.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag.mouse_filter = Control.MOUSE_FILTER_PASS
	drag.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			lobby.rotate_by((e as InputEventMouseMotion).relative.x)
		elif e is InputEventScreenDrag:
			lobby.rotate_by((e as InputEventScreenDrag).relative.x))
	screen.add_child(drag)
	# soft vignette at the edges so the UI reads over the 3D scene
	for side in [0, 1]:
		var v := TextureRect.new()
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.6))
		g.set_color(1, Color(0, 0, 0, 0.0))
		gt.gradient = g
		gt.fill_from = Vector2(0, 0) if side == 0 else Vector2(1, 0)
		gt.fill_to = Vector2(1, 0) if side == 0 else Vector2(0, 0)
		v.texture = gt
		v.stretch_mode = TextureRect.STRETCH_SCALE
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_LEFT_WIDE if side == 0 else Control.PRESET_RIGHT_WIDE)
		v.custom_minimum_size = Vector2(520, 0)
		if side == 1:
			v.offset_left = -520
		else:
			v.offset_right = 520
		screen.add_child(v)
	_profile_block()
	# top-right: coins + settings
	var tr_box := HBoxContainer.new()
	tr_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_box.offset_left = -330
	tr_box.offset_top = 24
	tr_box.alignment = BoxContainer.ALIGNMENT_END
	tr_box.custom_minimum_size = Vector2(306, 64)
	tr_box.add_theme_constant_override("separation", 12)
	screen.add_child(tr_box)
	tr_box.add_child(LobbyWidgets.coin_pill(int(Game.profile.get("coins", 0))))
	var gear := LobbyWidgets.tile("gear", "", _show_settings, Vector2(64, 64))
	tr_box.add_child(gear)
	# left rail
	var rail := _vbox(screen, Vector2(28, 180), 12)
	rail.add_child(LobbyWidgets.tile("shirt", tr("LOCKER_S"), func() -> void: Game.goto("res://scenes/locker.tscn")))
	rail.add_child(LobbyWidgets.tile("trophy", tr("CAREER"), _show_profile))
	rail.add_child(LobbyWidgets.tile("cone", tr("TRAINING"), _start_training))
	rail.add_child(LobbyWidgets.tile("people", tr("FRIENDS"), _show_friends))
	# right: daily missions
	var mp := _missions_panel()
	mp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mp.offset_left = -444
	mp.offset_top = 104
	mp.offset_right = -28
	screen.add_child(mp)
	# bottom-right: mode selector + PLAY
	var mode := int(Game.settings.get("mode", 11))
	var mcard := Button.new()
	mcard.focus_mode = Control.FOCUS_NONE
	mcard.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	mcard.offset_left = -444
	mcard.offset_top = -262
	mcard.offset_right = -28
	mcard.offset_bottom = -178
	mcard.custom_minimum_size = Vector2(416, 84)
	mcard.add_theme_stylebox_override("normal", LobbyWidgets.panel(14))
	mcard.add_theme_stylebox_override("hover", LobbyWidgets.panel(14, Color(0.08, 0.1, 0.14, 0.85), Color(1, 1, 1, 0.3)))
	mcard.add_theme_stylebox_override("pressed", LobbyWidgets.panel(14))
	mcard.pressed.connect(_show_quick)
	mcard.draw.connect(func() -> void:
		var f := UiKit.font()
		mcard.draw_string(f, Vector2(18, 26), tr("MODE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.55))
		mcard.draw_string(f, Vector2(18, 64), "%s · %s" % [tr("F%d" % mode), tr("MODE_%d" % mode)], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
		var c := Vector2(mcard.size.x - 30, mcard.size.y * 0.5)
		mcard.draw_polyline(PackedVector2Array([c + Vector2(-6, -11), c + Vector2(5, 0), c + Vector2(-6, 11)]), UiKit.GOLD, 3.0))
	screen.add_child(mcard)
	var play := LobbyWidgets.PlayButton.new()
	play.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	play.offset_left = -444
	play.offset_top = -164
	play.offset_right = -28
	play.offset_bottom = -36
	play.pressed.connect(_on_play)
	screen.add_child(play)
	_play_btn = play
	_update_play_btn()
	# room: team-mate pedestals ("+" = invite / search) and the room panel
	var party: Party = Net.party
	var mates := party.members().slice(1)
	lobby.set_squad(party.team_size(), mates)
	_slot_tags.clear()
	var slots := lobby.slot_positions()
	for i in slots.size():
		var mate: Dictionary = mates[i] if i < mates.size() else {}
		if mate.is_empty():
			var sb := Button.new()
			sb.custom_minimum_size = Vector2(74, 74)
			sb.size = Vector2(74, 74)
			sb.focus_mode = Control.FOCUS_NONE
			var st := LobbyWidgets.panel(37, Color(0.05, 0.15, 0.25, 0.55), Color(0.45, 0.8, 1.0, 0.7))
			sb.add_theme_stylebox_override("normal", st)
			sb.add_theme_stylebox_override("hover", LobbyWidgets.panel(37, Color(0.08, 0.25, 0.4, 0.7), Color(0.6, 0.9, 1.0)))
			sb.add_theme_stylebox_override("pressed", st)
			sb.pressed.connect(_show_invite)
			sb.draw.connect(func() -> void:
				Icons.draw(sb, "plus", Rect2(Vector2(20, 20), Vector2(34, 34)), Color(0.7, 0.92, 1.0))
				var f := UiKit.font()
				var t := tr("INVITE")
				var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				sb.draw_string(f, Vector2(37 - tw * 0.5, 96), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.9, 1.0, 0.9)))
			screen.add_child(sb)
			_slot_btns.append(sb)
		else:
			var tag := PanelContainer.new()
			tag.add_theme_stylebox_override("panel", LobbyWidgets.panel(10, Color(0, 0, 0, 0.6)))
			var tl := UiKit.label("%s  · LV %d" % [str(mate.get("name", "?")), int(mate.get("level", 1))], 18)
			tag.add_child(tl)
			tag.size = Vector2(180, 34)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			screen.add_child(tag)
			screen.move_child(tag, 1)     # under the UI panels, above the 3D
			_slot_btns.append(tag)
	# emote button: the footballer (and the room's mates) see it
	var eb := Button.new()
	eb.focus_mode = Control.FOCUS_NONE
	eb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	eb.offset_left = -548
	eb.offset_top = -150
	eb.offset_right = -460
	eb.offset_bottom = -62
	var est := LobbyWidgets.panel(44, Color(0.03, 0.04, 0.06, 0.8), UiKit.GOLD)
	eb.add_theme_stylebox_override("normal", est)
	eb.add_theme_stylebox_override("hover", LobbyWidgets.panel(44, Color(0.1, 0.08, 0.02, 0.9), UiKit.GOLD))
	eb.add_theme_stylebox_override("pressed", est)
	eb.draw.connect(func() -> void:
		var c := eb.size * 0.5 + Vector2(0, -8)
		eb.draw_arc(c, 18.0, 0, TAU, 32, UiKit.GOLD, 3.0, true)
		eb.draw_circle(c + Vector2(-6, -5), 2.8, UiKit.GOLD)
		eb.draw_circle(c + Vector2(6, -5), 2.8, UiKit.GOLD)
		eb.draw_arc(c + Vector2(0, 1), 9.5, 0.35, PI - 0.35, 12, UiKit.GOLD, 2.8, true)
		var f := UiKit.font()
		var t := tr("EMOTES")
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		eb.draw_string(f, Vector2(eb.size.x * 0.5 - tw * 0.5, eb.size.y - 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85)))
	eb.pressed.connect(_open_lobby_wheel)
	screen.add_child(eb)
	var rp := _room_panel()
	rp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rp.offset_left = 180
	rp.offset_top = -214
	rp.offset_bottom = -84
	screen.add_child(rp)
	# matchmaking banner
	_mm_banner = PanelContainer.new()
	_mm_banner.add_theme_stylebox_override("panel", LobbyWidgets.panel(14, Color(0.03, 0.04, 0.06, 0.88), UiKit.GOLD))
	_mm_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mm_banner.offset_left = -260
	_mm_banner.offset_right = 260
	_mm_banner.offset_top = 22
	_mm_label = UiKit.label("", 26, Color.WHITE)
	_mm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mm_banner.add_child(_mm_label)
	screen.add_child(_mm_banner)
	_on_queue_changed()
	var tip := UiKit.label(tr("TIP_%d" % (randi() % 5 + 1)), 18, Color(1, 1, 1, 0.5), false)
	tip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip.position = Vector2(28, -48)
	tip.size = Vector2(760, 30)
	screen.add_child(tip)


# ---------------------------------------------------------------------------
# Room + matchmaking (Brawl Stars style)
# ---------------------------------------------------------------------------

## Capture helpers (tools/shot.gd): fake room / versus screen.
func demo_room() -> void:
	var p: Party = Net.party
	p.my_id = 1
	var l1 := Look.random_look(RandomNumberGenerator.new())
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	var l2 := Look.random_look(r2)
	p.room = {"code": "K7Q2P", "mode": 5, "leader": 1, "open": true, "queue": false, "size": 5,
		"members": [{"id": 1, "name": "Me", "level": 7}, {"id": 2, "name": "Aziz", "level": 12, "look": l1},
			{"id": 3, "name": "Timur", "level": 4, "look": l2}]}
	p.online = true
	Game.settings["mode"] = 5
	_show_main()


func demo_room11() -> void:
	var p: Party = Net.party
	p.my_id = 1
	var ms := [{"id": 1, "name": "Me", "level": 7}]
	for i in 4:
		var r := RandomNumberGenerator.new()
		r.seed = 100 + i
		ms.append({"id": 2 + i, "name": ["Aziz", "Timur", "Sardor", "Jasur"][i], "level": 3 + i * 4, "look": Look.random_look(r)})
	p.room = {"code": "K7Q2P", "mode": 11, "leader": 1, "open": true, "queue": false, "size": 11, "members": ms}
	p.online = true
	Game.settings["mode"] = 11
	_show_main()


func demo_versus() -> void:
	var roster := [[{"name": "Karimov", "level": 7, "bot": false}, {"name": "Aziz", "level": 12, "bot": false}], [{"name": "Rustam", "level": 9, "bot": false}]]
	for t in 2:
		while roster[t].size() < 5:
			roster[t].append({"name": "BOT", "level": 0, "bot": true})
	_show_versus({"offline": false, "mode": 5, "teams": roster, "team": 0, "host": "", "port": 0, "token": ""})


func _web_ready() -> void:
	# hide the HTML loader once the lobby has rendered a few frames (shaders compiled)
	for i in 6:
		await get_tree().process_frame
	JavaScriptBridge.eval("window.maydonReady && window.maydonReady()", true)


func _open_lobby_wheel() -> void:
	if _lobby_wheel == null or not is_instance_valid(_lobby_wheel):
		_lobby_wheel = EmoteWheel.new()
		add_child(_lobby_wheel)
		_lobby_wheel.chosen.connect(func(i: int) -> void:
			lobby.play_emote(str(Emotes.LIST[i]["clip"]))
			Net.party.send_emote(i))
	move_child(_lobby_wheel, get_child_count() - 1)
	_lobby_wheel.open()


func _on_mate_emote(member_id: int, idx: int) -> void:
	var mates := Net.party.members().slice(1)
	for k in mates.size():
		if int(mates[k].get("id", -1)) == member_id and idx >= 0 and idx < Emotes.LIST.size():
			lobby.play_mate_emote(k, str(Emotes.LIST[idx]["clip"]))


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_T and _play_btn and is_instance_valid(_play_btn):
		_open_lobby_wheel()
	elif k and k.pressed and not k.echo and _lobby_wheel and _lobby_wheel.visible and k.keycode >= KEY_1 and k.keycode <= KEY_8:
		_lobby_wheel.pick(k.keycode - KEY_1)


func _hook_party() -> void:
	if _party_hooked:
		return
	_party_hooked = true
	Net.party.changed.connect(_on_party_changed)
	Net.party.queue_changed.connect(_on_queue_changed)
	Net.party.match_found.connect(_on_match_found)
	Net.party.notice.connect(_notice)
	Net.party.mate_emote.connect(_on_mate_emote)


func _on_party_changed() -> void:
	# rebuild the lobby when the room changes (someone joined/left, mode, leader)
	if _play_btn and is_instance_valid(_play_btn) and _versus == null:
		_show_main()


func _update_play_btn() -> void:
	if _play_btn == null or not is_instance_valid(_play_btn):
		return
	var b := _play_btn as LobbyWidgets.PlayButton
	var party: Party = Net.party
	var mode := party.mode()
	if party.searching:
		b.text = tr("CANCEL")
		b.sub = tr("MM_SEARCH")
	elif not party.is_leader():
		b.text = tr("READY")
		b.sub = tr("WAIT_LEADER")
	else:
		b.text = tr("PLAY")
		b.sub = "%s · %s" % [tr("F%d" % mode), tr("MODE_%d" % mode)]


func _on_play() -> void:
	var party: Party = Net.party
	if party.searching:
		party.cancel()
	elif party.is_leader():
		Game.save_game()
		party.play()
	_update_play_btn()


func _on_queue_changed() -> void:
	_update_play_btn()
	if _mm_banner == null or not is_instance_valid(_mm_banner):
		return
	var party: Party = Net.party
	_mm_banner.visible = party.searching
	if party.searching:
		var q: Dictionary = party.queue
		var w := int(float(q.get("wait", 0.0)))
		_mm_label.text = "%s   %d:%02d   ·   %s %d/%d" % [tr("MM_SEARCH"), w / 60, w % 60, tr("MM_FOUND"),
			int(q.get("found", 1)), int(q.get("need", party.team_size() * 2))]


func _on_match_found(info: Dictionary) -> void:
	_show_versus(info)


## "Match found" versus screen, then start (offline: vs bots locally; online:
## connect to the dedicated match server).
func _show_versus(info: Dictionary) -> void:
	if _versus and is_instance_valid(_versus):
		_versus.queue_free()
	_versus = Control.new()
	_versus.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_versus)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.02, 0.03, 0.92)
	_versus.add_child(bg)
	var title := UiKit.label(tr("MM_MATCH"), 64, UiKit.GOLD)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -400
	title.offset_right = 400
	title.offset_top = 40
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_versus.add_child(title)
	var teams: Array = info.get("teams", [[], []])
	var my_team := int(info.get("team", 0))
	var bots := 0
	for t in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.set_anchors_preset(Control.PRESET_CENTER_TOP)
		col.offset_left = -560 if t == 0 else 60
		col.offset_right = -60 if t == 0 else 560
		col.offset_top = 160
		_versus.add_child(col)
		var kit: Dictionary = Game.team_kit(t)
		var head := UiKit.label(tr("TEAM_BLUE") if t == 0 else tr("TEAM_ORANGE"), 34, kit.get("shirt", Color.WHITE))
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if t == 0 else HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(head)
		var rows: Array = teams[t] if t < teams.size() else []
		for r in rows.slice(0, 11):
			var is_bot := bool(r.get("bot", false))
			if is_bot:
				bots += 1
			var txt := tr("BOT") if is_bot else "%s   LV %d" % [str(r.get("name", "?")), int(r.get("level", 1))]
			var row := UiKit.label(txt, 22 if rows.size() > 5 else 28, Color(1, 1, 1, 0.4) if is_bot else (UiKit.GOLD if t == my_team else Color.WHITE))
			row.horizontal_alignment = head.horizontal_alignment
			col.add_child(row)
	var mode_l := UiKit.label("%s · %s" % [tr("F%d" % int(info.get("mode", 5))), tr("MODE_%d" % int(info.get("mode", 5)))], 24, Color(1, 1, 1, 0.7))
	mode_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mode_l.offset_left = -400
	mode_l.offset_right = 400
	mode_l.offset_top = 112
	mode_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_versus.add_child(mode_l)
	var vs := UiKit.label("VS", 64, Color.WHITE)
	vs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vs.offset_left = -60
	vs.offset_right = 60
	vs.offset_top = 150
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_versus.add_child(vs)
	if bots > 0:
		var note := UiKit.label(tr("MM_BOTS"), 22, Color(1, 1, 1, 0.6), false)
		note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		note.offset_left = -500
		note.offset_right = 500
		note.offset_top = -90
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_versus.add_child(note)
	Sfx.ui("ok")
	await get_tree().create_timer(2.6).timeout
	if not is_inside_tree():
		return
	if bool(info.get("offline", false)):
		var mode := int(info.get("mode", 5))
		_quick["format"] = mode
		_quick["role"] = int(Game.profile.get("role", 3))
		_quick["diff"] = int(Game.settings.get("difficulty", 1))
		_quick["len"] = int(Game.settings.get("match_len", 240))
		_launch_quick()
	else:
		title.text = tr("CONNECTING")
		if not Net.join_online(str(info.get("host", "")), int(info.get("port", 0)), str(info.get("token", ""))):
			_notice("ERR_connect")
			_versus.queue_free()
			_versus = null
			return
		# the dedicated server starts the match (h_start → match scene); give up after a while
		await get_tree().create_timer(20.0).timeout
		if is_inside_tree() and _versus and is_instance_valid(_versus):
			Net.stop()
			_notice("ERR_connect")
			_versus.queue_free()
			_versus = null


func _notice(key: String) -> void:
	var l := UiKit.label(tr(key), 26, Color.WHITE)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LobbyWidgets.panel(12, Color(0.35, 0.08, 0.08, 0.92), Color(1, 0.5, 0.5, 0.6)))
	p.add_child(l)
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.offset_left = -360
	p.offset_right = 360
	p.offset_top = 96
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(p)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


## Room panel: slots of the current mode's team, code, search-teammates switch.
func _room_panel() -> Control:
	var party: Party = Net.party
	var n := party.team_size()
	var ms := party.members()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LobbyWidgets.panel(14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(Icons.make("people", 24, Color.WHITE))
	head.add_child(UiKit.label("%s  %d/%d" % [tr("ROOM"), ms.size(), n], 22))
	if party.online:
		if party.in_room():
			head.add_child(UiKit.label("·  %s %s" % [tr("CODE"), str(party.room.get("code", ""))], 22, UiKit.GOLD))
	else:
		head.add_child(UiKit.label("·  " + tr("OFFLINE_BOTS"), 18, Color(1, 1, 1, 0.5), false))
	# slot dots
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 4)
	v.add_child(dots)
	for i in n:
		var d := Control.new()
		var dsz := 26.0 if n > 5 else 34.0
		d.custom_minimum_size = Vector2(dsz, dsz)
		var filled := i < ms.size()
		var me := i == 0
		var initial := str(ms[i].get("name", "?")).substr(0, 1).to_upper() if filled else ""
		d.draw.connect(func() -> void:
			var c := d.size * 0.5
			d.draw_circle(c, dsz * 0.5, (UiKit.GOLD if me else UiKit.ACCENT) if filled else Color(1, 1, 1, 0.1))
			if filled:
				var f := UiKit.font()
				var fs := int(dsz * 0.55)
				var tw := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				d.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.DARK)
			else:
				d.draw_arc(c, dsz * 0.5 - 1, 0, TAU, 24, Color(1, 1, 1, 0.3), 1.5, true))
		dots.add_child(d)
	# actions
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var mk := func(txt: String, on: bool, cb: Callable) -> Button:
		var b := Button.new()
		b.text = txt
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_override("font", UiKit.font())
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_stylebox_override("normal", UiKit.style(UiKit.ACCENT if on else Color(1, 1, 1, 0.1), 8))
		b.add_theme_stylebox_override("hover", UiKit.style((UiKit.ACCENT if on else Color(1, 1, 1, 0.1)).lightened(0.1), 8))
		b.add_theme_stylebox_override("pressed", UiKit.style(UiKit.ACCENT.darkened(0.2), 8))
		b.add_theme_color_override("font_color", UiKit.DARK if on else Color.WHITE)
		b.pressed.connect(func() -> void:
			Sfx.ui("click")
			cb.call())
		row.add_child(b)
		return b
	var on := party.search_mates_on()
	mk.call(tr("SEARCH_MATES") + ": " + (tr("ON") if on else tr("OFF")), on, func() -> void: party.set_search_mates(not on))
	mk.call(tr("JOIN_CODE"), false, _show_invite)
	if party.in_room() and ms.size() > 1:
		mk.call(tr("LEAVE"), false, func() -> void: party.leave())
	return p


## Invite / join: show my room code (online), join a friend's code, or play
## over Wi-Fi with friends nearby.
func _show_invite() -> void:
	var party: Party = Net.party
	var dlg := AcceptDialog.new()
	dlg.title = tr("INVITE")
	dlg.ok_button_text = tr("BACK")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	dlg.add_child(v)
	if party.online:
		if not party.in_room():
			party.create_room(party.search_mates_on())
		v.add_child(UiKit.label(tr("YOUR_CODE"), 22, Color(1, 1, 1, 0.7), false))
		var code := UiKit.label(str(party.room.get("code", "…")), 54, UiKit.GOLD)
		v.add_child(code)
		party.changed.connect(func() -> void:
			if is_instance_valid(code):
				code.text = str(party.room.get("code", "…")), CONNECT_ONE_SHOT)
		v.add_child(UiKit.label(tr("FRIEND_CODE"), 22, Color(1, 1, 1, 0.7), false))
		var h := HBoxContainer.new()
		v.add_child(h)
		var le := LineEdit.new()
		le.max_length = 6
		le.custom_minimum_size = Vector2(220, 52)
		le.placeholder_text = "ABC12"
		le.add_theme_font_size_override("font_size", 28)
		h.add_child(le)
		var jb := UiKit.big_button(tr("JOIN"), true, 24)
		jb.custom_minimum_size = Vector2(160, 52)
		jb.pressed.connect(func() -> void:
			if le.text.strip_edges().length() >= 4:
				party.join_code(le.text.strip_edges())
				dlg.hide())
		h.add_child(jb)
	else:
		var l := UiKit.label(tr("NO_SERVER"), 22, Color(1, 1, 1, 0.8), false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)
	var wifi := UiKit.big_button(tr("WIFI_FRIENDS"), false, 24)
	wifi.visible = not OS.has_feature("web")
	wifi.custom_minimum_size = Vector2(420, 56)
	wifi.pressed.connect(func() -> void:
		dlg.hide()
		_show_friends())
	v.add_child(wifi)
	add_child(dlg)
	dlg.popup_centered(Vector2i(640, 0))


func _profile_block() -> void:
	var prof := PanelContainer.new()
	prof.add_theme_stylebox_override("panel", LobbyWidgets.panel(16))
	prof.position = Vector2(28, 22)
	screen.add_child(prof)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	prof.add_child(h)
	# live portrait of the player's footballer
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0.6)
	fs.border_color = UiKit.GOLD
	fs.set_border_width_all(2)
	fs.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fs)
	h.add_child(frame)
	var av := SubViewportContainer.new()
	av.custom_minimum_size = Vector2(92, 92)
	av.stretch = true
	frame.add_child(av)
	var avp := SubViewport.new()
	avp.size = Vector2i(184, 184)
	avp.world_3d = lobby.get_world_3d()
	avp.audio_listener_enable_3d = false
	av.add_child(avp)
	_av_cam = Camera3D.new()
	_av_cam.fov = 22.0
	_av_cam.current = true
	avp.add_child(_av_cam)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	v.add_child(UiKit.label(Game.player_name().to_upper(), 32))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var lvl := int(Game.profile.get("level", 1))
	var badge := UiKit.label(" LV %d " % lvl, 20, UiKit.DARK)
	var bs := StyleBoxFlat.new()
	bs.bg_color = UiKit.GOLD
	bs.set_corner_radius_all(6)
	bs.content_margin_left = 6
	bs.content_margin_right = 6
	badge.add_theme_stylebox_override("normal", bs)
	row.add_child(badge)
	row.add_child(UiKit.label("%s %d" % [tr("OVR"), League.overall()], 20, Color(1, 1, 1, 0.75)))
	var need := League.xp_for_level(lvl)
	var xp := int(Game.profile.get("xp", 0))
	v.add_child(LobbyWidgets.bar(float(xp) / need, 230, 8, UiKit.GOLD))
	v.add_child(UiKit.label("%d / %d %s" % [xp, need, tr("XP")], 15, Color(1, 1, 1, 0.55), false))


func _missions_panel() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LobbyWidgets.panel(16))
	p.custom_minimum_size = Vector2(416, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(Icons.make("list", 26, UiKit.GOLD))
	head.add_child(UiKit.label(tr("DAILY"), 22, UiKit.GOLD))
	var ms := Missions.list()
	for i in ms.size():
		var m: Dictionary = ms[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 3)
		row.add_child(col)
		var done := int(m["prog"]) >= int(m["target"])
		var lab := UiKit.label(Missions.label(m), 18, Color(1, 1, 1, 0.45) if m["claimed"] else Color.WHITE, false)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(250, 0)
		col.add_child(lab)
		col.add_child(LobbyWidgets.bar(float(m["prog"]) / float(m["target"]), 250, 6, UiKit.ACCENT if done else Color(0.45, 0.8, 1.0)))
		if m["claimed"]:
			row.add_child(Icons.make("check", 30, UiKit.ACCENT))
		elif done:
			var cb := Button.new()
			cb.text = "+%d" % int(m["coins"])
			cb.custom_minimum_size = Vector2(108, 44)
			cb.add_theme_font_override("font", UiKit.font())
			cb.add_theme_font_size_override("font_size", 22)
			cb.add_theme_color_override("font_color", UiKit.DARK)
			cb.add_theme_stylebox_override("normal", UiKit.style(UiKit.GOLD, 10))
			cb.add_theme_stylebox_override("hover", UiKit.style(UiKit.GOLD.lightened(0.15), 10))
			cb.add_theme_stylebox_override("pressed", UiKit.style(UiKit.GOLD.darkened(0.15), 10))
			var idx := i
			cb.pressed.connect(func() -> void:
				if Missions.claim(idx) > 0:
					Sfx.ui("ok")
					_show_main())
			row.add_child(cb)
		else:
			var pl := UiKit.label("%d/%d" % [int(m["prog"]), int(m["target"])], 20, Color(1, 1, 1, 0.7))
			pl.custom_minimum_size = Vector2(108, 0)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(pl)
	return p


func _mini_card() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.style(Color(0, 0, 0, 0.55), 12, UiKit.ACCENT, 2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var ovr := UiKit.label(str(League.overall()), 56, UiKit.GOLD)
	h.add_child(ovr)
	var v := VBoxContainer.new()
	h.add_child(v)
	v.add_child(UiKit.label("%d  %s" % [int(Game.profile.get("number", 10)), Game.player_name().to_upper()], 30))
	var role := int(Game.profile.get("role", 3))
	v.add_child(UiKit.label("%s  ·  %s %d" % [tr(["GK", "DEF", "MID", "FWD"][role]), tr("LEVEL"), int(Game.profile.get("level", 1))], 20, Color(1, 1, 1, 0.7), false))
	return p


# ---------------------------------------------------------------------------
# Quick match
# ---------------------------------------------------------------------------

func _show_quick() -> void:
	_clear()
	_title(screen, "MODE", Vector2(70, 36))
	if _quick["role"] < 0:
		_quick["role"] = int(Game.profile.get("role", 3))
	if _quick["diff"] < 0:
		_quick["diff"] = int(Game.settings.get("difficulty", 1))
	if _quick["len"] < 0:
		_quick["len"] = int(Game.settings.get("match_len", 240))
	_quick["format"] = int(Game.settings.get("mode", 11))
	# mode cards
	var cards := HBoxContainer.new()
	cards.position = Vector2(70, 150)
	cards.add_theme_constant_override("separation", 22)
	screen.add_child(cards)
	for f in [11, 5, 3]:
		var sel: bool = _quick["format"] == f
		var card := Button.new()
		card.custom_minimum_size = Vector2(400, 330)
		card.focus_mode = Control.FOCUS_NONE
		card.clip_contents = true
		var st := LobbyWidgets.panel(16, Color(0.03, 0.04, 0.06, 0.9), UiKit.GOLD if sel else Color(1, 1, 1, 0.15))
		st.set_border_width_all(3 if sel else 1)
		card.add_theme_stylebox_override("normal", st)
		card.add_theme_stylebox_override("hover", st)
		card.add_theme_stylebox_override("pressed", st)
		var img: Texture2D = load("res://assets/gen/modes/f%d.jpg" % f) if ResourceLoader.exists("res://assets/gen/modes/f%d.jpg" % f) else null
		var ff: int = f
		card.draw.connect(func() -> void:
			if img:
				card.draw_texture_rect(img, Rect2(Vector2(3, 3), Vector2(card.size.x - 6, 220)), false, Color(1, 1, 1) if sel else Color(0.7, 0.7, 0.7))
			var g := UiKit.font()
			card.draw_string(g, Vector2(20, 268), tr("F%d" % ff), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.GOLD if sel else Color.WHITE)
			card.draw_string(g, Vector2(20, 306), tr("MODE_%d" % ff), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.85))
			if ff == 11:
				var tag := tr("RECOMMENDED")
				var tw := g.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				var sb := StyleBoxFlat.new()
				sb.bg_color = UiKit.GOLD
				sb.set_corner_radius_all(6)
				card.draw_style_box(sb, Rect2(Vector2(14, 14), Vector2(tw + 20, 28)))
				card.draw_string(g, Vector2(24, 34), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.DARK))
		card.pressed.connect(func() -> void:
			Sfx.ui("click")
			if not Net.party.is_leader():
				_notice("ERR_not_leader")
				return
			if Net.party.members().size() > Party.TEAM[ff]:
				_notice("ERR_too_many")
				return
			Net.party.set_mode(ff)
			_quick["format"] = ff
			_show_quick())
		cards.add_child(card)
	var desc := UiKit.label(tr({3: "F3_DESC", 5: "F5_DESC", 11: "F11_DESC"}[_quick["format"]]), 20, Color(1, 1, 1, 0.6), false)
	desc.position = Vector2(72, 494)
	desc.size = Vector2(1240, 30)
	screen.add_child(desc)
	# match options
	var col := _vbox(screen, Vector2(70, 530), 6)
	var roles := [[tr("GK"), 0], [tr("DEF"), 1], [tr("MID"), 2], [tr("FWD"), 3]]
	if _quick["format"] == 3:
		roles = [[tr("GK"), 0], [tr("DEF"), 1], [tr("FWD"), 3]]
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 40)
	col.add_child(row1)
	var c1 := VBoxContainer.new()
	row1.add_child(c1)
	_chips(c1, "POSITION", roles, _quick["role"], func(v) -> void: _quick["role"] = v, 120)
	var c2 := VBoxContainer.new()
	row1.add_child(c2)
	_chips(c2, "DIFFICULTY", [[tr("EASY"), 0], [tr("NORMAL"), 1], [tr("HARD"), 2], [tr("LEGEND"), 3]], _quick["diff"], func(v) -> void: _quick["diff"] = v; Game.settings["difficulty"] = v, 130)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	col.add_child(row)
	var c3 := VBoxContainer.new()
	row.add_child(c3)
	_chips(c3, "TIME_OF_DAY", [[tr("DAY"), false], [tr("NIGHT"), true]], _quick["night"], func(v) -> void: _quick["night"] = v, 120)
	var c4 := VBoxContainer.new()
	row.add_child(c4)
	var m := tr("MIN")
	_chips(c4, "MATCH_LENGTH", [["2 " + m, 120], ["4 " + m, 240], ["6 " + m, 360], ["10 " + m, 600]], _quick["len"], func(v) -> void: _quick["len"] = v; Game.settings["match_len"] = v, 100)
	if _quick["format"] == 11:
		var c5 := VBoxContainer.new()
		row.add_child(c5)
		_chips(c5, "CONTROL", [[tr("CTRL_TEAM"), "team"], [tr("CTRL_ONE"), "one"]], str(Game.settings.get("control", "team")), func(v) -> void: Game.settings["control"] = v, 150)
	var go := LobbyWidgets.PlayButton.new()
	go.text = tr("PLAY")
	go.sub = "%s · %s" % [tr("F%d" % _quick["format"]), tr("MODE_%d" % _quick["format"])]
	go.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	go.offset_left = -444
	go.offset_top = -164
	go.offset_right = -28
	go.offset_bottom = -36
	go.pressed.connect(_launch_quick)
	screen.add_child(go)
	_back_button(screen, _show_main)


func _launch_quick() -> void:
	Game.save_game()
	var cfg := Game.quick_match(_quick["format"], _quick["role"], _quick["diff"], _quick["night"])
	if _quick["format"] < 9:
		cfg.duration = float(_quick["len"])
	else:
		cfg.duration = float(_quick["len"]) * 1.5
	Game.next_match = cfg
	Game.next_match_meta = {"mode": "quick"}
	Sfx.stop_music()
	Game.goto("res://scenes/match.tscn")


# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------

func _show_profile() -> void:
	_clear()
	_title(screen, "PROFILE")
	var card := _player_card()
	card.position = Vector2(70, 200)
	screen.add_child(card)
	var col := _vbox(screen, Vector2(560, 200), 10)
	col.add_child(UiKit.label(tr("YOUR_NAME"), 22, Color(1, 1, 1, 0.6)))
	var name_e := _line_edit(Game.profile.get("name", ""), 14)
	name_e.text_changed.connect(func(t: String) -> void: Game.profile["name"] = t.strip_edges())
	col.add_child(name_e)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	col.add_child(row)
	var nc := VBoxContainer.new()
	row.add_child(nc)
	nc.add_child(UiKit.label(tr("YOUR_NUMBER"), 22, Color(1, 1, 1, 0.6)))
	var num := SpinBox.new()
	num.min_value = 1
	num.max_value = 99
	num.value = int(Game.profile.get("number", 10))
	num.custom_minimum_size = Vector2(160, 60)
	num.value_changed.connect(func(v: float) -> void: Game.profile["number"] = int(v))
	nc.add_child(num)
	_chips(col, "YOUR_POSITION", [[tr("GK"), 0], [tr("DEF"), 1], [tr("MID"), 2], [tr("FWD"), 3]], int(Game.profile.get("role", 3)), func(v) -> void: Game.profile["role"] = v, 190)
	var nf := _face_count()
	if nf > 1:
		var fc := VBoxContainer.new()
		row.add_child(fc)
		fc.add_child(UiKit.label(tr("FACE"), 22, Color(1, 1, 1, 0.6)))
		var fs := SpinBox.new()
		fs.min_value = 1
		fs.max_value = nf
		fs.value = int(Game.profile.get("face", 0)) % nf + 1
		fs.custom_minimum_size = Vector2(160, 60)
		fs.value_changed.connect(func(v: float) -> void: Game.profile["face"] = int(v) - 1)
		fc.add_child(fs)
	var sv := UiKit.big_button(tr("SAVE"), true)
	sv.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	sv.position = Vector2(-440, -120)
	sv.pressed.connect(func() -> void:
		Game.save_game()
		_show_main())
	screen.add_child(sv)
	_back_button(screen, func() -> void:
		Game.save_game()
		_show_main())


func _face_count() -> int:
	var d := DirAccess.open("res://assets/chars/variants")
	if d == null:
		return 0
	var names := {}
	for f in d.get_files():
		var nm: String = f.trim_suffix(".import").trim_suffix(".remap")
		if nm.ends_with(".glb"):
			names[nm] = true
	return names.size()


func _line_edit(txt: String, maxlen: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = txt
	e.max_length = maxlen
	e.custom_minimum_size = Vector2(520, 62)
	e.add_theme_font_override("font", UiKit.font())
	e.add_theme_font_size_override("font_size", 28)
	e.add_theme_stylebox_override("normal", UiKit.style(Color(1, 1, 1, 0.08), 10))
	e.add_theme_stylebox_override("focus", UiKit.style(Color(1, 1, 1, 0.12), 10, UiKit.ACCENT, 2))
	return e


func _kit_picker(current: int, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var btns := []
	for i in Game.KIT_PRESETS.size():
		var k: Dictionary = Game.KIT_PRESETS[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.toggle_mode = true
		b.button_pressed = i == current
		var sb := UiKit.style(k["shirt"], 10, Color(1, 1, 1, 0.2), 2)
		var sbp := UiKit.style(k["shirt"], 10, UiKit.GOLD, 5)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sbp)
		b.add_theme_stylebox_override("hover_pressed", sbp)
		b.add_theme_stylebox_override("focus", sbp if i == current else sb)
		var idx := i
		b.pressed.connect(func() -> void:
			for bb in btns:
				bb.button_pressed = false
			b.button_pressed = true
			Sfx.ui("click")
			cb.call(idx))
		btns.append(b)
		h.add_child(b)
	return h


func _player_card() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(420, 560)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.12, 0.92)
	sb.set_corner_radius_all(18)
	sb.border_color = UiKit.GOLD
	sb.set_border_width_all(3)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 26
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var ovr := UiKit.label(str(League.overall()), 96, UiKit.GOLD)
	top.add_child(ovr)
	var rv := VBoxContainer.new()
	top.add_child(rv)
	var role := int(Game.profile.get("role", 3))
	rv.add_child(UiKit.label(tr(["GK_S", "DEF_S", "MID_S", "FWD_S"][role]), 40))
	rv.add_child(UiKit.label("#%d" % int(Game.profile.get("number", 10)), 30, Color(1, 1, 1, 0.7)))
	v.add_child(UiKit.label(Game.player_name().to_upper(), 52))
	v.add_child(UiKit.label(tr(["GK", "DEF", "MID", "FWD"][role]), 26, Color(1, 1, 1, 0.7), false))
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(UiKit.GOLD, 0.5)
	v.add_child(sep)
	var c: Dictionary = Game.profile["career"]
	var m := int(c.get("matches", 0))
	var avg := float(c.get("rating_sum", 0.0)) / maxf(m, 1)
	var rows := [["S_MATCHES", str(m)], ["S_WINS", str(c.get("wins", 0))], ["S_GOALS", str(c.get("goals", 0))],
		["S_ASSISTS", str(c.get("assists", 0))], ["MOTM", str(c.get("motm", 0))], ["S_AVG", "%.1f" % avg if m > 0 else "-"],
		["LEVEL", str(Game.profile.get("level", 1))]]
	for r in rows:
		var h := HBoxContainer.new()
		var a := UiKit.label(tr(r[0]), 24, Color(1, 1, 1, 0.75), false)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UiKit.label(r[1], 28))
		v.add_child(h)
	return p


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func _show_settings() -> void:
	_clear()
	_title(screen, "SETTINGS")
	var sc := ScrollContainer.new()
	sc.position = Vector2(70, 190)
	sc.size = Vector2(1200, 600)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	sc.add_child(col)
	var s := Game.settings
	col.add_child(UiKit.label(tr("SERVER"), 24, Color(1, 1, 1, 0.65)))
	var srv := LineEdit.new()
	srv.text = str(s.get("server", Party.DEFAULT_SERVER))
	srv.placeholder_text = "ws://192.168.1.10:47900"
	srv.custom_minimum_size = Vector2(620, 52)
	srv.add_theme_font_size_override("font_size", 22)
	srv.text_changed.connect(func(t: String) -> void: s["server"] = t.strip_edges())
	col.add_child(srv)
	_chips(col, "LANGUAGE", [["O'zbekcha", "uz"], ["Русский", "ru"], ["English", "en"]], s["lang"], func(v) -> void:
		Game.set_lang(v)
		_show_settings(), 200)
	var q_opts := [[tr("LOW"), 0], [tr("MEDIUM"), 1], [tr("HIGH"), 2]]
	if VenueBuilder.forward_plus():
		q_opts.append([tr("ULTRA"), 3])
	_chips(col, "GRAPHICS", q_opts, int(s["quality"]), func(v) -> void: s["quality"] = v, 170)
	_chips(col, "CAMERA", [[tr("CAM_PRO"), 0], [tr("CAM_TV"), 1]], int(s["camera"]), func(v) -> void: s["camera"] = v, 200)
	_slider(col, "SOUND", float(s["sfx"]), func(v: float) -> void: s["sfx"] = v)
	_slider(col, "MUSIC", float(s["music"]), func(v: float) -> void:
		s["music"] = v
		Sfx.set_music_volume(v))
	if not Game.is_phone():
		_slider(col, "MOUSE_SENS", float(s.get("mouse_sens", 0.5)), func(v: float) -> void: s["mouse_sens"] = clampf(v, 0.05, 1.0))
		_chips(col, "INVERT_Y", [[tr("OFF"), false], [tr("ON"), true]], bool(s.get("invert_y", false)), func(v) -> void: s["invert_y"] = v, 140)
		var help := UiKit.label(tr("PC_CONTROLS"), 20, Color(1, 1, 1, 0.65), false)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.custom_minimum_size = Vector2(1100, 0)
		col.add_child(UiKit.label(tr("CONTROLS"), 24, Color(1, 1, 1, 0.65)))
		col.add_child(help)
	_slider(col, "BUTTON_SIZE", (float(s["btn_scale"]) - 0.7) / 0.6, func(v: float) -> void: s["btn_scale"] = 0.7 + v * 0.6)
	_slider(col, "BUTTON_ALPHA", float(s["btn_alpha"]), func(v: float) -> void: s["btn_alpha"] = clampf(v, 0.25, 1.0))
	_chips(col, "VIBRATION", [[tr("ON"), true], [tr("OFF"), false]], bool(s["vibration"]), func(v) -> void: s["vibration"] = v, 140)
	_chips(col, "GK_ASSIST", [[tr("ON"), true], [tr("OFF"), false]], bool(s["gk_assist"]), func(v) -> void: s["gk_assist"] = v, 140)
	_chips(col, "AIM_ASSIST", [[tr("ON"), 1.0], [tr("OFF"), 0.0]], float(s["aim_assist"]), func(v) -> void: s["aim_assist"] = v, 140)
	_chips(col, "FPS", [[tr("ON"), true], [tr("OFF"), false]], bool(s.get("fps60", true)), func(v) -> void:
		s["fps60"] = v
		Engine.max_fps = 60 if v else 30, 140)
	var cr := UiKit.big_button(tr("CREDITS"), false, 26)
	cr.custom_minimum_size = Vector2(300, 60)
	cr.pressed.connect(_show_credits)
	col.add_child(cr)
	_back_button(screen, func() -> void:
		Game.save_game()
		_show_main())


func _slider(parent: Control, key: String, val: float, cb: Callable) -> void:
	parent.add_child(UiKit.label(tr(key), 24, Color(1, 1, 1, 0.65)))
	var h := HSlider.new()
	h.min_value = 0.0
	h.max_value = 1.0
	h.step = 0.01
	h.value = val
	h.custom_minimum_size = Vector2(520, 44)
	h.value_changed.connect(cb)
	parent.add_child(h)


func _show_credits() -> void:
	_clear()
	_title(screen, "CREDITS")
	var t := RichTextLabel.new()
	t.position = Vector2(70, 190)
	t.size = Vector2(1300, 620)
	t.bbcode_enabled = true
	t.add_theme_font_override("normal_font", UiKit.text_font())
	t.add_theme_font_size_override("normal_font_size", 22)
	var f := FileAccess.open("res://CREDITS.txt", FileAccess.READ)
	t.text = f.get_as_text() if f else "MAYDON"
	screen.add_child(t)
	_back_button(screen, _show_settings)


# ---------------------------------------------------------------------------
# Onboarding (first launch)
# ---------------------------------------------------------------------------

func _show_onboarding(step: int) -> void:
	_clear()
	var logo := UiKit.label("MAYDON", 110)
	logo.position = Vector2(70, 40)
	screen.add_child(logo)
	var col := _vbox(screen, Vector2(70, 220), 14)
	match step:
		0:
			col.add_child(UiKit.label(tr("CHOOSE_LANG"), 36, Color(1, 1, 1, 0.8)))
			for l in [["O'zbekcha", "uz"], ["Русский", "ru"], ["English", "en"]]:
				var b := UiKit.big_button(l[0], l[1] == Game.settings["lang"], 36)
				var code: String = l[1]
				b.pressed.connect(func() -> void:
					Game.set_lang(code)
					_show_onboarding(1))
				col.add_child(b)
		1:
			col.add_child(UiKit.label(tr("WELCOME"), 44))
			col.add_child(UiKit.label(tr("YOUR_NAME"), 24, Color(1, 1, 1, 0.6)))
			var e := _line_edit(str(Game.profile.get("name", "")), 14)
			e.placeholder_text = "KARIMOV"
			e.text_changed.connect(func(t: String) -> void: Game.profile["name"] = t.strip_edges())
			col.add_child(e)
			col.add_child(UiKit.label(tr("YOUR_NUMBER"), 24, Color(1, 1, 1, 0.6)))
			var num := SpinBox.new()
			num.min_value = 1
			num.max_value = 99
			num.value = int(Game.profile.get("number", 10))
			num.custom_minimum_size = Vector2(160, 60)
			num.value_changed.connect(func(v: float) -> void: Game.profile["number"] = int(v))
			col.add_child(num)
			_chips(col, "YOUR_POSITION", [[tr("GK"), 0], [tr("DEF"), 1], [tr("MID"), 2], [tr("FWD"), 3]], int(Game.profile.get("role", 3)), func(v) -> void: Game.profile["role"] = v, 200)
			var nx := UiKit.big_button(tr("NEXT") + "  ›", true)
			nx.pressed.connect(func() -> void:
				Game.profile["created"] = true
				Game.profile["onboarding_locker"] = true
				Game.save_game()
				Game.goto("res://scenes/locker.tscn"))
			col.add_child(nx)


# ---------------------------------------------------------------------------
# LAN (same Wi-Fi / hotspot)
# ---------------------------------------------------------------------------

var _lan_format := 5


func _show_friends() -> void:
	Net.stop()
	_clear()
	_title(screen, "FRIENDS")
	var info := UiKit.label(tr("WIFI_SOON"), 24, Color(1, 1, 1, 0.7), false)
	info.position = Vector2(72, 160)
	screen.add_child(info)
	var col := _vbox(screen, Vector2(70, 220), 12)
	_chips(col, "FORMAT", [[tr("F3"), 3], [tr("F5"), 5], [tr("F11"), 11]], _lan_format, func(v) -> void: _lan_format = v, 190)
	var hb := UiKit.big_button(tr("HOST"), true)
	hb.pressed.connect(func() -> void:
		if Net.host(_lan_format):
			_show_lobby())
	col.add_child(hb)
	col.add_child(UiKit.label(tr("JOIN"), 26, Color(1, 1, 1, 0.6)))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	col.add_child(list)
	list.add_child(UiKit.label(tr("SEARCHING"), 24, Color(1, 1, 1, 0.5), false))
	Net.start_discovery()
	var refresh := func() -> void:
		if not is_instance_valid(list):
			return
		for c in list.get_children():
			c.queue_free()
		if Net.hosts.is_empty():
			list.add_child(UiKit.label(tr("SEARCHING"), 24, Color(1, 1, 1, 0.5), false))
		for ip in Net.hosts:
			var h: Dictionary = Net.hosts[ip]
			var b := UiKit.big_button("%s   ·   %s   ·   %d" % [h["name"], tr("F%d" % int(h["format"])), int(h["players"])], false, 28)
			var ipc: String = ip
			b.pressed.connect(func() -> void:
				if Net.join(ipc):
					_show_lobby())
			list.add_child(b)
	Net.hosts_changed.connect(refresh)
	_back_button(screen, func() -> void:
		Net.hosts_changed.disconnect(refresh)
		Net.stop_discovery()
		Net.stop()
		_show_main())


func _show_lobby() -> void:
	_clear()
	_title(screen, "FRIENDS")
	var cols := HBoxContainer.new()
	cols.position = Vector2(70, 200)
	cols.add_theme_constant_override("separation", 40)
	screen.add_child(cols)
	var teams := [VBoxContainer.new(), VBoxContainer.new()]
	for t in 2:
		teams[t].custom_minimum_size = Vector2(460, 0)
		teams[t].add_theme_constant_override("separation", 8)
		cols.add_child(teams[t])
	var status := UiKit.label(tr("WAITING_PLAYERS"), 24, Color(1, 1, 1, 0.6), false)
	status.position = Vector2(72, 160)
	screen.add_child(status)
	var draw_lobby := func() -> void:
		if not is_instance_valid(cols):
			return
		for t in 2:
			for c in teams[t].get_children():
				c.queue_free()
			var hdr := UiKit.label(tr(["TEAM_BLUE", "TEAM_ORANGE"][t]), 36, [Color(0.4, 0.6, 1.0), Color(1.0, 0.55, 0.2)][t])
			teams[t].add_child(hdr)
		for p in Net.lobby.get("players", []):
			var row := UiKit.label("%d  %s  ·  %s" % [int(p["number"]), str(p["name"]).to_upper(), tr(["GK_S", "DEF_S", "MID_S", "FWD_S"][int(p["role"])])], 28,
				UiKit.GOLD if int(p["peer"]) == Net.my_peer() else Color.WHITE)
			row.add_theme_stylebox_override("normal", UiKit.style(Color(1, 1, 1, 0.07), 10))
			teams[int(p["team"])].add_child(row)
	Net.lobby_changed.connect(draw_lobby)
	draw_lobby.call()
	var ctl := _vbox(screen, Vector2(1080, 200), 10)
	var my_role := int(Game.profile.get("role", 3))
	var my_team := [0]
	_chips(ctl, "TEAM_OF", [[tr("TEAM_BLUE"), 0], [tr("TEAM_ORANGE"), 1]], 0, func(v) -> void:
		my_team[0] = v
		Net.request_team(v, my_role), 200)
	_chips(ctl, "POSITION", [[tr("GK_S"), 0], [tr("DEF_S"), 1], [tr("MID_S"), 2], [tr("FWD_S"), 3]], my_role, func(v) -> void:
		my_role = v
		Net.request_team(my_team[0], v), 96)
	if Net.is_host:
		var go := UiKit.big_button(tr("START") + "  ›", true, 40)
		go.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		go.position = Vector2(-420, -130)
		go.pressed.connect(func() -> void:
			Net.lobby_changed.disconnect(draw_lobby)
			Net.host_start())
		screen.add_child(go)
	else:
		Net.match_starting.connect(func() -> void:
			if Net.lobby_changed.is_connected(draw_lobby):
				Net.lobby_changed.disconnect(draw_lobby))
	Net.disconnected.connect(func() -> void:
		if is_instance_valid(screen):
			_show_friends(), CONNECT_ONE_SHOT)
	_back_button(screen, func() -> void:
		if Net.lobby_changed.is_connected(draw_lobby):
			Net.lobby_changed.disconnect(draw_lobby)
		Net.stop()
		_show_friends())


func _start_training() -> void:
	var cfg := Game.quick_match(3, Footballer.Role.FWD, 0, true)
	cfg.duration = 600.0
	cfg.team_strength = [0.65, 0.4]
	Game.next_match = cfg
	Game.next_match_meta = {"mode": "training", "tutorial": true}
	Sfx.stop_music()
	Game.goto("res://scenes/match.tscn")
