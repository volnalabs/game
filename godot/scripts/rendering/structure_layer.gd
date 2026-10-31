class_name StructureLayer
extends Node2D
## Building icons drawn in map space at a constant screen size (only those in view).

const ICON_COLORS := [Color("#f2e6c9"), Color("#9ad1ff"), Color("#f0b54a"), Color("#c9d3dd"), Color("#ff8f8f"), Color("#d7a6ff")]

var sim: Sim
var cam: MapCamera


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or cam == null:
		return
	var view := cam.visible_rect().grow(4)
	var z := cam.zoom.x
	var r := clampf(7.0 / z, 0.6, 9.0)
	if z < 0.9:
		r = 6.0 / z
	var W := sim.map.width
	for s in sim.structures.structs:
		if not s.alive:
			continue
		var pos := Vector2(s.tile % W + 0.5, s.tile / W + 0.5)
		if not view.has_point(pos):
			continue
		var oc: Color = sim.st.o_color[s.owner]
		var building := s.done_tick > 0
		draw_circle(pos, r * 1.25, Color(0.05, 0.07, 0.1, 0.85))
		draw_circle(pos, r, oc.darkened(0.25) if not building else Color(0.3, 0.3, 0.3))
		_glyph(s.kind, pos, r * 0.62, ICON_COLORS[s.kind])
		if s.level > 1 and z > 2.0:
			draw_string(ThemeDB.fallback_font, pos + Vector2(r * 0.9, -r * 0.6), str(s.level), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(4, int(r * 1.1)), Color.WHITE)


func _glyph(kind: int, p: Vector2, s: float, c: Color) -> void:
	match kind:
		Rules.B_CITY:
			draw_rect(Rect2(p - Vector2(s, s * 0.4), Vector2(s * 0.8, s * 1.4)), c)
			draw_rect(Rect2(p + Vector2(s * 0.1, -s), Vector2(s * 0.8, s * 2.0)), c)
		Rules.B_PORT:
			draw_line(p + Vector2(0, -s), p + Vector2(0, s), c, s * 0.3)
			draw_arc(p + Vector2(0, s * 0.1), s * 0.8, 0.3, PI - 0.3, 8, c, s * 0.3)
		Rules.B_FACTORY:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-s, s), p + Vector2(-s, -s * 0.2), p + Vector2(-s * 0.3, s * 0.2),
				p + Vector2(-s * 0.3, -s * 0.2), p + Vector2(s * 0.4, s * 0.2), p + Vector2(s * 0.4, -s), p + Vector2(s, -s), p + Vector2(s, s)]), c)
		Rules.B_DEFENSE:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-s, -s), p + Vector2(s, -s), p + Vector2(s, s * 0.2),
				p + Vector2(0, s), p + Vector2(-s, s * 0.2)]), c)
		Rules.B_SAM:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.7, s), p + Vector2(-s * 0.7, s)]), c)
		Rules.B_SILO:
			draw_circle(p, s * 0.7, c)
