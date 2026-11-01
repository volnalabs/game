extends TestCase
## Map data derivation and the map registry.


func test_synthetic_split_map() -> void:
	var m := TestMaps.rect(40, 20, true)
	check_eq(m.landmass_sizes.size() - 1, 2, "two islands")
	check_eq(m.water_body_sizes.size() - 1, 1, "one connected sea")
	check(m.coast_tiles.size() > 0)
	check_eq(m.coast_by_body.size(), 1)
	var c := m.tile_at(5, 10)
	check_eq(m.land[c], 1)
	check_eq(m.coastal[m.tile_at(2, 10)], 1, "edge land is coastal")


func test_registry_lists_every_map_dir() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var ids: Array = []
	for d: MapDefinition in reg.all():
		ids.append(d.id)
	for id in ["earth", "pelagia", "avaris", "shattered_worlds", "europe", "asia", "africa", "north_america", "south_america"]:
		check(ids.has(id), "map %s registered" % id)
	var earth: MapDefinition = reg.get_map("earth")
	check_eq(earth.nations.size(), 71)
	check(earth.display_name("ru") == "Земля")


func test_earth_loads_with_expected_geography() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var m := MapLoader.load_map(reg.get_map("earth"))
	check_eq(m.width, 2000)
	check_eq(m.height, 1000)
	check_eq(m.land_count, 689018, "land tiles as in the original World map")
	check_eq(m.continent_count(), 5)
	check(m.island_count() > 50, "many islands")


func test_every_registered_map_loads() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	for d: MapDefinition in reg.all():
		var m := MapLoader.load_map(d)
		check(m != null and m.land_count > 1000, "%s loads" % d.id)
		check_eq(m.width, d.width, "%s width" % d.id)
		for n: Dictionary in d.nations:
			var t := m.tile_at(int(n["x"]), int(n["y"]))
			check(t >= 0, "%s nation inside the map" % d.id)
