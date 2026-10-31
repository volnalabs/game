class_name ShipPainter
extends RefCounted
## Top-down transport ships, drawn straight onto a CanvasItem (no nodes per ship): a light hull with
## a pointed bow and a squared stern, a row of cargo containers in the owner's colour, a bridge
## house near the stern with a dark window band, a soft offset shadow and a fading V-shaped wake.
## Shapes are in ship-local units (length 1, heading +x) and transformed per ship. Far away the ship
## keeps its hull silhouette and one cargo band; close up the containers and bridge are detailed.

const HULL_COLOR := Color("#ece6d9")
const EDGE := Color(0.09, 0.08, 0.07, 0.85)
const SHADOW := Color(0.04, 0.05, 0.08, 0.32)
## Beam (width) factor applied to every shape: a little fuller than real proportions, so the ship
## reads from above at small sizes.
const BEAM := 1.3

static var _hull: PackedVector2Array
static var _deck: PackedVector2Array


static func hull() -> PackedVector2Array:
	if _hull.is_empty():
		# Bow tip, curved shoulders, straight sides, slightly rounded squared stern.
		var pts := PackedVector2Array()
		pts.append(Vector2(0.5, 0.0))
		for i in range(1, 7):
			var t := float(i) / 6.0
			pts.append(Vector2(0.5 - 0.28 * t, 0.17 * sin(t * PI * 0.5)))
		pts.append(Vector2(-0.38, 0.17))
		pts.append(Vector2(-0.47, 0.15))
		pts.append(Vector2(-0.5, 0.11))
		pts.append(Vector2(-0.5, -0.11))
		pts.append(Vector2(-0.47, -0.15))
		pts.append(Vector2(-0.38, -0.17))
		for i in range(6, 0, -1):
			var t := float(i) / 6.0
			pts.append(Vector2(0.5 - 0.28 * t, -0.17 * sin(t * PI * 0.5)))
		_hull = pts
		var d := PackedVector2Array()
		for p in pts:
			d.append(Vector2(p.x * 0.9 - 0.01, p.y * 0.78))
		_deck = d
	return _hull


static func _xf(pts: PackedVector2Array, pos: Vector2, rot: float, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	var c := cos(rot)
	var s := sin(rot)
	for i in pts.size():
		var p := Vector2(pts[i].x, pts[i].y * BEAM) * scale
		out[i] = pos + Vector2(p.x * c - p.y * s, p.x * s + p.y * c)
	return out


static func _rect(x0: float, x1: float, y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## Draws one transport. `length` in canvas units, `rot` radians, `wake` 0..1 (speed feel),
## `px` on-screen length in pixels (level of detail), `t` seconds (wake animation).
static func draw_ship(ci: CanvasItem, pos: Vector2, rot: float, length: float, owner_color: Color, alpha: float,
		px: float, wake: float, t: float, selected: bool) -> void:
	var h := hull()
	var lw := length / maxf(px, 1.0)  # one screen pixel in canvas units
	# Wake: two thin trails opening behind the stern, with soft foam at the stern.
	if wake > 0.01:
		var back := Vector2(-cos(rot), -sin(rot))
		var side := Vector2(-sin(rot), cos(rot))
		var stern := pos + back * length * 0.5
		var wl := length * (0.6 + 0.8 * wake)
		for sgn: float in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for i in 9:
				var k := float(i) / 8.0
				var wob := sin(t * 3.0 + k * 6.0) * length * 0.02
				pts.append(stern + back * wl * k + side * sgn * (length * 0.1 + wl * 0.28 * k + wob))
				cols.append(Color(1, 1, 1, 0.45 * wake * alpha * (1.0 - k)))
			ci.draw_polyline_colors(pts, cols, maxf(lw * 1.6, length * 0.045), true)
		ci.draw_circle(stern + back * length * 0.04, length * 0.09, Color(1, 1, 1, 0.22 * wake * alpha))
	# Shadow, selection halo, hull.
	ci.draw_colored_polygon(_xf(h, pos + Vector2(length * 0.05, length * 0.08), rot, length), Color(SHADOW, SHADOW.a * alpha))
	var hp := _xf(h, pos, rot, length)
	if selected:
		var halo := _xf(h, pos, rot, length * 1.32)
		ci.draw_colored_polygon(halo, Color(UITheme.ACCENT, 0.9 * alpha))
	var closed := hp.duplicate()
	closed.append(hp[0])
	ci.draw_polyline(closed, Color(EDGE, EDGE.a * alpha), maxf(lw * 1.6, length * 0.03), true)
	ci.draw_colored_polygon(hp, Color(HULL_COLOR, alpha))
	var oc := owner_color.lightened(0.05)
	if px < 22.0:
		# Far: one cargo band in the owner's colour keeps ownership readable.
		ci.draw_colored_polygon(_xf(_rect(-0.28, 0.22, -0.09, 0.09), pos, rot, length), Color(oc, alpha))
		ci.draw_colored_polygon(_xf(_rect(-0.44, -0.32, -0.1, 0.1), pos, rot, length), Color(EDGE, 0.8 * alpha))
		return
	# Deck, containers, bridge house.
	ci.draw_colored_polygon(_xf(_deck, pos, rot, length), Color(HULL_COLOR.darkened(0.08), alpha))
	var dark := oc.darkened(0.35)
	for i in 3:
		var x0 := -0.26 + i * 0.165
		ci.draw_colored_polygon(_xf(_rect(x0, x0 + 0.14, -0.105, 0.105), pos, rot, length), Color(dark, alpha))
		ci.draw_colored_polygon(_xf(_rect(x0 + 0.012, x0 + 0.128, -0.093, 0.093), pos, rot, length), Color(oc, alpha))
		if px >= 34.0:
			ci.draw_colored_polygon(_xf(_rect(x0 + 0.06, x0 + 0.08, -0.093, 0.093), pos, rot, length), Color(dark, 0.6 * alpha))
	ci.draw_colored_polygon(_xf(_rect(-0.45, -0.31, -0.115, 0.115), pos, rot, length), Color(EDGE, alpha))
	ci.draw_colored_polygon(_xf(_rect(-0.44, -0.32, -0.1, 0.1), pos, rot, length), Color("#f6f2ea", alpha))
	ci.draw_colored_polygon(_xf(_rect(-0.345, -0.32, -0.085, 0.085), pos, rot, length), Color(0.15, 0.17, 0.2, alpha))
	if px >= 34.0:
		# Bow mark: a small dark wedge on the foredeck.
		ci.draw_colored_polygon(_xf(PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.28, 0.05), Vector2(0.28, -0.05)]), pos, rot, length),
			Color(EDGE, 0.5 * alpha))
