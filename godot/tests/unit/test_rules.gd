extends TestCase
## Balance formulas (data/rules/default_rules.json, scripts/rules/*.gd).

var r: Rules


func before_each() -> void:
	r = Rules.for_k(1.0)


func test_troop_cap_matches_original_formula() -> void:
	# 2 * (tiles^0.6 * 1000 + 50000) + cities * 250000 (RoWorld Rules.luau:133).
	check_near(r.troop_cap(Rules.KIND_NATION, 0, 0), 100000.0, 0.01)
	check_near(r.troop_cap(Rules.KIND_NATION, 1000, 0), 2.0 * (pow(1000.0, 0.6) * 1000.0 + 50000.0), 0.01)
	check_near(r.troop_cap(Rules.KIND_NATION, 1000, 2), 2.0 * (pow(1000.0, 0.6) * 1000.0 + 50000.0) + 500000.0, 0.01)
	check_near(r.troop_cap(Rules.KIND_TRIBE, 1000, 0), r.troop_cap(Rules.KIND_NATION, 1000, 0) / 3.0, 0.01)


func test_growth_peaks_mid_cap_and_stops_at_cap() -> void:
	var cap := 500000.0
	check(r.troop_growth(Rules.KIND_NATION, 0.4 * cap, cap) > r.troop_growth(Rules.KIND_NATION, 0.05 * cap, cap), "growth at 40% > at 5%")
	check(r.troop_growth(Rules.KIND_NATION, 0.4 * cap, cap) > r.troop_growth(Rules.KIND_NATION, 0.9 * cap, cap), "growth at 40% > at 90%")
	check_near(r.troop_growth(Rules.KIND_NATION, cap, cap), 0.0, 0.001, "no growth at cap")
	check(r.troop_growth(Rules.KIND_NATION, cap * 1.2, cap) < 0.0, "troops above cap snap down")


func test_gold_income_grows_sublinearly_with_territory() -> void:
	var small := r.gold_income(Rules.KIND_NATION, 1000.0, 0, 0.0, 0)
	var big := r.gold_income(Rules.KIND_NATION, 100000.0, 0, 0.0, 0)
	check(big > small, "more land, more gold")
	check(big < small * 100.0 / 5.0, "100x the land gives far less than 100x the gold")
	check_near(r.gold_income(Rules.KIND_NATION, 1000.0, 0, 0.0, 5), small * 1.5, 0.01, "factory bonus capped at +50%")
	check_near(r.gold_income(Rules.KIND_NATION, 1000.0, 0, 0.0, 9), small * 1.5, 0.01, "cap holds")


func test_upkeep_only_above_free_share() -> void:
	var cap := 400000.0
	var free: float = r.e["upkeep_free_share"]
	check_near(r.upkeep(cap * free, cap), 0.0, 0.0001)
	check(r.upkeep(cap, cap) > 0.0, "a full army costs gold")


func test_building_costs() -> void:
	check_near(r.building_cost(Rules.B_CITY, 0), 125000.0, 0.1)
	check_near(r.building_cost(Rules.B_CITY, 1), 250000.0, 0.1)
	check_near(r.building_cost(Rules.B_CITY, 10), 1000000.0, 0.1, "capped")
	check_near(r.building_cost(Rules.B_DEFENSE, 0), 50000.0, 0.1)
	check_near(r.building_cost(Rules.B_DEFENSE, 2), 150000.0, 0.1)
	check_near(r.building_cost(Rules.B_DEFENSE, 9), 250000.0, 0.1, "capped")
	check_eq(r.building_index("port"), Rules.B_PORT)


func test_k_lin_scales_distances() -> void:
	var r2 := Rules.for_k(2.0)
	check_near(r2.spawn_radius, r.spawn_radius / 2.0, 0.001)
	check_near(r2.defense_radius(), r.defense_radius() / 2.0, 0.001)
	check_eq(r2.max_tiles_per_tick, int(floor(572.0 / 4.0)))
