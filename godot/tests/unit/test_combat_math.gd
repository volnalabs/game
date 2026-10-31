extends TestCase
## Combat formulas shared by the simulation and the AI forecaster.

var r: Rules


func before_each() -> void:
	r = Rules.for_k(1.0)


func test_neutral_loss_is_16_per_plains_tile() -> void:
	check_near(CombatMath.neutral_loss(r, r.t_mag[Rules.T_PLAINS], Rules.KIND_NATION), 16.0, 0.001)
	check_near(CombatMath.neutral_loss(r, r.t_mag[Rules.T_PLAINS], Rules.KIND_TRIBE), 8.0, 0.001)


func test_large_territory_bonus_bounds() -> void:
	check_near(CombatMath.large_territory_bonus(r, 1.0, 0.7), 1.0, 0.01, "tiny territory ~1")
	check_near(CombatMath.large_territory_bonus(r, 1e9, 0.7), 0.3, 0.01, "huge territory 1 - depth")


func test_player_loss_grows_with_density_and_ratio() -> void:
	var b := CombatMath.player_bonuses(r, 1000, 1000, 50.0)
	var lo := CombatMath.player_loss(r, 80.0, 1.0, 10.0, b.x, 1.0)
	var hi := CombatMath.player_loss(r, 80.0, 1.0, 200.0, b.x, 1.0)
	check(hi > lo, "denser defence costs more")
	check(CombatMath.player_loss(r, 80.0, 2.0, 10.0, b.x, 1.0) > lo, "stronger defender costs more")
	check_near(CombatMath.player_loss(r, 80.0, 5.0, 10.0, b.x, 1.0), CombatMath.player_loss(r, 80.0, 2.0, 10.0, b.x, 1.0), 0.0001, "ratio clamped at 2")


func test_mountains_and_defense_posts_cost_more() -> void:
	var plain := CombatMath.tile_mag_cost(r, Rules.T_PLAINS, false, false)
	var mount := CombatMath.tile_mag_cost(r, Rules.T_MOUNTAIN, false, false)
	var post := CombatMath.tile_mag_cost(r, Rules.T_PLAINS, false, true)
	var river := CombatMath.tile_mag_cost(r, Rules.T_PLAINS, true, false)
	check(mount.x > plain.x and mount.y > plain.y)
	check_near(post.x, plain.x * 5.0, 0.01)
	check_near(post.y, plain.y * 3.0, 0.01)
	check(river.x > plain.x and river.y > plain.y)


func test_forecaster_agrees_with_formulas() -> void:
	# Neutral: 16 troops per plains tile.
	var f := BattleForecaster.vs_neutral(r, 1600.0, 80.0, Rules.KIND_NATION, 1000.0)
	check_near(float(f["captured"]), 100.0, 0.01)
	# Against a much weaker, small player the attack annexes it.
	var c := BattleForecaster.player_curve(r, {"att_tiles": 2000.0, "troops": 200000.0, "def_troops": 5000.0,
		"def_tiles": 300.0, "border": 40.0, "mag": 80.0, "cost": 16.5, "steps": 30})
	check(bool(BattleForecaster.sample(c, 200000.0)["annex"]), "weak small target gets annexed")
	# Against a fortified, dense player the same troops take far less.
	var c2 := BattleForecaster.player_curve(r, {"att_tiles": 2000.0, "troops": 50000.0, "def_troops": 500000.0,
		"def_tiles": 3000.0, "border": 40.0, "mag": 80.0, "cost": 16.5, "defended_share": 1.0, "steps": 30})
	var s2 := BattleForecaster.sample(c2, 50000.0)
	check(not bool(s2["annex"]))
	check(float(s2["captured"]) < 100.0, "fortified target: few tiles (%.1f)" % float(s2["captured"]))
