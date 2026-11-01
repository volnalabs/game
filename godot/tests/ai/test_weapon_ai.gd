extends TestCase
## Phase 2E: the AI uses weapons sensibly and reproducibly.


func _setup(seed_value: int, pers: String = "") -> Dictionary:
	var m := TestMaps.rect(240, 120)
	var sim := TestMaps.sim(m, 2, false, seed_value)
	sim._start_playing()
	var a := 1
	var b := 2
	for y in 120:
		for x in 240:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, a if x < 120 else b)
	var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
	for o: int in [a, b]:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 300000.0
		sim.st.add_gold(o, 5e7)
		sim.st.add_supplies(o, 1e5)
		sim.research.state[o] = {"done": all, "current": "", "progress": {}}
		sim.mods.mark(o)
	var bot: StrategicAI = null
	for br in sim.ai.brains:
		if br.id == a and br is StrategicAI:
			bot = br
	if pers != "" and bot != null:
		bot.pers = AIProfile.personality(pers)
	return {"sim": sim, "map": m, "a": a, "b": b, "bot": bot}


func _put(sim: Sim, owner: int, kind: int, tile: int, level: int = 1) -> StructureSystem.Structure:
	var ss := sim.structures
	var s := StructureSystem.Structure.new()
	s.id = ss.structs.size()
	s.kind = kind
	s.owner = owner
	s.tile = tile
	s.level = level
	s.active_levels = level
	ss.structs.append(s)
	sim.st.set_struct_at(tile, s.id)
	ss._grid_add(s)
	sim.st.add_blevel(owner, kind, level)
	sim.st.add_bowned(owner, kind, level)
	ss.invalidate_caches()
	return s


func _strike(c: Dictionary) -> Dictionary:
	var bot: StrategicAI = c["bot"]
	bot.target = c["b"]
	bot.state = StrategicAI.S_WAR
	bot.next_weapon = 0
	bot.perception.refresh()
	var sim: Sim = c["sim"]
	var before := sim._commands.size()
	var fired := WeaponPlanner.act(bot)
	if not fired or sim._commands.size() <= before:
		return {}
	return sim._commands[sim._commands.size() - 1]


func test_strikes_a_valuable_target_and_never_its_own_land() -> void:
	var c := _setup(3, "balanced")
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	check(c["bot"] != null, "bot")
	_put(sim, c["a"], Rules.B_SILO, m.tile_at(40, 60), 2)
	_put(sim, c["b"], Rules.B_CITY, m.tile_at(200, 60), 3)
	var cmd := _strike(c)
	check(not cmd.is_empty(), "the bot strikes")
	if cmd.is_empty():
		return
	check_eq(String(cmd["type"]), Commands.LAUNCH, "a launch order")
	var w := sim.rules.weapon_index(String(cmd["weapon"]))
	check(not sim.weapons.is_nuclear(w), "no nuclear first strike")
	check(sim.weapons.check(c["a"], w, int(cmd["tile"]))["ok"], "the order is possible")
	var est := sim.weapons.estimate(c["a"], w, int(cmd["tile"]))
	check_eq(int(est["own_tiles"]), 0, "no friendly fire")


func test_nuclear_only_in_retaliation() -> void:
	var c := _setup(4, "balanced")
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var bot: StrategicAI = c["bot"]
	_put(sim, c["a"], Rules.B_SILO, m.tile_at(40, 60), 3)
	for i in 4:
		_put(sim, c["b"], Rules.B_CITY, m.tile_at(170 + i * 16, 30 + i * 18), 2)
	check(not WeaponPlanner._nuclear_ok(bot, [c["b"]] as Array[int]), "no reason for nukes yet")
	sim.weapons.nukes_launched[c["b"]] = 1
	check(WeaponPlanner._nuclear_ok(bot, [c["b"]] as Array[int]), "retaliation allowed after the enemy used nukes")


func test_prefers_undefended_targets() -> void:
	var c := _setup(5, "balanced")
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	_put(sim, c["a"], Rules.B_SILO, m.tile_at(40, 60), 2)
	var guarded := _put(sim, c["b"], Rules.B_CITY, m.tile_at(135, 20), 3)
	_put(sim, c["b"], Rules.B_SAM, m.tile_at(130, 20), 3)
	_put(sim, c["b"], Rules.B_RADAR, m.tile_at(132, 25))
	var open := _put(sim, c["b"], Rules.B_CITY, m.tile_at(230, 110), 3)
	check(sim.weapons.intercept_risk(c["a"], sim.rules.weapon_index("missile"), open.tile)["sams"] == 0, "the second city is outside SAM cover")
	var cmd := _strike(c)
	check(not cmd.is_empty(), "strikes")
	if cmd.is_empty():
		return
	var t := int(cmd["tile"])
	check(m.dist2(t, open.tile) < m.dist2(t, guarded.tile), "aims at the city without SAM cover")


func test_ai_war_with_weapons_is_reproducible_and_valid() -> void:
	var results: Array = []
	for run in 2:
		var c := _setup(21, "aggressive")
		var sim: Sim = c["sim"]
		var m: MapData = c["map"]
		_put(sim, c["a"], Rules.B_SILO, m.tile_at(40, 60), 2)
		_put(sim, c["b"], Rules.B_SILO, m.tile_at(200, 60), 2)
		_put(sim, c["b"], Rules.B_CITY, m.tile_at(180, 40), 2)
		_put(sim, c["a"], Rules.B_CITY, m.tile_at(60, 40), 2)
		var launches := 0
		var bad := 0
		for i in 1500:
			sim.step()
			for e in sim.events.drain():
				if String(e["type"]) == SimEvents.WEAPON_LAUNCHED:
					launches += 1
				if String(e["type"]) == SimEvents.COMMAND_REJECTED and String(e.get("command", e.get("cmd", ""))) == Commands.LAUNCH:
					bad += 1
		results.append([sim.state_hash(), launches, bad])
	print("      launches %d, rejected %d" % [results[0][1], results[0][2]])
	check_eq(results[0][0], results[1][0], "same seed, same war")
	check(int(results[0][1]) > 0, "the bots use their weapons")
	check_eq(int(results[0][2]), 0, "no impossible launch orders")


func test_artillery_aims_at_the_front_within_reach() -> void:
	# Phase 2G: in real matches the planner sampled the enemy's whole border and found nothing in
	# range; artillery must aim at the shared front near our defence posts.
	var c := _setup(6, "aggressive")
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var bot: StrategicAI = c["bot"]
	_put(sim, c["a"], Rules.B_DEFENSE, m.tile_at(110, 60), 2)
	var w := sim.rules.weapon_index("artillery")
	var targets := WeaponPlanner._targets(bot, c["b"], w)
	check(targets.size() > 0, "front tiles found (%d)" % targets.size())
	var rng_max := float(sim.rules.weapon(w)["range"])
	for t in targets:
		check(sim.st.owner[t] == c["b"], "enemy land")
		check(float(m.dist2(t, m.tile_at(110, 60))) <= rng_max * rng_max, "within the post's reach")


func test_research_reaches_weapons_later_in_the_match() -> void:
	var c := _setup(7, "aggressive")
	var sim: Sim = c["sim"]
	var bot: StrategicAI = c["bot"]
	var a: int = c["a"]
	# Everything but the weapons branch is known; the bot is at war late in the match.
	var done: Array = []
	for t: Dictionary in ResearchSystem.techs():
		if String(t["branch"]) != "weapons":
			done.append(String(t["id"]))
	sim.research.state[a] = {"done": done, "current": "", "progress": {}}
	sim.play_start_tick = sim.st.tick - 12000
	sim.st.add_troops(a, -1000.0)
	sim.attacks.start(a, c["b"], 1000.0)
	sim._commands.clear()
	ResearchPlanner.act(bot)
	var cmds: Array = sim._commands.filter(func(x: Dictionary) -> bool: return String(x["type"]) == Commands.RESEARCH)
	check_eq(cmds.size(), 1, "a research order")
	if cmds.size() == 1:
		check_eq(String(ResearchSystem.tech(String(cmds[0]["tech"]))["branch"]), "weapons", "from the weapons branch")
