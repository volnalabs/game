extends TestCase
## The attack front advances the same way in every direction (no west / east bias in tile
## indexing, neighbour order, border lists or front priorities).


func _run_attack(dir: Vector2i) -> int:
	var sim := TestMaps.sim(TestMaps.rect(200, 200), 1, true, 5)
	sim.config.victory.eliminate_all = false
	var m := sim.map
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, m.tile_at(100, 100)))
	sim._start_playing()
	for t in m.land_tiles:
		sim.st.set_owner(t, 0)
	var enemy: int = sim.ai.brains[0].id
	sim.ai.brains.clear()
	for y in range(80, 121):
		for x in range(80, 121):
			sim.st.set_owner(m.tile_at(x, y), p)
	var c := Vector2i(100, 100) + dir * 41
	for y in range(c.y - 20, c.y + 21):
		for x in range(c.x - 20, c.x + 21):
			sim.st.set_owner(m.tile_at(x, y), enemy)
	sim.st.set_troops(p, 200000.0)
	sim.st.set_troops(enemy, 20000.0)
	sim.apply_command(Commands.attack_target(p, enemy, 60000.0))
	for i in 30:
		sim.attacks.tick()
		sim.st.tick += 1
	var taken := 0
	for y in range(c.y - 20, c.y + 21):
		for x in range(c.x - 20, c.x + 21):
			if sim.st.owner[m.tile_at(x, y)] == p:
				taken += 1
	return taken


func test_attacks_advance_equally_in_all_directions() -> void:
	var res := {}
	for d in {"W": Vector2i(-1, 0), "E": Vector2i(1, 0), "N": Vector2i(0, -1), "S": Vector2i(0, 1)}.values():
		res[d] = _run_attack(d)
	var lo := 1 << 30
	var hi := 0
	for d in res:
		lo = mini(lo, res[d])
		hi = maxi(hi, res[d])
	check(lo > 50, "every direction advances (%s)" % str(res))
	check(float(hi) <= float(lo) * 1.15, "advances are symmetric within 15%% (%s)" % str(res))
