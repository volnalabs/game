extends TestCase
## Determinism and saves: the same seed replays the same match; a save restores the exact state.


func _new_sim(seed_value: int) -> Sim:
	var sim := TestMaps.sim(TestMaps.rect(160, 100), 5, false, seed_value, 6)
	return sim


func test_same_seed_same_match() -> void:
	var a := _new_sim(21)
	var b := _new_sim(21)
	for i in 600:
		a.step()
		b.step()
	check_eq(a.state_hash(), b.state_hash(), "identical after 600 ticks")
	var c := _new_sim(22)
	for i in 600:
		c.step()
	check(a.state_hash() != c.state_hash(), "another seed diverges")


func test_save_load_continues_identically() -> void:
	var a := _new_sim(31)
	for i in 400:
		a.step()
	var bytes := var_to_bytes(a.to_dict())
	var b := _new_sim(31)
	b.from_dict(bytes_to_var(bytes))
	check_eq(b.state_hash(), a.state_hash(), "restored state equals the saved one")
	for i in 400:
		a.step()
		b.step()
	check_eq(b.state_hash(), a.state_hash(), "loaded match continues exactly like the original")


func test_save_file_roundtrip_with_generated_map() -> void:
	var res := MapGenerator.new().generate(GenParams.from_preset("archipelago", 77, "S"))
	var def := MapGenerator.definition_for(res)
	var cfg := TestMaps.config(4, true, 5, 4)
	cfg.map_id = "generated"
	cfg.generator = def.generator
	var sim := Sim.new(cfg, def, res.map)
	var start := res.starts[0]
	sim.submit(Commands.spawn(sim.player_id, start))
	for i in 300:
		sim.step()
	var path := SaveManager.save(sim, "test_roundtrip")
	check(path != "", "saved")
	var h := SaveManager.read_header(path)
	check_eq(int(h["version"]), SaveFormat.VERSION)
	var data := SaveManager.read(path)
	var m := SaveManager.restore_match(data)
	check(not m.is_empty(), "restorable")
	check_eq((m["map"] as MapData).terrain_hash, res.map.terrain_hash, "generated map rebuilt from its seed")
	var sim2 := Sim.new(m["config"], m["def"], m["map"])
	sim2.from_dict(m["state"])
	check_eq(sim2.state_hash(), sim.state_hash(), "state restored from file")
	for i in 200:
		sim.step()
		sim2.step()
	check_eq(sim2.state_hash(), sim.state_hash(), "continues identically")
	SaveManager.delete(path)
