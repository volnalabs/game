class_name StructureLayer
extends Node2D
## Buildings on the map, drawn with the game's own symbols (Symbols) as free-standing silhouettes —
## no plates or rings: a pale tint of the owner's colour over a soft shadow, at a screen size that
## grows gently with zoom, in three levels of detail (far silhouette / full / near with level dots).
## Hover lifts a building slightly, selection adds a calm halo; a short pop when it completes.

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
	return clampf(13.0 + (z - 1.0) * 3.4, 13.0, 36.0)


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
		var sid := icon_id(sim.rules, s.kind)
		var tint := Color("#f2efe8").lerp(oc, 0.38)
		if building:
			tint = Color(tint, 0.55)
		var hh := half * k * (1.12 if s.id == hovered else 1.0)
		if s.id == selected:
			draw_circle(pos + Vector2(0, hh * 0.15), hh * 1.25, Color(1, 1, 1, 0.10))
			draw_arc(pos + Vector2(0, hh * 0.15), hh * 1.25, 0.0, TAU, 40, Color(1, 1, 1, 0.55), lw)
		# The player's cosmetic building skin: a faint shape under their own buildings.
		if s.owner == sim.player_id and player_shape != "circle":
			var pts := PlateShape.points(player_shape, pos + Vector2(0, hh * 0.1), hh * 1.15)
			if not pts.is_empty():
				draw_colored_polygon(pts, Color(oc, 0.22))
		_draw_symbol(sid, pos, hh, tint, lod, z)
		if s.done_tick > 0:
			var total := float(sim.rules.building_ticks(s.kind))
			var prog := clampf(1.0 - float(s.done_tick - now) / maxf(total, 1.0), 0.0, 1.0)
			draw_arc(pos + Vector2(0, half * 0.15), half * 1.05, -PI / 2.0, -PI / 2.0 + TAU * prog, 32, Color(1, 1, 1, 0.7), lw * 1.4)
		if s.level > 1 and lod == "near":
			_pips(pos + Vector2(0, half * 1.35), s.level, half * 0.11, Color("#f2efe8"))


## The building's silhouette with a soft drop shadow (no outline, no plate).
func _draw_symbol(sid: String, pos: Vector2, half: float, col: Color, lod: String, z: float) -> void:
	var px := maxi(10, int(round(half * 2.0 * z)))
	var tex := Symbols.tex_px(sid, px, lod)
	if tex == null:
		return
	var rect := Rect2(pos - Vector2(half, half), Vector2(half, half) * 2.0)
	var o := maxf(0.6, half * z * 0.09) / z
	draw_texture_rect(tex, Rect2(rect.position + Vector2(o * 0.4, o), rect.size), false, Color(0.08, 0.07, 0.06, 0.55 * col.a))
	draw_texture_rect(tex, rect, false, col)


func _pips(at: Vector2, level: int, pr: float, c: Color) -> void:
	if level > 5:
		draw_string(ThemeDB.fallback_font, at + Vector2(-pr * 3.0, pr * 2.0), "×%d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1,
			maxi(4, int(pr * 7.0)), c)
		return
	var w := (level - 1) * pr * 2.6
	for i in level:
		draw_circle(at + Vector2(-w * 0.5 + i * pr * 2.6, 0), pr, c)
