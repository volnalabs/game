extends TestCase
## Phase 2A.3-D: the AI uses sea landings on a two-island map — reproducibly, only on expeditions
## the simulation's planner accepts, and (when worth it) towards inland goals.


func _run(seed_value: int, ticks: int) -> Dictionary:
	var m := TestMaps.rect(200, 100, true)
	var sim := TestMaps.sim(m, 6, false, seed_value)
	var launched := 0
	var inland := 0
	var rejected := 0
	for i in ticks:
		sim.step()
		for e in sim.events.drain():
			match String(e["type"]):
				SimEvents.BOAT_LAUNCHED:
					launched += 1
					if int(e.get("goal", -1)) >= 0 and m.coastal[int(e["goal"])] == 0:
						inland += 1
				SimEvents.COMMAND_REJECTED:
					if String(e["reason"]) in ["no_route", "no_coast", "no_land_path", "no_landing", "not_land"]:
						rejected += 1
	return {"sim": sim, "launched": launched, "inland": inland, "rejected": rejected}


func test_ai_lands_across_the_sea_without_impossible_expeditions() -> void:
	var r := _run(41, 3000)
	print("      launched %d (inland goals %d), impossible orders %d" % [r["launched"], r["inland"], r["rejected"]])
	check(int(r["launched"]) > 0, "bots use transports to reach the other island")
	check_eq(int(r["rejected"]), 0, "no transport ordered on an impossible route")


func test_ai_landings_are_reproducible() -> void:
	var a := _run(42, 1500)
	var b := _run(42, 1500)
	check_eq((a["sim"] as Sim).state_hash(), (b["sim"] as Sim).state_hash(), "same seed, same naval war")
	check_eq(int(a["launched"]), int(b["launched"]), "same landings")


func test_refine_prefers_a_valuable_inland_goal() -> void:
	var m := TestMaps.rect(160, 80, true)
	var sim := TestMaps.sim(m, 2, false, 7)
	sim._start_playing()
	var a := 1
	var b := 2
	for y in 80:
		for x in 160:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, a if x < 80 else b)
	for o: int in [a, b]:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
	sim.st.add_gold(b, 1e7)
	sim.st.add_supplies(b, 1e5)
	# A city 10 tiles from the coast (worth aiming past the beach)...
	var city := m.tile_at(94, 40)
	var r := sim.structures.try_build(b, Rules.B_CITY, city)
	check(r["ok"], "enemy city inland")
	var bot: StrategicAI = null
	for br in sim.ai.brains:
		if br.id == a and br is StrategicAI:
			bot = br
	check(bot != null, "bot A")
	if bot == null:
		return
	var coast := m.tile_at(84, 40)
	var best := {"tile": coast, "owner": b, "u": 1000.0, "troops": 5000.0, "reason": "overseas_war"}
	var out := NavalPlanner.refine(bot, best)
	check(not out.is_empty(), "a landing remains possible")
	check_eq(int(out["tile"]), int(LandingPlanner.key_tile(sim.naval, b)), "the bot aims at the enemy city")
	check(LandingPlanner.plan(sim.naval, a, int(out["tile"]))["ok"], "the chosen goal is reachable")
	# ...but not one deep inland: the landing stays on the beach.
	sim.structures.destroy(sim.structures.structs[int(r["id"])])
	var far := sim.structures.try_build(b, Rules.B_CITY, m.tile_at(130, 40))
	check(far["ok"], "a deep inland city")
	check_eq(int(NavalPlanner.refine(bot, best)["tile"]), coast, "too deep: the bot lands on the beach")
	# An impossible landing is dropped instead of being sent.
	var lake := {"tile": m.tile_at(80, 40), "owner": 0, "u": 10.0, "troops": 100.0, "reason": "free_shore"}
	check(NavalPlanner.refine(bot, lake).is_empty(), "a landing on water is never sent")
