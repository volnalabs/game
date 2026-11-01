class_name PlateShape
extends Control
## Draws a building plate shape (also used by the structure layer for the player's skin).

var shape: String = "circle"
var color: Color = Color("#3a4a5a")
var stroke: Color = Color("#c9d3dd")


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var pts := points(shape, size * 0.5, r)
	if pts.is_empty():
		draw_circle(size * 0.5, r, color)
		draw_arc(size * 0.5, r, 0.0, TAU, 32, stroke, 2.0)
		return
	draw_colored_polygon(pts, color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, stroke, 2.0)


## Polygon of a plate shape centred on c with radius r ([] = circle).
static func points(shape: String, c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	match shape:
		"square":
			for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				out.append(c + p * r * 0.86)
		"diamond":
			for p in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
				out.append(c + p * r * 1.1)
		"hex":
			for i in 6:
				out.append(c + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * r)
		"shield":
			for p in [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(0.9, 0.15), Vector2(0, 1.0), Vector2(-0.9, 0.15)]:
				out.append(c + p * r)
		"star":
			for i in 10:
				var rr := r * (1.05 if i % 2 == 0 else 0.55)
				out.append(c + Vector2.from_angle(TAU * i / 10.0 - PI / 2.0) * rr)
	return out
