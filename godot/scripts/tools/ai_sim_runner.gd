class_name AISimRunner
extends RefCounted
## Headless AI-vs-AI matches with statistics (docs/ai/AI_DESIGN.md §11). Used by
## scripts/tools/ai_sim_cli.gd and tests/ai. Every game is reproducible from its seed.
##
## Modes (bot groups are interleaved so both sides get comparable starts):
##   mixed               — every bot is the strategic AI, personalities spread
##   strategic_vs_legacy — group A strategic (normal), group B the legacy RoWorld AI (normal)
##   hard_vs_easy        — group A strategic hard, group B strategic easy (same personality)
##   personalities       — one bot per personality, repeated


static func overrides_for(mode: String, bots: int) -> Array:
	var out: Array = []
	var pers: Array = AIProfile.personality_ids()
	for i in bots:
		match mode:
			"strategic_vs_legacy":
				out.append({"group": "strategic" if i % 2 == 0 else "legacy", "ai": "strategic" if i % 2 == 0 else "legacy",
					"difficulty": "normal", "personality": "balanced"})
			"hard_vs_easy":
				out.append({"group": "hard" if i % 2 == 0 else "easy", "ai": "strategic",
					"difficulty": "hard" if i % 2 == 0 else "easy", "personality": "balanced"})
			"personalities":
				var p: String = pers[i % pers.size()]
				out.append({"group": p, "ai": "strategic", "difficulty": "normal", "personality": p})
			_:
				out.append({"group": "strategic", "ai": "strategic", "difficulty": "normal", "personality": pers[i % pers.size()]})
	return out


## Builds a map: a registry id, or "gen:<preset>:<size>" for a generated world (seeded per game).
static func make_map(map_spec: String, seed_value: int, reg: Node) -> Array:
	if map_spec.begins_with("gen:"):
		var parts := map_spec.split(":")
		var p := GenParams.from_preset(parts[1], seed_value, parts[2] if parts.size() > 2 else "S")
		var res := MapGenerator.new().generate(p)
		return [MapGenerator.definition_for(res), res.map]
	var def: MapDefinition = reg.get_map(map_spec)
	return [def, MapLoader.load_map(def)]


static func run_game(map_spec: String, seed_value: int, bots: int, mode: String, max_ticks: int, reg: Node,
		tribes: int = 0, domination: float = 0.6) -> Dictionary:
	var md := make_map(map_spec, seed_value if map_spec.begins_with("gen:") else 0, reg)
	var def: MapDefinition = md[0]
	var map: MapData = md[1]
	var cfg := MatchConfig.new()
	cfg.has_player = false
	cfg.seed = seed_value
	cfg.bots = bots
	cfg.tribes = tribes
	cfg.victory.domination_share = domination
	cfg.victory.eliminate_all = true
	cfg.bot_overrides = overrides_for(mode, bots)
	var t0 := Time.get_ticks_msec()
	var sim := Sim.new(cfg, def, map)
	var groups := {}
	var nation_i := 0
	for id in range(1, sim.st.owner_count + 1):
		if sim.st.o_kind[id] == Rules.KIND_NATION:
			groups[id] = cfg.bot_overrides[nation_i]["group"] if nation_i < cfg.bot_overrides.size() else "?"
			nation_i += 1
	var atk := {}
	while sim.st.tick < max_ticks and sim.phase != Sim.Phase.OVER:
		sim.step()
		for e in sim.events.drain():
			if e["type"] == SimEvents.ATTACK_ENDED and int(e["target"]) != 0:
				var a := int(e["attacker"])
				if not atk.has(a):
					atk[a] = [0, 0]
				atk[a][0] += 1
				if int(e["taken"]) >= 20:
					atk[a][1] += 1
	var st := sim.st
	var bots_out: Array = []
	for id: int in groups:
		var brain := sim.ai.brain_of(id)
		var a: Array = atk.get(id, [0, 0])
		bots_out.append({
			"id": id, "group": groups[id], "name": st.o_name[id],
			"personality": brain.personality_id if brain != null else "", "difficulty": brain.difficulty_id if brain != null else "",
			"alive": st.o_alive[id] == 1, "tiles": st.o_tiles[id], "share": st.land_share(id),
			"peak": st.o_st_peak_tiles[id], "lifetime": (st.o_elim_tick[id] if st.o_alive[id] == 0 else st.tick),
			"gold_earned": st.o_st_gold_earned[id], "gold_spent": st.o_st_gold_spent[id], "upkeep": st.o_st_upkeep_paid[id],
			"attacks": a[0], "attacks_won": a[1], "conquered": st.o_st_conquered[id], "lost_tiles": st.o_st_lost_tiles[id],
			"troops_lost": st.o_st_troops_lost[id],
			"buildings": _levels(st, id),
			"decisions": brain.log.counts.duplicate() if brain != null else {},
			"states": (brain as StrategicAI).stats().get("state_ticks", {}) if brain is StrategicAI else {},
		})
	var winner := int(sim.result.get("winner", 0))
	if winner == 0:
		var best := -1
		for b: Dictionary in bots_out:
			if int(b["tiles"]) > best:
				best = int(b["tiles"])
				winner = int(b["id"])
	return {"seed": seed_value, "map": map_spec, "mode": mode, "ticks": st.tick, "over": sim.phase == Sim.Phase.OVER,
		"reason": sim.result.get("reason", "tick_limit"), "winner": winner, "winner_group": groups.get(winner, "?"),
		"bots": bots_out, "ms": Time.get_ticks_msec() - t0}


static func _levels(st: SimState, id: int) -> int:
	var n := 0
	for k in Rules.BUILDING_KINDS:
		n += st.blevel(id, k)
	return n


## Aggregates many games into per-group statistics.
static func summarize(games: Array) -> Dictionary:
	var g := {}
	for game: Dictionary in games:
		var wg: String = game["winner_group"]
		for b: Dictionary in game["bots"]:
			var k: String = b["group"]
			if not g.has(k):
				g[k] = {"bots": 0, "wins": 0, "alive": 0, "tiles": 0.0, "share": 0.0, "lifetime": 0.0, "gold_earned": 0.0,
					"gold_spent": 0.0, "upkeep": 0.0, "attacks": 0, "attacks_won": 0, "conquered": 0.0, "lost_tiles": 0.0,
					"buildings": 0.0, "states": {}, "decisions": {}}
			var s: Dictionary = g[k]
			s["bots"] += 1
			s["alive"] += 1 if b["alive"] else 0
			for f in ["tiles", "share", "lifetime", "gold_earned", "gold_spent", "upkeep", "conquered", "lost_tiles", "buildings"]:
				s[f] += float(b[f])
			s["attacks"] += int(b["attacks"])
			s["attacks_won"] += int(b["attacks_won"])
			for st_name: String in b["states"]:
				s["states"][st_name] = float(s["states"].get(st_name, 0.0)) + float(b["states"][st_name])
			for d: String in b["decisions"]:
				s["decisions"][d] = int(s["decisions"].get(d, 0)) + int(b["decisions"][d])
		if g.has(wg):
			g[wg]["wins"] += 1
	for k: String in g:
		var s: Dictionary = g[k]
		var n := maxf(1.0, float(s["bots"]))
		for f in ["tiles", "share", "lifetime", "gold_earned", "gold_spent", "upkeep", "conquered", "lost_tiles", "buildings"]:
			s["avg_" + f] = float(s[f]) / n
		s["survival"] = float(s["alive"]) / n
		s["attack_success"] = float(s["attacks_won"]) / maxf(1.0, float(s["attacks"]))
		s["win_rate"] = float(s["wins"]) / maxf(1.0, float(games.size()))
		var tot := 0.0
		for st_name: String in s["states"]:
			tot += float(s["states"][st_name])
		var shares := {}
		var entropy := 0.0
		for st_name: String in s["states"]:
			var p := float(s["states"][st_name]) / maxf(tot, 1.0)
			shares[st_name] = snappedf(p, 0.001)
			if p > 0.0:
				entropy -= p * log(p) / log(2.0)
		s["state_shares"] = shares
		s["strategy_entropy"] = entropy
	return g
