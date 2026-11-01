class_name MatchResult
extends RefCounted
## Summary of a finished (or abandoned) match for the player, built from the simulation once. It is
## what RewardManager pays from; `match_id` makes payment idempotent (a reloaded save or a second
## call never pays twice).


## `tracked` holds what the controller observed during play (e.g. {"min_share_late": 0.003}).
static func from_sim(sim: Sim, abandoned: bool = false, tracked: Dictionary = {}) -> Dictionary:
	var st := sim.st
	var pid := sim.player_id
	var won := not abandoned and sim.won(pid)
	var elims := 0
	for o in range(1, st.owner_count + 1):
		if o != pid and st.o_alive[o] == 0 and st.o_killer[o] == pid:
			elims += 1
	var posts := 0
	if pid > 0:
		posts = sim.structures.of_owner(pid, Rules.B_DEFENSE).size()
	var rank := 1
	for o in range(1, st.owner_count + 1):
		if o != pid and st.o_tiles[o] > st.o_tiles[pid]:
			rank += 1
	var cfg := sim.config
	return {
		"match_id": cfg.match_id,
		"map_id": cfg.map_id,
		"map_category": sim.def.category,
		"generated": sim.def.is_generated(),
		"difficulty": cfg.difficulty,
		"bots": cfg.bots,
		"fair": cfg.fair_mode,
		"won": won,
		"abandoned": abandoned,
		"reason": String(sim.result.get("reason", "")),
		"minutes": sim.elapsed_seconds() / 60.0,
		"conquered": st.o_st_conquered[pid] if pid > 0 else 0,
		"peak_tiles": st.o_st_peak_tiles[pid] if pid > 0 else 0,
		"share": st.land_share(pid) if pid > 0 else 0.0,
		"gold_earned": st.o_st_gold_earned[pid] if pid > 0 else 0.0,
		"troops_lost": st.o_st_troops_lost[pid] if pid > 0 else 0.0,
		"attacks": st.o_st_attacks[pid] if pid > 0 else 0,
		"built": st.o_st_built[pid] if pid > 0 else 0,
		"actions": st.o_st_commands[pid] if pid > 0 else 0,
		"eliminations": elims,
		"posts": posts,
		"rank": rank,
		"comeback": won and float(tracked.get("min_share_late", 1.0)) < 0.005,
	}
