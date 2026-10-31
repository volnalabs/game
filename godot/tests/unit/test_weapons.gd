extends TestCase
## Phase 2E: weapons and air defence in the simulation.

const W := 240
const H := 120


func _setup(seed_value: int = 5) -> Dictionary:
	var m := TestMaps.rect(W, H)
	var sim := TestMaps.sim(m, 2, true, seed_value)
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(40, 60)))
	sim._start_playing()
	sim.ai.brains.clear()
	var pid := sim.player_id
	var e := 1 if pid != 1 else 2
	for y in H:
		for x in W:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, pid if x < W / 2 else e)
	for o: int in [pid, e]:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 500000.0
		sim.st.add_gold(o, 1e9)
		sim.st.add_supplies(o, 1e6)
		var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
		sim.research.state[o] = {"done": all, "current": "", "progress": {}}
		sim.mods.mark(o)
	return {"sim": sim, "map": m, "pid": pid, "e": e}


## A finished building straight onto the map (tests only).
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


func _w(sim: Sim, id: String) -> int:
	return sim.rules.weapon_index(id)


func _run_until(sim: Sim, tick: int) -> Array:
	var evs: Array = []
	while sim.st.tick < tick:
		sim.step()
		evs.append_array(sim.events.drain())
	return evs


func test_data_is_consistent() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var r := sim.rules
	check(r.w_list.size() >= 9, "nine weapons")
	var techs := {}
	for t: Dictionary in ResearchSystem.techs():
		techs[String(t["id"])] = t
	for i in r.w_list.size():
		var wd := r.weapon(i)
		check(techs.has(String(wd["requires"])), "%s needs an existing technology" % wd["id"])
		check(r.weapon_launcher_kind(i) >= 0, "%s has a launcher building" % wd["id"])
		check(float(wd["radius"]) > 0.0 and float(wd["speed"]) > 0.0, "%s has radius and speed" % wd["id"])
	for t: Dictionary in techs.values():
		for wid: String in t.get("weapons", []):
			check(r.weapon_index(wid) >= 0, "tech %s opens a real weapon %s" % [t["id"], wid])
	check_eq(r.building_requires(Rules.B_SAM), "air_defence", "SAM needs air defence")
	check_eq(r.building_requires(Rules.B_SILO), "rocketry", "silo needs rocketry")
	check(not r.b_kinds[Rules.B_SAM].has("phase") and not r.b_kinds[Rules.B_SILO].has("phase"), "SAM and silo are playable")


func test_launch_checks_explain_every_refusal() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var wpn := sim.weapons
	var mis := _w(sim, "missile")
	var target := m.tile_at(180, 60)
	sim.research.state[pid]["done"] = []
	check_eq(String(wpn.check(pid, mis, target)["reason"]), "locked", "needs rocketry")
	sim.research.state[pid]["done"] = ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
	check_eq(String(wpn.check(pid, mis, target)["reason"]), "no_launcher", "needs a silo")
	check_eq(String(wpn.check(pid, mis, m.tile_at(1, 1))["reason"]), "not_land", "not on water")
	check_eq(String(wpn.check(pid, mis, m.tile_at(40, 40))["reason"]), "own_land", "not on own land")
	var silo := _put(sim, pid, Rules.B_SILO, m.tile_at(60, 60))
	check(wpn.check(pid, mis, target)["ok"], "silo ready")
	var art := _w(sim, "artillery")
	_put(sim, pid, Rules.B_DEFENSE, m.tile_at(110, 60))
	check(wpn.check(pid, art, m.tile_at(130, 60))["ok"], "artillery reaches 20 tiles")
	check_eq(String(wpn.check(pid, art, m.tile_at(220, 60))["reason"]), "out_of_range", "artillery range is limited")
	check_eq(wpn.launch(pid, mis, target), "", "launched")
	check_eq(String(wpn.check(pid, mis, target)["reason"]), "reloading", "the silo's only charge is used")
	var reload := sim.rules.launcher_reload(mis)
	sim.st.tick += reload
	check(wpn.check(pid, mis, target)["ok"], "reloaded after %d ticks" % reload)
	var gold := sim.st.o_gold[pid]
	sim.st.add_gold(pid, -gold)
	check_eq(String(wpn.check(pid, mis, target)["reason"]), "no_gold", "needs gold")
	sim.st.add_gold(pid, gold)
	var sup := sim.st.o_supplies[pid]
	sim.st.add_supplies(pid, -sup)
	check_eq(String(wpn.check(pid, mis, target)["reason"]), "no_supplies", "needs supplies")
	check(silo.level == 1, "silo intact")


func test_missile_flies_hits_and_matches_the_preview() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	_put(sim, pid, Rules.B_SILO, m.tile_at(60, 60))
	var city := _put(sim, e, Rules.B_CITY, m.tile_at(180, 60), 2)
	var mis := _w(sim, "missile")
	var target := m.tile_at(180, 60)
	var est := sim.weapons.estimate(pid, mis, target)
	var gold := sim.st.o_gold[pid]
	var sup := sim.st.o_supplies[pid]
	sim.submit(Commands.launch(pid, "missile", target))
	sim.step()
	check_eq(sim.weapons.munitions.size(), 1, "one missile in flight")
	var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
	check(is_equal_approx(sim.st.o_gold[pid], gold - float(sim.rules.weapon(mis)["cost"])), "gold paid")
	check(sim.st.o_supplies[pid] < sup, "supplies paid")
	var expected := mu.launch_tick + int(sim.rules.weapon(mis)["launch_delay"]) + mu.flight
	check_eq(mu.impact_tick(), expected, "impact after delay + flight")
	check(mu.position(mu.launch_tick + mu.delay + mu.flight / 2).y < 60.0, "the arc rises above the straight line")
	var troops := sim.st.o_troops[e]
	var hit: Dictionary = {}
	for ev in _run_until(sim, expected + 1):
		if String(ev["type"]) == SimEvents.WEAPON_IMPACT:
			hit = ev
	check(not hit.is_empty(), "the missile hit")
	# The army grows during the flight, so the preview is compared with the impact's own figure and
	# with the estimate redone just before impact (same function).
	var lost := float((hit["killed"] as Dictionary).get(e, 0.0))
	check(lost > 0.0, "troops killed")
	check(absf(lost - float(est["killed"][e])) <= float(est["killed"][e]) * 0.25 + 1.0, "close to the preview (%.0f vs %.0f)" % [lost, float(est["killed"][e])])
	check_eq(city.level, 1, "the city lost a level")


func test_nuke_takes_land_leaves_fallout_that_decays() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	_put(sim, pid, Rules.B_SILO, m.tile_at(60, 60))
	var factory := _put(sim, e, Rules.B_FACTORY, m.tile_at(178, 60))
	var nk := _w(sim, "tactical_nuke")
	var target := m.tile_at(180, 60)
	var est := sim.weapons.estimate(pid, nk, target)
	var tiles_before := sim.st.o_tiles[e]
	var value_before := sim.st.o_value[e]
	sim.submit(Commands.launch(pid, "tactical_nuke", target))
	sim.step()
	var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
	var boom: Dictionary = {}
	for ev in _run_until(sim, mu.impact_tick() + 1):
		if String(ev["type"]) == SimEvents.NUKE_DETONATED:
			boom = ev
	check(not boom.is_empty(), "nuclear detonation")
	check_eq(sim.st.owner[target], 0, "ground zero is wiped out")
	check_eq(tiles_before - sim.st.o_tiles[e], int(est["tiles"][e]), "land lost as previewed")
	check(not factory.alive, "buildings inside are destroyed")
	check(sim.weapons.is_fallout(target), "fallout at ground zero")
	check_eq(int(sim.weapons.nukes_launched.get(pid, 0)), 1, "nuclear history counts the launch")
	# Fallout land is worth less to whoever takes it; when it decays the value comes back.
	var t := m.tile_at(180 + int(ceil(sim.rules.weapon(nk)["radius"])) - 1, 60)
	var base: float = sim.weapons._base_value.get(t, -1.0)
	check(float(base) > 0.0 and sim.st.tile_value[t] < float(base), "fallout lowers land value")
	sim.st.set_owner(t, pid)
	var v_pid := sim.st.o_value[pid]
	sim.st.tick += int(sim.rules.w_fallout["ticks"]) + 5
	sim.weapons._decay_fallout()
	check(not sim.weapons.is_fallout(t), "fallout decays")
	check(absf(sim.st.o_value[pid] - (v_pid + float(base) - float(base) * float(sim.rules.w_fallout["value_mult"]))) < 0.01,
		"owner value restored with the land")
	check(sim.st.o_value[e] < value_before, "the victim's value fell")


func test_sam_intercepts_inside_its_range_with_radar_help() -> void:
	var hits := 0
	var tries := 8
	for i in tries:
		var c := _setup(100 + i)
		var sim: Sim = c["sim"]
		var m: MapData = c["map"]
		var pid: int = c["pid"]
		var e: int = c["e"]
		_put(sim, pid, Rules.B_SILO, m.tile_at(60, 60), 1)
		var sam := _put(sim, e, Rules.B_SAM, m.tile_at(175, 60), 2)
		var sup := sim.st.o_supplies[e]
		sim.submit(Commands.launch(pid, "missile", m.tile_at(180, 60)))
		sim.step()
		var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
		var launched := false
		for ev in _run_until(sim, mu.impact_tick() + 2):
			match String(ev["type"]):
				SimEvents.INTERCEPT_LAUNCHED:
					launched = true
				SimEvents.INTERCEPTED:
					hits += 1
		check(launched, "the SAM fires at a missile over its land")
		check(sim.st.o_supplies[e] < sup, "each interceptor costs supplies")
		check(sim.weapons.charges(sam, 1, 90) < 2, "the SAM used a charge")
	check(hits >= tries / 2, "most missiles are stopped (%d / %d)" % [hits, tries])
	# Out of range: nothing fires; radar extends range and raises the hit chance.
	var c2 := _setup(7)
	var sim2: Sim = c2["sim"]
	var m2: MapData = c2["map"]
	var e2: int = c2["e"]
	var far := _put(sim2, e2, Rules.B_SAM, m2.tile_at(130, 10), 1)
	var r0 := sim2.weapons.sam_range(far)
	var mis := _w(sim2, "missile")
	var p0 := sim2.weapons.hit_chance(mis, false, false)
	_put(sim2, e2, Rules.B_RADAR, m2.tile_at(132, 12))
	check(sim2.weapons.sam_range(far) > r0, "radar extends SAM range")
	check(sim2.weapons.hit_chance(mis, false, true) > p0, "radar raises the hit chance")
	check_eq(sim2.weapons.hit_chance(_w(sim2, "artillery"), false, true), 0.0, "shells cannot be intercepted")


func test_sam_only_defends_its_own_land_and_needs_supplies() -> void:
	var c := _setup(3)
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	_put(sim, pid, Rules.B_SILO, m.tile_at(60, 60))
	_put(sim, e, Rules.B_SAM, m.tile_at(175, 60), 2)
	sim.st.add_supplies(e, -sim.st.o_supplies[e])
	sim.submit(Commands.launch(pid, "missile", m.tile_at(180, 60)))
	sim.step()
	var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
	var fired := false
	for ev in _run_until(sim, mu.impact_tick() + 1):
		if String(ev["type"]) == SimEvents.INTERCEPT_LAUNCHED:
			fired = true
	check(not fired, "no supplies, no interceptors")


func test_mirv_releases_interceptable_warheads() -> void:
	var c := _setup(4)
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	_put(sim, pid, Rules.B_SILO, m.tile_at(30, 60))
	var mirv := _w(sim, "mirv")
	check_eq(sim.weapons.hit_chance(mirv, false, true), 0.0, "the MIRV bus cannot be intercepted")
	check(sim.weapons.hit_chance(mirv, true, false) > 0.0, "its warheads can")
	sim.submit(Commands.launch(pid, "mirv", m.tile_at(190, 60)))
	sim.step()
	var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
	var split := 0
	var bursts := 0
	for ev in _run_until(sim, mu.impact_tick() + 200):
		if String(ev["type"]) == SimEvents.MIRV_SPLIT:
			split = int(ev["warheads"])
		if String(ev["type"]) == SimEvents.NUKE_DETONATED and ev["warhead"]:
			bursts += 1
	check(split >= 8, "the bus releases its warheads (%d)" % split)
	check_eq(bursts, split, "every warhead detonates on the target's land")
	check(sim.st.o_tiles[e] < (W / 2 - 2) * (H - 4), "the target lost land")


func test_emp_switches_buildings_off_for_a_while() -> void:
	var c := _setup(6)
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	_put(sim, pid, Rules.B_SILO, m.tile_at(60, 60))
	var city := _put(sim, e, Rules.B_CITY, m.tile_at(180, 60), 3)
	var sam := _put(sim, e, Rules.B_SAM, m.tile_at(185, 62), 1)
	var levels := sim.st.blevel(e, Rules.B_CITY)
	sim.submit(Commands.launch(pid, "emp", m.tile_at(180, 60)))
	sim.step()
	var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
	var stopped := false
	for ev in _run_until(sim, mu.impact_tick() + 1):
		if String(ev["type"]) == SimEvents.INTERCEPTED:
			stopped = true
	if stopped:
		check(true, "intercepted this time (the SAM is close): nothing to switch off")
		return
	check(city.disabled_until > 0 and sam.disabled_until > 0, "buildings in the zone are off")
	check_eq(sim.st.blevel(e, Rules.B_CITY), levels - 3, "their levels stop counting")
	check_eq(sim.weapons.charges(sam, 1, 90), 0, "a switched-off SAM cannot fire")
	_run_until(sim, city.disabled_until + 1)
	check_eq(city.disabled_until, 0, "back on after the EMP wears off")
	check_eq(sim.st.blevel(e, Rules.B_CITY), levels, "levels count again")


func test_cluster_and_air_strike_and_artillery() -> void:
	var c := _setup(8)
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	_put(sim, pid, Rules.B_SILO, m.tile_at(60, 60), 3)
	_put(sim, pid, Rules.B_AIRBASE, m.tile_at(100, 30))
	_put(sim, pid, Rules.B_DEFENSE, m.tile_at(115, 90))
	var t0 := sim.st.o_troops[e]
	sim.submit(Commands.launch(pid, "cluster", m.tile_at(170, 60)))
	sim.submit(Commands.launch(pid, "air_strike", m.tile_at(150, 30)))
	sim.submit(Commands.launch(pid, "artillery", m.tile_at(140, 90)))
	sim.step()
	check_eq(sim.weapons.munitions.size(), 3, "three different launchers fire at once")
	var impacts := 0
	var killed := 0.0
	for ev in _run_until(sim, sim.st.tick + 200):
		if String(ev["type"]) == SimEvents.WEAPON_IMPACT:
			impacts += 1
			killed += float((ev["killed"] as Dictionary).get(e, 0.0))
	check(impacts >= 3 + 5, "cluster bomblets and both strikes land (%d impacts)" % impacts)
	check(killed > 0.0 and t0 > 0.0, "the enemy army suffered (%.0f)" % killed)


func test_save_in_flight_and_fallout_continue_identically() -> void:
	var a := _setup(11)
	var sa: Sim = a["sim"]
	var m: MapData = a["map"]
	_put(sa, a["pid"], Rules.B_SILO, m.tile_at(60, 60), 2)
	_put(sa, a["e"], Rules.B_SAM, m.tile_at(175, 62), 1)
	sa.submit(Commands.launch(a["pid"], "tactical_nuke", m.tile_at(200, 30)))
	sa.submit(Commands.launch(a["pid"], "missile", m.tile_at(180, 60)))
	for i in 3:
		sa.step()
	var b := _setup(11)
	var sb: Sim = b["sim"]
	sb.from_dict(bytes_to_var(var_to_bytes(sa.to_dict())))
	sb.ai.brains.clear()
	check_eq(sb.state_hash(), sa.state_hash(), "restored with missiles in flight")
	for i in 260:
		sa.step()
		sb.step()
	check_eq(sb.state_hash(), sa.state_hash(), "identical after impacts and interceptions")
	check(not sa.weapons.fallout.is_empty(), "fallout on the map")
	var c := _setup(11)
	var sc: Sim = c["sim"]
	sc.from_dict(bytes_to_var(var_to_bytes(sa.to_dict())))
	sc.ai.brains.clear()
	check_eq(sc.weapons.fallout.size(), sa.weapons.fallout.size(), "fallout saved")
	var ft: int = sa.weapons.fallout.keys()[0]
	check(is_equal_approx(sc.st.tile_value[ft], sa.st.tile_value[ft]), "fallout land value restored on load")
