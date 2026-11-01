extends TestCase
## Phase 2F: the diplomatic AI answers and proposes pacts, honours them in every planner, asks for
## and gives help, betrays only rarely, and plays in teams without a single refused command.

var sim: Sim
var bot: StrategicAI
var weak: int
var strong: int


func _own_rect(id: int, x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			sim.st.set_owner(sim.map.tile_at(x, y), id)


## Three states in a row with no free land: weak (left) | bot (middle) | strong (right).
func before_each() -> void:
	sim = TestMaps.sim(TestMaps.rect(180, 60), 3, false, 11)
	sim.config.victory.eliminate_all = false
	sim._start_playing()
	var ids: Array[int] = []
	for b in sim.ai.brains:
		ids.append(b.id)
	weak = ids[0]
	bot = sim.ai.brain_of(ids[1]) as StrategicAI
	strong = ids[2]
	bot.pers = AIProfile.personality("balanced").duplicate()
	for y in 60:
		for x in 180:
			var t := sim.map.tile_at(x, y)
			if sim.map.land[t] == 1:
				sim.st.set_owner(t, weak if x < 60 else (bot.id if x < 120 else strong))
	for o in ids:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
	sim.st.set_troops(weak, 8000.0)
	sim.st.set_troops(bot.id, 300000.0)
	sim.st.set_troops(strong, 900000.0)
	sim.economy.tick()
	_refresh()


func _refresh() -> void:
	bot.perception.refresh()
	ThreatAssessment.evaluate(bot)


## Commands the bot queued, then cleared.
func _taken() -> Array:
	var out: Array = sim._commands.filter(func(c: Dictionary) -> bool: return int(c.get("owner", 0)) == bot.id)
	sim._commands.clear()
	return out


func _cmds_of(cmds: Array, type: String, action: String = "") -> Array:
	return cmds.filter(func(c: Dictionary) -> bool:
		return String(c["type"]) == type and (action == "" or String(c.get("action", "")) == action))


func test_answers_requests_by_value() -> void:
	var dip := sim.diplomacy
	# The strong neighbour offers a NAP: welcome. The weak one, our war target, offers an alliance: no.
	bot.state = StrategicAI.S_WAR
	bot.target = weak
	check_eq(dip.request(strong, bot.id, DiplomacySystem.NAP), "", "strong asks for a NAP")
	check_eq(dip.request(weak, bot.id, DiplomacySystem.ALLIANCE), "", "weak asks for an alliance")
	DiplomacyPlanner.act(bot)
	var replies := _cmds_of(_taken(), Commands.DIPLO, "reply")
	var by := {}
	for c: Dictionary in replies:
		by[int(c["other"])] = bool(c["accept"])
	check(bool(by.get(strong, false)), "accepts peace with the stronger neighbour")
	check(by.has(weak) and not bool(by[weak]), "declines its own war target")
	# A neighbour who betrayed us is not trusted again soon.
	bot.state = StrategicAI.S_DEVELOP
	bot.target = 0
	bot.relation(weak)["grudge"] = 1.5
	check(DiplomacyPlanner.pact_value(bot, weak, DiplomacySystem.NAP) < float(AIProfile.diplomacy()["accept_bar"]), "a grudge blocks pacts")


func test_never_plans_attacks_on_partners() -> void:
	var dip := sim.diplomacy
	var before := AttackPlanner.rank_targets(bot, 200000.0)
	check(before.any(func(o: Dictionary) -> bool: return int(o["target"]) == weak), "the weak neighbour is a target before")
	dip._form(bot.id, weak, DiplomacySystem.NAP)
	_refresh()
	check_eq(String((bot.perception.neighbors[weak] as AIPerception.NeighborView).pact), "pact", "perception knows the pact")
	var after := AttackPlanner.rank_targets(bot, 200000.0)
	check(not after.any(func(o: Dictionary) -> bool: return int(o["target"]) == weak), "no attack options against a partner")
	# A war plan against a new partner is dropped.
	bot.state = StrategicAI.S_WAR
	bot.target = weak
	bot.next_offense = 0
	bot._wage_war()
	check(bot.state != StrategicAI.S_WAR, "war on a partner ends")
	check(_cmds_of(_taken(), Commands.ATTACK).is_empty(), "and no attack is sent")


func test_partners_stay_watched_teammates_do_not() -> void:
	var th := float(bot.threats.get(strong, 0.0))
	sim.diplomacy._form(bot.id, strong, DiplomacySystem.ALLIANCE)
	_refresh()
	var th2 := float(bot.threats.get(strong, 0.0))
	check(th > 0.0 and th2 > th * 0.8, "an ally is still watched: pacts end (%.2f -> %.2f)" % [th, th2])
	sim.diplomacy.set_teams({bot.id: 1, strong: 1, weak: 2})
	_refresh()
	check_eq(float(bot.threats.get(strong, 0.0)), 0.0, "a teammate is no threat at all")


func test_proposes_a_pact_to_a_dangerous_neighbour() -> void:
	var cfg := AIProfile.diplomacy().duplicate()
	cfg["propose_chance"] = 1.0
	bot.diff = AIProfile.difficulty("hard")
	# The weak neighbour is prey (room to grow), the strong one is not a target: securing that flank
	# pays off.
	bot.options = AttackPlanner.rank_targets(bot, 200000.0).filter(func(o: Dictionary) -> bool: return int(o["target"]) == weak)
	bot.next_proposal = 0
	DiplomacyPlanner._propose(bot, cfg)
	var req := _cmds_of(_taken(), Commands.DIPLO, "request")
	check_eq(req.size(), 1, "one proposal")
	if req.size() == 1:
		check_eq(int(req[0]["other"]), strong, "to the strong neighbour")
	check(bot.next_proposal > sim.st.tick, "then waits before proposing again")
	DiplomacyPlanner._propose(bot, cfg)
	check(_cmds_of(_taken(), Commands.DIPLO, "request").is_empty(), "no spam")


func test_renews_a_useful_alliance() -> void:
	var dip := sim.diplomacy
	dip._form(bot.id, strong, DiplomacySystem.ALLIANCE)
	var p := dip.pact(bot.id, strong)
	p["until"] = sim.st.tick + 100
	_refresh()
	DiplomacyPlanner.act(bot)
	check_eq(_cmds_of(_taken(), Commands.DIPLO, "extend").size(), 1, "asks to renew in the window")


func test_asks_for_and_gives_help() -> void:
	var dip := sim.diplomacy
	dip._form(bot.id, weak, DiplomacySystem.ALLIANCE)
	# The strong neighbour invades: the bot asks its ally for help.
	sim.st.add_troops(strong, -300000.0)
	sim.attacks.start(strong, bot.id, 300000.0)
	sim.st.tick += 20
	_refresh()
	bot.next_help = 0
	DiplomacyPlanner.act(bot)
	var asks := _cmds_of(_taken(), Commands.HELP)
	check_eq(asks.size(), 1, "asks for help")
	if asks.size() == 1:
		check_eq(int(asks[0]["ally"]), weak, "from its ally")
		check_eq(int(asks[0]["enemy"]), strong, "against the invader")
	# Now the ally asks the bot for help against the strong state. Attacking a much stronger state does
	# not pay off: a shrewd (hard) bot refuses...
	for a in sim.attacks.attacks:
		if a.alive:
			sim.attacks.end_attack(a, true)
	sim.st.set_troops(strong, 900000.0)
	bot.diff = AIProfile.difficulty("hard")
	_refresh()
	check_eq(dip.ask_help(weak, bot.id, strong), "", "ally asks")
	DiplomacyPlanner.act(bot)
	var answers := _cmds_of(_taken(), Commands.HELP_ANSWER)
	check_eq(answers.size(), 1, "answers")
	if answers.size() == 1:
		check(not bool(answers[0]["accept"]), "a hard bot refuses an attack that does not pay off")
		sim.apply_command(answers[0])
	# ...but helps a worthy ally (not tomorrow's prey) against a weakened enemy.
	sim.st.set_troops(strong, 20000.0)
	sim.st.set_troops(weak, 700000.0)
	_refresh()
	bot.options = AttackPlanner.rank_targets(bot, 200000.0)
	check_eq(dip.ask_help(weak, bot.id, strong), "", "ally asks again")
	DiplomacyPlanner.act(bot)
	answers = _cmds_of(_taken(), Commands.HELP_ANSWER)
	check_eq(answers.size(), 1, "answers")
	if answers.size() == 1:
		check(bool(answers[0]["accept"]) and float(answers[0]["troops"]) >= 500.0, "with troops (%.0f)" % float(answers[0]["troops"]))


func test_betrayal_is_rare_and_needs_treachery() -> void:
	var dip := sim.diplomacy
	dip._form(bot.id, weak, DiplomacySystem.ALLIANCE)
	sim.play_start_tick = sim.st.tick - 20000
	_refresh()
	var cfg := AIProfile.diplomacy()
	bot.pers["treachery"] = 0.0
	var broke := false
	for i in 300:
		if DiplomacyPlanner._betray(bot, cfg):
			broke = true
	check(not broke, "a loyal personality never betrays")
	bot.pers["treachery"] = 0.6
	var tries := 0
	while tries < 2000 and not DiplomacyPlanner._betray(bot, cfg):
		tries += 1
	check(tries > 5 and tries < 2000, "a treacherous one does, but not at once (%d cycles)" % tries)
	check_eq(_cmds_of(_taken(), Commands.DIPLO, "break").size(), 1, "by breaking the pact")
	# Teammates are never betrayed.
	dip.set_teams({bot.id: 1, weak: 1, strong: 2})
	_refresh()
	var t2 := 0
	while t2 < 2000 and not DiplomacyPlanner._betray(bot, cfg):
		t2 += 1
	check_eq(t2, 2000, "never a teammate")


func test_remembers_a_betrayal() -> void:
	var dip := sim.diplomacy
	dip._form(bot.id, strong, DiplomacySystem.NAP)
	DiplomacyPlanner.act(bot)
	_taken()
	check_eq(dip.break_pact(strong, bot.id), "", "the partner breaks the pact")
	DiplomacyPlanner.act(bot)
	_taken()
	check(float(bot.relation(strong)["grudge"]) >= 1.0, "the bot holds a grudge")
	check(DiplomacyPlanner.pact_value(bot, strong, DiplomacySystem.NAP) < float(AIProfile.diplomacy()["accept_bar"]), "and won't sign again soon")


func test_ai_matches_respect_pacts_and_teams() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var ffa := AISimRunner.run_game("gen:continents:S", 910, 8, "mixed", 5000, reg)
	var team := AISimRunner.run_game("gen:continents:S", 911, 8, "mixed", 5000, reg, 0, 0.6, 2)
	var dffa: Dictionary = ffa["diplomacy"]
	var dteam: Dictionary = team["diplomacy"]
	print("      free-for-all: ", dffa, " | teams: ", dteam, " winner team ", team["team_winner"])
	check_eq(int(dffa["blocked"]), 0, "no AI command refused because of a pact (FFA)")
	check_eq(int(dteam["blocked"]), 0, "nor in a team match")
	check(int(dffa["formed"]) > 0, "bots make pacts in a free-for-all")
	var again := AISimRunner.run_game("gen:continents:S", 910, 8, "mixed", 1500, reg)
	var again2 := AISimRunner.run_game("gen:continents:S", 910, 8, "mixed", 1500, reg)
	check_eq(JSON.stringify(again["diplomacy"]), JSON.stringify(again2["diplomacy"]), "diplomacy is reproducible from the seed")
