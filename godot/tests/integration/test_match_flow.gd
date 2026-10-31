extends TestCase
## Full match cycle on small maps: spawn, expansion, war between bots, landings, victory, defeat.


func test_player_spawn_countdown_and_expansion() -> void:
	var sim := TestMaps.sim(TestMaps.rect(160, 100), 3, true, 11)
	check_eq(sim.phase, Sim.Phase.SPAWN)
	var p := sim.player_id
	var start := -1
	for t in sim.map.land_tiles:
		if sim.spawn.is_valid_start(t):
			start = t
			break
	sim.submit(Commands.spawn(p, start))
	for i in sim.rules.countdown_ticks + 2:
		sim.step()
	check_eq(sim.phase, Sim.Phase.PLAYING, "countdown started the match")
	var tiles0 := sim.st.o_tiles[p]
	check(tiles0 > 20, "start disk claimed")
	sim.submit(Commands.attack_target(p, 0, 10000.0))
	for i in 100:
		sim.step()
	check(sim.st.o_tiles[p] > tiles0 * 3, "expanded into free land (%d -> %d)" % [tiles0, sim.st.o_tiles[p]])
	check(sim.st.o_gold[p] > 0.0, "earned gold")


func test_bots_fight_each_other_and_someone_wins() -> void:
	var sim := TestMaps.sim(TestMaps.rect(200, 120), 4, false, 5)
	sim.config.victory.domination_share = 0.6
	var wars := 0
	var conquered_from_states := 0
	while sim.st.tick < 12000 and sim.phase != Sim.Phase.OVER:
		sim.step()
		for e in sim.events.drain():
			if e["type"] == SimEvents.ATTACK_STARTED and int(e["target"]) != 0:
				wars += 1
			if e["type"] == SimEvents.ATTACK_ENDED and int(e["target"]) != 0:
				conquered_from_states += int(e["taken"])
	check(wars > 3, "bots attack each other (%d)" % wars)
	check(conquered_from_states > 500, "real wars move borders (%d tiles)" % conquered_from_states)
	check_eq(sim.phase, Sim.Phase.OVER, "the match ends with a winner (tick %d)" % sim.st.tick)
	check(int(sim.result.get("winner", 0)) > 0)


func test_naval_landing_on_another_island() -> void:
	var sim := TestMaps.sim(TestMaps.rect(120, 60, true), 0, true, 3)
	sim.config.victory.eliminate_all = false
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(20, 30)))
	sim._start_playing()
	sim.st.add_supplies(p, 100.0)
	var target := sim.map.tile_at(64, 30)
	check_eq(sim.map.coastal[target], 1)
	# Grow to the coast first so a port of departure exists.
	sim.submit(Commands.attack_target(p, 0, 20000.0))
	for i in 150:
		sim.step()
	var reason := sim.apply_command(Commands.boat(p, target, 3000.0))
	check_eq(reason, "", "boat launched")
	check_eq(sim.naval.boats.size(), 1)
	for i in 200:
		sim.step()
	check_eq(sim.naval.boats.size(), 0, "boat arrived")
	var on_east := 0
	for t in sim.map.land_tiles:
		if sim.st.owner[t] == p and t % sim.map.width > 64:
			on_east += 1
	check(on_east > 20, "landing took land on the other island (%d)" % on_east)


func test_player_defeat_when_eliminated() -> void:
	var sim := TestMaps.sim(TestMaps.rect(80, 60), 1, true, 2)
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(40, 30)))
	sim._start_playing()
	var bot := 2
	for t in sim.map.land_tiles:
		if sim.st.owner[t] == p:
			sim.st.set_owner(t, bot)
	sim.step()
	check(not sim.is_player_alive(), "player eliminated")
	check_eq(sim.st.o_killer[p], bot)


func test_victory_by_domination() -> void:
	var sim := TestMaps.sim(TestMaps.rect(80, 60), 1, true, 2)
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(40, 30)))
	sim._start_playing()
	for t in sim.map.land_tiles:
		if sim.st.owner[t] == 0:
			sim.st.set_owner(t, p)
	for i in 10:
		sim.step()
	check_eq(sim.phase, Sim.Phase.OVER)
	check_eq(int(sim.result.get("winner", 0)), p)
