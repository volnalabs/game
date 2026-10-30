class_name NavalPlanner
extends RefCounted
## Naval landings: samples coastal tiles of the water bodies the bot touches, scores free islands
## and enemy shores with the same forecast as land attacks (plus travel distance), and launches a
## transport when the best landing is worth it. Matters most on archipelago maps.


## Water bodies where the bot has a coast (sampled from its border, then its spawn area).
static func my_bodies(bot: StrategicAI) -> Array[int]:
	var st := bot.sim.st
	var out: Array[int] = []
	var t := st.o_border_head[bot.id]
	var n := 0
	while t >= 0 and n < 4000:
		var b := st.map.coast_body[t]
		if b > 0 and not out.has(b):
			out.append(b)
		t = st.bnext[t]
		n += 1
	return out


static func best_landing(bot: StrategicAI) -> Dictionary:
	var sim := bot.sim
	var st := sim.st
	if st.o_boats[bot.id] >= sim.naval.max_boats() or st.o_supplies[bot.id] < float(sim.rules.n["boat_supplies"]):
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
			var dist := Vector2(t % st.W, t / st.W).distance_to(c)
			var u := 0.0
			var reason := ""
			if o == 0:
				# A free shore: value the island (or coast) we can grab.
				var lm := st.map.landmass[t]
				var size := float(st.map.landmass_sizes[lm]) if lm > 0 else 50.0
				var grab := minf(size, send / maxf(CombatMath.neutral_loss(sim.rules, 80.0, Rules.KIND_NATION), 1.0))
				u = grab * worth * float(bot.pers["expansion"]) - grab * 16.0
				reason = "free_shore"
			else:
				var their := bot.perception.guess_troops(o)
				var dens := their / maxf(1.0, float(st.o_tiles[o]))
				var curve := BattleForecaster.player_curve(sim.rules, {
					"att_tiles": float(st.o_tiles[bot.id]), "troops": send, "def_troops": their,
					"def_tiles": float(st.o_tiles[o]), "def_kind": st.o_kind[o], "border": 6.0,
					"mag": 90.0, "cost": 18.0, "steps": 8})
				var f := BattleForecaster.sample(curve, send)
				u = float(f["captured"]) * worth - send * (1.0 + (1.0 - bot.fill()) * 0.6) + float(f["killed"]) * 0.3
				if o == bot.perception.leader:
					u += float(bot.pers["coalition"]) * 0.2 * send
				if dens > 200.0:
					u -= send * 0.3
				reason = "overseas_war"
			u *= float(bot.pers["naval"]) / (1.0 + dist / 300.0)
			if u > 0.0 and (best.is_empty() or u > float(best["u"])):
				best = {"tile": t, "owner": o, "u": u, "troops": send, "reason": reason}
	return best


static func act(bot: StrategicAI) -> bool:
	var best := best_landing(bot)
	if best.is_empty():
		return false
	bot.submit(Commands.boat(bot.id, int(best["tile"]), float(best["troops"])))
	bot.log.add(bot.sim.st.tick, "boat", int(best["owner"]), {"troops": best["troops"], "u": best["u"], "reason": best["reason"]})
	return true
