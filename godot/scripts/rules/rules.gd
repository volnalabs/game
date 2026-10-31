class_name Rules
extends RefCounted
## Balance data loaded from data/rules/default_rules.json and data/buildings/buildings.json, scaled
## to one map's tile size (k_lin). Every number in the JSON is in "full-size tiles"; one map tile is
## k_lin full-size tiles across, so distances are divided by k_lin and tile counts multiplied by
## k_area = k_lin^2 (same convention as RoWorld's Rules.luau:8-70).

const RULES_PATH := "res://data/rules/default_rules.json"
const WEAPONS_PATH := "res://data/weapons/weapons.json"
const BUILDINGS_PATH := "res://data/buildings/buildings.json"

# Terrain codes (map_data.gd mirrors these).
const T_DEEP := 0
const T_SHALLOW := 1
const T_LAKE := 2
const T_PLAINS := 3
const T_FOREST := 4
const T_HILLS := 5
const T_MOUNTAIN := 6
const T_DESERT := 7
const T_TUNDRA := 8
const T_ICE := 9

# Owner kinds.
const KIND_NONE := -1
const KIND_HUMAN := 0
const KIND_NATION := 1
const KIND_TRIBE := 2

# Building kinds (index into kinds[] of buildings.json, kept in this order).
const B_CITY := 0
const B_PORT := 1
const B_FACTORY := 2
const B_DEFENSE := 3
const B_SAM := 4
const B_SILO := 5
const B_RESEARCH := 6
const B_RADAR := 7
const B_AIRBASE := 8
const B_ACADEMY := 9
const B_LOGISTICS := 10
const B_COMMAND := 11
const B_BUNKER := 12
const B_POWER := 13
const B_NAVAL_BASE := 14
## Stride of the per-owner building arrays (SimState.o_blevels / o_bowned); the real number of
## kinds comes from data/buildings/buildings.json (building_count()).
const MAX_BUILDING_KINDS := 16

var raw: Dictionary
var buildings_raw: Dictionary
var k_lin: float = 1.0
var k_area: float = 1.0
var tick_rate: int = 10
var max_owners: int = 512

# Terrain tables (index = terrain code).
var t_mag: PackedFloat32Array
var t_cost: PackedFloat32Array
var t_prio: PackedFloat32Array
var t_value: PackedFloat32Array
var river_mag_mult: float
var river_cost_mult: float
var river_value_add: float
var coast_value_add: float

# Spawn.
var spawn_radius: float
var start_troops: float
var start_gold: float
var start_supplies: float
var tribe_start_troops: float
var tribe_min_dist: float
var nation_jitter: float
var countdown_ticks: int

# Attack.
var a: Dictionary
var default_ratio: float
var annex_below_tiles: float
var max_tiles_per_tick: int
var retreat_keep: float
var retreat_delay_ticks: int

# Economy and naval sections, used by name.
var e: Dictionary
var n: Dictionary
var victory_defaults: Dictionary
## Diplomacy numbers (default_rules.json "diplomacy"; convoy_speed already in this map's tiles).
var dip: Dictionary

# Buildings.
var b_kinds: Array = []
var b_min_dist: float
var b_search_radius: float
var b_port_search: float
var b_ids: PackedStringArray

# Weapons and air defence (data/weapons/weapons.json), distances already in this map's tiles.
var weapons_raw: Dictionary
## Weapon definitions (scaled copies): id, launcher, requires, cost, supplies, range, radius,
## radius_inner, speed, flight, launch_delay, intercept, threat, effect.
var w_list: Array[Dictionary] = []
var w_ids: PackedStringArray
var w_launchers: Dictionary = {}
var w_sam: Dictionary = {}
var w_fallout: Dictionary = {}


static var _cache: Dictionary = {}


## Shared, cached Rules for a map scale.
static func for_k(k: float) -> Rules:
	var key := snappedf(k, 0.0001)
	if not _cache.has(key):
		var r := Rules.new()
		r._load(key)
		_cache[key] = r
	return _cache[key]


static func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Rules: cannot parse %s" % path)
		return {}
	return parsed


func _load(k: float) -> void:
	raw = _read_json(RULES_PATH)
	buildings_raw = _read_json(BUILDINGS_PATH)
	k_lin = maxf(k, 0.01)
	k_area = k_lin * k_lin
	tick_rate = int(raw.get("tick_rate", 10))
	max_owners = int(raw.get("max_owners", 512))
	var t: Dictionary = raw["terrain"]
	t_mag = PackedFloat32Array(t["mag"])
	t_cost = PackedFloat32Array(t["tile_cost"])
	t_prio = PackedFloat32Array(t["priority_mag"])
	t_value = PackedFloat32Array(t["value"])
	river_mag_mult = t["river_mag_mult"]
	river_cost_mult = t["river_cost_mult"]
	river_value_add = t["river_value_add"]
	coast_value_add = t["coast_value_add"]
	var s: Dictionary = raw["spawn"]
	spawn_radius = float(s["radius"]) / k_lin
	start_troops = s["start_troops"]
	start_gold = s["start_gold"]
	start_supplies = s["start_supplies"]
	tribe_start_troops = s["tribe_start_troops"]
	tribe_min_dist = float(s["tribe_min_dist"]) / k_lin
	nation_jitter = float(s["nation_jitter"]) / k_lin
	countdown_ticks = int(s["countdown_ticks"])
	a = raw["attack"]
	default_ratio = a["default_ratio"]
	annex_below_tiles = a["annex_below_tiles"]
	max_tiles_per_tick = maxi(1, int(floor(float(a["max_tiles_per_tick"]) / k_area)))
	retreat_keep = a["retreat_keep"]
	retreat_delay_ticks = int(a["retreat_delay_ticks"])
	e = raw["economy"]
	n = raw["naval"]
	victory_defaults = raw["victory_defaults"]
	dip = raw.get("diplomacy", {}).duplicate()
	dip["convoy_speed"] = float(dip.get("convoy_speed", 4.0)) / k_lin
	b_kinds = buildings_raw["kinds"]
	b_min_dist = float(buildings_raw["min_distance"]) / k_lin
	b_search_radius = float(buildings_raw["search_radius"]) / k_lin
	b_port_search = float(buildings_raw["port_search_manhattan"]) / k_lin
	b_ids = PackedStringArray()
	for kd: Dictionary in b_kinds:
		b_ids.append(kd["id"])
	_load_weapons()


func _load_weapons() -> void:
	weapons_raw = _read_json(WEAPONS_PATH)
	w_launchers = weapons_raw.get("launchers", {})
	w_sam = weapons_raw.get("sam", {}).duplicate()
	w_sam["interceptor_speed"] = float(w_sam.get("interceptor_speed", 12.0)) / k_lin
	w_fallout = weapons_raw.get("fallout", {})
	w_list.clear()
	w_ids = PackedStringArray()
	for wd: Dictionary in weapons_raw.get("weapons", []):
		var w := wd.duplicate(true)
		for key: String in ["range", "radius", "radius_inner", "speed"]:
			if w.has(key):
				w[key] = float(w[key]) / k_lin
		var ef: Dictionary = w["effect"]
		for key: String in ["spread", "warhead_inner", "warhead_outer", "warhead_speed"]:
			if ef.has(key):
				ef[key] = float(ef[key]) / k_lin
		if ef.has("kill_per_tile"):
			ef["kill_per_tile"] = float(ef["kill_per_tile"]) * k_area
		w_list.append(w)
		w_ids.append(String(w["id"]))


func weapon_index(id: String) -> int:
	return w_ids.find(id)


func weapon(i: int) -> Dictionary:
	return w_list[i]


## Building kind a weapon is launched from.
func weapon_launcher_kind(i: int) -> int:
	var l: Dictionary = w_launchers.get(String(w_list[i]["launcher"]), {})
	return building_index(String(l.get("building", "")))


func launcher_reload(i: int) -> int:
	return int(w_launchers.get(String(w_list[i]["launcher"]), {}).get("reload_ticks", 100))


func launcher_charges_per_level(i: int) -> int:
	return int(w_launchers.get(String(w_list[i]["launcher"]), {}).get("charges_per_level", 1))


# ---------------------------------------------------------------------------------------------
# Economy formulas
# ---------------------------------------------------------------------------------------------

## Troop capacity: 2 * (tiles^0.6 * 1000 + 50000) + city_levels * 250000 (tribes / 3).
func troop_cap(kind: int, tiles: int, city_levels: int) -> float:
	var full := maxf(float(tiles) * k_area, 0.0)
	var m: float = 2.0 * (pow(full, e["troop_cap_tile_exp"]) * e["troop_cap_tile_mult"] + e["troop_cap_base"]) \
		+ float(city_levels) * e["troop_cap_city"]
	if kind == KIND_TRIBE:
		m /= e["tribe_cap_div"]
	return m


## Troops added this tick: (10 + troops^0.73 / 4) * (1 - troops / cap), never past the cap.
func troop_growth(kind: int, troops: float, cap: float) -> float:
	var add: float = (float(e["growth_base"]) + pow(maxf(troops, 0.0), e["growth_exp"]) / float(e["growth_div"])) \
		* (1.0 - troops / maxf(cap, 1.0))
	if kind == KIND_TRIBE:
		add *= e["tribe_growth_mult"]
	return minf(troops + add, cap) - troops


## Gold income per tick before the factory multiplier.
func gold_income(kind: int, value: float, city_levels: int, port_trade: float, factory_levels: int) -> float:
	var g: float = float(e["gold_base"]) + float(e["gold_value_mult"]) * pow(maxf(value * k_area, 0.0), e["gold_value_exp"]) \
		+ float(city_levels) * float(e["gold_city"]) + port_trade
	g *= 1.0 + minf(float(factory_levels) * float(e["factory_income_bonus"]), e["factory_income_bonus_max"])
	if kind == KIND_TRIBE:
		g *= e["tribe_gold_mult"]
	return g


func supplies_income(factory_levels: int) -> float:
	return float(e["supplies_base"]) + float(e["supplies_factory"]) * float(factory_levels)


## Gold per tick for the troops above the free share of the cap.
func upkeep(troops: float, cap: float) -> float:
	return maxf(0.0, troops - cap * float(e["upkeep_free_share"])) * float(e["upkeep_per_troop"])


# ---------------------------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------------------------

func building_index(id: String) -> int:
	return b_ids.find(id)


func building_count() -> int:
	return b_kinds.size()


## Research that unlocks a kind ("" = available from the start).
func building_requires(kind: int) -> String:
	return String(b_kinds[kind].get("requires", ""))


## Effect numbers of a kind (buildings.json "effect").
func building_effect(kind: int) -> Dictionary:
	return b_kinds[kind].get("effect", {})


## Building kinds whose zone counts as defended ground (defence posts, bunkers).
func defended_kinds() -> Array[int]:
	var out: Array[int] = [B_DEFENSE]
	for k in building_count():
		if bool(building_effect(k).get("defended", false)) and not out.has(k):
			out.append(k)
	return out


func building_cost(kind: int, owned_levels: int) -> float:
	var d: Dictionary = b_kinds[kind]
	if d["cost_mode"] == "exp":
		var steps := mini(owned_levels, int(d.get("cost_growth_max_n", 4)))
		return minf(float(d["cost_cap"]), float(d["cost_base"]) * pow(float(d["cost_growth"]), steps))
	return minf(float(d["cost_cap"]), float(d["cost_base"]) * float(owned_levels + 1))


func building_supplies(kind: int) -> float:
	return float(b_kinds[kind].get("supplies", 0))


func building_ticks(kind: int) -> int:
	return int(b_kinds[kind]["build_ticks"])


func building_upgradable(kind: int) -> bool:
	return bool(b_kinds[kind]["upgradable"])


func building_coastal(kind: int) -> bool:
	return bool(b_kinds[kind]["coastal"])


## Effect radius of a building kind in tiles (0 when it has none) — what zone overlays draw.
func building_radius(kind: int) -> float:
	return float(b_kinds[kind].get("radius", 0.0)) / k_lin


func defense_radius() -> float:
	return float(b_kinds[B_DEFENSE]["radius"]) / k_lin


func defense_mag_mult() -> float:
	return float(b_kinds[B_DEFENSE]["mag_mult"])


func defense_cost_mult() -> float:
	return float(b_kinds[B_DEFENSE]["cost_mult"])
