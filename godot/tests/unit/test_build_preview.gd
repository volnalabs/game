extends TestCase
## The build ghost uses StructureSystem.preview: it must agree with the real build on every tile
## (same site, same verdict, same reason) and explain refusals precisely.


func _setup() -> Sim:
	var sim := TestMaps.sim(TestMaps.rect(120, 80), 0, true)
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(40, 40)))
	sim._start_playing()
	for y in range(20, 60):
		for x in range(2, 70):
			sim.st.set_owner(sim.map.tile_at(x, y), p)
	return sim


func test_preview_matches_the_real_build_everywhere() -> void:
	var sim := _setup()
	var p := sim.player_id
	sim.st.add_gold(p, 50000000.0)
	sim.st.add_supplies(p, 100000.0)
	var mismatches := 0
	var checked := 0
	for kind in [Rules.B_CITY, Rules.B_PORT, Rules.B_FACTORY, Rules.B_DEFENSE]:
		for y in range(10, 70, 7):
			for x in range(0, 90, 9):
				var t := sim.map.tile_at(x, y)
				var pv := sim.structures.preview(p, kind, t)
				var n_before := sim.structures.structs.size()
				var r := sim.structures.try_build(p, kind, t)
				checked += 1
				if bool(r["ok"]) != bool(pv["ok"]) or (not r["ok"] and String(r["reason"]) != String(pv["reason"])):
					mismatches += 1
				elif r["ok"]:
					var s: StructureSystem.Structure = sim.structures.structs[int(r["id"])]
					if s.tile != int(pv["tile"]):
						mismatches += 1
					if int(pv["upgrade"]) >= 0 and sim.structures.structs.size() != n_before:
						mismatches += 1
	check(checked > 100, "enough samples")
	check_eq(mismatches, 0, "preview agrees with try_build")


func test_preview_has_no_side_effects() -> void:
	var sim := _setup()
	var p := sim.player_id
	sim.st.add_gold(p, 1000000.0)
	var gold := sim.st.o_gold[p]
	var pv := sim.structures.preview(p, Rules.B_CITY, sim.map.tile_at(40, 40))
	check(pv["ok"], "valid")
	check_near(sim.st.o_gold[p], gold, 0.001, "no gold spent")
	check_eq(sim.structures.structs.size(), 0, "nothing built")


func test_refusal_reasons() -> void:
	var sim := _setup()
	var p := sim.player_id
	# Not enough gold: still shows where it would go.
	var poor := sim.structures.preview(p, Rules.B_CITY, sim.map.tile_at(40, 40))
	sim.st.add_gold(p, -sim.st.o_gold[p])
	poor = sim.structures.preview(p, Rules.B_CITY, sim.map.tile_at(40, 40))
	check_eq(poor["reason"], "no_gold")
	check(int(poor["tile"]) >= 0, "site still shown")
	sim.st.add_gold(p, 10000000.0)
	check_eq(sim.structures.preview(p, Rules.B_CITY, sim.map.tile_at(100, 40))["detail"], "not_own_land")
	check_eq(sim.structures.preview(p, Rules.B_PORT, sim.map.tile_at(40, 40))["detail"], "no_coast")
	check_eq(sim.structures.preview(p, Rules.B_DEFENSE, sim.map.tile_at(40, 40))["reason"], "no_supplies")
	sim.st.add_supplies(p, 10000.0)
	var d := sim.structures.preview(p, Rules.B_DEFENSE, sim.map.tile_at(40, 40))
	check(d["ok"], "defence post valid")
	check_near(float(d["radius"]), sim.rules.defense_radius(), 0.001, "radius = the radius combat uses")
	sim.structures.try_build(p, Rules.B_CITY, sim.map.tile_at(40, 40))
	var up := sim.structures.preview(p, Rules.B_CITY, sim.map.tile_at(41, 40))
	check(int(up["upgrade"]) < 0, "an unfinished city is not upgraded")
	for i in sim.rules.building_ticks(Rules.B_CITY) + 1:
		sim.st.tick += 1
		sim.structures.tick()
	up = sim.structures.preview(p, Rules.B_CITY, sim.map.tile_at(41, 40))
	check(int(up["upgrade"]) >= 0, "next to a finished city: upgrade")
	check_eq(int(up["level"]), 2)
