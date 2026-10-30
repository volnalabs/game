class_name ThreatAssessment
extends RefCounted
## Situation evaluation: how dangerous each neighbour is to the bot, from what the bot can see.
## threat = (their troops / my troops) x contact factor x hostility, where hostility grows with
## grudges, an ongoing attack on us, fast growth and being the runaway leader.


## Fills bot.threats ({id: threat}) and returns the highest threat.
static func evaluate(bot: StrategicAI) -> float:
	var p := bot.perception
	var mine := maxf(bot.troops(), 1.0)
	var top := 0.0
	bot.threats.clear()
	for o: int in p.neighbors:
		var nv: AIPerception.NeighborView = p.neighbors[o]
		if nv.kind == Rules.KIND_TRIBE:
			continue
		var rel: Dictionary = bot.relation(o)
		var hostility := 0.35 + float(rel["grudge"])
		if nv.attacking_me > 0.0:
			hostility += 1.0
		hostility += clampf(float(rel["growth"]) * 3.0, 0.0, 0.6)
		if o == p.leader:
			hostility += 0.5
		if o == bot.sim.player_id and p.leader == o:
			hostility += 0.3
		var contact_f := float(nv.contact) / (float(nv.contact) + 20.0)
		var th := nv.est_troops / mine * contact_f * hostility
		bot.threats[o] = th
		top = maxf(top, th)
	return top


## Expected troops a neighbour might throw at us soon (for reserve and exposure).
static func danger_from(bot: StrategicAI, o: int) -> float:
	var nv: AIPerception.NeighborView = bot.perception.neighbors.get(o)
	if nv == null or nv.kind == Rules.KIND_TRIBE:
		return 0.0
	var rel: Dictionary = bot.relation(o)
	var p := 0.12 + 0.5 * float(rel["grudge"]) + clampf(float(rel["growth"]) * 2.0, 0.0, 0.3)
	if nv.attacking_me > 0.0:
		p += 0.4
	if nv.war_out > 0.3 * nv.est_troops:
		p *= 0.6
	return nv.est_troops * minf(p, 1.0)
