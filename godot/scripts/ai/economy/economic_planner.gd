class_name EconomicPlanner
extends RefCounted
## What to build next (docs/ai/AI_DESIGN.md §7). Each candidate building gets a payback score:
## expected gain over a planning horizon (gold income, troop capacity when the army is near its
## cap, upkeep relief, supplies, protection of a threatened border) divided by its cost, times
## the personality's economy / defence weights. The best affordable one is built; otherwise the
## bot saves for it.

const HORIZON := 6000.0
## Gold has no other use than buildings: build whenever the best option pays back at least this
## share of its cost over the horizon (the real choice is WHICH building, and saving for it).
const MIN_RATIO := 0.08


static func act(bot: StrategicAI) -> void:
	var sim := bot.sim
	var st := sim.st
	var r := sim.rules
	var id := bot.id
	var gold := st.o_gold[id]
	if gold < 40000.0:
		return
	var net := st.o_income[id] - st.o_upkeep[id]
	var buffer := 0.0
	if net < 0.0:
		buffer = -net * 300.0
	var options: Array = []
	var fill := bot.fill()
	var cap := maxf(st.o_cap[id], 1.0)
	var econ: float = bot.pers["economy"]
	# City: income, troop capacity, upkeep relief.
	var pressure := clampf((fill - 0.45) * 2.0, 0.15, 1.0)
	var excess := maxf(0.0, bot.troops() - cap * float(r.e["upkeep_free_share"]))
	var city_v := float(r.e["gold_city"]) * HORIZON * econ \
		+ 250000.0 * pressure * 0.6 \
		+ minf(excess, 125000.0) * float(r.e["upkeep_per_troop"]) * HORIZON
	options.append({"kind": Rules.B_CITY, "value": city_v})
	# Factory: income bonus (capped) and supplies.
	var fl := st.bowned(id, Rules.B_FACTORY)
	if float(fl) * float(r.e["factory_income_bonus"]) < float(r.e["factory_income_bonus_max"]):
		var sup_need := 25.0 if st.o_supplies[id] < 3000.0 else 6.0
		var fact_v := st.o_income[id] * float(r.e["factory_income_bonus"]) * HORIZON * econ \
			+ float(r.e["supplies_factory"]) * HORIZON * sup_need * 0.1
		options.append({"kind": Rules.B_FACTORY, "value": fact_v})
	# Port: trade income, only with a coast.
	if bot.has_coast:
		var port_v := (float(r.e["port_trade_base"]) + 10.0) * HORIZON * econ * float(bot.pers["naval"])
		if st.bowned(id, Rules.B_PORT) == 0:
			port_v *= 1.5
		options.append({"kind": Rules.B_PORT, "value": port_v})
	# Defence post on the border with the main threat.
	var top := 0
	var top_t := 0.0
	for o: int in bot.threats:
		if float(bot.threats[o]) > top_t:
			top_t = bot.threats[o]
			top = o
	if top > 0 and top_t > 0.35:
		var posts := 0
		for s in sim.structures.of_owner(id, Rules.B_DEFENSE):
			posts += 1
		if posts < 2 + st.o_border_count[id] / 400:
			var def_v := minf(top_t, 2.0) * float(bot.pers["defense"]) * 220000.0
			options.append({"kind": Rules.B_DEFENSE, "value": def_v, "threat": top})
	_phase2_options(bot, options, top, top_t)
	var best: Dictionary = {}
	var best_ratio := 0.0
	for o: Dictionary in options:
		var k: int = o["kind"]
		if not sim.structures.unlocked(id, k):
			continue
		# Phase 2 buildings are surplus spending: only with money to spare.
		if k >= Rules.B_RESEARCH and gold < 2.5 * sim.structures.cost(id, k):
			continue
		var c := sim.structures.cost(id, k)
		var ratio: float = float(o["value"]) / maxf(c, 1.0)
		if ratio > best_ratio:
			best_ratio = ratio
			best = o
			best["cost"] = c
	if best.is_empty() or best_ratio < MIN_RATIO:
		return
	var kind: int = best["kind"]
	if gold - buffer < float(best["cost"]) or st.o_supplies[id] < r.building_supplies(kind):
		bot.plan_note = "saving for %s" % r.b_ids[kind]
		return
	var t := BuildPlacement.site(bot, kind, int(best.get("threat", 0)))
	if t < 0:
		if kind == Rules.B_PORT:
			bot.has_coast = false
		return
	bot.submit(Commands.build(id, kind, t))
	bot.log.add(st.tick, "build", -1, {"building": r.b_ids[kind], "u": best_ratio})
	bot.plan_note = ""


## Phase 2 buildings, valued in the same "gain over the horizon" units as the classic ones.
static func _phase2_options(bot: StrategicAI, options: Array, top: int, top_t: float) -> void:
	var sim := bot.sim
	var st := sim.st
	var r := sim.rules
	var id := bot.id
	var econ: float = bot.pers["economy"]
	var war: float = bot.pers.get("war_appetite", 1.0)
	# Only once the classic economy stands (cities and factories pay back fastest).
	if st.blevel(id, Rules.B_CITY) < 3 or st.blevel(id, Rules.B_FACTORY) < 1:
		if top > 0 and top_t > 0.8:
			options.append({"kind": Rules.B_BUNKER, "value": minf(top_t, 2.0) * float(bot.pers["defense"]) * 100000.0, "threat": top})
		return
	var n0 := options.size()
	# Research centre: worth it while there is something left to research.
	var left := 0
	for t: Dictionary in ResearchSystem.techs():
		if not sim.research.has_tech(id, String(t["id"])):
			left += 1
	if left > 3 and st.bowned(id, Rules.B_RESEARCH) < 3:
		options.append({"kind": Rules.B_RESEARCH, "value": 90000.0 * econ * minf(float(left) / 8.0, 1.5)})
	# Academy: cheaper attacks for a warlike state.
	if st.bowned(id, Rules.B_ACADEMY) < 3:
		options.append({"kind": Rules.B_ACADEMY, "value": bot.troops() * 0.04 * 6.0 * war})
	# Logistics hub: faster troop growth.
	if st.bowned(id, Rules.B_LOGISTICS) < 4:
		options.append({"kind": Rules.B_LOGISTICS, "value": maxf(st.o_growth[id], 0.0) * 0.05 * HORIZON * 0.5})
	# Power plant: factories produce more supplies.
	if st.blevel(id, Rules.B_FACTORY) > 0 and st.bowned(id, Rules.B_POWER) < 3:
		options.append({"kind": Rules.B_POWER, "value": float(r.e["supplies_factory"]) * st.blevel(id, Rules.B_FACTORY) * 0.2 * HORIZON * 2.0})
	# Command centre: keeps troops on retreat, faster attacks.
	if st.bowned(id, Rules.B_COMMAND) < 2:
		options.append({"kind": Rules.B_COMMAND, "value": bot.troops() * 0.06 * 4.0 * war})
	# Bunker on the threatened border; radar against landings.
	if top > 0 and top_t > 0.5:
		options.append({"kind": Rules.B_BUNKER, "value": minf(top_t, 2.0) * float(bot.pers["defense"]) * 140000.0, "threat": top})
	if bot.has_coast and st.bowned(id, Rules.B_RADAR) < 2 and top_t > 0.3:
		options.append({"kind": Rules.B_RADAR, "value": 60000.0 * float(bot.pers["defense"])})
	# Airbase for an attacking state; naval base for a seafaring one.
	if st.bowned(id, Rules.B_AIRBASE) < 2:
		options.append({"kind": Rules.B_AIRBASE, "value": bot.troops() * 0.1 * 3.0 * war})
	if bot.has_coast and st.bowned(id, Rules.B_NAVAL_BASE) < 2:
		options.append({"kind": Rules.B_NAVAL_BASE, "value": 70000.0 * float(bot.pers.get("naval", 1.0))})
	for i in range(n0, options.size()):
		options[i]["value"] = float(options[i]["value"]) * 0.5
