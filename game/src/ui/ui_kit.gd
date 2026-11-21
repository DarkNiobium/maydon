class_name UiKit
extends RefCounted
## Shared UI widgets and styles.

const ACCENT := Color(0.16, 0.86, 0.48)
const GOLD := Color(1.0, 0.78, 0.24)
const DARK := Color(0.035, 0.05, 0.07)
const PANEL := Color(0.07, 0.09, 0.12, 0.92)

static var _font: Font
static var _text: Font


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/Oswald.ttf")
	return _font


static func text_font() -> Font:
	if _text == null:
		_text = load("res://assets/fonts/Inter.ttf")
	return _text


static func style(bg: Color, radius := 10, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func big_button(txt: String, accent := false, fs := 34) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(380, 76)
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", fs)
	var base := ACCENT if accent else Color(1, 1, 1, 0.1)
	var col := DARK if accent else Color.WHITE
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col)
	b.add_theme_color_override("font_pressed_color", col)
	b.add_theme_color_override("font_focus_color", col)
	b.add_theme_stylebox_override("normal", style(base, 12))
	b.add_theme_stylebox_override("hover", style(base.lightened(0.12), 12))
	b.add_theme_stylebox_override("pressed", style(base.darkened(0.2), 12))
	b.add_theme_stylebox_override("focus", style(base, 12, Color.WHITE, 2))
	b.pressed.connect(func() -> void: Sfx.ui("click"))
	return b


static func label(txt: String, fs := 28, col := Color.WHITE, display := true) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font() if display else text_font())
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


## Display cutout insets (punch-hole cameras) in canvas units.
static func _insets() -> Vector2:
	if not Game.is_phone():
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or scr.x <= 0:
		return Vector2.ZERO
	var vp := tree.root.get_visible_rect().size
	var k := vp.x / float(scr.x)
	var left := float(safe.position.x) * k
	var right := float(scr.x - safe.end.x) * k
	return Vector2(clampf(left, 0.0, 160.0), clampf(right, 0.0, 160.0))


static func safe_left() -> float:
	return _insets().x


static func safe_right() -> float:
	return _insets().y
