class_name FlagGen
extends RefCounted
## Procedural flags for states without a real flag: stripes, crosses, triangles and discs in
## heraldic colours, chosen deterministically from a seed.

const COLORS := [Color("#b22234"), Color("#1f4e9c"), Color("#f2f2f2"), Color("#1a1a1a"), Color("#2a8a3e"),
	Color("#f4c430"), Color("#e0701c"), Color("#5b2a86"), Color("#3fa7d6"), Color("#7a1f1f")]

static var _cache: Dictionary = {}


static func texture(seed_value: int, base: Color = Color.TRANSPARENT) -> Texture2D:
	var key := hash([seed_value, base])
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(image(seed_value, base))
	return _cache[key]


static func image(seed_value: int, base: Color = Color.TRANSPARENT, w: int = 48, h: int = 32) -> Image:
	var rng := SimRng.new(seed_value)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c0: Color = base if base.a > 0.0 else COLORS[rng.below(COLORS.size())]
	var c1: Color = COLORS[rng.below(COLORS.size())]
	var c2: Color = COLORS[rng.below(COLORS.size())]
	while c1.is_equal_approx(c0):
		c1 = COLORS[rng.below(COLORS.size())]
	while c2.is_equal_approx(c1):
		c2 = COLORS[rng.below(COLORS.size())]
	var pattern := rng.below(6)
	for y in h:
		for x in w:
			var c := c0
			var fx := float(x) / w
			var fy := float(y) / h
			match pattern:
				0:
					c = c0 if fy < 0.333 else (c1 if fy < 0.666 else c2)
				1:
					c = c0 if fx < 0.333 else (c1 if fx < 0.666 else c2)
				2:
					c = c1 if absf(fx - 0.35) < 0.08 or absf(fy - 0.5) < 0.12 else c0
				3:
					c = c1 if fy < 0.5 else c2
					if fx < 0.5 - absf(fy - 0.5):
						c = c0
				4:
					c = c1 if Vector2(fx - 0.5, (fy - 0.5) * 0.66).length() < 0.2 else c0
				5:
					c = c0 if fx + fy * 0.66 < 0.8 else c1
			img.set_pixel(x, y, c)
	return img
