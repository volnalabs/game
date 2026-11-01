class_name ResearchPlanner
extends RefCounted
## Which technology to research next (docs/ai/AI_DESIGN.md §13). Branch preference comes from the
## personality (research_order); the situation adds weight (threatened → defence, at war →
## military, money trouble → economy, coast → logistics) scaled by the difficulty's
## exposure_weight; mistake_rate adds noise. Cheaper techs of the same appeal come first.


static func _hash01(x: int) -> float:
	var h := (x * 2654435761) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 100000) / 100000.0


static func act(bot: StrategicAI) -> void:
	var sim := bot.sim
	var id := bot.id
	if sim.research.current(id) != "":
		return
	var order: Array = bot.pers.get("research_order", ResearchSystem.tree()["branches"])
	var aware := float(bot.diff.get("exposure_weight", 1.0))
	var noise := float(bot.diff.get("mistake_rate", 0.0))
	var st := sim.st
	var threat := 0.0
	for o: int in bot.threats:
		threat = maxf(threat, float(bot.threats[o]))
	var at_war := sim.attacks.outgoing(id).any(func(a: AttackSystem.Attack) -> bool: return a.target > 0)
	var poor := st.o_income[id] - st.o_upkeep[id] < 0.0
	var best := ""
	var best_u := -INF
	for t: Dictionary in ResearchSystem.techs():
		var tid := String(t["id"])
		if not sim.research.available(id, tid):
			continue
		var br := String(t["branch"])
		var idx := order.find(br)
		# Weapons rank one step below the military branch (personalities list five classic branches).
		if br == "weapons":
			var mi := order.find("military")
			idx = (mi if mi >= 0 else 3) + 1
		var u := 5.0 - float(idx if idx >= 0 else 4)
		match br:
			"defense":
				u += aware * clampf(threat, 0.0, 2.0)
			"military":
				u += aware * (1.5 if at_war else 0.0)
			"economy":
				u += aware * (2.0 if poor else 0.0)
			"logistics":
				u += aware * (0.8 if bot.has_coast else 0.0) * float(bot.pers.get("naval", 1.0))
			"weapons":
				# Weapons come after the basics: for a warlike state at war, or in answer to rivals' weapons.
				u += aware * (1.0 if at_war else 0.0) * (float(bot.pers.get("war_appetite", 1.0)) - 0.6)
				# The arms race picks up later in a match.
				if sim.elapsed_seconds() > 900.0:
					u += aware * 0.5 * float(bot.pers.get("war_appetite", 1.0))
		if tid == "air_defence":
			for o: int in bot.perception.neighbors:
				if st.bowned(o, Rules.B_SILO) > 0:
					u += aware * 2.0
					break
		# Early on everyone wants income first.
		if br == "economy" and sim.elapsed_seconds() < 600.0:
			u += 1.5
		u -= float(t["cost"]) / 150.0
		# Noise from a hash, not the bot's RNG: research choices must not reshuffle the bot's
		# other random decisions.
		u += (_hash01(id * 7919 + st.tick * 31 + tid.hash()) * 2.0 - 1.0) * noise * 6.0
		if u > best_u:
			best_u = u
			best = tid
	if best != "":
		bot.submit(Commands.research(id, best))
		bot.log.add(st.tick, "research", -1, {"tech": best, "u": best_u})
