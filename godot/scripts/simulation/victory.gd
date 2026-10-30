class_name Victory
extends RefCounted
## Match end detection. The only place where win conditions are evaluated; their parameters live in
## VictoryConfig (scripts/simulation/victory_config.gd).

var st: SimState
var config: VictoryConfig
var time_limit_ticks: int = 0
var start_tick: int = 0


func _init(state: SimState, cfg: VictoryConfig, tick_rate: int) -> void:
	st = state
	config = cfg
	time_limit_ticks = cfg.time_limit_minutes * 60 * tick_rate


## Returns {} while the match goes on, else {"winner": id, "reason": String}.
func check() -> Dictionary:
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
