class_name TestMaps
extends RefCounted
## Small synthetic maps and matches for tests.


## A W x H map: land (plains) everywhere except a 2-tile ocean frame; optional vertical sea strip
## splitting it into two islands.
static func rect(w: int, h: int, split: bool = false) -> MapData:
	var terr := PackedByteArray()
	terr.resize(w * h)
	var elev := PackedByteArray()
	elev.resize(w * h)
	for y in h:
		for x in w:
			var t := y * w + x
			var water := x < 2 or y < 2 or x >= w - 2 or y >= h - 2
			if split and absi(x - w / 2) <= 3:
				water = true
			terr[t] = Rules.T_DEEP if water else Rules.T_PLAINS
			elev[t] = 0 if water else 60
	return MapData.from_arrays("test_rect_%dx%d_%s" % [w, h, split], w, h, terr, elev)


static func definition(map: MapData, nations: Array = []) -> MapDefinition:
	var d := MapDefinition.new()
	d.id = map.id
	d.category = "generated"
	d.names = {"en": "Test", "ru": "Тест"}
	d.width = map.width
	d.height = map.height
	d.nations = nations
	return d


static func config(bots: int, has_player: bool, seed_value: int = 1, tribes: int = 0) -> MatchConfig:
	var c := MatchConfig.new()
	c.seed = seed_value
	c.bots = bots
	c.tribes = tribes
	c.has_player = has_player
	return c


static func sim(map: MapData, bots: int, has_player: bool, seed_value: int = 1, tribes: int = 0, nations: Array = []) -> Sim:
	return Sim.new(config(bots, has_player, seed_value, tribes), definition(map, nations), map)
