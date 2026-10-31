extends TestCase
## World generator: reproducibility, presets, start positions, authored maps.


func test_same_seed_same_world() -> void:
	var a := MapGenerator.new().generate(GenParams.from_preset("continents", 42, "S"))
	var b := MapGenerator.new().generate(GenParams.from_preset("continents", 42, "S"))
	check_eq(a.map.terrain_hash, b.map.terrain_hash, "terrain bytes identical")
	check_eq(a.starts, b.starts, "start positions identical")
	var c := MapGenerator.new().generate(GenParams.from_preset("continents", 43, "S"))
	check(a.map.terrain_hash != c.map.terrain_hash, "another seed, another world")


func test_presets_meet_their_parameters() -> void:
	for preset: String in GenParams.preset_ids():
		var p := GenParams.from_preset(preset, 7, "S")
		var res := MapGenerator.new().generate(p)
		var share := float(res.map.land_count) / float(res.map.size)
		check(absf(share - p.land_percent) < 0.08, "%s land share %.2f vs %.2f" % [preset, share, p.land_percent])
		check(res.starts.size() >= p.start_positions * 3 / 4, "%s starts %d" % [preset, res.starts.size()])
		check(float(res.stats["fairness"]) > 0.4, "%s fairness %.2f" % [preset, float(res.stats["fairness"])])
		for t in res.starts:
			check_eq(res.map.land[t], 1, "%s start on land" % preset)


func test_archipelago_has_more_landmasses_than_pangaea() -> void:
	var arch := MapGenerator.new().generate(GenParams.from_preset("archipelago", 3, "S"))
	var pan := MapGenerator.new().generate(GenParams.from_preset("pangaea", 3, "S"))
	check(arch.map.landmass_sizes.size() > pan.map.landmass_sizes.size() * 2, "archipelago is fragmented")
	check_eq(pan.map.continent_count(), 1, "pangaea is one continent")


func test_symmetry_mirror() -> void:
	var p := GenParams.from_preset("continents", 9, "S")
	p.symmetry = "mirror"
	var m := MapGenerator.new().generate(p).map
	var diff := 0
	for y in range(0, m.height, 7):
		for x in range(0, m.width / 2, 7):
			if m.land[y * m.width + x] != m.land[y * m.width + (m.width - 1 - x)]:
				diff += 1
	check(diff < 30, "mirror symmetric land (%d mismatches)" % diff)


func test_authored_map_is_reproducible() -> void:
	# Baking data/map_specs/pelagia.json again gives the committed terrain.
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_specs/pelagia.json"))
	var p := GenParams.new()
	p.apply_preset("continents")
	p.seed = int(d["seed"])
	p.width = int(d["width"])
	p.height = int(d["height"])
	p.land_percent = float(d["land_percent"])
	p.roughness = float(d["roughness"])
	p.mountains = float(d["mountains"])
	p.river_density = float(d["river_density"])
	p.start_positions = int(d["start_positions"])
	p.inland_seas = int(d.get("inland_seas", 0))
	p.spec = d["spec"]
	p.climate = d.get("climate", {})
	var res := MapGenerator.new().generate(p)
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var committed := MapLoader.load_map(reg.get_map("pelagia"))
	check_eq(res.map.terrain_hash, committed.terrain_hash, "pelagia terrain identical to the baked file")
