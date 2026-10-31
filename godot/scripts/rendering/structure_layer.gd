class_name StructureLayer
extends Node2D
## Buildings on the map, drawn with the game's own symbols (Symbols) at a screen size that grows
## with zoom, in three levels of detail so they never turn into identical dots:
##   far  (< 14 px) — the building's silhouette in the owner's colour with a dark outline;
##   full (14-30 px) — an owner-coloured plate with the symbol;
##   near (> 30 px) — the detailed symbol, level pips and the construction ring.
## Also: hover / selection highlight and a short pop when construction completes.

const POP_SECS := 0.6

var sim: Sim
var cam: MapCamera
## Structure id -> seconds since its construction finished (completion pop).
var _pops: Dictionary = {}
## Plate shape of the player's buildings (cosmetic item), "circle" by default.
var player_shape: String = "circle"
## Structure under the cursor / selected (-1 = none).
var hovered: int = -1
var selected: int = -1


## Plays the completion pop of structure `id` (called on BUILD_DONE).
func pop(id: int) -> void:
	_pops[id] = 0.0


func _process(delta: float) -> void:
	for id: int in _pops.keys():
		_pops[id] = float(_pops[id]) + delta
		if float(_pops[id]) > POP_SECS:
			_pops.erase(id)
	queue_redraw()


## On-screen symbol size in pixels for the current zoom.
func symbol_px() -> float:
	var z := cam.zoom.x
	return clampf(12.0 + (z - 1.0) * 4.5, 12.0, 44.0)


## Plate radius in tiles (half the symbol size plus a margin).
func plate_radius() -> float:
	return symbol_px() * 0.62 / cam.zoom.x


static func icon_id(rules: Rules, kind: int) -> String:
	return Symbols.building_id(rules, kind)


func _center(s: StructureSystem.Structure) -> Vector2:
	var W := sim.map.width
	return Vector2(s.tile % W + 0.5, s.tile / W + 0.5)


## The alive structure drawn under a screen position (within its plate), or -1.
func pick(screen_pos: Vector2) -> int:
	if sim == null or cam == null:
		return -1
	var p := cam.get_canvas_transform().affine_inverse() * screen_pos
	var r := plate_radius() * 1.15
	var best := -1
	var bd := r * r
	for s in sim.structures.near(sim.map.tile_at(clampi(int(p.x), 0, sim.map.width - 1), clampi(int(p.y), 0, sim.map.height - 1)), r + 2.0):
		var d := _center(s).distance_squared_to(p)
		if d <= bd:
			bd = d
			best = s.id
	return best


func _draw() -> void:
	if sim == null or cam == null:
		return
	var view := cam.visible_rect().grow(4)
	var z := cam.zoom.x
	var spx := symbol_px()
	var lod := Symbols.lod_for(spx)
	var half := spx * 0.5 / z
	var r := plate_radius()
	var px := int(round(spx))
	var lw := maxf(0.12, 1.5 / z)
	var now := sim.st.tick
	for s in sim.structures.structs:
		if not s.alive:
			continue
		var pos := _center(s)
		if not view.has_point(pos):
			continue
		var oc: Color = sim.st.o_color[s.owner]
		var building := s.done_tick > 0 and s.active_levels == 0
		var k := 1.0
		if _pops.has(s.id):
			var t := float(_pops[s.id]) / POP_SECS
			k = 1.0 + 0.4 * sin(t * PI)
			draw_arc(pos, r * (1.2 + t * 2.2), 0.0, TAU, 32, Color(oc.lightened(0.4), 1.0 - t), lw * 1.5)
		if s.id == selected or s.id == hovered:
			draw_arc(pos, r * 1.45, 0.0, TAU, 40, Color(1, 1, 1, 0.95 if s.id == selected else 0.55), lw * 1.6)
		var sid := icon_id(sim.rules, s.kind)
		if lod == "far":
			_draw_silhouette(sid, pos, half * k, oc.lightened(0.25), building, z)
		else:
			_draw_plate(s, pos, r * k, oc, building, lw)
			var tex := Symbols.tex_px(sid, int(px * 0.86), lod)
			if tex != null:
				var ir := half * 0.86 * k
				draw_texture_rect(tex, Rect2(pos - Vector2(ir, ir), Vector2(ir, ir) * 2.0), false,
					Color(1, 1, 1, 0.55) if building else Color(1, 1, 1, 0.97))
		if s.done_tick > 0:
			var total := float(sim.rules.building_ticks(s.kind))
			var prog := clampf(1.0 - float(s.done_tick - now) / maxf(total, 1.0), 0.0, 1.0)
			draw_arc(pos, r * 1.2, -PI / 2.0, -PI / 2.0 + TAU * prog, 32, UITheme.ACCENT, lw * 2.0)
		if s.level > 1 and lod == "near":
			_pips(pos + Vector2(0, r * 1.5), s.level, r * 0.16, oc.lightened(0.5))


## Far zoom: the building's own silhouette, owner-coloured, with a dark outline (no plate).
func _draw_silhouette(sid: String, pos: Vector2, half: float, col: Color, building: bool, z: float) -> void:
	var px := maxi(10, int(round(half * 2.0 * z)))
	var tex := Symbols.tex_px(sid, px, "far")
	if tex == null:
		return
	var rect := Rect2(pos - Vector2(half, half), Vector2(half, half) * 2.0)
	var o := 1.2 / z
	for d: Vector2 in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o)]:
		draw_texture_rect(tex, Rect2(rect.position + d, rect.size), false, Color(0.03, 0.05, 0.08, 0.9))
	draw_texture_rect(tex, rect, false, Color(col, 0.6) if building else col)


func _draw_plate(s: StructureSystem.Structure, pos: Vector2, r: float, oc: Color, building: bool, lw: float) -> void:
	var fill := Color(0.10, 0.12, 0.15, 0.94) if not building else Color(0.16, 0.17, 0.19, 0.9)
	var shape_pts := PlateShape.points(player_shape, pos, r) if s.owner == sim.player_id else PackedVector2Array()
	if shape_pts.is_empty():
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0.0, TAU, 32, oc.lightened(0.2), lw * 1.6)
	else:
		draw_colored_polygon(shape_pts, fill)
		var closed := shape_pts.duplicate()
		closed.append(shape_pts[0])
		draw_polyline(closed, oc.lightened(0.2), lw * 1.6)


func _pips(at: Vector2, level: int, pr: float, c: Color) -> void:
	if level > 5:
		draw_string(ThemeDB.fallback_font, at + Vector2(-pr * 3.0, pr * 2.0), "×%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1,
			maxi(4, int(pr * 7.0)), c)
		return
	var w := (level - 1) * pr * 2.6
	for i in level:
		draw_circle(at + Vector2(-w * 0.5 + i * pr * 2.6, 0), pr, c)
