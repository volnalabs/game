class_name CombatMath
extends RefCounted
## Combat formulas shared by the simulation (military/attack_system.gd) and the AI's battle
## forecaster (ai/tactics/battle_forecaster.gd). Ported from RoWorld's Rules.luau:594-637 and
## SimAttacks._process_attack (OpenFront's attackLogic), AGPL-3.0.


static func sigmoid(value: float, rate: float, midpoint: float) -> float:
	return 1.0 / (1.0 + exp(-rate * (value - midpoint)))


## ~1 for small territories, 1 - depth for huge ones (logistic in log(full-size tiles)).
static func large_territory_bonus(r: Rules, full_tiles: float, depth: float) -> float:
	var a := r.a
	return 1.0 - depth * sigmoid(log(maxf(full_tiles, 1.0)), a["large_territory_steepness"],
		log(float(a["large_territory_midpoint"])))


## Per-tick constants of an attack against a player: [bonus_loss, bonus_speed].
static func player_bonuses(r: Rules, att_tiles: int, def_tiles: int, border: float) -> Vector2:
	var a := r.a
	var att_full := float(att_tiles) * r.k_area
	var def_full := maxf(float(def_tiles) * r.k_area, 1.0)
	var ldb := large_territory_bonus(r, def_full, a["large_defender_depth"])
	var bonus_l: float = float(a["attacker_loss_base"]) * large_territory_bonus(r, att_full, a["large_attacker_depth"]) * ldb
	var bonus_s: float = large_territory_bonus(r, att_full, a["large_attacker_speed_depth"]) * ldb \
		/ (float(a["speed_cost_divisor"]) * maxf(border, 1.0))
	return Vector2(bonus_l, bonus_s)


## Attacker troops lost per full-size tile of unclaimed land.
static func neutral_loss(r: Rules, mag: float, attacker_kind: int) -> float:
	var per: float = r.a["tribe_neutral_loss_per_mag"] if attacker_kind == Rules.KIND_TRIBE else r.a["neutral_loss_per_mag"]
	return mag * per


## Budget fraction of one full-size tile of unclaimed land.
static func neutral_tile_fraction(r: Rules, tile_cost: float, troops: float, border: float) -> float:
	var a := r.a
	var v := clampf(float(a["neutral_cost_scale"]) * tile_cost / maxf(troops, 1.0), a["neutral_min_cost"], a["neutral_max_cost"])
	return maxf(v / (maxf(border, 1.0) * 2.0), 1e-6)


## Attacker troops lost per full-size tile of a player's land.
## density = defender troops per full-size tile; ratio = defender troops / attack troops.
static func player_loss(r: Rules, mag: float, ratio: float, density: float, bonus_l: float, mag_k: float) -> float:
	return mag * mag_k * clampf(ratio, 0.6, 2.0) * (bonus_l + float(r.a["attacker_loss_per_density"]) * density)


## Budget fraction of one full-size tile of a player's land.
static func player_tile_fraction(tile_cost: float, ratio: float, bonus_s: float) -> float:
	return maxf(clampf(ratio, 0.82, 7.5) * clampf(ratio / 20.0, 1.0, 50.0) * tile_cost * bonus_s, 1e-6)


## Terrain-dependent magnitude and tile cost of a tile, with river and defense-post modifiers.
static func tile_mag_cost(r: Rules, code: int, river: bool, defended: bool) -> Vector2:
	var mag: float = r.t_mag[code]
	var tc: float = r.t_cost[code]
	if river:
		mag *= r.river_mag_mult
		tc *= r.river_cost_mult
	if defended:
		mag *= r.defense_mag_mult()
		tc *= r.defense_cost_mult()
	return Vector2(mag, tc)
