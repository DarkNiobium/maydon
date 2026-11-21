class_name Tutorial
extends CanvasLayer
## Guided first match: move, sprint, pass, call for the ball, through ball,
## shoot, tackle, score. Steps advance on real match events.

var view: MatchView
var step := 0
var _panel: PanelContainer
var _label: Label
var _dots: HBoxContainer
var _start_pos := Vector3.ZERO
var _sprint_t := 0.0
var _done_t := -1.0
const STEPS := ["TUT_MOVE", "TUT_SPRINT", "TUT_PASS", "TUT_CALL", "TUT_THROUGH", "TUT_SHOOT", "TUT_TACKLE", "TUT_SCORE", "TUT_DONE"]


func _init(v: MatchView) -> void:
	view = v
	layer = 20


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-430, 90)
	_panel.custom_minimum_size = Vector2(860, 110)
	_panel.add_theme_stylebox_override("panel", UiKit.style(Color(0.02, 0.04, 0.05, 0.82), 14, UiKit.ACCENT, 2))
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_label = UiKit.label("", 34)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_label)
	if not Game.is_phone():
		var pc := UiKit.label(tr("PC_CONTROLS"), 17, Color(1, 1, 1, 0.7), false)
		pc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pc.custom_minimum_size = Vector2(840, 0)
		v.add_child(pc)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 8)
	v.add_child(_dots)
	var skip := UiKit.big_button(tr("SKIP"), false, 22)
	skip.custom_minimum_size = Vector2(200, 54)
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.position = Vector2(-230, 100)
	skip.pressed.connect(_finish)
	add_child(skip)
	_show()


func _show() -> void:
	_label.text = tr(STEPS[step])
	for c in _dots.get_children():
		c.queue_free()
	for i in STEPS.size() - 1:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(26, 6)
		d.color = UiKit.ACCENT if i < step else Color(1, 1, 1, 0.25)
		_dots.add_child(d)
	_panel.scale = Vector2(1.08, 1.08)
	_panel.pivot_offset = _panel.size * 0.5
	create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.25)
	Sfx.ui("ok")
	if view.human_id >= 0:
		_start_pos = view.sim.players[view.human_id].pos


func _advance() -> void:
	step += 1
	if step >= STEPS.size() - 1:
		step = STEPS.size() - 1
		_done_t = 3.0
	_show()


func _process(delta: float) -> void:
	if view.human_id < 0 or view.paused:
		return
	var p: Footballer = view.sim.players[view.human_id]
	match STEPS[step]:
		"TUT_MOVE":
			if p.pos.distance_to(_start_pos) > 8.0:
				_advance()
		"TUT_SPRINT":
			if view.human.inp.held[InputState.B.SPRINT] and p.vel.length() > 6.0:
				_sprint_t += delta
				if _sprint_t > 1.2:
					_advance()
		"TUT_CALL":
			if view.now - view.human.called_t < 0.3 and view.human.called_t > 0.0:
				_advance()
	if _done_t > 0.0:
		_done_t -= delta
		if _done_t <= 0.0:
			_finish()


func on_event(e: Dictionary) -> void:
	if view.human_id < 0:
		return
	var mine: bool = e.get("id", -1) == view.human_id
	match STEPS[step]:
		"TUT_PASS":
			if mine and e["t"] == "kick" and e.get("kind", "") in ["pass", "lob"]:
				_advance()
		"TUT_THROUGH":
			if mine and e["t"] == "kick" and e.get("kind", "") == "through":
				_advance()
		"TUT_SHOOT":
			if mine and e["t"] == "shot":
				_advance()
		"TUT_TACKLE":
			if mine and e["t"] in ["tackle"]:
				_advance()
		"TUT_SCORE":
			if e["t"] == "goal" and int(e.get("team", -1)) == view.sim.players[view.human_id].team:
				_advance()


func _finish() -> void:
	Game.profile["tutorial_done"] = true
	Game.save_game()
	Sfx.match_end()
	Game.goto("res://scenes/menu.tscn")
