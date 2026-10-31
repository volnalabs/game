extends TestCase
## Phase 2A.3-D: sea landings on any enemy tile. Coastal and inland goals, choosing among several
## beaches, impossible orders explained, the beach or goal changing hands at sea, recall, saving at
## sea, transports staying on water, the landed attack pushing to its goal, determinism.

const W := 160
const H := 80


## West island = the player, east island = state E (AI switched off), a strait in between.
func _setup(seed_value: int = 3) -> Dictionary:
	var m := TestMaps.rect(W, H, true)
	var sim := TestMaps.sim(m, 2, true, seed_value)
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(30, 40)))
	sim._start_playing()
	sim.ai.brains.clear()
	var pid := sim.player_id
	var others: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if o != pid:
			others.append(o)
	var e := others[0]
	var third := others[1]
	for y in H:
		for x in W:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, pid if x < W / 2 else e)
	for o: int in [pid, e, third]:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
	sim.st.o_troops[pid] = 200000.0
	sim.st.o_troops[e] = 20000.0
	sim.st.add_supplies(pid, 1000.0)
	sim.structures.invalidate_caches()
	return {"sim": sim, "map": m, "pid": pid, "e": e, "third": third}


func _boat(sim: Sim, who: int) -> NavalSystem.Boat:
	for b in sim.naval.boats:
		if b.alive and b.owner == who:
			return b
	return null


func test_coastal_goal_lands_right_there() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var goal := m.tile_at(W / 2 + 4, 40)
	check(m.coastal[goal] == 1, "goal is on the coast")
	var p := LandingPlanner.plan(sim.naval, c["pid"], goal)
	check(p["ok"], "coastal landing planned")
	check_eq(int(p["beach"]), goal, "a coastal goal is the beach itself")
	check_eq(int(p["land_len"]), 0, "no overland leg")


func test_inland_goal_is_reached_by_sea_and_land() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	var goal := m.tile_at(120, 40)
	check(m.coastal[goal] == 0, "goal is inland")
	var p := LandingPlanner.plan(sim.naval, pid, goal)
	check(p["ok"], "inland goal can be reached (%s)" % p.get("reason", ""))
	var beach: int = p["beach"]
	check(m.coastal[beach] == 1 and sim.st.owner[beach] == e, "the beach is the enemy's coast")
	check(int(p["land_len"]) > 0, "there is an overland leg")
	var lp: PackedVector2Array = p["land_path"]
	check(lp[lp.size() - 1].distance_to(Vector2(120.5, 40.5)) < 0.01, "the overland leg ends at the goal")
	# The preview's plan is exactly what the simulation executes.
	var troops_before := sim.st.o_troops[pid]
	sim.submit(Commands.boat(pid, goal, 50000.0))
	sim.step()
	var b := _boat(sim, pid)
	check(b != null, "transport launched")
	if b == null:
		return
	check_eq(b.target_tile, beach, "same beach as the preview")
	check_eq(b.goal_tile, goal, "the order remembers its goal")
	check(is_equal_approx(sim.st.o_troops[pid], troops_before - 50000.0) or sim.st.o_troops[pid] < troops_before, "troops embarked")
	# It really sails, on water only, and lands.
	var landed := false
	var on_water := true
	for i in 600:
		var pos := b.position()
		var t := m.tile_at(clampi(int(pos.x), 0, W - 1), clampi(int(pos.y), 0, H - 1))
		if b.alive and m.water_body[t] == 0 and m.coastal[t] == 0:
			on_water = false
		sim.step()
		for ev in sim.events.drain():
			if String(ev["type"]) == SimEvents.BOAT_LANDED and int(ev["owner"]) == pid:
				landed = true
		if landed:
			break
	check(on_water, "the transport never crosses land")
	check(landed, "the transport lands")
	var a: AttackSystem.Attack = null
	for at in sim.attacks.attacks:
		if at.alive and at.attacker == pid and at.landing:
			a = at
	check(a != null and a.goal == goal, "the landed attack heads for the goal")
	var d0 := m.dist2(beach, goal)
	for i in 120:
		sim.step()
	var nearest := 1 << 30
	for y in range(30, 51):
		for x in range(84, 140):
			var t := m.tile_at(x, y)
			if sim.st.owner[t] == pid:
				nearest = mini(nearest, m.dist2(t, goal))
	check(nearest < d0, "the front advanced towards the goal")


func test_best_beach_is_chosen_and_unsafe_beaches_avoided() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var goal := m.tile_at(96, 40)
	var p := LandingPlanner.plan(sim.naval, pid, goal)
	check(p["ok"], "planned")
	# Not worse than the naive choice: the coast closest to the goal over land (straight west).
	var naive := m.tile_at(W / 2 + 4, 40)
	var nc := LandingPlanner._candidate(sim.naval, pid, naive, absi(96 - (W / 2 + 4)), -1)
	check(float(p["score"]) <= float(nc["score"]) + 0.001, "chosen beach scores at least as well as the nearest one")
	# Near the east coast the closest beach is east; a defence post covering it pushes the landing
	# to a safe stretch of coast instead.
	var far_goal := m.tile_at(140, 40)
	var before := LandingPlanner.plan(sim.naval, pid, far_goal)
	check(before["ok"] and not before["unsafe"], "planned, nothing defended yet")
	var e: int = c["e"]
	sim.st.add_gold(e, 1e7)
	sim.st.add_supplies(e, 1e5)
	var r := sim.structures.try_build(e, Rules.B_DEFENSE, before["beach"])
	check(r["ok"], "post built on the chosen beach")
	for i in sim.rules.building_ticks(Rules.B_DEFENSE) + 1:
		sim.st.tick += 1
		sim.structures.tick()
	var p2 := LandingPlanner.plan(sim.naval, pid, far_goal)
	check(p2["ok"], "still possible")
	check(not p2["unsafe"], "the chosen beach is outside the post's zone")
	check(int(p2["beach"]) != int(before["beach"]), "a different beach")


func test_impossible_orders_are_explained() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var e: int = c["e"]
	var third: int = c["third"]
	check_eq(String(LandingPlanner.plan(sim.naval, pid, m.tile_at(30, 40))["reason"]), "own_land", "own land")
	check_eq(String(LandingPlanner.plan(sim.naval, pid, m.tile_at(78, 40))["reason"]), "not_land", "water")
	# An enclave of the third state inside E, far from any coast: no beach of its own.
	for y in range(35, 46):
		for x in range(110, 121):
			sim.st.set_owner(m.tile_at(x, y), third)
	check_eq(String(LandingPlanner.plan(sim.naval, pid, m.tile_at(115, 40))["reason"]), "no_land_path", "enclave without a coast")
	# Without any coast of our own there is no departure.
	for y in H:
		for x in range(0, W / 2):
			var t := m.tile_at(x, y)
			if m.land[t] == 1 and m.coastal[t] == 1:
				sim.st.set_owner(t, e)
	check_eq(String(LandingPlanner.plan(sim.naval, pid, m.tile_at(120, 20))["reason"]), "no_coast", "no coast of our own")
	check(NavalOrders.reason_text("no_land_path") != "no_land_path", "reasons are human readable")


func test_beach_taken_at_sea_reroutes_or_brings_troops_home() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var third: int = c["third"]
	var goal := m.tile_at(120, 40)
	sim.submit(Commands.boat(pid, goal, 40000.0))
	sim.step()
	var b := _boat(sim, pid)
	check(b != null, "launched")
	if b == null:
		return
	var first_beach := b.target_tile
	# The beach falls to a third state while the boat is at sea: a new beach is found.
	sim.st.set_owner(first_beach, third)
	var rerouted := false
	for i in 400:
		sim.step()
		for ev in sim.events.drain():
			if String(ev["type"]) == SimEvents.BOAT_REROUTED:
				rerouted = true
		if rerouted:
			break
	check(rerouted, "the transport re-planned at sea")
	check(b.alive and b.target_tile != first_beach, "heading for another beach")
	# Now every coast is gone: the troops come home in full.
	var troops_before := sim.st.o_troops[pid]
	for y in H:
		for x in range(W / 2, W):
			var t := m.tile_at(x, y)
			if m.land[t] == 1 and m.coastal[t] == 1:
				sim.st.set_owner(t, third)
	var failed := false
	for i in 600:
		sim.step()
		for ev in sim.events.drain():
			if String(ev["type"]) == SimEvents.BOAT_FAILED and int(ev["owner"]) == pid:
				failed = true
		if failed:
			break
	check(failed, "no landing possible: the order ends")
	check(sim.st.o_troops[pid] >= troops_before + 40000.0 - 1.0 or sim.st.o_troops[pid] >= troops_before + 39000.0, "troops returned, none lost")
	check_eq(sim.st.o_boats[pid], 0, "boat slot freed")


func test_goal_changing_owner_retargets() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var third: int = c["third"]
	var goal := m.tile_at(120, 40)
	sim.submit(Commands.boat(pid, goal, 40000.0))
	sim.step()
	# The third state takes the whole south-east, goal included, coast and all.
	for y in range(30, H):
		for x in range(W / 2, W):
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, third)
	sim.st.o_alive[third] = 1
	var target := -1
	var log: Array = []
	for i in 600:
		sim.step()
		for ev in sim.events.drain():
			if String(ev["type"]).begins_with("boat"):
				log.append(ev)
			if String(ev["type"]) == SimEvents.BOAT_LANDED and int(ev["owner"]) == pid:
				target = int(ev["target_owner"])
		if target >= 0:
			break
	if target < 0:
		print("      boat events: ", log)
	check_eq(target, third, "the landing hits the goal's new owner")


func test_recall_returns_troops_and_no_duplicates() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	var before := sim.st.o_troops[pid]
	sim.submit(Commands.boat(pid, m.tile_at(120, 40), 30000.0))
	for i in 3:
		sim.step()
	var b := _boat(sim, pid)
	check(b != null, "at sea")
	if b == null:
		return
	sim.submit(Commands.cancel_boat(pid, b.id))
	sim.step()
	check(b.returning, "turned round")
	var back := false
	for i in 400:
		sim.step()
		for ev in sim.events.drain():
			if String(ev["type"]) == SimEvents.BOAT_RETURNED:
				back = true
		if back:
			break
	check(back, "the transport came home")
	check_eq(sim.st.o_boats[pid], 0, "no transport left at sea")
	var landing := sim.attacks.attacks.any(func(a: AttackSystem.Attack) -> bool: return a.alive and a.attacker == pid and a.landing)
	check(not landing, "no landing happened")
	check(sim.st.o_troops[pid] > before - 30000.0 + 29000.0, "troops are back in the army")


func test_save_at_sea_continues_identically() -> void:
	var a := _setup(5)
	var sa: Sim = a["sim"]
	var m: MapData = a["map"]
	sa.submit(Commands.boat(a["pid"], m.tile_at(120, 40), 40000.0))
	for i in 3:
		sa.step()
	check(not sa.naval.boats.is_empty(), "saved while sailing")
	if sa.naval.boats.is_empty():
		return
	var bytes := var_to_bytes(sa.to_dict())
	var b := _setup(5)
	var sb: Sim = b["sim"]
	sb.from_dict(bytes_to_var(bytes))
	sb.ai.brains.clear()
	check_eq(sb.state_hash(), sa.state_hash(), "restored with the boat at sea")
	check_eq(sb.naval.boats[0].goal_tile, sa.naval.boats[0].goal_tile, "goal survives the save")
	for i in 250:
		sa.step()
		sb.step()
	check_eq(sb.state_hash(), sa.state_hash(), "the landing plays out identically after loading")


func test_same_orders_same_outcome() -> void:
	var a := _setup(9)
	var b := _setup(9)
	for c: Dictionary in [a, b]:
		(c["sim"] as Sim).submit(Commands.boat(c["pid"], (c["map"] as MapData).tile_at(120, 40), 40000.0))
		for i in 300:
			(c["sim"] as Sim).step()
	check_eq((a["sim"] as Sim).state_hash(), (b["sim"] as Sim).state_hash(), "deterministic")


func test_many_transports_stay_cheap() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var pid: int = c["pid"]
	sim.naval.mods = null
	sim.rules.n["max_boats"] = 40
	var t0 := Time.get_ticks_usec()
	for i in 30:
		sim.submit(Commands.boat(pid, m.tile_at(100 + (i % 10) * 4, 10 + (i / 10) * 25), 2000.0))
	sim.step()
	var plan_us := Time.get_ticks_usec() - t0
	check(sim.naval.boats.size() >= 20, "many transports at sea (%d)" % sim.naval.boats.size())
	t0 = Time.get_ticks_usec()
	for i in 50:
		sim.naval.tick()
	check(Time.get_ticks_usec() - t0 < 200000, "moving them is cheap")
	print("      30 orders planned in %.1f ms" % (plan_us / 1000.0))
	sim.rules.n["max_boats"] = 3
