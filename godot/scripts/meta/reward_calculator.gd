class_name RewardCalculator
extends RefCounted
## Pure computation of what a match result is worth (data/meta/rewards.json), with a line-by-line
## breakdown for the results screen. Participation (time played, actions per minute) protects
## against AFK; recent short matches and repeated identical wins reduce rewards (restart farming).
## Abandoned matches give partial XP and no Credits.


static func compute(result: Dictionary, history: Array, now: int) -> Dictionary:
	var R := MetaData.rewards()
	var xp_d: Dictionary = R["xp"]
	var cr_d: Dictionary = R["credits"]
	var lines: Array = []
	var minutes := float(result["minutes"])
	var won: bool = result["won"]
	var abandoned: bool = result["abandoned"]
	var xp := 0.0
	var cr := 0.0
	# Base components.
	xp += float(xp_d["complete"])
	cr += float(cr_d["complete"])
	lines.append(_line("RW_COMPLETE", xp_d["complete"], cr_d["complete"]))
	if won:
		xp += float(xp_d["victory"])
		cr += float(cr_d["victory"])
		lines.append(_line("RW_VICTORY", xp_d["victory"], cr_d["victory"]))
	var mins := minf(minutes, float(xp_d["per_minute_cap"]))
	var xm := mins * float(xp_d["per_minute"])
	var cm := minf(minutes, float(cr_d["per_minute_cap"])) * float(cr_d["per_minute"])
	xp += xm
	cr += cm
	lines.append(_line("RW_TIME", xm, cm, "%d" % int(minutes)))
	var k := float(result["conquered"]) / 1000.0
	var xc := minf(k * float(xp_d["per_1k_tiles_conquered"]), float(xp_d["conquered_cap"]))
	var cc := minf(k * float(cr_d["per_1k_tiles_conquered"]), float(cr_d["conquered_cap"]))
	xp += xc
	cr += cc
	lines.append(_line("RW_CONQUEST", xc, cc, str(int(result["conquered"]))))
	var el := mini(int(result["eliminations"]), int(xp_d["elimination_cap"]))
	if el > 0:
		xp += el * float(xp_d["per_elimination"])
		cr += el * float(cr_d["per_elimination"])
		lines.append(_line("RW_ELIMINATIONS", el * float(xp_d["per_elimination"]), el * float(cr_d["per_elimination"]), str(el)))
	if not won:
		cr *= float(cr_d["loss_mult"])
		xp *= float(xp_d["loss_mult"])
	# Multipliers.
	var mult := float(R["difficulty_mult"].get(result["difficulty"], 1.0))
	mult *= minf(1.0 + float(R["bots_mult"]["per_bot"]) * float(result["bots"]), float(R["bots_mult"]["max"]))
	if bool(result.get("fair", false)):
		mult *= float(R["fair_mode_mult"])
	lines.append(_mult("RW_DIFFICULTY", mult))
	var part := participation(result)
	lines.append(_mult("RW_PARTICIPATION", part["credits"]))
	var farm := farm_mult(result, history, now)
	if farm < 1.0:
		lines.append(_mult("RW_REPEAT", farm))
	xp *= mult * float(part["xp"]) * farm
	cr *= mult * float(part["credits"]) * farm
	if abandoned:
		xp *= float(xp_d["abandon_mult"])
		cr = 0.0
		lines.append(_mult("RW_ABANDONED", float(xp_d["abandon_mult"])))
	var out := {"xp": int(round(xp)), "credits": int(round(cr)), "lines": lines, "participation": part, "farm": farm}
	return out


## Participation 0..1: full after `full_minutes` and with enough actions per minute; below
## `min_minutes` nothing is paid. XP is less sensitive to activity than Credits.
static func participation(result: Dictionary) -> Dictionary:
	var P: Dictionary = MetaData.rewards()["participation"]
	var minutes := float(result["minutes"])
	if minutes < float(P["min_minutes"]):
		return {"xp": 0.0, "credits": 0.0, "time": 0.0, "activity": 0.0}
	var time_f := clampf(minutes / float(P["full_minutes"]), 0.0, 1.0)
	var apm := float(result["actions"]) / maxf(minutes, 1.0)
	var act := clampf(apm / float(P["actions_per_minute_full"]), 0.0, 1.0)
	var floor_a := float(P["activity_floor"])
	return {"xp": time_f * (0.5 + 0.5 * act), "credits": time_f * (floor_a + (1.0 - floor_a) * act), "time": time_f, "activity": act}


## Recent short matches and identical repeated wins (same map, difficulty) in the history window.
static func farm_mult(result: Dictionary, history: Array, now: int) -> float:
	var F: Dictionary = MetaData.rewards()["anti_farm"]
	var window := int(float(F["window_minutes"]) * 60.0)
	var rep_window := int(float(F["repeat_window_hours"]) * 3600.0)
	var short := 0
	var repeats := 0
	for h: Dictionary in history:
		var age := now - int(h.get("time", 0))
		if age < window and float(h.get("minutes", 0.0)) < float(F["short_minutes"]):
			short += 1
		if age < rep_window and bool(h.get("won", false)) and bool(result["won"]) and h.get("map_id") == result["map_id"] \
				and h.get("difficulty") == result["difficulty"] and float(h.get("minutes", 0.0)) < float(F["short_minutes"]) * 2.0:
			repeats += 1
	var m := 1.0 / (1.0 + float(F["short_penalty"]) * short)
	m *= maxf(pow(float(F["repeat_penalty"]), repeats), float(F["repeat_floor"]))
	return m


static func _line(key: String, xp: Variant, cr: Variant, arg: String = "") -> Dictionary:
	return {"key": key, "arg": arg, "xp": int(round(float(xp))), "credits": int(round(float(cr)))}


static func _mult(key: String, m: float) -> Dictionary:
	return {"key": key, "mult": m}
