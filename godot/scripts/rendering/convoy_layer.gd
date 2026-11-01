class_name ConvoyLayer
extends Node2D
## Shipments between allies (DiplomacySystem.convoys) on the map: a faint dotted route from capital
## to capital in the sender's colour and a marker at the convoy's current position — a troop
## square or a gold coin. Read-only; positions come from Convoy.position().

var sim: Sim
var cam: MapCamera


func _process(_delta: float) -> void:
	if sim != null and (not sim.diplomacy.convoys.is_empty() or _had):
		_had = not sim.diplomacy.convoys.is_empty()
		queue_redraw()


var _had: bool = false


func _draw() -> void:
	if sim == null:
		return
	var z := cam.zoom.x if cam != null else 1.0
	var px := 1.0 / maxf(z, 0.01)
	var now := sim.st.tick
	for c in sim.diplomacy.convoys:
		var col := sim.st.o_color[c.from]
		var pos := c.position(now)
		# Route: dots every 6 screen pixels from here to the destination.
		var to := c.to_pos
		var seg := to - pos
		var n := int(seg.length() / (6.0 * px))
		for i in range(1, mini(n, 400)):
			draw_circle(pos + seg * (float(i) / float(n)), 1.1 * px, Color(col.lightened(0.3), 0.55))
		var r := 7.0 * px
		draw_circle(pos, r + 1.5 * px, Color(0, 0, 0, 0.75))
		if c.kind == "gold":
			draw_circle(pos, r, UITheme.GOLD)
			draw_circle(pos, r * 0.45, UITheme.GOLD.darkened(0.35))
		else:
			draw_rect(Rect2(pos - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), col.lightened(0.15))
			draw_rect(Rect2(pos - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), Color(1, 1, 1, 0.8), false, 1.0 * px)
