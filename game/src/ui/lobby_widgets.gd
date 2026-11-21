class_name LobbyWidgets
extends RefCounted
## Lobby UI building blocks (PUBG-style): glossy panels, icon tiles, the big
## animated PLAY button, coin pill, progress bars.

const PANEL_BG := Color(0.03, 0.04, 0.06, 0.72)
const EDGE := Color(1, 1, 1, 0.14)
const GOLD_TOP := Color(1.0, 0.86, 0.32)
const GOLD_BOT := Color(0.96, 0.62, 0.05)


static func panel(radius := 14, bg := PANEL_BG, edge := EDGE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = edge
	s.set_border_width_all(1)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	return s


## Square icon tile with a caption (left rail / bottom bar).
static func tile(kind: String, caption: String, cb: Callable, size := Vector2(124, 108), badge := 0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", panel(14))
	b.add_theme_stylebox_override("hover", panel(14, Color(0.08, 0.1, 0.14, 0.85), Color(1, 1, 1, 0.3)))
	b.add_theme_stylebox_override("pressed", panel(14, Color(0.12, 0.1, 0.03, 0.9), UiKit.GOLD))
	b.pressed.connect(func() -> void:
		Sfx.ui("click")
		cb.call())
	b.draw.connect(func() -> void:
		var isz := size.y * 0.42
		Icons.draw(b, kind, Rect2(Vector2((b.size.x - isz) * 0.5, size.y * 0.12), Vector2(isz, isz)), Color.WHITE)
		var f := UiKit.font()
		var fs := 17
		var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		b.draw_string(f, Vector2((b.size.x - tw) * 0.5, b.size.y - 13), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))
		if badge > 0:
			var bc := Vector2(b.size.x - 14, 14)
			b.draw_circle(bc, 11, Color(0.92, 0.18, 0.2))
			var bt := str(badge)
			b.draw_string(f, bc + Vector2(-f.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x * 0.5, 6), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE))
	return b


## The big gold PLAY button with a moving shine.
class PlayButton extends Control:
	signal pressed
	var text := "PLAY"
	var sub := ""
	var _t := 0.0
	var _down := false
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		mouse_entered.connect(func() -> void: _hover = true)
		mouse_exited.connect(func() -> void:
			_hover = false
			_down = false)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch:
			if e.is_pressed():
				_down = true
			elif _down:
				_down = false
				Sfx.ui("ok")
				pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var k := 0.94 if _down else 1.0
		var rr := Rect2(r.position + r.size * (1.0 - k) * 0.5, r.size * k)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(16)
		sb.bg_color = LobbyWidgets.GOLD_BOT
		sb.shadow_color = Color(0.9, 0.55, 0.0, 0.45 + 0.15 * sin(_t * 2.5))
		sb.shadow_size = 14
		draw_style_box(sb, rr)
		var top := StyleBoxFlat.new()
		top.bg_color = LobbyWidgets.GOLD_TOP.lightened(0.08 if _hover else 0.0)
		top.corner_radius_top_left = 16
		top.corner_radius_top_right = 16
		draw_style_box(top, Rect2(rr.position, Vector2(rr.size.x, rr.size.y * 0.52)))
		# moving shine
		var ph := fmod(_t * 0.45, 1.6) - 0.3
		var x := rr.position.x + ph * rr.size.x
		var w := rr.size.x * 0.12
		draw_colored_polygon(PackedVector2Array([Vector2(x, rr.position.y), Vector2(x + w, rr.position.y),
			Vector2(x + w - rr.size.y * 0.5, rr.end.y), Vector2(x - rr.size.y * 0.5, rr.end.y)]), Color(1, 1, 1, 0.22))
		var f := UiKit.font()
		var fs := int(rr.size.y * 0.42)
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ty := rr.position.y + rr.size.y * (0.58 if sub == "" else 0.52)
		draw_string(f, Vector2(rr.get_center().x - tw * 0.5, ty + fs * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.16, 0.09, 0.0))
		if sub != "":
			var fs2 := int(rr.size.y * 0.15)
			var tw2 := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			draw_string(f, Vector2(rr.get_center().x - tw2 * 0.5, rr.end.y - rr.size.y * 0.1), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.25, 0.14, 0.0, 0.85))


static func coin_pill(amount: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(22, Color(0, 0, 0, 0.55)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(Icons.make("coin", 30, UiKit.GOLD))
	var l := UiKit.label(str(amount), 28, Color(1, 0.92, 0.7))
	h.add_child(l)
	return p


static func bar(frac: float, w: float, h := 8.0, col := UiKit.ACCENT) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(h * 0.5))
		sb.bg_color = Color(1, 1, 1, 0.12)
		c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size))
		if frac > 0.0:
			var fb := StyleBoxFlat.new()
			fb.set_corner_radius_all(int(h * 0.5))
			fb.bg_color = col
			c.draw_style_box(fb, Rect2(Vector2.ZERO, Vector2(maxf(c.size.x * clampf(frac, 0.0, 1.0), h), c.size.y))))
	return c
