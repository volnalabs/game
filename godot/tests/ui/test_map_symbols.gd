extends TestCase
## Phase 2A.3-A: buildings on the map are recognisable by shape, large enough at play zoom, readable
## on any territory colour, and grouped (not shrunk) when they would overlap.

const TERRITORY := [Color("#e9e3d3"), Color("#34343f"), Color("#5f9e58"), Color("#e2c247"), Color("#8b8a86"), Color("#3c6fd1"),
	Color("#d9534f"), Color("#ffffff"), Color("#101010")]


func _mask(id: String, lod: String, px: int) -> PackedByteArray:
	var img := Symbols.tex_px(id, px, lod).get_image()
	img.convert(Image.FORMAT_RGBA8)
	var out := PackedByteArray()
	out.resize(px * px)
	for y in px:
		for x in px:
			var c := img.get_pixel(x, y)
			# Light silhouette pixels only (the dark contour is not part of the shape).
			out[y * px + x] = 1 if c.a > 0.5 and c.get_luminance() > 0.5 else 0
	return out


func _iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var inter := 0
	var uni := 0
	for i in a.size():
		inter += a[i] & b[i]
		uni += a[i] | b[i]
	return float(inter) / maxf(1.0, float(uni))


func _rules() -> Rules:
	return TestMaps.sim(TestMaps.rect(40, 40), 0, true).rules


func test_every_building_has_map_layers() -> void:
	var rules := _rules()
	check(rules.b_ids.size() >= 15, "all building kinds loaded")
	for k in rules.b_ids.size():
		var id := Symbols.building_id(rules, k)
		for lod: String in ["map_far", "map_full", "map_near", "det_full", "det_near"]:
			check(Symbols.tex_px(id, 24, lod) != null, "%s has %s" % [id, lod])


func test_silhouettes_are_distinct_at_play_size() -> void:
	var rules := _rules()
	for lod: String in ["map_far", "map_full"]:
		var px := 20 if lod == "map_far" else 26
		var masks: Array = []
		for k in rules.b_ids.size():
			masks.append(_mask(Symbols.building_id(rules, k), lod, px))
		var worst := 0.0
		var pair := ""
		var all: Array = []
		for a in masks.size():
			for b in range(a + 1, masks.size()):
				var v := _iou(masks[a], masks[b])
				all.append([v, "%s/%s" % [rules.b_ids[a], rules.b_ids[b]]])
				if v > worst:
					worst = v
					pair = "%s/%s" % [rules.b_ids[a], rules.b_ids[b]]
		all.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
		print("      top: ", all.slice(0, 6))
		print("      %s: most similar pair %s, overlap %.2f" % [lod, pair, worst])
		check(worst < 0.72, "%s silhouettes differ (worst %s %.2f)" % [lod, pair, worst])


## WCAG contrast ratio (relative luminance of linearised sRGB).
func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance() + 0.05
	var lb := b.srgb_to_linear().get_luminance() + 0.05
	return maxf(la, lb) / minf(la, lb)


func test_readable_on_every_territory_colour() -> void:
	var outline := Color("#1c1a17")
	for c: Color in TERRITORY:
		# Either the light body or the dark contour must stand out clearly from the territory.
		var best := maxf(_contrast(StructureLayer.BODY, c), _contrast(outline, c))
		check(best >= 3.0, "symbol separates from territory %s (%.1f)" % [c.to_html(false), best])
		# The light body must always contrast with the contour around it.
		check(_contrast(StructureLayer.BODY, outline) >= 7.0, "body vs contour")
		# Owner accent details stay dark enough to read on the light body.
		check(_contrast(StructureLayer.BODY, StructureLayer.detail_color(c)) >= 3.0, "detail of owner %s readable" % c.to_html(false))


func test_size_follows_zoom_with_a_minimum() -> void:
	var prev := 0.0
	for z: float in [0.3, 0.8, 1.0, 2.0, 3.2, 5.0, 10.0, 40.0]:
		var px := StructureLayer.symbol_px_for(z)
		check(px >= StructureLayer.MIN_PX, "never below the minimum at zoom %.1f" % z)
		check(px <= StructureLayer.MAX_PX, "capped at zoom %.1f" % z)
		check(px >= prev, "grows with zoom")
		prev = px
	check(StructureLayer.symbol_px_for(3.2) >= 24.0, "normal play zoom shows a full-size icon")
	check_eq(StructureLayer.lod_for(StructureLayer.symbol_px_for(1.0)), "far", "far LOD when zoomed out")
	check_eq(StructureLayer.lod_for(StructureLayer.symbol_px_for(3.2)), "full", "full LOD at play zoom")
	check_eq(StructureLayer.lod_for(StructureLayer.symbol_px_for(10.0)), "near", "near LOD up close")


func test_overlapping_buildings_are_grouped_not_shrunk() -> void:
	var m := TestMaps.rect(200, 120)
	var sim := TestMaps.sim(m, 0, true)
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(60, 60)))
	sim._start_playing()
	for y in range(10, 110):
		for x in range(10, 190):
			sim.st.set_owner(m.tile_at(x, y), sim.player_id)
	var ss := sim.structures
	var tiles := [m.tile_at(50, 50), m.tile_at(56, 50), m.tile_at(53, 55), m.tile_at(150, 90)]
	var kinds := [Rules.B_FACTORY, Rules.B_CITY, Rules.B_DEFENSE, Rules.B_PORT]
	for i in tiles.size():
		var s := StructureSystem.Structure.new()
		s.id = ss.structs.size()
		s.kind = kinds[i]
		s.owner = sim.player_id
		s.tile = tiles[i]
		s.active_levels = 1
		ss.structs.append(s)
		sim.st.set_struct_at(s.tile, s.id)
		ss._grid_add(s)
	var layer := StructureLayer.new()
	var cam := MapCamera.new()
	layer.sim = sim
	layer.cam = cam
	cam.zoom = Vector2.ONE * 1.0
	var groups := layer.layout(Rect2(0, 0, 200, 120))
	check_eq(groups.size(), 2, "three close buildings form one group, the far one stays alone")
	var big: Array = groups[0] if int(groups[0][1]) == 3 else groups[1]
	check_eq(int(big[1]), 3, "group counts its members")
	check_eq((big[0] as StructureSystem.Structure).kind, Rules.B_CITY, "the most important building represents the group")
	layer.selected = 2
	groups = layer.layout(Rect2(0, 0, 200, 120))
	var reps := groups.map(func(g: Array) -> int: return (g[0] as StructureSystem.Structure).id)
	check(reps.has(2), "the selected building is always drawn itself")
	cam.zoom = Vector2.ONE * 8.0
	check_eq(layer.layout(Rect2(0, 0, 200, 120)).size(), 4, "zoomed in, every building is separate")
	layer.free()
	cam.free()
