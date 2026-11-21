class_name Icons
extends RefCounted
## Vector icons drawn with CanvasItem primitives (no font/emoji dependency).

static func draw(ci: CanvasItem, kind: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var u := s / 24.0      # icon grid: 24 units
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x - 12.0, y - 12.0) * u
	match kind:
		"shirt":
			var pts := PackedVector2Array([p.call(8, 3), p.call(10, 4.5), p.call(14, 4.5), p.call(16, 3), p.call(22, 6.5),
				p.call(19.5, 11), p.call(17, 9.8), p.call(17, 21), p.call(7, 21), p.call(7, 9.8), p.call(4.5, 11), p.call(2, 6.5)])
			ci.draw_colored_polygon(pts, col)
			ci.draw_arc(p.call(12, 3.6), 2.2 * u, 0.2, PI - 0.2, 10, Color(0, 0, 0, 0.35), 1.6 * u)
		"trophy":
			var cup := PackedVector2Array([p.call(6, 3), p.call(18, 3), p.call(17.5, 9), p.call(15, 13), p.call(13, 14), p.call(11, 14),
				p.call(9, 13), p.call(6.5, 9)])
			ci.draw_colored_polygon(cup, col)
			ci.draw_arc(p.call(5.5, 7), 3.0 * u, PI * 0.5, PI * 1.5, 12, col, 1.6 * u)
			ci.draw_arc(p.call(18.5, 7), 3.0 * u, -PI * 0.5, PI * 0.5, 12, col, 1.6 * u)
			ci.draw_rect(Rect2(p.call(11, 14), Vector2(2, 4) * u), col)
			ci.draw_rect(Rect2(p.call(7.5, 18), Vector2(9, 3) * u), col)
		"cone":
			ci.draw_colored_polygon(PackedVector2Array([p.call(12, 2.5), p.call(17.5, 19), p.call(6.5, 19)]), col)
			ci.draw_rect(Rect2(p.call(4, 19), Vector2(16, 2.5) * u), col)
			ci.draw_line(p.call(9.2, 11), p.call(14.8, 11), Color(0, 0, 0, 0.45), 1.8 * u)
			ci.draw_line(p.call(8.1, 15), p.call(15.9, 15), Color(0, 0, 0, 0.45), 1.8 * u)
		"people":
			ci.draw_circle(p.call(9, 7.5), 3.6 * u, col)
			ci.draw_circle(p.call(17, 8.5), 3.0 * u, Color(col, 0.75))
			_round_body(ci, p.call(9, 19.5), 6.5 * u, 6.0 * u, col)
			_round_body(ci, p.call(17.5, 19.5), 5.0 * u, 5.0 * u, Color(col, 0.75))
		"gear":
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				var tooth := fmod(i, 6.0) < 3.0
				pts.append(c + Vector2(cos(a), sin(a)) * (9.5 if tooth else 7.6) * u)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, 3.2 * u, Color(0, 0, 0, 0.55))
		"coin":
			ci.draw_circle(c, 10.5 * u, Color(0.75, 0.5, 0.05))
			ci.draw_circle(c, 9.0 * u, col)
			ci.draw_arc(c, 7.0 * u, 0, TAU, 24, Color(0.8, 0.55, 0.05, 0.8), 1.2 * u)
			var m := PackedVector2Array([p.call(8, 16), p.call(8, 8), p.call(12, 12.5), p.call(16, 8), p.call(16, 16)])
			ci.draw_polyline(m, Color(0.55, 0.35, 0.02), 1.8 * u)
		"list":
			ci.draw_rect(Rect2(p.call(5, 3.5), Vector2(14, 18) * u), col, false, 1.8 * u)
			ci.draw_rect(Rect2(p.call(9, 2), Vector2(6, 3) * u), col)
			for k in 3:
				var y := 9.0 + k * 4.0
				ci.draw_polyline(PackedVector2Array([p.call(7.5, y), p.call(8.7, y + 1.2), p.call(10.5, y - 1.0)]), col, 1.6 * u)
				ci.draw_line(p.call(12, y), p.call(17, y), col, 1.6 * u)
		"plus":
			ci.draw_line(p.call(12, 4), p.call(12, 20), col, 2.6 * u)
			ci.draw_line(p.call(4, 12), p.call(20, 12), col, 2.6 * u)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([p.call(7, 4), p.call(20, 12), p.call(7, 20)]), col)
		"ball":
			ci.draw_circle(c, 10 * u, col)
			var pent := PackedVector2Array()
			for i in 5:
				var a := -PI * 0.5 + TAU * i / 5.0
				pent.append(c + Vector2(cos(a), sin(a)) * 3.6 * u)
			ci.draw_colored_polygon(pent, Color(0.08, 0.08, 0.1))
			for i in 5:
				var a := -PI * 0.5 + TAU * i / 5.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * 3.6 * u, c + Vector2(cos(a), sin(a)) * 9.5 * u, Color(0.08, 0.08, 0.1), 1.2 * u)
		"lock":
			ci.draw_arc(p.call(12, 10), 4.5 * u, PI, TAU, 14, col, 2.2 * u)
			ci.draw_rect(Rect2(p.call(5.5, 10), Vector2(13, 10) * u), col)
		"check":
			ci.draw_polyline(PackedVector2Array([p.call(5, 12.5), p.call(10, 17.5), p.call(19.5, 6.5)]), col, 3.0 * u)


static func _round_body(ci: CanvasItem, base: Vector2, w: float, h: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		pts.append(base + Vector2(cos(a) * w, sin(a) * h))
	ci.draw_colored_polygon(pts, col)


## A Control that draws one icon (for use inside containers).
static func make(kind: String, size: float, col := Color.WHITE) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: Icons.draw(c, kind, Rect2(Vector2.ZERO, c.size), col))
	return c
