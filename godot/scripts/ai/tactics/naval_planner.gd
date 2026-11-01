class_name NavalPlanner
extends RefCounted
## Naval landings: samples coastal tiles of the water bodies the bot touches, scores free islands
## and enemy shores with the same forecast as land attacks (plus travel distance), and launches a
## transport when the best landing is worth it. Matters most on archipelago maps.
## Every candidate is checked with LandingPlanner (the simulation's own planner), so no transport is
## sent on an impossible expedition. Against an overseas state the bot may aim at an inland city
## instead of the beach — only when it lies close to a safe coast (≤ 30 tiles overland) and is worth
## clearly more after the overland distance and sailing time.


## Water bodies where the bot owns coast. A state that owns a whole island has no land border at
## all, so the coast lists of the map are checked (fully for small bodies, sampled for big ones);
## cached for a while.
static func my_bodies(bot: StrategicAI) -> Array[int]:
	var st := bot.sim.st
	if bot.sim.st.tick - bot.bodies_tick < 300 and not bot.bodies_cache.is_empty():
		return bot.bodies_cache
	var out: Array[int] = []
	for b: int in st.map.coast_by_body:
		var list: PackedInt32Array = st.map.coast_by_body[b]
		if list.size() <= 4000:
			for t in list:
				if st.owner[t] == bot.id:
					out.append(b)
					break
		else:
			for _i in 400:
				if st.owner[list[bot.rng.below(list.size())]] == bot.id:
					out.append(b)
					break
	bot.bodies_cache = out
	bot.bodies_tick = st.tick
	return out


static func best_landing(bot: StrategicAI) -> Dictionary:
	var sim := bot.sim
	var st := sim.st
	if st.o_boats[bot.id] >= sim.naval.max_boats(bot.id) or st.o_supplies[bot.id] < float(sim.rules.n["boat_supplies"]):
		return {}
	var bodies := my_bodies(bot)
	if bodies.is_empty():
		return {}
	var samples := int(bot.diff["naval_samples"])
	var c := st.centroid(bot.id)
	var worth := AttackPlanner.tile_worth(st.o_tiles[bot.id])
	var available := maxf(0.0, bot.troops() - DefensePlanner.reserve_needed(bot))
	var send := available * 0.5
	if send < 500.0:
		return {}
	var best: Dictionary = {}
	for b in bodies:
		var list: PackedInt32Array = st.map.coast_by_body.get(b, PackedInt32Array())
		if list.is_empty():
			continue
		for _i in samples:
			var t := list[bot.rng.below(list.size())]
			var o := st.owner[t]
			if o == bot.id:
				continue
			if o > 0 and bot.perception.neighbors.has(o):
				continue  # reachable over land: the land planner handles it
			if o > 0 and not bot.may_attack(o):
				continue
			if _partner_near(bot, t):
				continue  # a partner is advancing there: the shore may be theirs before we land
			var dist := Vector2(t % st.W, t / st.W).distance_to(c)
			var u := 0.0
			var reason := ""
			if o == 0:
				# A free shore: value the island (or coast) we can grab.
				var lm := st.map.landmass[t]
				var size := float(st.map.landmass_sizes[lm]) if lm > 0 else 50.0
				var per := maxf(CombatMath.neutral_loss(sim.rules, 80.0, Rules.KIND_NATION), 1.0)
				var grab := minf(size, send / per)
				u = grab * worth * float(bot.pers["expansion"]) - grab * per * AttackPlanner.troop_cost(bot, grab * per)
				reason = "free_shore"
			else:
				var their := bot.perception.guess_troops(o)
				var dens := their / maxf(1.0, float(st.o_tiles[o]))
				var curve := BattleForecaster.player_curve(sim.rules, {
					"att_tiles": float(st.o_tiles[bot.id]), "troops": send, "def_troops": their,
					"def_tiles": float(st.o_tiles[o]), "def_kind": st.o_kind[o], "border": 6.0,
					"mag": 90.0, "cost": 18.0, "steps": 8})
				var f := BattleForecaster.sample(curve, send)
				u = float(f["captured"]) * worth - send * AttackPlanner.troop_cost(bot, send) + float(f["killed"]) * 0.3
				if o == bot.perception.leader:
					u += float(bot.pers["coalition"]) * 0.2 * send
				if dens > 200.0:
					u -= send * 0.3
				reason = "overseas_war"
			u *= float(bot.pers["naval"]) / (1.0 + dist / 300.0)
			if u > 0.0 and (best.is_empty() or u > float(best["u"])):
				var n := send
				if o == 0:
					var lm2 := st.map.landmass[t]
					var isl := float(st.map.landmass_sizes[lm2]) if lm2 > 0 else 50.0
					n = clampf(isl * 16.0 * 1.3, 500.0, send)
				best = {"tile": t, "owner": o, "u": u, "troops": n, "reason": reason}
	return best


## Whether a treaty partner owns land within 2 tiles of free tile `t`.
static func _partner_near(bot: StrategicAI, t: int) -> bool:
	var st := bot.sim.st
	var x0 := t % st.W
	var y0 := t / st.W
	for dy in range(-2, 3):
		var y := y0 + dy
		if y < 0 or y >= st.H:
			continue
		for dx in range(-2, 3):
			var x := x0 + dx
			if x < 0 or x >= st.W:
				continue
			var o := st.owner[y * st.W + x]
			if o > 0 and o != bot.id and not bot.sim.diplomacy.can_attack(bot.id, o):
				return true
	return false


static func act(bot: StrategicAI) -> bool:
	var best := best_landing(bot)
	if best.is_empty():
		return false
	best = refine(bot, best)
	if best.is_empty():
		return false
	launch(bot, best)
	return true


## Validates the chosen landing with the simulation's planner and, against a state, compares it
## with an inland goal. Returns {} when no landing is possible.
static func refine(bot: StrategicAI, best: Dictionary) -> Dictionary:
	var nv := bot.sim.naval
	var direct := LandingPlanner.plan(nv, bot.id, int(best["tile"]))
	if not direct["ok"]:
		return {}
	var o := int(best["owner"])
	if o <= 0:
		return best
	var goal := LandingPlanner.key_tile(nv, o)
	if goal < 0 or goal == int(best["tile"]):
		return best
	# Only a city within 30 tiles (overland) of a shore is worth aiming past the beach (below). The
	# overland way is never shorter than the straight line, so without any coast of `o` within 30
	# tiles of the goal the rule fails anyway — skip the second plan (each plan searches the sea).
	if bot.sim.structures.of_owner(o, Rules.B_CITY).is_empty() or not _coast_near(bot.sim.st, o, goal, 30):
		return best
	var inland := LandingPlanner.plan(nv, bot.id, goal)
	if not inland["ok"]:
		return best
	var land_len := float(inland["land_len"])
	# Only a city close to the coast is worth aiming past the beach (measured in AI series: a
	# generous inland valuation sent landings too deep and cost the bots land overall).
	if bot.sim.structures.of_owner(o, Rules.B_CITY).is_empty() or land_len > 30.0 or inland["unsafe"]:
		return best
	var u := float(best["u"]) * 1.6 / (1.0 + land_len / 40.0)
	u /= 1.0 + float(inland["eta_ticks"]) / 1200.0
	if u > float(best["u"]) * 1.1:
		var out := best.duplicate()
		out["tile"] = goal
		out["u"] = u
		out["reason"] = "inland_goal"
		return out
	return best


## Whether `o` owns a coastal tile within `r` tiles (straight line) of `t`.
static func _coast_near(st: SimState, o: int, t: int, r: int) -> bool:
	var x0 := t % st.W
	var y0 := t / st.W
	for y in range(maxi(0, y0 - r), mini(st.H, y0 + r + 1)):
		for x in range(maxi(0, x0 - r), mini(st.W, x0 + r + 1)):
			if (x - x0) * (x - x0) + (y - y0) * (y - y0) > r * r:
				continue
			var u := y * st.W + x
			if st.map.coastal[u] == 1 and st.owner[u] == o:
				return true
	return false


static func launch(bot: StrategicAI, best: Dictionary) -> void:
	bot.submit(Commands.boat(bot.id, int(best["tile"]), float(best["troops"])))
	bot.log.add(bot.sim.st.tick, "boat", int(best["owner"]), {"troops": best["troops"], "u": best["u"], "reason": best["reason"]})
