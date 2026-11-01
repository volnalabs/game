class_name AttackPlanner
extends RefCounted
## Utility of attacking a target with N troops (docs/ai/AI_DESIGN.md §6):
##   U = (captured x tile_worth x w_expand + killed x weaken_worth + annex bonus
##        + opportunism + grudge + coalition) x war_appetite - losses x troop_cost - exposure
## The forecast uses the same combat formulas as the simulation, fed with estimates.


## Marginal worth of one more tile, in troops (troop cap and income it brings).
static func tile_worth(tiles: int) -> float:
	return 25.0 + 600.0 * pow(maxf(float(tiles), 1.0), -0.4)


## Value of one troop spent: troops regrow (fastest around 40 % of the cap), land stays. A troop
## costs the share of the planning horizon needed to regrow the `n` troops sent, so a state
## with fast growth can afford bold attacks and an exhausted one cannot.
const REGROW_HORIZON := 1500.0


static func troop_cost(bot: StrategicAI, n: float) -> float:
	var st := bot.sim.st
	var r := bot.sim.rules
	var cap := bot.cap()
	var after := maxf(0.0, bot.troops() - n)
	var g := maxf(r.troop_growth(st.o_kind[bot.id], (after + bot.troops()) * 0.5, cap), 1.0)
	var c := clampf(n / g / REGROW_HORIZON, 0.2, 1.5)
	# An army at its cap does not grow and costs upkeep: troops above ~85 % of the cap are
	# nearly free to spend.
	if bot.fill() > 0.85:
		c *= clampf((1.0 - bot.fill()) / 0.15, 0.25, 1.0)
	return c


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
	var troop_cost := AttackPlanner.troop_cost(bot, troops)
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
	# Learned correction from earlier attacks on this target.
	var eff: float = rel.get("eff", 1.0)
	if eff < 0.999 or eff > 1.001:
		fc["captured"] = float(fc["captured"]) * eff
		fc["killed"] = float(fc["killed"]) * eff
		if eff < 0.7:
			fc["annex"] = false
	var threat: float = bot.threats.get(target, 0.0)
	var value_mult := clampf(nv.avg_value(), 0.3, 1.6)
	var gain: float = float(fc["captured"]) * worth * value_mult * float(pers["expansion"])
	# Killed enemies regrow too: worth a share of a troop, more when the target threatens us.
	var weaken: float = float(fc["killed"]) * (0.1 + 0.25 * minf(threat, 1.6))
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
	# The target itself may strike back with what survives the attack.
	danger += maxf(0.0, nv.est_troops - float(fc["killed"])) * 0.5
	# Its allies may answer its call for help: a neighbour of ours can attack us, a distant one can
	# send troops. Seeing this is part of diplomatic insight (difficulty).
	danger += ally_risk(bot, target)
	var exposure := maxf(0.0, danger - home) * 0.25 * float(bot.diff["exposure_weight"]) * (1.0 - float(pers["risk_tolerance"]))
	var u: float = (gain + weaken + annex_bonus + opp + grudge + coalition) * float(pers["war_appetite"]) - losses - exposure
	# Stalemate pressure: a full army that has not attacked for a long time accepts harder fights.
	var stagnation := 0.0
	if bot.fill() > 0.9 and st.tick - bot.last_offense > 1200:
		stagnation = minf(1.0, float(st.tick - bot.last_offense - 1200) / 1800.0) * 0.25 * troops
		u += stagnation
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
	elif stagnation > 0.0 and u < stagnation:
		reason = "break_stalemate"
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


## Troops the target's allies could throw at us if it calls them for help (weighted by insight).
static func ally_risk(bot: StrategicAI, target: int) -> float:
	var dip := bot.sim.diplomacy
	var allies := dip.allies_of(target)
	if allies.is_empty():
		return 0.0
	var cfg := AIProfile.diplomacy()
	var p := bot.perception
	var risk := 0.0
	for a in allies:
		if a == bot.id or not dip.can_attack(a, bot.id):
			continue
		if p.neighbors.has(a):
			risk += (p.neighbors[a] as AIPerception.NeighborView).est_troops * float(cfg.get("ally_help_risk", 0.35))
		else:
			risk += p.guess_troops(a) * float(cfg.get("ally_far_risk", 0.1))
	return risk * float(bot.diff.get("diplomacy_insight", 0.7))


## Land options ranked by utility (best first).
static func rank_targets(bot: StrategicAI, available: float) -> Array:
	var out: Array = []
	for o: int in bot.perception.neighbors:
		if not bot.sim.st.is_alive(o):
			continue
		var nv: AIPerception.NeighborView = bot.perception.neighbors[o]
		if nv.contact < 2 or nv.partner() or not bot.may_attack(o):
			continue
		var e := best_size(bot, o, available)
		if not e.is_empty():
			e["target"] = o
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["u"]) > float(b["u"]))
	return out
