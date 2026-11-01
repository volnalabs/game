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
		hostility *= pact_factor(nv.pact)
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
	return nv.est_troops * minf(p, 1.0) * pact_factor(nv.pact)


## How much of a neighbour's threat remains under a pact. A teammate never attacks. An ally or a NAP
## partner stays fully watched: pacts last minutes and can be broken. AI series showed that bots which
## lowered their guard for partners (×0.15 / ×0.3, also only while the pact had time left) kept too
## small a reserve and were punished when the pact ended — hard bots lost their edge over easy ones.
static func pact_factor(pact: String) -> float:
	return 0.0 if pact == "team" else 1.0
