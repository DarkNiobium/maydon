class_name TouchControls
extends Control
## Mobile controls: floating joystick (left), 4 action buttons + sprint (right).
## Labels change with the play context (attack / support / defend / keeper).

signal pause_pressed

var inp: InputState
var ctx := "attack"
var btn_scale := 1.0
var btn_alpha := 0.8
var team_mode := false
var _stick_touch := -1
var _look_touch := -1
var _look_last := Vector2.ZERO
var _look_acc := Vector2.ZERO
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_touch := {}           # touch index -> button id
var _buttons := []             # [{id, center(rel), r, label}]
var _font: Font
var _font_small: Font
var _power := -1.0
var _now := 0.0
var _pressed_vis := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

const LABELS := {
	"attack": ["B_PASS", "B_SHOOT", "B_THROUGH", "B_SKILL"],
	"setpiece": ["B_PASS", "B_SHOOT", "B_THROUGH", ""],
	"support": ["B_CALL", "B_SHOOT", "B_RUN", ""],
	"defend": ["B_TACKLE", "B_SLIDE", "B_CONTAIN", ""],
	"gk_defend": ["B_RUSH", "B_DIVE", "B_CONTAIN", ""],
	"gk_hold": ["B_THROW", "B_KICK", "B_THROW", ""],
	"throw": ["B_THROW", "B_THROW", "B_THROW", ""],
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/Oswald.ttf")
	_font_small = _font
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_layout()
	get_viewport().size_changed.connect(func() -> void:
		size = get_viewport_rect().size
		_layout())


func _layout() -> void:
	var s := get_viewport_rect().size
	var u := minf(s.y, s.x * 0.5625) / 900.0 * btn_scale
	var W := s.x - UiKit.safe_right()
	var H := s.y
	_buttons = [
		{"id": InputState.B.A, "c": Vector2(W - 250 * u, H - 150 * u), "r": 90.0 * u},
		{"id": InputState.B.B, "c": Vector2(W - 110 * u, H - 295 * u), "r": 80.0 * u},
		{"id": InputState.B.C, "c": Vector2(W - 335 * u, H - 335 * u), "r": 70.0 * u},
		{"id": InputState.B.D, "c": Vector2(W - 190 * u, H - 470 * u), "r": 56.0 * u},
		{"id": InputState.B.SPRINT, "c": Vector2(W - 475 * u, H - 105 * u), "r": 72.0 * u},
	]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if inp == null:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var b := _hit_button(e.position)
			if b >= 0:
				_btn_touch[e.index] = b
				inp.set_button(b, true, _now)
				_pressed_vis[b] = 1.0
				if Game.settings.get("vibration", true) and Game.is_phone():
					Input.vibrate_handheld(18)
			elif e.position.x >= get_viewport_rect().size.x * 0.48 and _look_touch < 0:
				_look_touch = e.index
				_look_last = e.position
			elif e.position.x < get_viewport_rect().size.x * 0.48 and _stick_touch < 0:
				_stick_touch = e.index
				_stick_origin = e.position
				_stick_pos = e.position
				inp.stick = Vector2.ZERO
		else:
			if _btn_touch.has(e.index):
				inp.set_button(_btn_touch[e.index], false, _now)
				_btn_touch.erase(e.index)
			if e.index == _stick_touch:
				_stick_touch = -1
				inp.stick = Vector2.ZERO
			if e.index == _look_touch:
				_look_touch = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_stick_pos = d.position
			var radius := 110.0 * _unit()
			var v := (_stick_pos - _stick_origin)
			if v.length() > radius:
				# drag the base along (floating stick)
				_stick_origin = _stick_pos - v.normalized() * radius
				v = v.normalized() * radius
			var dead := 0.12
			var vv := v / radius
			var l := vv.length()
			if l < dead:
				inp.stick = Vector2.ZERO
			else:
				vv = vv.normalized() * ((l - dead) / (1.0 - dead))
				inp.stick = Vector2(vv.x, -vv.y)
			queue_redraw()
		elif d.index == _look_touch:
			_look_acc += d.position - _look_last
			_look_last = d.position


func _unit() -> float:
	var s := get_viewport_rect().size
	return minf(s.y, s.x * 0.5625) / 900.0 * btn_scale


func _hit_button(p: Vector2) -> int:
	for b in _buttons:
		if p.distance_to(b["c"]) < b["r"] * 1.15:
			return b["id"]
	return -1


## Camera drag accumulated since the last call (right-hand side, off the buttons).
func take_look_delta() -> Vector2:
	var d := _look_acc
	_look_acc = Vector2.ZERO
	return d


func set_context(c: String) -> void:
	if c != ctx:
		ctx = c
		queue_redraw()


func set_power(p: float) -> void:
	_power = p
	queue_redraw()


func tick(now: float, dt: float) -> void:
	_now = now
	var any := false
	for i in _pressed_vis.size():
		if _pressed_vis[i] > 0.0:
			_pressed_vis[i] = maxf(0.0, _pressed_vis[i] - dt * 4.0)
			any = true
	if any:
		queue_redraw()


func _draw() -> void:
	var u := _unit()
	var a := btn_alpha
	# joystick
	if _stick_touch >= 0:
		draw_circle(_stick_origin, 110.0 * u, Color(1, 1, 1, 0.1 * a))
		draw_arc(_stick_origin, 110.0 * u, 0, TAU, 48, Color(1, 1, 1, 0.35 * a), 3.0 * u, true)
		draw_circle(_stick_pos, 46.0 * u, Color(1, 1, 1, 0.45 * a))
	else:
		var hint := Vector2(230 * u + UiKit.safe_left(), get_viewport_rect().size.y - 210 * u)
		draw_arc(hint, 100.0 * u, 0, TAU, 48, Color(1, 1, 1, 0.16 * a), 3.0 * u, true)
		draw_circle(hint, 40.0 * u, Color(1, 1, 1, 0.12 * a))
	var labels: Array = LABELS.get(ctx, LABELS["attack"])
	if team_mode and ctx in ["defend", "support"]:
		labels = labels.duplicate()
		labels[3] = "B_SWITCH"
	for b in _buttons:
		var id: int = b["id"]
		var key := "B_SPRINT" if id == InputState.B.SPRINT else str(labels[id])
		if key == "":
			continue
		var label := tr(key)
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		var held: bool = inp != null and inp.held[id]
		var base := Color(0.05, 0.07, 0.09, 0.45 * a)
		var ring := Color(1, 1, 1, 0.55 * a)
		if id == InputState.B.A:
			ring = Color(0.2, 0.9, 0.5, 0.85 * a)
		elif id == InputState.B.B:
			ring = Color(1.0, 0.35, 0.3, 0.85 * a)
		elif id == InputState.B.C:
			ring = Color(0.35, 0.7, 1.0, 0.85 * a)
		elif id == InputState.B.D:
			ring = Color(1.0, 0.8, 0.25, 0.85 * a)
		if held:
			base = Color(ring.r, ring.g, ring.b, 0.4 * a)
		draw_circle(c, r, base)
		draw_arc(c, r, 0, TAU, 56, ring, 4.0 * u, true)
		var fs := int(clampf(r * 0.36, 12.0, 40.0))
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(_font, c + Vector2(-ts.x * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95 * a))
	# shot power meter around the shoot button
	if _power >= 0.0:
		var sb: Dictionary = _buttons[1]
		var col := Color(0.2, 0.9, 0.4).lerp(Color(1.0, 0.25, 0.15), clampf((_power - 0.6) / 0.4, 0.0, 1.0))
		draw_arc(sb["c"], sb["r"] + 12.0 * u, -PI * 0.5, -PI * 0.5 + TAU * _power, 64, col, 10.0 * u, true)
