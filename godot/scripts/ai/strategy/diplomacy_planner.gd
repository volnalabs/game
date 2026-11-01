class_name DiplomacyPlanner
extends RefCounted
## Diplomatic AI (docs/ai/AI_DESIGN.md, "Diplomacy"). Every `interval` ticks a strategic bot:
##   1. remembers who betrayed it (a pact that vanished while the partner became a traitor);
##   2. answers pact requests (from bots and the player) by the value of the pact;
##   3. renews expiring alliances that are still worth it;
##   4. answers its allies' help requests (attack when it borders the enemy, else a troop convoy);
##   5. asks an ally for help when an invasion is too big to hold alone;
##   6. rarely betrays an ally that became easy prey (treacherous personalities, late game only);
##   7. proposes an alliance or a NAP when a pact would pay off.
## It sees only what the bot sees (perception estimates, public pacts) and acts through Commands.
## Weights live in data/ai/personalities.json ("diplomacy" + per-personality diplomacy/treachery).


static func act(bot: StrategicAI) -> void:
	var cfg := AIProfile.diplomacy()
	var dip := bot.sim.diplomacy
	var st := bot.sim.st
	var now := st.tick
	_remember_betrayals(bot, cfg)
	for r: Dictionary in dip.requests_to(bot.id):
		var from := int(r["from"])
		var kind := String(r["kind"])
		var v := pact_value(bot, from, kind)
		var ok := v >= float(cfg.get("accept_bar", 0.35))
		bot.submit(Commands.diplo(bot.id, "reply", from, "", ok))
		bot.log.add(now, "diplo_accept" if ok else "diplo_decline", from, {"u": v, "reason": kind})
	for a in dip.allies_of(bot.id):
		var p := dip.pact(bot.id, a)
		if bool(p.get("team", false)) or not dip.in_extend_window(bot.id, a):
			continue
		var mine := "ext_a" if bot.id < a else "ext_b"
		if bool(p.get(mine, false)):
			continue
		var v := pact_value(bot, a, DiplomacySystem.ALLIANCE)
		if v >= float(cfg.get("renew_bar", 0.0)):
			bot.submit(Commands.diplo(bot.id, "extend", a))
			bot.log.add(now, "diplo_renew", a, {"u": v})
	_answer_help(bot, cfg)
	_ask_help(bot, cfg)
	if _betray(bot, cfg):
		return
	_propose(bot, cfg)


## How much a pact of `kind` with `o` is worth to the bot (higher = better; compared with the bars).
static func pact_value(bot: StrategicAI, o: int, kind: String) -> float:
	var cfg := AIProfile.diplomacy()
	var sim := bot.sim
	var st := sim.st
	if o <= 0 or not st.is_alive(o) or st.o_kind[o] == Rules.KIND_TRIBE:
		return -10.0
	var p := bot.perception
	var mine := maxf(bot.troops(), 1.0)
	var ratio := p.guess_troops(o) / mine
	var nv: AIPerception.NeighborView = p.neighbors.get(o)
	var u := 0.0
	# Fear: a strong neighbour is better kept as a partner.
	if nv != null:
		u += clampf(ratio - float(cfg.get("fear_from", 0.6)), 0.0, 1.5) * float(cfg.get("fear_weight", 0.6))
		# Peace with whoever is invading us right now ends the invasion.
		if nv.attacking_me > 0.0:
			u += clampf(nv.attacking_me / mine, 0.0, 1.0) * float(cfg.get("peace_weight", 0.8))
	# A common enemy: somebody else threatens us.
	var other := 0.0
	for t: int in bot.threats:
		if t != o:
			other = maxf(other, float(bot.threats[t]))
	u += clampf(other - float(cfg.get("enemy_from", 0.5)), 0.0, 1.5) * float(cfg.get("enemy_weight", 0.5))
	if kind == DiplomacySystem.NAP:
		u += float(cfg.get("nap_bonus", 0.15))
	u *= float(bot.pers.get("diplomacy", 1.0))
	# Against: grudges, our own war plans, helping the runaway leader, known traitors.
	var rel := bot.relation(o)
	u -= float(rel["grudge"]) * float(cfg.get("grudge_weight", 1.0))
	if o == bot.target and (bot.state == StrategicAI.S_WAR or bot.state == StrategicAI.S_PREPARE):
		u -= float(cfg.get("target_penalty", 1.0))
	if o == p.leader and p.leader_share > float(cfg.get("leader_share", 0.3)):
		u -= 1.0
	if sim.diplomacy.is_traitor(o):
		u -= float(cfg.get("traitor_penalty", 0.8))
	# Good prey is worth more than peace — a weaker neighbour is tomorrow's target, not a partner
	# (how clearly the bot sees that is its difficulty's diplomacy_insight); and a pact must leave
	# room to grow (free land or someone else to fight), or the army would sit idle and eat the
	# treasury.
	var insight := float(bot.diff.get("diplomacy_insight", 0.7))
	if nv != null and ratio < 1.0:
		u -= (1.0 - ratio) * float(cfg.get("weak_partner_penalty", 0.8)) * insight
	for opt: Dictionary in bot.options:
		if int(opt["target"]) == o and float(opt["u"]) > 0.0:
			u -= float(cfg.get("prey_penalty", 0.6)) * insight
			break
	if bot.state != StrategicAI.S_DEFEND and p.free_contact == 0:
		# Room to grow = another target worth attacking (a positive option), not merely a neighbour
		# without a treaty: two bots at peace with no prey left stall while others take the map.
		var room := false
		for opt: Dictionary in bot.options:
			var k := int(opt["target"])
			if k != o and float(opt["u"]) > 0.0 and sim.diplomacy.can_attack(bot.id, k):
				room = true
				break
		if not room:
			u -= float(cfg.get("no_room_penalty", 0.6))
	return u


## A pact that ended while the partner became a traitor means the partner broke it.
static func _remember_betrayals(bot: StrategicAI, cfg: Dictionary) -> void:
	var dip := bot.sim.diplomacy
	var now_pacts := {}
	for k: int in dip.pacts:
		var a := k / 1024
		var b := k % 1024
		if a == bot.id:
			now_pacts[b] = true
		elif b == bot.id:
			now_pacts[a] = true
	for o: int in bot.pacts_seen:
		if not now_pacts.has(o) and dip.is_traitor(o) and bot.sim.st.is_alive(o):
			var rel := bot.relation(o)
			rel["grudge"] = minf(1.5, float(rel["grudge"]) + float(cfg.get("betrayed_grudge", 1.0)))
			bot.log.add(bot.sim.st.tick, "betrayed", o, {})
	bot.pacts_seen = now_pacts


static func _answer_help(bot: StrategicAI, cfg: Dictionary) -> void:
	var sim := bot.sim
	var dip := sim.diplomacy
	var now := sim.st.tick
	for h: Dictionary in dip.help_for(bot.id):
		var asker := int(h["from"])
		var enemy := int(h["enemy"])
		var available := maxf(0.0, bot.troops() - DefensePlanner.reserve_needed(bot))
		var send := available * float(cfg.get("help_share", 0.25))
		var team := dip.same_team(bot.id, asker)
		if team:
			send *= 1.5
		var loyal := team or pact_value(bot, asker, DiplomacySystem.ALLIANCE) >= 0.0
		var ok := loyal and send >= float(cfg.get("help_min", 500)) and dip.can_attack(bot.id, enemy)
		# Help costs troops: outside a team a shrewd bot only helps when the attack pays off for
		# itself or the enemy threatens it too (a distant ally would just get our troops by convoy).
		if ok and not team:
			var worth := false
			if bot.perception.neighbors.has(enemy):
				var e := AttackPlanner.evaluate(bot, enemy, send)
				worth = float(e["u"]) > 0.0 or float(bot.threats.get(enemy, 0.0)) > float(cfg.get("help_threat", 0.8))
			if not worth and bot.rng.chance(float(bot.diff.get("diplomacy_insight", 0.7))):
				ok = false
		bot.submit(Commands.help_answer(bot.id, asker, ok, send if ok else 0.0))
		bot.log.add(now, "help_give" if ok else "help_refuse", enemy, {"troops": send if ok else 0.0, "reason": "ally %d" % asker})
		if ok and bot.perception.neighbors.has(enemy):
			bot.note_attacked_by(enemy, 0.0)


static func _ask_help(bot: StrategicAI, cfg: Dictionary) -> void:
	var sim := bot.sim
	var dip := sim.diplomacy
	var now := sim.st.tick
	if now < bot.next_help:
		return
	var allies := dip.allies_of(bot.id)
	if allies.is_empty():
		return
	var by := {}
	for e: Dictionary in bot.perception.incoming:
		var a := int(e["attacker"])
		if a > 0 and sim.st.o_kind[a] != Rules.KIND_TRIBE:
			by[a] = float(by.get(a, 0.0)) + float(e["troops"])
	var worst := 0
	var worst_t := 0.0
	for a: int in by:
		if float(by[a]) > worst_t:
			worst_t = by[a]
			worst = a
	if worst == 0 or worst_t < float(cfg.get("help_from", 0.25)) * maxf(bot.troops(), 1.0):
		return
	var best := 0
	var best_t := -1.0
	for a in allies:
		if not dip.can_attack(a, worst):
			continue
		var t := bot.perception.guess_troops(a)
		if t > best_t:
			best_t = t
			best = a
	if best == 0:
		return
	# Calling in allies at the right moment is a skill: weaker bots (low insight) often miss it.
	if not bot.rng.chance(float(bot.diff.get("diplomacy_insight", 0.7))):
		return
	bot.next_help = now + int(cfg.get("help_gap", 600))
	bot.submit(Commands.help(bot.id, best, worst))
	bot.log.add(now, "help_ask", worst, {"troops": worst_t, "reason": "ally %d" % best})


## Treachery: break a pact with a weak neighbour when there is no free land left to take.
static func _betray(bot: StrategicAI, cfg: Dictionary) -> bool:
	var sim := bot.sim
	var dip := sim.diplomacy
	var p := bot.perception
	var treachery := float(bot.pers.get("treachery", 0.0))
	if treachery <= 0.0 or p.free_contact > 0 or sim.elapsed_seconds() < float(cfg.get("betray_after_seconds", 600)):
		return false
	var mine := maxf(bot.troops(), 1.0)
	var keys: Array = p.neighbors.keys()
	keys.sort()
	for o: int in keys:
		var nv: AIPerception.NeighborView = p.neighbors[o]
		if nv.pact != "ally" and nv.pact != "pact":
			continue
		if nv.est_troops > float(cfg.get("betray_ratio", 0.4)) * mine:
			continue
		if not bot.rng.chance(float(cfg.get("betray_chance", 0.04)) * treachery):
			continue
		bot.submit(Commands.diplo(bot.id, "break", o))
		bot.log.add(sim.st.tick, "betray", o, {"reason": "weak partner %.0f vs %.0f" % [nv.est_troops, mine]})
		bot.pacts_seen.erase(o)
		return true
	return false


static func _propose(bot: StrategicAI, cfg: Dictionary) -> void:
	var sim := bot.sim
	var dip := sim.diplomacy
	var now := sim.st.tick
	if now < bot.next_proposal:
		return
	# Seeking treaties is a skill too: the chance scales with the difficulty's insight.
	if not bot.rng.chance(float(cfg.get("propose_chance", 0.5)) * float(bot.diff.get("diplomacy_insight", 0.7))):
		bot.next_proposal = now + int(cfg.get("interval", 50)) * 4
		return
	var max_allies := int(sim.rules.dip.get("max_allies", 3))
	var room := dip.allies_of(bot.id).size() < max_allies
	var bar := float(cfg.get("propose_bar", 0.55))
	var best := 0
	var best_kind := ""
	var best_u := bar
	var keys: Array = bot.perception.neighbors.keys()
	keys.sort()
	for o: int in keys:
		var nv: AIPerception.NeighborView = bot.perception.neighbors[o]
		if nv.kind == Rules.KIND_TRIBE or nv.pact == "team" or nv.pact == "ally":
			continue
		if dip.cooldown_left(bot.id, o) > 0 or not dip.pending(bot.id, o).is_empty() or not dip.pending(o, bot.id).is_empty():
			continue
		var kinds: Array[String] = []
		if nv.pact == "":
			kinds.append(DiplomacySystem.NAP)
		if room and dip.allies_of(o).size() < max_allies:
			kinds.append(DiplomacySystem.ALLIANCE)
		for kind in kinds:
			var u := pact_value(bot, o, kind)
			if u > best_u:
				best_u = u
				best = o
				best_kind = kind
	if best == 0:
		return
	bot.next_proposal = now + int(cfg.get("propose_gap", 1200))
	bot.submit(Commands.diplo(bot.id, "request", best, best_kind))
	bot.log.add(now, "diplo_propose", best, {"u": best_u, "reason": best_kind})
