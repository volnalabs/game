extends TestCase
## Phase 2D: research gates and progress, modifiers from techs / perks / buildings acting on the
## simulation, new building effects, Fair mode, determinism, saves and the v1 → v2 migration.


func _sim(bots: int = 0, fair: bool = false, perks: Array = []) -> Sim:
	var m := TestMaps.rect(160, 100)
	var cfg := TestMaps.config(bots, true, 3, 0)
	cfg.fair_mode = fair
	cfg.player_perks = perks
	var sim := Sim.new(cfg, TestMaps.definition(m), m)
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(40, 50)))
	sim._start_playing()
	for y in range(2, 98):
		for x in range(2, 80):
			sim.st.set_owner(m.tile_at(x, y), sim.player_id)
	return sim


func _finish_research(sim: Sim, id: int, tech: String) -> void:
	var t := ResearchSystem.tech(tech)
	for r: String in t["requires"]:
		if not sim.research.has_tech(id, r):
			_finish_research(sim, id, r)
	check_eq(sim.apply_command(Commands.research(id, tech)), "", "start %s" % tech)
	var guard := 0
	while not sim.research.has_tech(id, tech) and guard < 100000:
		sim.research.tick()
		guard += 1
	sim.mods.update()


func _build_now(sim: Sim, id: int, kind: int, t: int) -> StructureSystem.Structure:
	sim.st.add_gold(id, 50000000.0)
	sim.st.add_supplies(id, 50000.0)
	var r := sim.structures.try_build(id, kind, t)
	check(r["ok"], "built %s (%s)" % [sim.rules.b_ids[kind], r.get("reason", "")])
	if not r["ok"]:
		return null
	for i in sim.rules.building_ticks(kind) + 1:
		sim.st.tick += 1
		sim.structures.tick()
	sim.mods.update()
	return sim.structures.structs[int(r["id"])]


func test_buildings_are_gated_by_research() -> void:
	var sim := _sim()
	var p := sim.player_id
	sim.st.add_gold(p, 10000000.0)
	sim.st.add_supplies(p, 10000.0)
	var pv := sim.structures.preview(p, Rules.B_BUNKER, sim.map.tile_at(40, 50))
	check_eq(pv["reason"], "locked", "bunker locked")
	check_eq(pv["detail"], "fortification")
	check_eq(sim.apply_command(Commands.build(p, Rules.B_BUNKER, sim.map.tile_at(40, 50))), "locked")
	check_eq(sim.apply_command(Commands.research(p, "radar")), "tech_locked", "prerequisites enforced")
	_finish_research(sim, p, "fortification")
	check(sim.structures.preview(p, Rules.B_BUNKER, sim.map.tile_at(40, 50))["ok"], "unlocked after research")
	check(sim.structures.preview(p, Rules.B_RESEARCH, sim.map.tile_at(40, 50))["ok"], "research centre needs nothing")


func test_research_rate_and_centres() -> void:
	var sim := _sim()
	var p := sim.player_id
	var base := sim.research.rate(p)
	check(base > 0.0, "base research")
	_build_now(sim, p, Rules.B_RESEARCH, sim.map.tile_at(40, 50))
	check(sim.research.rate(p) > base * 2.0, "a research centre multiplies research (%.3f vs %.3f)" % [sim.research.rate(p), base])
	sim.apply_command(Commands.research(p, "trade_routes"))
	sim.research.tick()
	check(sim.research.progress(p, "trade_routes") > 0.0, "progress accumulates")
	sim.apply_command(Commands.research(p, "doctrine"))
	sim.research.tick()
	check(sim.research.progress(p, "trade_routes") > 0.0, "switching keeps progress")


func test_tech_modifiers_change_the_economy() -> void:
	var a := _sim()
	var b := _sim()
	_finish_research(b, b.player_id, "trade_routes")
	for i in 5:
		a.economy.tick()
		b.economy.tick()
	check(b.st.o_income[b.player_id] > a.st.o_income[a.player_id] * 1.05, "+6%% income (%.1f vs %.1f)" % [b.st.o_income[b.player_id], a.st.o_income[a.player_id]])


func test_perks_apply_and_fair_mode_removes_them() -> void:
	var a := _sim(0, false, [])
	var b := _sim(0, false, ["eco_tax"])
	var c := _sim(0, true, ["eco_tax"])
	check_near(b.mods.mult("gold_mult", b.player_id), 1.05, 0.0001, "perk gold +5%")
	check_near(b.mods.mult("growth_mult", b.player_id), 0.98, 0.0001, "and its cost")
	check_near(c.mods.mult("gold_mult", c.player_id), 1.0, 0.0001, "Fair mode: no perks")
	check_near(a.mods.mult("gold_mult", a.player_id), 1.0, 0.0001, "no loadout: no perks")
	var withbots := _sim(4, false)
	var any := false
	for br in withbots.ai.brains:
		if not (withbots.mods.perks.get(br.id, []) as Array).is_empty():
			any = true
	check(any, "bots get personality perks")
	var fairbots := _sim(4, true)
	for br in fairbots.ai.brains:
		check((fairbots.mods.perks.get(br.id, []) as Array).is_empty(), "no bot perks in Fair mode")


func test_academy_lowers_attack_losses() -> void:
	var losses := []
	for with_academy in [false, true]:
		var sim := _sim(1)
		var p := sim.player_id
		var bot: int = sim.ai.brains[0].id
		sim.ai.brains.clear()
		for y in range(20, 80):
			for x in range(80, 150):
				sim.st.set_owner(sim.map.tile_at(x, y), bot)
		if with_academy:
			_finish_research(sim, p, "doctrine")
			_build_now(sim, p, Rules.B_ACADEMY, sim.map.tile_at(30, 50))
		sim.st.set_troops(p, 300000.0)
		sim.st.set_troops(bot, 100000.0)
		sim.apply_command(Commands.attack_target(p, bot, 100000.0))
		for i in 30:
			sim.attacks.tick()
		var a: AttackSystem.Attack = sim.attacks.find(p, bot)
		losses.append(a.lost / maxf(float(a.taken), 1.0))
	check(float(losses[1]) < float(losses[0]) * 0.97, "academy: fewer losses per tile (%.2f vs %.2f)" % [losses[1], losses[0]])


func test_bunker_survives_capture_post_does_not() -> void:
	var sim := _sim(1)
	var p := sim.player_id
	var bot: int = sim.ai.brains[0].id
	_finish_research(sim, p, "fortification")
	var bunker := _build_now(sim, p, Rules.B_BUNKER, sim.map.tile_at(30, 30))
	var post := _build_now(sim, p, Rules.B_DEFENSE, sim.map.tile_at(60, 70))
	if bunker == null or post == null:
		return
	sim.st.set_owner(bunker.tile, bot)
	sim.st.set_owner(post.tile, bot)
	check(bunker.alive and bunker.owner == bot, "bunker captured intact")
	check(not post.alive, "post destroyed")


func test_radar_spots_landings() -> void:
	var sim := _sim(1)
	var p := sim.player_id
	var bot: int = sim.ai.brains[0].id
	_finish_research(sim, p, "radar")
	_build_now(sim, p, Rules.B_RADAR, sim.map.tile_at(8, 30))
	# A coastal tile of the player inside the radar radius.
	var t := -1
	for c in sim.map.land_tiles:
		if sim.map.coastal[c] == 1 and sim.st.owner[c] == p and sim.structures.in_zone(p, Rules.B_RADAR, c):
			t = c
			break
	check(t >= 0, "a covered coast")
	if t < 0:
		return
	var b := NavalSystem.Boat.new()
	b.owner = bot
	b.troops = 10000.0
	b.target_tile = t
	sim.st.add_boats(bot, 1)
	sim.events.drain()
	sim.naval._land(b)
	var landed := {}
	for e in sim.events.drain():
		if e["type"] == SimEvents.BOAT_LANDED:
			landed = e
	check(bool(landed.get("spotted", false)), "landing spotted")
	check_near(float(landed.get("troops", 0.0)), 7000.0, 1.0, "30% lost")


func test_new_building_owner_effects() -> void:
	var sim := _sim()
	var p := sim.player_id
	_finish_research(sim, p, "naval_doctrine")
	var before := sim.naval.max_boats(p)
	var speed0 := sim.mods.mult("boat_speed_mult", p)
	var t := -1
	for c in sim.map.land_tiles:
		if sim.map.coastal[c] == 1 and sim.st.owner[c] == p:
			t = c
			break
	_build_now(sim, p, Rules.B_NAVAL_BASE, t)
	check_eq(sim.naval.max_boats(p), before + 1, "naval base: +1 transport")
	check(sim.mods.mult("boat_speed_mult", p) > speed0, "and faster transports")


func test_research_is_saved_and_deterministic() -> void:
	var a := TestMaps.sim(TestMaps.rect(120, 80), 6, false, 9)
	var b := TestMaps.sim(TestMaps.rect(120, 80), 6, false, 9)
	for i in 1500:
		a.step()
		b.step()
	check_eq(a.state_hash(), b.state_hash(), "deterministic with research and perks")
	var any := false
	for br in a.ai.brains:
		if not a.research.done(br.id).is_empty() or a.research.current(br.id) != "":
			any = true
	check(any, "bots research")
	# Through bytes, like a save file (no shared references between the two matches).
	var d: Dictionary = bytes_to_var(var_to_bytes(a.to_dict()))
	var c := TestMaps.sim(TestMaps.rect(120, 80), 6, false, 9)
	c.from_dict(d)
	for i in 200:
		a.step()
		c.step()
	check_eq(c.state_hash(), a.state_hash(), "save/load round trip continues identically")


func test_save_v1_building_arrays_are_restrided() -> void:
	var old := PackedInt32Array()
	old.resize(3 * 6)
	old[1 * 6 + Rules.B_CITY] = 4
	old[2 * 6 + Rules.B_DEFENSE] = 2
	var state := {"state": {"o_blevels": old, "o_bowned": old}}
	var out := SaveFormat.migrate(1, {"version": 1}, state)
	var nb: PackedInt32Array = out["state"]["state"]["o_blevels"]
	check_eq(nb.size(), 3 * Rules.MAX_BUILDING_KINDS)
	check_eq(nb[1 * Rules.MAX_BUILDING_KINDS + Rules.B_CITY], 4, "city levels kept")
	check_eq(nb[2 * Rules.MAX_BUILDING_KINDS + Rules.B_DEFENSE], 2, "posts kept")
	check(out["state"].has("research"), "research state added")


func test_skill_tree_rules() -> void:
	var p := ProfileData.fresh()
	p.data["skill_points"] = 10
	check_eq(SkillTree.unlock_block(p, "eco_industry"), "level", "level requirement")
	p.data["level"] = 12
	check_eq(SkillTree.unlock_block(p, "eco_industry"), "requires", "prerequisite")
	check(SkillTree.unlock(p, "eco_tax") and SkillTree.unlock(p, "eco_industry") and SkillTree.unlock(p, "eco_merchant"), "chain")
	check_eq(SkillTree.unlock_block(p, "eco_planned"), "excluded", "exclusive choice")
	check(SkillTree.equip(p, "eco_tax") and SkillTree.equip(p, "eco_industry") and SkillTree.equip(p, "eco_merchant"), "3 slots at level 12")
	check(not SkillTree.equip(p, "eco_merchant"), "no duplicate")
	var points := int(p.data["skill_points"])
	SkillTree.reset(p)
	check_eq(int(p.data["skill_points"]), points + 1 + 1 + 2, "reset refunds")
	check((p.data["perks"]["loadout"] as Array).is_empty())
