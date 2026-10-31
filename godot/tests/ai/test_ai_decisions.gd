extends TestCase
## Decision quality of the strategic AI on hand-made situations: it must weigh losses against
## gains, read fortifications, learn from outcomes, react to invasions, and never see what it
## should not see.

var sim: Sim
var bot: StrategicAI
var weak: int
var strong: int


func _own_rect(id: int, x0: int, y0: int, w: int, h: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			sim.st.set_owner(sim.map.tile_at(x, y), id)


## Three states in a row: weak (left) | bot (middle) | strong & fortified (right).
func before_each() -> void:
	sim = TestMaps.sim(TestMaps.rect(180, 60), 3, false, 9)
	sim.config.victory.eliminate_all = false
	for t in sim.map.land_tiles:
		sim.st.set_owner(t, 0)
	var ids: Array[int] = []
	for b in sim.ai.brains:
		ids.append(b.id)
	weak = ids[0]
	bot = sim.ai.brain_of(ids[1]) as StrategicAI
	strong = ids[2]
	_own_rect(weak, 2, 2, 58, 56)
	_own_rect(bot.id, 60, 2, 60, 56)
	_own_rect(strong, 120, 2, 58, 56)
	sim.st.set_troops(weak, 8000.0)
	sim.st.set_troops(bot.id, 300000.0)
	sim.st.set_troops(strong, 900000.0)
	sim.economy.tick()
	# Defence posts all along the strong state's border.
	sim.st.add_gold(strong, 5e6)
	sim.st.add_supplies(strong, 5e4)
	for y in [8, 25, 42, 55]:
		sim.structures.try_build(strong, Rules.B_DEFENSE, sim.map.tile_at(122, y))
	for i in 60:
		sim.st.tick += 1
		sim.structures.tick()
	bot.perception.refresh()
	ThreatAssessment.evaluate(bot)


func test_perception_sees_neighbours_and_posts_not_gold() -> void:
	var p := bot.perception
	check(p.neighbors.has(weak) and p.neighbors.has(strong), "both neighbours seen")
	var nv: AIPerception.NeighborView = p.neighbors[strong]
	check(nv.posts_seen >= 3, "fortifications seen (%d)" % nv.posts_seen)
	check(nv.defended_share > 0.5, "most of the strong border is covered (%.2f)" % nv.defended_share)
	var err := absf(nv.est_troops - sim.st.o_troops[strong]) / sim.st.o_troops[strong]
	check(err <= float(bot.diff["perception_noise"]) + 0.01, "estimate within the difficulty's noise (%.2f)" % err)
	check(not ("gold" in (nv as Object).get_property_list().map(func(d: Dictionary) -> String: return d["name"])), "no gold in the view")


func test_attacks_the_weak_refuses_the_fortified() -> void:
	var weak_e := AttackPlanner.best_size(bot, weak, 150000.0)
	var strong_e := AttackPlanner.best_size(bot, strong, 150000.0)
	check(float(weak_e["u"]) > 0.0, "weak neighbour is worth attacking (u=%.0f)" % float(weak_e["u"]))
	check(float(strong_e["u"]) < 0.0, "fortified strong neighbour is not (u=%.0f, %s)" % [float(strong_e["u"]), strong_e["reason"]])
	check(String(strong_e["reason"]) in ["target_fortified", "loss_exceeds_value", "insufficient_troops", "exposed_to_threats"], "a reason is given")
	check(float(weak_e["troops"]) < 150000.0, "sends what the job needs, not everything (%.0f)" % float(weak_e["troops"]))
	var ranked := AttackPlanner.rank_targets(bot, 150000.0)
	check_eq(int(ranked[0]["target"]), weak, "best target is the weak one")


func test_learns_from_a_failed_attack() -> void:
	var e := AttackPlanner.evaluate(bot, weak, 50000.0)
	bot.expect(weak, 50000.0, float(e["captured"]))
	bot.on_attack_ended({"id": 1, "attacker": bot.id, "target": weak, "taken": int(float(e["captured"]) * 0.2),
		"initial": 50000.0, "lost": 50000.0, "killed": 0.0})
	var eff: float = bot.relation(weak)["eff"]
	check(eff < 0.6, "efficiency against that target lowered (%.2f)" % eff)
	var e2 := AttackPlanner.evaluate(bot, weak, 50000.0)
	check(float(e2["captured"]) < float(e["captured"]) * 0.7, "next forecast is more careful")


func test_counters_an_invasion() -> void:
	sim.phase = Sim.Phase.PLAYING
	sim.st.add_troops(strong, -100000.0)
	sim.attacks.start(strong, bot.id, 100000.0)
	sim.st.tick += 50
	bot.perception.refresh()
	check_eq(bot.perception.incoming.size(), 1, "invasion noticed after the reaction delay")
	var before := sim._commands.size()
	DefensePlanner.counter(bot)
	check(sim._commands.size() > before, "a counter-attack was ordered")
	var c: Dictionary = sim._commands.back()
	check_eq(int(c["target"]), strong)
	check(float(c["troops"]) <= 300000.0 - bot.home_floor() * 0.6 + 1.0, "keeps a home army")


func test_difficulty_changes_decisions_not_resources() -> void:
	var easy := AIProfile.difficulty("easy")
	var hard := AIProfile.difficulty("hard")
	check(float(easy["perception_noise"]) > float(hard["perception_noise"]))
	check(int(easy["reaction_delay"]) > int(hard["reaction_delay"]))
	check(int(easy["forecast_steps"]) < int(hard["forecast_steps"]))
	# Every bot starts with the same troops whatever the difficulty.
	var s2 := TestMaps.sim(TestMaps.rect(120, 60), 2, false, 3)
	var t := []
	for b in s2.ai.brains:
		t.append(s2.st.o_troops[b.id])
	check_eq(t[0], t[1])
