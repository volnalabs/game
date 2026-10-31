class_name TerrainColors
extends RefCounted
## The map's terrain palette (own design), shared by the renderer and map previews.

const BASE := [
	Color("#1d3d5c"),  # deep ocean
	Color("#2c5b80"),  # shallow
	Color("#3a6f94"),  # lake
	Color("#93b46a"),  # plains
	Color("#5f8a4e"),  # forest
	Color("#b3a676"),  # hills
	Color("#a8a29a"),  # mountain
	Color("#d8c48e"),  # desert
	Color("#b5bcae"),  # tundra
	Color("#eef2f4"),  # ice
]
const RIVER := Color("#3f7fae")


static func color_of(code: int, river: bool, elevation: int) -> Color:
	if river and code >= Rules.T_PLAINS and code != Rules.T_MOUNTAIN:
		return RIVER
	var c: Color = BASE[code]
	if code >= Rules.T_PLAINS:
		var shade := (float(elevation) - 128.0) / 255.0 * 0.22
		c = c.lightened(shade) if shade > 0.0 else c.darkened(-shade)
	return c


## Cosmetic map styles (profile item "map_style"): a colour transform of the palette.
static func styled(c: Color, style: String) -> Color:
	match style:
		"parchment":
			var l := c.get_luminance()
			return Color(0.55 + l * 0.45, 0.45 + l * 0.42, 0.30 + l * 0.30).lerp(c, 0.18)
		"night":
			return Color(c.r * 0.42, c.g * 0.48, c.b * 0.62 + 0.06)
		"arctic":
			return c.lerp(Color("#e9f1f7"), 0.35).lerp(Color("#8fb7d4"), 0.08)
		"atlas":
			if c.b > c.r and c.b > c.g:
				return Color("#a9cfe8").lerp(c, 0.25)
			return c.lerp(Color("#f1e7c9"), 0.4)
	return c


## Full-resolution terrain image (one pixel per tile), in a cosmetic style ("" = standard).
static func terrain_image(map: MapData, style: String = "") -> Image:
	var n := map.size
	var data := PackedByteArray()
	data.resize(n * 4)
	var lut := PackedByteArray()
	# Precompute colours for (code, river, elevation/8).
	lut.resize(10 * 2 * 32 * 4)
	for code in 10:
		for rv in 2:
			for e in 32:
				var c := styled(color_of(code, rv == 1, e * 8), style)
				var k := ((code * 2 + rv) * 32 + e) * 4
				lut[k] = c.r8
				lut[k + 1] = c.g8
				lut[k + 2] = c.b8
				lut[k + 3] = 255
	var terr := map.terrain
	var elev := map.elevation
	for i in n:
		var b := terr[i]
		var code := b & MapData.CODE_MASK
		var rv := 1 if (b & MapData.RIVER_BIT) != 0 else 0
		var k2 := ((code * 2 + rv) * 32 + (elev[i] >> 3)) * 4
		var o := i * 4
		data[o] = lut[k2]
		data[o + 1] = lut[k2 + 1]
		data[o + 2] = lut[k2 + 2]
		data[o + 3] = 255
	return Image.create_from_data(map.width, map.height, false, Image.FORMAT_RGBA8, data)


## Small preview image for menus.
static func preview(map: MapData, max_w: int = 480) -> Image:
	var w := mini(max_w, map.width)
	var h := maxi(1, roundi(float(map.height) * float(w) / float(map.width)))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var t := map.tile_at(int(float(x) * map.width / w), int(float(y) * map.height / h))
			img.set_pixel(x, y, color_of(map.code(t), map.is_river(t), map.elevation[t]))
	return img
