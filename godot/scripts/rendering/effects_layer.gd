class_name EffectsLayer
extends Node2D
## Transports at sea, attack fronts of the selected / player state, and short-lived rings
## (captures, eliminations, landings).

var sim: Sim
var cam: MapCamera
var rings: Array = []
var spawn_hover: int = -1


func ring(tile: int, color: Color, radius: float = 12.0) -> void:
	var W := sim.map.width
	rings.append({"pos": Vector2(tile % W + 0.5, tile / W + 0.5), "c": color, "r": radius, "t": 0.0})


func _process(delta: float) -> void:
	for r: Dictionary in rings:
		r["t"] = float(r["t"]) + delta
	rings = rings.filter(func(r: Dictionary) -> bool: return float(r["t"]) < 1.2)
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var z := cam.zoom.x
	var view := cam.visible_rect().grow(8)
	for b in sim.naval.boats:
		if not b.alive:
			continue
		var p := b.position()
		if not view.has_point(p):
			continue
		var c: Color = sim.st.o_color[b.owner]
		var s := clampf(6.0 / z, 0.8, 8.0)
		var pts := PackedVector2Array([p + Vector2(s * 1.4, 0), p + Vector2(-s, s * 0.8), p + Vector2(-s, -s * 0.8)])
		draw_colored_polygon(pts, c)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.8), maxf(0.15, 1.0 / z))
		# Remaining route.
		if b.owner == sim.player_id and b.path.size() > 1:
			draw_line(p, b.path[b.path.size() - 1], Color(c, 0.35), maxf(0.2, 1.2 / z))
	if spawn_hover >= 0 and sim.phase == Sim.Phase.SPAWN:
		var hp := Vector2(spawn_hover % sim.map.width + 0.5, spawn_hover / sim.map.width + 0.5)
		var ok := sim.spawn.is_valid_start(spawn_hover)
		var rad := sim.rules.spawn_radius + 0.5
		draw_circle(hp, rad, Color(UITheme.GOOD if ok else UITheme.BAD, 0.35))
		draw_arc(hp, rad, 0.0, TAU, 32, UITheme.GOOD if ok else UITheme.BAD, maxf(0.2, 2.0 / z))
		draw_arc(hp, 30.0, 0.0, TAU, 64, Color(1, 1, 1, 0.25), maxf(0.2, 1.0 / z))
	for r: Dictionary in rings:
		var k := float(r["t"]) / 1.2
		var c2: Color = r["c"]
		draw_arc(r["pos"], float(r["r"]) * (0.3 + k), 0.0, TAU, 32, Color(c2, 1.0 - k), maxf(0.3, 2.0 / z))
