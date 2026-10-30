class_name Palette
extends RefCounted
## Distinct owner colours: golden-ratio hues with alternating saturation / value bands.

const PLAYER := Color(0.16, 0.47, 1.0)
const TRIBE := Color(0.78, 0.75, 0.70)


static func nation_color(index: int, salt: int = 0) -> Color:
	var h := fposmod(0.08 + float(index) * 0.61803398875 + float(salt % 997) * 0.0007, 1.0)
	# Keep away from the player's blue.
	if absf(h - 0.6) < 0.035:
		h = fposmod(h + 0.08, 1.0)
	var band := index % 3
	var s: float = [0.62, 0.78, 0.5][band]
	var v: float = [0.88, 0.74, 0.95][band]
	return Color.from_hsv(h, s, v)


static func tribe_color(index: int) -> Color:
	var k := float(index % 7) / 7.0
	return TRIBE.lerp(Color(0.68, 0.66, 0.62), k)
