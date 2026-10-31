class_name GhostLayer
extends Node2D
## Build placement preview: where the order would really go (StructureSystem.preview — the same
## code path as the build itself), valid / invalid colour, the building's effect radius, the
## minimum-distance rings of nearby buildings that block placement, and an upgrade marker.

var sim: Sim
var cam: MapCamera
var cursor: int = -1
var preview: Dictionary = {}


func set_preview(cursor_tile: int, pv: Dictionary) -> void:
	cursor = cursor_tile
	preview = pv
	queue_redraw()


func clear() -> void:
	if cursor >= 0 or not preview.is_empty():
		cursor = -1
		preview = {}
		queue_redraw()


func _process(_delta: float) -> void:
	if cursor >= 0:
		queue_redraw()


func _center(t: int) -> Vector2:
	var W := sim.map.width
	return Vector2(t % W + 0.5, t / W + 0.5)


func _draw() -> void:
	if sim == null or cam == null or cursor < 0 or preview.is_empty():
		return
	var z := cam.zoom.x
	var lw := maxf(0.15, 1.6 / z)
	var kind: int = preview["kind"]
	var ok: bool = preview["ok"]
	var c := UITheme.GOOD if ok else UITheme.BAD
	var cp := _center(cursor)
	# Rings that block placement: other buildings' minimum distance.
	var md := sim.rules.b_min_dist
	for s in sim.structures.near(cursor, md * 2.5):
		draw_arc(_center(s.tile), md, 0.0, TAU, 48, Color(1, 1, 1, 0.14), lw * 0.8)
	var site: int = preview["tile"]
	if site < 0:
		var k := maxf(0.6, 6.0 / z)
		draw_line(cp - Vector2(k, k), cp + Vector2(k, k), UITheme.BAD, lw * 2.0)
		draw_line(cp - Vector2(k, -k), cp + Vector2(k, -k), UITheme.BAD, lw * 2.0)
		return
	var sp := _center(site)
	if site != cursor:
		draw_line(cp, sp, Color(c, 0.6), lw)
	var radius: float = preview["radius"]
	if radius > 0.0:
		draw_circle(sp, radius, Color(ZoneLayer.kind_color(sim.rules, kind), 0.08))
		draw_arc(sp, radius, 0.0, TAU, 96, Color(ZoneLayer.kind_color(sim.rules, kind), 0.5), lw * 0.8)
	var r := clampf(13.0 / z, 0.9, 13.0)
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 160.0)
	draw_circle(sp, r * 1.15, Color(c, 0.18 * pulse))
	var tex := Icons.tex(StructureLayer.icon_id(sim.rules, kind), maxi(16, int(r * z * 2.0)))
	if tex != null:
		var ir := r * 0.85
		draw_texture_rect(tex, Rect2(sp - Vector2(ir, ir) + Vector2(0, ir * 0.08), Vector2(ir, ir) * 2.0), false, Color(0.08, 0.07, 0.06, 0.5))
		draw_texture_rect(tex, Rect2(sp - Vector2(ir, ir), Vector2(ir, ir) * 2.0), false, Color("#f2efe8").lerp(c, 0.45))
	if int(preview["upgrade"]) >= 0:
		draw_arc(sp, r * 1.6, 0.0, TAU, 32, Color(UITheme.ACCENT, pulse), lw * 1.5)
