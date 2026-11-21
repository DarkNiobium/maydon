class_name EmoteWheel
extends Control
## Radial emote picker. Touch: tap a slot. PC: hold T, move the mouse toward a
## slot, release T (or click); keys 1-8 pick directly.

signal chosen(index: int)

var sel := -1
var _virt := Vector2.ZERO        # virtual cursor offset (captured mouse)
var _icons: Array = []
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	for i in Emotes.LIST.size():
		_icons.append(Emotes.icon(i))


func open() -> void:
	if visible:
		return
	visible = true
	sel = -1
	_virt = Vector2.ZERO
	_t = 0.0
	Sfx.ui("click")
	queue_redraw()


func close() -> void:
	visible = false


func confirm() -> void:
	if not visible:
		return
	var s := sel
	close()
	if s >= 0:
		chosen.emit(s)


func pick(i: int) -> void:
	if i >= 0 and i < Emotes.LIST.size():
		close()
		chosen.emit(i)


func _center() -> Vector2:
	return get_viewport_rect().size * 0.5


func _radius() -> float:
	return minf(get_viewport_rect().size.y * 0.34, 300.0)


func _slot_at(off: Vector2) -> int:
	if off.length() < _radius() * 0.28:
		return -1
	var n := Emotes.LIST.size()
	var a := fposmod(atan2(off.x, -off.y) + PI / n, TAU)
	return int(a / (TAU / n)) % n


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_virt += (e as InputEventMouseMotion).relative
			_virt = _virt.limit_length(_radius())
		else:
			_virt = (e as InputEventMouseMotion).position - _center()
		sel = _slot_at(_virt)
		accept_event()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			sel = _slot_at(mb.position - _center())
			if sel < 0:
				close()
				accept_event()
				return
		confirm()
		accept_event()
	elif e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
		var st := e as InputEventScreenTouch
		var s := _slot_at(st.position - _center())
		if s < 0:
			close()
		else:
			sel = s
			confirm()
		accept_event()


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.35))
	var c := _center()
	var r := _radius() * minf(1.0, 0.75 + _t * 2.5)
	var n := Emotes.LIST.size()
	var font := UiKit.font()
	draw_circle(c, r, Color(0.04, 0.05, 0.07, 0.82))
	draw_arc(c, r, 0, TAU, 96, Color(1, 1, 1, 0.18), 3.0, true)
	draw_circle(c, r * 0.28, Color(0.02, 0.03, 0.04, 0.9))
	for i in n:
		var a0 := -PI * 0.5 + (i - 0.5) * TAU / n
		var a1 := a0 + TAU / n
		if i == sel:
			var pts := PackedVector2Array()
			for k in 17:
				var a := lerpf(a0, a1, k / 16.0)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			for k in 17:
				var a := lerpf(a1, a0, k / 16.0)
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.3)
			draw_colored_polygon(pts, Color(UiKit.ACCENT, 0.85))
		var sep := Vector2(cos(a0), sin(a0))
		draw_line(c + sep * r * 0.3, c + sep * r, Color(1, 1, 1, 0.12), 2.0, true)
		var am := (a0 + a1) * 0.5
		var p := c + Vector2(cos(am), sin(am)) * r * 0.66
		var col := UiKit.DARK if i == sel else Color.WHITE
		var tex: Texture2D = _icons[i]
		if tex:
			var isz := r * 0.34
			draw_texture_rect(tex, Rect2(p - Vector2(isz * 0.5, isz * 0.62), Vector2(isz, isz)), false, col)
		var txt := TranslationServer.translate(Emotes.LIST[i]["label"])
		var fs := int(r * 0.085)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, p + Vector2(-tw * 0.5, r * 0.2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if not Game.is_phone():
			draw_string(font, p + Vector2(-5, -r * 0.2), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), Color(col, 0.55))
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		draw_circle(c + _virt, 7.0, Color(1, 1, 1, 0.9))
