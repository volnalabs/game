class_name StructureLayer
extends Node2D
## Buildings drawn in map space at a constant screen size (only those in view): an owner-coloured
## plate with the building's icon, a progress ring while it is built or upgraded, level pips, and
## a short pop when construction completes.

const POP_SECS := 0.6

var sim: Sim
var cam: MapCamera
## Structure id -> seconds since its construction finished (completion pop).
var _pops: Dictionary = {}
## Plate shape of the player's buildings (cosmetic item), "circle" by default.
var player_shape: String = "circle"


## Plays the completion pop of structure `id` (called on BUILD_DONE).
func pop(id: int) -> void:
	_pops[id] = 0.0


func _process(delta: float) -> void:
	for id: int in _pops.keys():
		_pops[id] = float(_pops[id]) + delta
		if float(_pops[id]) > POP_SECS:
			_pops.erase(id)
	queue_redraw()


## Plate radius in tiles for the current zoom (about 9 px on screen, bigger when zoomed out).
func plate_radius() -> float:
	var z := cam.zoom.x
	return clampf(9.0 / z, 0.7, 11.0)


static func icon_id(rules: Rules, kind: int) -> String:
	return "b_" + rules.b_ids[kind]


func _draw() -> void:
	if sim == null or cam == null:
		return
	var view := cam.visible_rect().grow(4)
	var z := cam.zoom.x
	var r := plate_radius()
	var px := maxi(16, int(r * z * 2.0))
	var W := sim.map.width
	var now := sim.st.tick
	var lw := maxf(0.12, 1.6 / z)
	for s in sim.structures.structs:
		if not s.alive:
			continue
		var pos := Vector2(s.tile % W + 0.5, s.tile / W + 0.5)
		if not view.has_point(pos):
			continue
		var oc: Color = sim.st.o_color[s.owner]
		var building := s.done_tick > 0
		var rr := r
		if _pops.has(s.id):
			var k := float(_pops[s.id]) / POP_SECS
			rr = r * (1.0 + 0.45 * sin(k * PI))
			draw_arc(pos, r * (1.2 + k * 2.2), 0.0, TAU, 32, Color(oc.lightened(0.4), 1.0 - k), lw * 1.5)
		var fill := Color(0.16, 0.18, 0.22) if building and s.active_levels == 0 else oc.darkened(0.35)
		var shape_pts := PlateShape.points(player_shape, pos, rr) if s.owner == sim.player_id else PackedVector2Array()
		if shape_pts.is_empty():
			draw_circle(pos, rr * 1.18, Color(0.04, 0.06, 0.09, 0.9))
			draw_circle(pos, rr, fill)
			draw_arc(pos, rr, 0.0, TAU, 32, oc.lightened(0.15), lw)
		else:
			draw_colored_polygon(PlateShape.points(player_shape, pos, rr * 1.18), Color(0.04, 0.06, 0.09, 0.9))
			draw_colored_polygon(shape_pts, fill)
			var closed := shape_pts.duplicate()
			closed.append(shape_pts[0])
			draw_polyline(closed, oc.lightened(0.15), lw)
		var tex := Icons.tex(icon_id(sim.rules, s.kind), px)
		if tex != null:
			var ir := rr * 0.68
			draw_texture_rect(tex, Rect2(pos - Vector2(ir, ir), Vector2(ir, ir) * 2.0), false,
				Color(1, 1, 1, 0.55) if building else Color(1, 1, 1, 0.95))
		if building:
			var total := float(sim.rules.building_ticks(s.kind))
			var prog := clampf(1.0 - float(s.done_tick - now) / maxf(total, 1.0), 0.0, 1.0)
			draw_arc(pos, rr * 1.18, -PI / 2.0, -PI / 2.0 + TAU * prog, 32, UITheme.ACCENT, lw * 1.6)
		if s.level > 1 and z > 1.5:
			_pips(pos + Vector2(0, rr * 1.55), s.level, rr * 0.18, oc.lightened(0.5))


func _pips(at: Vector2, level: int, pr: float, c: Color) -> void:
	if level > 5:
		draw_string(ThemeDB.fallback_font, at + Vector2(-pr * 3.0, pr * 2.0), "×%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1,
			maxi(4, int(pr * 7.0)), c)
		return
	var w := (level - 1) * pr * 2.6
	for i in level:
		draw_circle(at + Vector2(-w * 0.5 + i * pr * 2.6, 0), pr, c)
