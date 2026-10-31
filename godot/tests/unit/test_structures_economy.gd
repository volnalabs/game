extends TestCase
## Buildings and the economy inside a running simulation.


func _own_block(sim: Sim, id: int, x0: int, y0: int, size: int) -> void:
	for y in range(y0, y0 + size):
		for x in range(x0, x0 + size):
			sim.st.set_owner(sim.map.tile_at(x, y), id)


func test_city_build_upgrade_and_capture() -> void:
	var sim := TestMaps.sim(TestMaps.rect(120, 80), 0, true)
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(30, 30)))
	sim._start_playing()
	_own_block(sim, p, 10, 10, 50)
	sim.st.add_gold(p, 1000000.0)
	var gold0 := sim.st.o_gold[p]
	check_eq(sim.apply_command(Commands.build(p, Rules.B_CITY, sim.map.tile_at(30, 30))), "")
	check_near(gold0 - sim.st.o_gold[p], 125000.0, 0.1, "city costs 125K")
	check_eq(sim.st.blevel(p, Rules.B_CITY), 0, "not active while building")
	for i in sim.rules.building_ticks(Rules.B_CITY) + 1:
		sim.st.tick += 1
		sim.structures.tick()
	check_eq(sim.st.blevel(p, Rules.B_CITY), 1, "active when finished")
	# A second order next to it upgrades (costs the next price).
	check_eq(sim.apply_command(Commands.build(p, Rules.B_CITY, sim.map.tile_at(32, 31))), "")
	check_eq(sim.structures.of_owner(p, Rules.B_CITY).size(), 1, "upgrade, not a new city")
	check_eq(sim.st.bowned(p, Rules.B_CITY), 2)
	# Too close to another building: a new factory goes at least 15 tiles away.
	check_eq(sim.apply_command(Commands.build(p, Rules.B_FACTORY, sim.map.tile_at(31, 30))), "")
	var f: StructureSystem.Structure = sim.structures.of_owner(p, Rules.B_FACTORY)[0]
	check(sim.map.dist2(f.tile, sim.structures.of_owner(p, Rules.B_CITY)[0].tile) >= 15 * 15, "spacing kept")
	# Capture: the city changes hands with its tile, a defence post is destroyed.
	var enemy := sim.st.add_owner("E", Rules.KIND_NATION, Color.RED)
	sim.st.o_alive[enemy] = 1
	var city: StructureSystem.Structure = sim.structures.of_owner(p, Rules.B_CITY)[0]
	sim.st.set_owner(city.tile, enemy)
	check_eq(city.owner, enemy, "captured")
	check_eq(sim.st.bowned(enemy, Rules.B_CITY), 2)


func test_ports_need_a_coast() -> void:
	var sim := TestMaps.sim(TestMaps.rect(120, 80), 0, true)
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(50, 40)))
	sim._start_playing()
	_own_block(sim, p, 40, 30, 20)
	sim.st.add_gold(p, 1000000.0)
	check_eq(sim.apply_command(Commands.build(p, Rules.B_PORT, sim.map.tile_at(50, 40))), "no_site", "inland: no port")
	_own_block(sim, p, 2, 2, 20)
	check_eq(sim.apply_command(Commands.build(p, Rules.B_PORT, sim.map.tile_at(3, 10))), "")


func test_upkeep_and_bankruptcy() -> void:
	var sim := TestMaps.sim(TestMaps.rect(120, 80), 0, true)
	var p := sim.player_id
	sim._start_playing()
	_own_block(sim, p, 10, 10, 20)
	sim.st.o_spawned[p] = 1
	sim.st.set_troops(p, 1e7)
	sim.st.add_gold(p, 100.0)
	sim.economy.tick()
	check(sim.st.o_upkeep[p] > sim.st.o_income[p], "a huge army costs more than it earns")
	var troops := sim.st.o_troops[p]
	for i in 20:
		sim.economy.tick()
	check_near(sim.st.o_gold[p], 0.0, 0.001, "treasury empty")
	check(sim.st.o_troops[p] < troops, "bankrupt army deserts")
