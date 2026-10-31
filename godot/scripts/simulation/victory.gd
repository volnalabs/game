class_name Victory
extends RefCounted
## Match end detection. The only place where win conditions are evaluated; their parameters live in
## VictoryConfig (scripts/simulation/victory_config.gd).

var st: SimState
var config: VictoryConfig
var time_limit_ticks: int = 0
var start_tick: int = 0
## Team play: teams win together (their land adds up; elimination means only one team left).
var diplomacy: DiplomacySystem


func _init(state: SimState, cfg: VictoryConfig, tick_rate: int) -> void:
	st = state
	config = cfg
	time_limit_ticks = cfg.time_limit_minutes * 60 * tick_rate


## Returns {} while the match goes on, else {"winner": id, "reason": String} (team play: also
## "team": n and "winners": [ids]).
func check() -> Dictionary:
	if diplomacy != null and not diplomacy.team.is_empty():
		return _check_teams()
	var best := 0
	var best_tiles := -1
	var rivals_alive := 0
	for id in range(1, st.owner_count + 1):
		if st.o_alive[id] == 0 or st.o_spawned[id] == 0:
			continue
		if st.o_tiles[id] > best_tiles:
			best_tiles = st.o_tiles[id]
			best = id
		if st.o_kind[id] != Rules.KIND_TRIBE:
			rivals_alive += 1
	if best == 0:
		return {"winner": 0, "reason": "nobody"}
	var contestable := maxf(1.0, float(st.map.land_count))
	if float(best_tiles) >= config.domination_share * contestable:
		return {"winner": best, "reason": "domination"}
	if config.eliminate_all and rivals_alive <= 1 and st.o_kind[best] != Rules.KIND_TRIBE:
		return {"winner": best, "reason": "elimination"}
	if time_limit_ticks > 0 and st.tick - start_tick >= time_limit_ticks:
		return {"winner": best, "reason": "time"}
	return {}


## Share of the domination goal reached by `id` (0..1).
func progress(id: int) -> float:
	var goal := config.domination_share * maxf(1.0, float(st.map.land_count))
	return clampf(float(st.o_tiles[id]) / goal, 0.0, 1.0)


func _team_of(o: int) -> int:
	return int(diplomacy.team.get(o, 0))


## Team victory: a team's combined land reaches the domination share, or it is the only team left
## (tribes do not count); on time the team with the most land wins.
func _check_teams() -> Dictionary:
	var land := {}
	var alive_teams := {}
	for id in range(1, st.owner_count + 1):
		if st.o_alive[id] == 0 or st.o_spawned[id] == 0:
			continue
		var tm := _team_of(id)
		if tm <= 0:
			continue
		land[tm] = int(land.get(tm, 0)) + st.o_tiles[id]
		alive_teams[tm] = true
	if alive_teams.is_empty():
		return {"winner": 0, "reason": "nobody"}
	var best := 0
	var best_land := -1
	var keys: Array = land.keys()
	keys.sort()
	for tm: int in keys:
		if int(land[tm]) > best_land:
			best_land = int(land[tm])
			best = tm
	var contestable := maxf(1.0, float(st.map.land_count))
	var reason := ""
	if float(best_land) >= config.domination_share * contestable:
		reason = "domination"
	elif config.eliminate_all and alive_teams.size() <= 1:
		reason = "elimination"
	elif time_limit_ticks > 0 and st.tick - start_tick >= time_limit_ticks:
		reason = "time"
	if reason == "":
		return {}
	var members: Array[int] = []
	var lead := 0
	for id in range(1, st.owner_count + 1):
		if _team_of(id) == best and st.o_alive[id] == 1:
			members.append(id)
			if lead == 0 or st.o_tiles[id] > st.o_tiles[lead]:
				lead = id
	return {"winner": lead, "reason": reason, "team": best, "winners": members}


## Team progress towards the domination goal (0..1) for `id`'s team (or `id` alone).
func team_progress(id: int) -> float:
	if diplomacy == null or _team_of(id) <= 0:
		return progress(id)
	var tm := _team_of(id)
	var sum := 0
	for o in range(1, st.owner_count + 1):
		if _team_of(o) == tm and st.o_alive[o] == 1:
			sum += st.o_tiles[o]
	var goal := config.domination_share * maxf(1.0, float(st.map.land_count))
	return clampf(float(sum) / goal, 0.0, 1.0)
