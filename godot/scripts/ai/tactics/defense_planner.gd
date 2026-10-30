class_name DefensePlanner
extends RefCounted
## Reaction to invasions and protection of the borders (docs/ai/AI_DESIGN.md §6):
## counter-attacks cancel the enemy's attack troops 1:1 (simulation rule), so the bot sends what is
## needed to neutralise each noticed invasion (precision by difficulty), strongest first; it
## retreats from its own attacks whose forecast turned bad; it keeps a reserve against threats.


## Troops to keep at home against the visible threats.
static func reserve_needed(bot: StrategicAI) -> float:
	var danger := 0.0
	for o: int in bot.perception.neighbors:
		danger = maxf(danger, ThreatAssessment.danger_from(bot, o))
	var base := bot.troops() * float(bot.pers["reserve"]) * 0.5
	return maxf(base, danger * 0.6 * float(bot.pers["defense"]))


## Counter-attacks. Returns true when it acted.
static func counter(bot: StrategicAI) -> bool:
	var inc := bot.perception.incoming
	if inc.is_empty():
		return false
	var st := bot.sim.st
	var acted := false
	var sorted := inc.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["troops"]) > float(b["troops"]))
	var precision: float = bot.diff["counter_precision"]
	for e: Dictionary in sorted:
		var attacker: int = e["attacker"]
		var their: float = e["troops"]
		if their < maxf(200.0, bot.troops() * 0.01):
			continue
		var mine := bot.troops()
		var own := bot.sim.attacks.find(bot.id, attacker)
		if own != null and own.troops >= their:
			continue
		var need := their * 1.05 * precision - (own.troops if own != null else 0.0)
		if bot.perception.neighbors.has(attacker) and (bot.perception.neighbors[attacker] as AIPerception.NeighborView).kind == Rules.KIND_TRIBE:
			need *= 0.8
		var send := minf(need, mine * 0.85)
		if send < 100.0:
			bot.log.add(st.tick, "refuse", attacker, {"reason": "cannot_counter", "troops": their})
			continue
		bot.submit(Commands.attack_target(bot.id, attacker, send))
		bot.log.add(st.tick, "counter", attacker, {"troops": send, "reason": "invasion %.0f" % their})
		bot.note_attacked_by(attacker, their)
		acted = true
	return acted


## Retreat from own attacks that no longer pay off (Normal / Hard).
static func review_attacks(bot: StrategicAI) -> void:
	if not bool(bot.diff["retreat"]):
		return
	var st := bot.sim.st
	for a in bot.sim.attacks.outgoing(bot.id):
		if a.target == 0 or a.retreat_at > 0 or st.tick - a.start_tick < 40:
			continue
		if not bot.perception.neighbors.has(a.target):
			continue
		var e := AttackPlanner.evaluate(bot, a.target, a.troops)
		# Gains so far per troop spent, and what the rest of the attack is expected to bring.
		if float(e["u"]) < -0.3 * a.troops and float(e["captured"]) < a.troops / 400.0:
			bot.submit(Commands.retreat(bot.id, a.id))
			bot.log.add(st.tick, "retreat", a.target, {"troops": a.troops, "u": e["u"], "reason": e["reason"]})
