class_name AttackPlanner
extends RefCounted
## Utility of attacking a target with N troops (docs/ai/AI_DESIGN.md §6):
##   U = (captured x tile_worth x w_expand + killed x weaken_worth + annex bonus
##        + opportunism + grudge + coalition) x war_appetite - losses x troop_cost - exposure
## The forecast uses the same combat formulas as the simulation, fed with estimates.


## Marginal worth of one more tile, in troops (troop cap and income it brings).
static func tile_worth(tiles: int) -> float:
	return 25.0 + 600.0 * pow(maxf(float(tiles), 1.0), -0.4)


static func curve_for(bot: StrategicAI, target: int, n_max: float) -> Dictionary:
	var nv: AIPerception.NeighborView = bot.perception.neighbors.get(target)
	if nv == null:
		return {}
	var st := bot.sim.st
	return BattleForecaster.player_curve(bot.sim.rules, {
		"att_tiles": float(st.o_tiles[bot.id]), "att_kind": st.o_kind[bot.id], "troops": n_max,
		"def_troops": nv.est_troops, "def_tiles": float(nv.tiles), "def_kind": nv.kind,
		"border": float(nv.contact), "mag": nv.avg_mag(), "cost": nv.avg_cost(),
		"defended_share": nv.defended_share, "steps": int(bot.diff["forecast_steps"]),
	})


## Utility of sending `troops` against `target` (0 = unclaimed land). `curve` may be passed in
## to avoid recomputing the forecast.
static func evaluate(bot: StrategicAI, target: int, troops: float, curve: Dictionary = {}) -> Dictionary:
	var sim := bot.sim
	var st := sim.st
	var r := sim.rules
	var p := bot.perception
	var pers := bot.pers
	var worth := tile_worth(st.o_tiles[bot.id])
	var troop_cost := 1.0 + (1.0 - bot.fill()) * 0.6
	if target == 0:
		if p.free_contact == 0:
			return {"u": -1.0, "reason": "no_free_land", "troops": troops}
		var free := float(maxi(p.free_estimate, p.free_contact))
		var f := BattleForecaster.vs_neutral(r, troops, p.free_mag, st.o_kind[bot.id], free)
		f["u"] = float(f["captured"]) * worth * float(pers["expansion"]) - float(f["loss"]) * troop_cost
		f["troops"] = troops
		f["reason"] = "expand"
		return f
	var nv: AIPerception.NeighborView = p.neighbors.get(target)
	if nv == null:
		return {"u": -1.0, "reason": "not_neighbor", "troops": troops}
	if curve.is_empty():
		curve = curve_for(bot, target, troops)
	var fc := BattleForecaster.sample(curve, troops)
	var rel: Dictionary = bot.relation(target)
	var threat: float = bot.threats.get(target, 0.0)
	var value_mult := clampf(nv.avg_value(), 0.3, 1.6)
	var gain: float = float(fc["captured"]) * worth * value_mult * float(pers["expansion"])
	var weaken: float = float(fc["killed"]) * (0.25 + 0.6 * minf(threat, 1.5))
	var annex_bonus := 0.0
	if fc["annex"]:
		annex_bonus = 0.25 * troops + float(nv.tiles) * 2.0
	var opp := 0.0
	var war_load := nv.war_out + nv.war_in
	if war_load > 0.0:
		opp = float(pers["opportunism"]) * float(bot.diff["opportunism_detect"]) \
			* minf(1.0, war_load / maxf(nv.est_troops, 1.0)) * 0.25 * troops
	var grudge: float = float(rel["grudge"]) * float(pers["grudge"]) * 0.1 * troops
	var coalition := 0.0
	if target == p.leader:
		coalition = float(pers["coalition"]) * 0.2 * troops
	var losses: float = float(fc["loss"]) * troop_cost
	var home := bot.troops() - troops
	var danger := 0.0
	for o: int in p.neighbors:
		if o != target:
			danger += ThreatAssessment.danger_from(bot, o)
	var exposure := maxf(0.0, danger - home) * 0.6 * float(bot.diff["exposure_weight"]) * (1.0 - float(pers["risk_tolerance"]))
	var u: float = (gain + weaken + annex_bonus + opp + grudge + coalition) * float(pers["war_appetite"]) - losses - exposure
	var grace := false
	if target == sim.player_id and sim.elapsed_seconds() * 10.0 < float(bot.diff["player_grace_ticks"]) and float(rel["grudge"]) <= 0.0:
		u = u * 0.25 - 0.05 * troops if u > 0.0 else u
		grace = true
	var reason := "ok"
	if u <= 0.0:
		if grace:
			reason = "player_grace"
		elif exposure > losses * 0.5 and exposure > gain * 0.5:
			reason = "exposed_to_threats"
		elif nv.defended_share > 0.4:
			reason = "target_fortified"
		elif float(fc["captured"]) < 5.0:
			reason = "insufficient_troops"
		else:
			reason = "loss_exceeds_value"
	elif opp > 0.25 * gain:
		reason = "weak_neighbor_at_war"
	elif coalition > 0.0:
		reason = "contain_leader"
	elif float(rel["grudge"]) > 0.3:
		reason = "retaliation"
	fc["u"] = u
	fc["troops"] = troops
	fc["reason"] = reason
	fc["exposure"] = exposure
	return fc


static func size_fractions(bot: StrategicAI) -> Array:
	match int(bot.diff["size_candidates"]):
		3:
			return [0.95, 0.65, 0.35]
		5:
			return [0.95, 0.75, 0.55, 0.35, 0.2]
	return [1.0, 0.85, 0.7, 0.58, 0.46, 0.35, 0.25, 0.15]


## Tries several attack sizes (one forecast) and returns the best evaluation (with "troops").
static func best_size(bot: StrategicAI, target: int, available: float) -> Dictionary:
	if available < 100.0:
		return {}
	var curve := {} if target == 0 else curve_for(bot, target, available)
	var best: Dictionary = {}
	for f: float in size_fractions(bot):
		var n := available * f
		if n < 100.0:
			continue
		var e := evaluate(bot, target, n, curve)
		if best.is_empty() or float(e["u"]) > float(best["u"]):
			best = e
	return best


## Land options ranked by utility (best first).
static func rank_targets(bot: StrategicAI, available: float) -> Array:
	var out: Array = []
	for o: int in bot.perception.neighbors:
		if not bot.sim.st.is_alive(o):
			continue
		var nv: AIPerception.NeighborView = bot.perception.neighbors[o]
		if nv.contact < 2:
			continue
		var e := best_size(bot, o, available)
		if not e.is_empty():
			e["target"] = o
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u"]) > float(b["u"]))
	return out
