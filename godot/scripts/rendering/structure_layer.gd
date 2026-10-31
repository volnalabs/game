class_name StructureLayer
extends Node2D
## Buildings on the map, drawn with the game's own symbols (Symbols) in layers that stay readable on
## any territory colour, without plates or rings:
##   1. a soft offset shadow that lifts the building off the map,
##   2. a thin dark contour (baked into the "map_*" symbol variants),
##   3. the light filled silhouette — the same for every owner, so shape alone identifies the type,
##   4. small detail shapes tinted with a dark shade of the owner's colour (ownership accent).
## The on-screen size follows the zoom with a sensible minimum; three levels of detail (far / full /
## near). When buildings would overlap on screen they are grouped: the most important one is drawn
## with a small count badge instead of shrinking everything into dots.
## Hover lifts a building slightly; selection adds a calm accent contour (the zone layer draws its
## radius). A short pop plays when construction completes.

const POP_SECS := 0.6
## Order of importance when buildings are grouped (the first kind in a group is drawn).
const PRIORITY := ["city", "port", "naval_base", "airbase", "silo", "sam", "command_center", "factory",
	"research_center", "military_academy", "radar", "defense", "bunker", "power_plant", "logistics_hub"]
const BODY := Color("#f4f1ea")
const SHADOW := Color(0.06, 0.05, 0.04, 0.38)
const SELECT := Color("#d58b67")
const MIN_PX := 18.0
const MAX_PX := 48.0

var sim: Sim
var cam: MapCamera
## Structure id -> seconds since its construction finished (completion pop).
var _pops: Dictionary = {}
## Plate shape of the player's buildings (cosmetic item), "circle" by default (= no shape).
var player_shape: String = "circle"
## Structure under the cursor / selected (-1 = none).
var hovered: int = -1
var selected: int = -1
var _rank: PackedInt32Array = PackedInt32Array()


## Plays the completion pop of structure `id` (called on BUILD_DONE).
func pop(id: int) -> void:
	_pops[id] = 0.0


func _process(delta: float) -> void:
	for id: int in _pops.keys():
		_pops[id] = float(_pops[id]) + delta
		if float(_pops[id]) > POP_SECS:
			_pops.erase(id)
	queue_redraw()


## On-screen symbol size in pixels for a zoom (grows with zoom, never below MIN_PX).
static func symbol_px_for(z: float) -> float:
	return clampf(MIN_PX + (z - 1.0) * 5.0, MIN_PX, MAX_PX)


func symbol_px() -> float:
	return symbol_px_for(cam.zoom.x)


## Level of detail of map symbols at an on-screen size.
static func lod_for(px: float) -> String:
	if px < 21.0:
		return "far"
	if px < 36.0:
		return "full"
	return "near"


## Pick radius in tiles (half the symbol plus a margin).
func plate_radius() -> float:
	return symbol_px() * 0.55 / cam.zoom.x


static func icon_id(rules: Rules, kind: int) -> String:
	return Symbols.building_id(rules, kind)


func _center(s: StructureSystem.Structure) -> Vector2:
	var W := sim.map.width
	return Vector2(s.tile % W + 0.5, s.tile / W + 0.5)


func _kind_rank(kind: int) -> int:
	if _rank.size() != sim.rules.b_ids.size():
		_rank.resize(sim.rules.b_ids.size())
		for k in sim.rules.b_ids.size():
			var i := PRIORITY.find(sim.rules.b_ids[k])
			_rank[k] = i if i >= 0 else PRIORITY.size()
	return _rank[kind]


## Visible buildings grouped so no two drawn symbols overlap on screen. Returns an array of
## [structure, count, members] with the most important building of each group first; the hovered and
## selected buildings always stay their own representative.
func layout(view: Rect2) -> Array:
	var spx := symbol_px()
	var z := cam.zoom.x
	var min_d := spx * 0.92 / z  # tiles
	var list: Array = []
	for s in sim.structures.structs:
		if s.alive and view.has_point(_center(s)):
			list.append(s)
	list.sort_custom(func(a: StructureSystem.Structure, b: StructureSystem.Structure) -> bool:
		var pa := 0 if a.id == selected or a.id == hovered else 1
		var pb := 0 if b.id == selected or b.id == hovered else 1
		if pa != pb:
			return pa < pb
		var ra := _kind_rank(a.kind)
		var rb := _kind_rank(b.kind)
		if ra != rb:
			return ra < rb
		return a.id < b.id)
	var cell := maxf(min_d, 0.5)
	var grid: Dictionary = {}
	var groups: Array = []
	for s: StructureSystem.Structure in list:
		var p := _center(s)
		var cx := int(floor(p.x / cell))
		var cy := int(floor(p.y / cell))
		var hit := -1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var key := Vector2i(cx + dx, cy + dy)
				if not grid.has(key):
					continue
				for gi: int in grid[key]:
					var g: Array = groups[gi]
					if _center(g[0]).distance_to(p) < min_d:
						hit = gi
						break
				if hit >= 0:
					break
			if hit >= 0:
				break
		if hit >= 0:
			groups[hit][1] = int(groups[hit][1]) + 1
			(groups[hit][2] as Array).append(s.id)
			continue
		var gk := Vector2i(cx, cy)
		if not grid.has(gk):
			grid[gk] = []
		(grid[gk] as Array).append(groups.size())
		groups.append([s, 1, [s.id]])
	return groups


## The building drawn under a screen position, or -1. Grouped buildings answer with the drawn one.
func pick(screen_pos: Vector2) -> int:
	if sim == null or cam == null:
		return -1
	var p := cam.get_canvas_transform().affine_inverse() * screen_pos
	var r := plate_radius() * 1.15
	var best := -1
	var bd := r * r
	for g: Array in layout(Rect2(p - Vector2(r, r) * 4.0, Vector2(r, r) * 8.0)):
		var s: StructureSystem.Structure = g[0]
		var d := _center(s).distance_squared_to(p)
		if d <= bd:
			bd = d
			best = s.id
	return best


## Owner accent for detail shapes: a dark, still recognisable shade of the owner's colour.
static func detail_color(owner_color: Color) -> Color:
	var c := Color("#2a2622").lerp(owner_color, 0.5)
	# Darken until it reads on the light body (WCAG contrast >= 3.5).
	for i in 8:
		var lc := c.srgb_to_linear().get_luminance() + 0.05
		var lb := BODY.srgb_to_linear().get_luminance() + 0.05
		if lb / lc >= 3.5:
			break
		c = c.darkened(0.2)
	return c


func _draw() -> void:
	if sim == null or cam == null:
		return
	var view := cam.visible_rect().grow(4)
	var z := cam.zoom.x
	var spx := symbol_px()
	var lod := lod_for(spx)
	var half := spx * 0.5 / z
	var lw := maxf(0.12, 1.4 / z)
	var now := sim.st.tick
	for g: Array in layout(view):
		var s: StructureSystem.Structure = g[0]
		var count: int = g[1]
		var pos := _center(s)
		var oc: Color = sim.st.o_color[s.owner]
		var building := s.done_tick > 0 and s.active_levels == 0
		var k := 1.0
		if _pops.has(s.id):
			var t := float(_pops[s.id]) / POP_SECS
			k = 1.0 + 0.3 * sin(t * PI)
			draw_arc(pos, half * (1.1 + t * 1.6), 0.0, TAU, 32, Color(1, 1, 1, 0.6 * (1.0 - t)), lw)
		var sid := icon_id(sim.rules, s.kind)
		var hh := half * k * (1.14 if s.id == hovered else 1.0)
		# The player's cosmetic building skin: a faint shape under their own buildings.
		if s.owner == sim.player_id and player_shape != "circle":
			var pts := PlateShape.points(player_shape, pos, hh * 1.05)
			if not pts.is_empty():
				draw_colored_polygon(pts, Color(oc, 0.3))
		var alpha := 0.6 if building else 1.0
		_draw_symbol(sid, pos, hh, lod, z, oc, alpha, s.id == selected, s.id == hovered)
		if s.done_tick > 0:
			var total := float(sim.rules.building_ticks(s.kind))
			var prog := clampf(1.0 - float(s.done_tick - now) / maxf(total, 1.0), 0.0, 1.0)
			draw_arc(pos, hh * 1.08, -PI / 2.0, -PI / 2.0 + TAU, 40, Color(0, 0, 0, 0.35), lw * 1.6)
			draw_arc(pos, hh * 1.08, -PI / 2.0, -PI / 2.0 + TAU * prog, 40, Color(1, 1, 1, 0.85), lw * 1.3)
		if s.level > 1 and lod != "far":
			_pips(pos + Vector2(0, hh * 1.12), s.level, maxf(hh * 0.1, 1.6 / z), z)
		if count > 1:
			_badge(pos + Vector2(hh * 0.85, -hh * 0.85), count, z)


## Shadow, contour + silhouette, owner-tinted details; selection = accent contour behind.
func _draw_symbol(sid: String, pos: Vector2, half: float, lod: String, z: float, owner_color: Color,
		alpha: float, is_selected: bool, is_hovered: bool) -> void:
	var px := maxi(12, int(round(half * 2.0 * z)))
	var body := Symbols.tex_px(sid, px, "map_" + lod)
	if body == null:
		return
	var rect := Rect2(pos - Vector2(half, half), Vector2(half, half) * 2.0)
	var o := maxf(1.0, px * 0.06) / z
	draw_texture_rect(body, Rect2(rect.position + Vector2(o * 0.35, o), rect.size), false, Color(SHADOW, SHADOW.a * alpha))
	if is_selected:
		var g := half * 0.24
		var sel_rect := rect.grow(g)
		var sel := Symbols.tex_px(sid, maxi(12, int(round(sel_rect.size.x * z))), "map_" + lod)
		draw_texture_rect(sel, sel_rect, false, Color(SELECT, 0.95))
	var col := BODY if not is_hovered else Color(1, 1, 1)
	draw_texture_rect(body, rect, false, Color(col, alpha))
	if lod != "far":
		var det := Symbols.tex_px(sid, px, "det_" + lod)
		if det != null:
			draw_texture_rect(det, rect, false, Color(detail_color(owner_color), alpha))


## Level dots under a building (dark-rimmed so they read on any colour).
func _pips(at: Vector2, level: int, pr: float, z: float) -> void:
	if level > 5:
		var txt := "×%d" % level
		var font := ThemeDB.fallback_font
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_set_transform(at, 0.0, Vector2(1.0 / z, 1.0 / z))
		draw_string_outline(font, Vector2(-sz.x * 0.5, sz.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0.11, 0.1, 0.09, 0.85))
		draw_string(font, Vector2(-sz.x * 0.5, sz.y * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BODY)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var step := pr * 2.7
	var w := (level - 1) * step
	for i in level:
		var c := at + Vector2(-w * 0.5 + i * step, 0)
		draw_circle(c, pr * 1.35, Color(0.11, 0.1, 0.09, 0.85))
		draw_circle(c, pr, BODY)


## Small count badge of a group of buildings (constant on-screen size).
func _badge(at: Vector2, count: int, z: float) -> void:
	var r := 7.0 / z
	var txt := str(count) if count < 100 else "99+"
	draw_circle(at, r + 1.0 / z, Color(0.11, 0.1, 0.09, 0.9))
	draw_circle(at, r, Color("#38332d"))
	var font := ThemeDB.fallback_font
	var fs := 10
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# Draw text in screen pixels: scale the canvas temporarily.
	draw_set_transform(at, 0.0, Vector2(1.0 / z, 1.0 / z))
	draw_string(font, Vector2(-sz.x * 0.5, sz.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BODY)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
