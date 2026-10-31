class_name ZoneLayer
extends Node2D
## Effect zones of buildings (defence posts, later SAM, radar, airbases...): the exact radius the
## simulation uses (Rules.building_radius, euclidean distance from the building's tile). Shown for
## the player's buildings when zones are on, for the selected state as well, and for the kind
## being placed.

const KIND_COLORS := {"defense": Color("#6fb7ff"), "sam": Color("#ff7a7a"), "silo": Color("#ffb454")}

var sim: Sim
var cam: MapCamera
## Draw every zone of the player and the selected state.
var show_all: bool = false
## Owner whose zones are added to the player's (selected state).
var extra_owner: int = 0
## Kind being placed: its zones are shown even when show_all is off.
var focus_kind: int = -1


static func kind_color(rules: Rules, kind: int) -> Color:
	return KIND_COLORS.get(rules.b_ids[kind], UITheme.ACCENT)


## Kinds that have an effect radius (for the legend).
static func zone_kinds(rules: Rules) -> Array[int]:
	var out: Array[int] = []
	for k in rules.building_count():
		if rules.building_radius(k) > 0.0 and not rules.b_kinds[k].has("phase"):
			out.append(k)
	return out


func visible_zones() -> bool:
	return show_all or focus_kind >= 0


func _process(_delta: float) -> void:
	if visible_zones():
		queue_redraw()


func _draw() -> void:
	if sim == null or cam == null or not visible_zones():
		return
	var pid := sim.player_id
	var view := cam.visible_rect()
	var W := sim.map.width
	var lw := maxf(0.15, 1.5 / cam.zoom.x)
	for s in sim.structures.structs:
		if not s.alive:
			continue
		var r := sim.rules.building_radius(s.kind)
		if r <= 0.0:
			continue
		var mine := s.owner == pid
		var show := (show_all or s.kind == focus_kind) and (mine or s.owner == extra_owner)
		if not show:
			continue
		var pos := Vector2(s.tile % W + 0.5, s.tile / W + 0.5)
		if not view.grow(r).has_point(pos):
			continue
		var c := kind_color(sim.rules, s.kind)
		if not mine:
			c = c.lerp(UITheme.BAD, 0.5)
		var active := s.active_levels > 0
		draw_circle(pos, r, Color(c, 0.10 if active else 0.05))
		_dashed_circle(pos, r, Color(c, 0.85 if active else 0.45), lw, not active)


func _dashed_circle(p: Vector2, r: float, c: Color, w: float, dashed: bool) -> void:
	if not dashed:
		draw_arc(p, r, 0.0, TAU, 96, c, w)
		return
	var n := 48
	for i in n:
		if i % 2 == 0:
			draw_arc(p, r, TAU * i / n, TAU * (i + 1) / n, 4, c, w)
