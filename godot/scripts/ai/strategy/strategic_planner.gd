class_name StrategicPlanner
extends RefCounted
## Strategic state machine driven by utilities (docs/ai/AI_DESIGN.md §5). Every strategic cycle
## the bot scores EXPAND / DEVELOP / PREPARE_WAR / WAR / DEFEND / CONSOLIDATE from its perception
## and switches only when another state beats the current one by HYSTERESIS.

const HYSTERESIS := 1.15


static func decide(bot: StrategicAI) -> void:
	var p := bot.perception
	var st := bot.sim.st
	var now := st.tick
	var top_threat := ThreatAssessment.evaluate(bot)
	if p.free_contact > 0:
		p.estimate_free_land()
	else:
		p.free_estimate = 0
	var troops := bot.troops()
	var reserve := DefensePlanner.reserve_needed(bot)
	var available := maxf(0.0, troops - reserve)
	var scores := {}
	# DEFEND: invasions in progress, or a neighbour strong and hostile enough to fear.
	var incoming := 0.0
	for e: Dictionary in p.incoming:
		incoming += float(e["troops"])
	var defend := incoming * 1.5
	if top_threat > 1.2:
		defend += (top_threat - 1.2) * troops * 0.1 * float(bot.pers["defense"])
	scores[StrategicAI.S_DEFEND] = defend
	# EXPAND: unclaimed land within reach.
	var expand := 0.0
	if p.free_contact > 0 and p.free_estimate > 0:
		var e := AttackPlanner.best_size(bot, 0, bot._available_expand())
		if not e.is_empty():
			expand = maxf(0.0, float(e["u"])) + troops * 0.1
	scores[StrategicAI.S_EXPAND] = expand
	# WAR: the best land target (with deliberate mistakes on easier levels).
	bot.options = AttackPlanner.rank_targets(bot, available)
	var war: Dictionary = {}
	var positive: Array = bot.options.filter(func(o: Dictionary) -> bool: return float(o["u"]) > 0.0)
	if not positive.is_empty():
		war = positive[0]
		if positive.size() > 1 and bot.rng.chance(float(bot.diff["mistake_rate"])):
			war = positive[bot.rng.below(mini(3, positive.size()))]
	elif not bot.options.is_empty():
		var refused: Dictionary = bot.options[0]
		bot.log.add(now, "refuse", int(refused["target"]), {"u": refused["u"], "reason": refused["reason"],
			"troops": refused["troops"]})
	var war_u := 0.0
	if not war.is_empty():
		war_u = float(war["u"])
		# An army eating the treasury wants to be used.
		if st.o_upkeep[bot.id] > 0.5 * maxf(st.o_income[bot.id], 1.0):
			war_u *= 1.3
	scores[StrategicAI.S_WAR] = war_u
	# DEVELOP: baseline when nothing pressing; CONSOLIDATE after a costly war.
	scores[StrategicAI.S_DEVELOP] = troops * 0.04 * float(bot.pers["economy"])
	var cons := 0.0
	if now - bot.last_war_end < 900 and bot.fill() < 0.35:
		cons = troops * 0.12
	scores[StrategicAI.S_CONSOLIDATE] = cons
	# Pick with hysteresis.
	var cur := bot.state
	var cur_key := StrategicAI.S_WAR if cur == StrategicAI.S_PREPARE else cur
	var best := cur_key
	var best_s: float = float(scores.get(cur_key, 0.0)) * HYSTERESIS
	for k: int in scores:
		if float(scores[k]) > best_s:
			best_s = scores[k]
			best = k
	var new_state := best
	var target := 0
	if best == StrategicAI.S_WAR:
		if war.is_empty():
			new_state = StrategicAI.S_DEVELOP
		else:
			target = war["target"]
			bot.war_plan = war
			var war_fill := 0.3 + float(bot.pers["reserve"]) * 0.5
			if bot.fill() < war_fill and incoming <= 0.0:
				new_state = StrategicAI.S_PREPARE
	bot.set_state(new_state, target)
