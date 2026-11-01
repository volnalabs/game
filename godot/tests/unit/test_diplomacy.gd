extends TestCase
## Phase 2F: diplomacy in the simulation.

const W := 240
const H := 120


## Three states in vertical bands: A (west), B (middle), C (east). AI off.
func _setup(seed_value: int = 3, teams: int = 0) -> Dictionary:
	var m := TestMaps.rect(W, H)
	var cfg := TestMaps.config(3, false, seed_value, 0)
	cfg.teams = teams
	var sim := Sim.new(cfg, TestMaps.definition(m), m)
	sim.ai.brains.clear()
	var ids: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if sim.st.o_kind[o] != Rules.KIND_TRIBE:
			ids.append(o)
	for y in H:
		for x in W:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, ids[0] if x < 80 else (ids[1] if x < 160 else ids[2]))
	for o in ids:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 200000.0
		sim.st.add_gold(o, 1e8)
		sim.st.add_supplies(o, 1e5)
	return {"sim": sim, "map": m, "a": ids[0], "b": ids[1], "c": ids[2]}


func _run(sim: Sim, ticks: int) -> Array:
	var evs: Array = []
	for i in ticks:
		sim.step()
		evs.append_array(sim.events.drain())
	return evs


func test_alliance_request_answer_expiry_and_cooldown() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var dp := sim.diplomacy
	var a: int = c["a"]
	var b: int = c["b"]
	check_eq(dp.request(a, b, "alliance"), "", "asked")
	check_eq(dp.request(a, b, "alliance"), "already_asked", "no double request")
	check_eq(dp.requests_to(b).size(), 1, "B sees the request")
	check_eq(dp.reply(b, a, true), "", "accepted")
	check(dp.allied(a, b), "allied")
	check_eq(dp.relation(a, b), "alliance", "relation")
	check_eq(dp.request(a, b, "nap"), "already", "already allied")
	# Requests expire; asking again waits for the cooldown.
	var cc: int = c["c"]
	dp.request(a, cc, "nap")
	_run(sim, int(sim.rules.dip["request_ticks"]) + 1)
	check(dp.pending(a, cc).is_empty(), "the request expired")
	check_eq(dp.request(a, cc, "nap"), "cooldown", "cooldown before asking again")
	_run(sim, int(sim.rules.dip["request_cooldown_ticks"]))
	check_eq(dp.request(a, cc, "nap"), "", "can ask again later")
	# Both asking at once is an agreement.
	check_eq(dp.request(cc, a, "nap"), "", "the answer by asking back")
	check(dp.has_nap(a, cc), "pact formed")


func test_partners_cannot_attack_land_on_or_strike_each_other() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var a: int = c["a"]
	var b: int = c["b"]
	var cc: int = c["c"]
	var atk := sim.attacks.start(a, b, 20000.0)
	check(atk != null and atk.alive, "at war before the pact")
	check_eq(sim.diplomacy.relation(a, b), "neutral", "war shows once the tick sees the attack")
	sim.step()
	check_eq(sim.diplomacy.relation(a, b), "war", "now at war")
	sim.diplomacy.request(a, b, "nap")
	sim.diplomacy.reply(b, a, true)
	check(not atk.alive, "a new pact stops the fighting")
	sim.submit(Commands.attack_target(a, b, 10000.0))
	sim.step()
	var rejected := ""
	for e in sim.events.drain():
		if String(e["type"]) == SimEvents.COMMAND_REJECTED:
			rejected = String(e["reason"])
	check_eq(rejected, "pact", "attacks on a pact partner are refused")
	sim.st.add_supplies(a, 1000.0)
	check_eq(sim.naval.launch(a, m.tile_at(120, 60), 1000.0), "pact", "no landings on a partner")
	var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
	sim.research.state[a] = {"done": all, "current": "", "progress": {}}
	check_eq(String(sim.weapons.check(a, sim.rules.weapon_index("missile"), m.tile_at(120, 60))["reason"]), "pact", "no strikes on a partner")
	check(sim.diplomacy.can_attack(a, cc), "others remain fair game")


func test_alliance_expires_unless_both_renew() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var dp := sim.diplomacy
	var a: int = c["a"]
	var b: int = c["b"]
	dp.request(a, b, "alliance")
	dp.reply(b, a, true)
	check_eq(dp.extend(a, b), "too_early", "renewal only near the end")
	var length := int(sim.rules.dip["alliance_ticks"])
	var window := int(sim.rules.dip["extend_window_ticks"])
	_run(sim, length - window + 1)
	check(dp.in_extend_window(a, b), "renewal window open")
	check_eq(dp.extend(a, b), "asked", "one side asked")
	check_eq(dp.extend(b, a), "renewed", "both asked: renewed")
	check(dp.time_left(a, b) > window, "extended")
	_run(sim, dp.time_left(a, b) + 1)
	check(not dp.allied(a, b), "expired without a second renewal")


func test_breaking_a_pact_makes_a_traitor_who_is_cheaper_to_attack() -> void:
	var c := _setup(5)
	var sim: Sim = c["sim"]
	var dp := sim.diplomacy
	var a: int = c["a"]
	var b: int = c["b"]
	var cc: int = c["c"]
	dp.request(b, cc, "alliance")
	dp.reply(cc, b, true)
	check_eq(dp.break_pact(b, cc), "", "broken")
	check(not dp.allied(b, cc), "no longer allied")
	check(dp.is_traitor(b), "the breaker is a traitor")
	check(not dp.is_traitor(cc), "the other side is not")
	# Same attack on B, with and without the traitor mark: fewer attacker losses on a traitor.
	var lost := []
	for traitor in [true, false]:
		var c2 := _setup(5)
		var s2: Sim = c2["sim"]
		if traitor:
			s2.diplomacy.traitor_until[c2["b"]] = 1 << 30
		var at := s2.attacks.start(c2["a"], c2["b"], 50000.0)
		for i in 30:
			s2.attacks.tick()
		lost.append(at.lost / maxf(1.0, float(at.taken)))
	check(float(lost[0]) < float(lost[1]) * 0.75, "attacking a traitor costs fewer troops (%.1f vs %.1f per tile)" % [lost[0], lost[1]])
	check(a > 0, "ok")


func test_convoys_carry_troops_and_gold_to_allies() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var dp := sim.diplomacy
	var a: int = c["a"]
	var b: int = c["b"]
	var cc: int = c["c"]
	check_eq(dp.send(a, b, "troops", 1000.0), "not_ally", "only to allies")
	dp.request(a, b, "alliance")
	dp.reply(b, a, true)
	var ta := sim.st.o_troops[a]
	check_eq(dp.send(a, b, "troops", 30000.0), "", "troops sent")
	check(is_equal_approx(sim.st.o_troops[a], ta - 30000.0), "they leave the army now")
	check_eq(dp.send(a, b, "gold", 500000.0), "", "gold sent")
	var cv := dp.convoys[0]
	check(cv.arrive > sim.st.tick + int(sim.rules.dip["convoy_min_ticks"]) - 1, "they travel")
	var tb := sim.st.o_troops[b]
	var gb := sim.st.o_gold[b]
	var arrived := 0
	for e in _run(sim, cv.arrive - sim.st.tick + 2):
		if String(e["type"]) == SimEvents.CONVOY_ARRIVED:
			arrived += 1
	check_eq(arrived, 2, "both convoys arrive")
	check(sim.st.o_troops[b] > tb + 29000.0, "troops joined the ally")
	check(sim.st.o_gold[b] > gb + 490000.0, "gold arrived")
	# A convoy goes home when the alliance ends on the way.
	dp.send(a, b, "troops", 10000.0)
	var back_from := sim.st.o_troops[a]
	dp.break_pact(a, b)
	var returned := false
	for e in _run(sim, 200):
		if String(e["type"]) == SimEvents.CONVOY_ARRIVED and e["returned"]:
			returned = true
	check(returned, "the convoy turned back")
	check(sim.st.o_troops[a] > back_from + 9000.0, "troops came home")
	check(cc > 0, "ok")


func test_help_request_answered_with_an_attack() -> void:
	var c := _setup()
	var sim: Sim = c["sim"]
	var dp := sim.diplomacy
	var a: int = c["a"]
	var b: int = c["b"]
	var cc: int = c["c"]
	dp.request(a, b, "alliance")
	dp.reply(b, a, true)
	check_eq(dp.ask_help(a, b, cc), "", "A asks B for help against C")
	check_eq(dp.help_for(b).size(), 1, "B sees it")
	check_eq(dp.answer_help(b, a, true, 30000.0), "", "B answers")
	check(sim.attacks.find(b, cc) != null, "B attacks C")
	check_eq(dp.ask_help(a, b, b), "bad_target", "cannot ask for help against the ally itself")


func test_sam_defends_an_ally_and_nukes_break_alliances() -> void:
	var c := _setup(7)
	var sim: Sim = c["sim"]
	var m: MapData = c["map"]
	var a: int = c["a"]
	var b: int = c["b"]
	var cc: int = c["c"]
	var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
	for o in [a, b, cc]:
		sim.research.state[o] = {"done": all, "current": "", "progress": {}}
	sim.diplomacy.request(b, cc, "alliance")
	sim.diplomacy.reply(cc, b, true)
	# C's SAM stands next to B's land and defends it.
	var ss := sim.structures
	for spec: Array in [[a, Rules.B_SILO, m.tile_at(30, 60), 2], [cc, Rules.B_SAM, m.tile_at(165, 60), 3]]:
		var s := StructureSystem.Structure.new()
		s.id = ss.structs.size()
		s.owner = spec[0]
		s.kind = spec[1]
		s.tile = spec[2]
		s.level = spec[3]
		s.active_levels = spec[3]
		ss.structs.append(s)
		sim.st.set_struct_at(s.tile, s.id)
		ss._grid_add(s)
		sim.st.add_blevel(s.owner, s.kind, s.level)
	ss.invalidate_caches()
	sim.submit(Commands.launch(a, "missile", m.tile_at(150, 60)))
	sim.step()
	var fired := false
	var mu: WeaponSystem.Munition = sim.weapons.munitions[0]
	while sim.st.tick <= mu.impact_tick():
		sim.step()
		for e in sim.events.drain():
			if String(e["type"]) == SimEvents.INTERCEPT_LAUNCHED and int(e["owner"]) == cc:
				fired = true
	check(fired, "the ally's SAM fires at a missile aimed at B")
	# A nuke by B on C's land would break their alliance: simulate the hook.
	sim.diplomacy.on_nuked(b, cc, 500)
	check(not sim.diplomacy.allied(b, cc), "nuking an ally ends the alliance")
	check(sim.diplomacy.is_traitor(b), "and makes a traitor")


func test_teams_are_permanent_and_win_together() -> void:
	var c := _setup(9, 2)
	var sim: Sim = c["sim"]
	var dp := sim.diplomacy
	var ids: Array[int] = [c["a"], c["b"], c["c"]]
	var teams := {}
	for o in ids:
		teams[o] = int(dp.team.get(o, 0))
		check(int(teams[o]) > 0, "everyone is on a team")
	var mates: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if int(teams[ids[i]]) == int(teams[ids[j]]):
				mates = [ids[i], ids[j]]
	check(mates.size() == 2, "two of three share a team")
	if mates.size() < 2:
		return
	check(dp.same_team(mates[0], mates[1]) and dp.allied(mates[0], mates[1]), "teammates are allied")
	check_eq(dp.break_pact(mates[0], mates[1]), "team", "a team cannot be broken")
	check_eq(dp.block_reason(mates[0], mates[1]), "team", "teammates cannot attack each other")
	# The team holds most of the land together: team victory.
	var other := 0
	for o in ids:
		if not mates.has(o):
			other = o
	var m: MapData = c["map"]
	for y in H:
		for x in W:
			var t := m.tile_at(x, y)
			if m.land[t] == 1 and sim.st.owner[t] == other and x % 4 != 0:
				sim.st.set_owner(t, mates[0])
	sim._check_end()
	check_eq(sim.phase, Sim.Phase.OVER, "the match ends")
	check_eq(int(sim.result.get("team", 0)), int(teams[mates[0]]), "their team wins")
	check((sim.result["winners"] as Array).has(mates[1]), "both teammates are winners")


func test_diplomacy_is_saved_and_deterministic() -> void:
	var a := _setup(11)
	var sa: Sim = a["sim"]
	sa.diplomacy.request(a["a"], a["b"], "alliance")
	sa.diplomacy.reply(a["b"], a["a"], true)
	sa.diplomacy.send(a["a"], a["b"], "troops", 5000.0)
	sa.diplomacy.request(a["c"], a["a"], "nap")
	for i in 5:
		sa.step()
	var b := _setup(11)
	var sb: Sim = b["sim"]
	sb.from_dict(bytes_to_var(var_to_bytes(sa.to_dict())))
	sb.ai.brains.clear()
	check_eq(sb.state_hash(), sa.state_hash(), "restored")
	check(sb.diplomacy.allied(a["a"], a["b"]), "alliance restored")
	check_eq(sb.diplomacy.convoys.size(), 1, "convoy restored")
	check(not sb.diplomacy.pending(a["c"], a["a"]).is_empty(), "request restored")
	for i in 300:
		sa.step()
		sb.step()
	check_eq(sb.state_hash(), sa.state_hash(), "continues identically")


func test_treaty_commands_apply_after_the_ticks_orders() -> void:
	var c := _setup(7)
	var sim: Sim = c["sim"]
	var a: int = c["a"]
	var b: int = c["b"]
	sim._start_playing()
	check_eq(sim.diplomacy.request(a, b, DiplomacySystem.NAP), "", "a asks b for a pact")
	var troops := sim.st.o_troops[a]
	# b accepts and, in the same tick, a's attack on b is queued after the answer.
	sim.submit(Commands.diplo(b, "reply", a, "", true))
	sim.submit(Commands.attack_target(a, b, 5000.0))
	sim.step()
	var evs := sim.events.drain()
	check(not evs.any(func(e: Dictionary) -> bool: return e["type"] == SimEvents.COMMAND_REJECTED), "nothing is refused")
	check(sim.diplomacy.has_nap(a, b), "the pact is signed")
	check(sim.attacks.find(a, b) == null, "and the attack it overtook is cancelled")
	check(absf(sim.st.o_troops[a] - troops) < 5000.0 * 0.5, "with the troops back home (%.0f -> %.0f)" % [troops, sim.st.o_troops[a]])
