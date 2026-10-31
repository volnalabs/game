class_name RewardManager
extends RefCounted
## The only place that pays the player: match results (once per match_id), level-ups and
## milestones, achievements and challenges. Everything goes into one report for the results screen.

const KEEP_APPLIED := 300


## Pays a match result. Returns the report; {"duplicate": true} if this match was already paid.
## An abandoned match is paid partially once; if the same match (loaded from a save) is later
## finished, only the difference to the full reward is paid.
static func apply_match(p: ProfileData, result: Dictionary, now: int) -> Dictionary:
	var mid := String(result.get("match_id", ""))
	var applied: Dictionary = p.data["applied_matches"]
	if mid == "":
		return {"duplicate": true}
	var prev: Dictionary = applied.get(mid, {})
	if not prev.is_empty() and (bool(prev["final"]) or bool(result["abandoned"])):
		return {"duplicate": true}
	var report := {"duplicate": false, "match_id": mid, "level_before": p.level(), "xp_before": p.xp(),
		"credits_before": p.credits(), "levels": [], "achievements": [], "quests": [], "cases": {}, "items": [],
		"skill_points": 0, "bonus_xp": 0, "bonus_credits": 0}
	var calc := RewardCalculator.compute(result, p.data["history"], now)
	report["lines"] = calc["lines"]
	report["participation"] = calc["participation"]
	report["farm"] = calc["farm"]
	var xp: int = calc["xp"]
	var cr: int = calc["credits"]
	# First victory of the (local) day.
	var today := Time.get_date_string_from_unix_time(now)
	if bool(result["won"]) and p.data["last_daily_win"] != today and float(calc["participation"]["credits"]) > 0.5:
		var fw: Dictionary = MetaData.rewards()["first_win_of_day"]
		xp += int(fw["xp"])
		cr += int(fw["credits"])
		p.data["last_daily_win"] = today
		(report["lines"] as Array).append({"key": "RW_FIRST_WIN", "arg": "", "xp": int(fw["xp"]), "credits": int(fw["credits"])})
	if not prev.is_empty():
		var px := int(prev["xp"])
		var pc := int(prev["credits"])
		(report["lines"] as Array).append({"key": "RW_ALREADY_PAID", "arg": "", "xp": -mini(px, xp), "credits": -mini(pc, cr)})
		xp = maxi(0, xp - px)
		cr = maxi(0, cr - pc)
	report["match_xp"] = xp
	report["match_credits"] = cr
	applied[mid] = {"xp": xp + int(prev.get("xp", 0)), "credits": cr + int(prev.get("credits", 0)), "final": not bool(result["abandoned"]),
		"time": now}
	if prev.is_empty():
		_record(p, result, now)
	_add_credits(p, cr)
	_add_xp(p, xp, report)
	# Achievements and challenges (their rewards can unlock more: loop until stable).
	for pass_i in 3:
		var got := false
		for id in AchievementSystem.check(p, result, now):
			(report["achievements"] as Array).append(id)
			grant(p, MetaData.achievement(id)["reward"], report)
			got = true
		if pass_i == 0:
			for id in QuestSystem.on_match(p, result, now):
				(report["quests"] as Array).append(id)
				grant(p, MetaData.quest(id)["reward"], report)
				got = true
		if not got:
			break
	if applied.size() > KEEP_APPLIED:
		var ids := applied.keys()
		ids.sort_custom(func(a: String, b: String) -> bool: return int(applied[a].get("time", 0)) < int(applied[b].get("time", 0)))
		for i in ids.size() - KEEP_APPLIED:
			applied.erase(ids[i])
	report["level_after"] = p.level()
	report["xp_after"] = p.xp()
	report["credits_after"] = p.credits()
	return report


## Pays a reward dictionary {"credits", "xp", "cases": {id: n}, "item", "skill_points"}.
static func grant(p: ProfileData, reward: Dictionary, report: Dictionary) -> void:
	if reward.has("credits"):
		_add_credits(p, int(reward["credits"]))
		report["bonus_credits"] = int(report.get("bonus_credits", 0)) + int(reward["credits"])
	if reward.has("skill_points"):
		p.data["skill_points"] = int(p.data["skill_points"]) + int(reward["skill_points"])
		report["skill_points"] = int(report.get("skill_points", 0)) + int(reward["skill_points"])
	for cid: String in reward.get("cases", {}):
		var n := int(reward["cases"][cid])
		p.data["cases"][cid] = p.case_count(cid) + n
		report["cases"][cid] = int((report["cases"] as Dictionary).get(cid, 0)) + n
	if reward.has("item"):
		var g := Inventory.grant(p, String(reward["item"]))
		(report["items"] as Array).append({"item": reward["item"], "duplicate": g["duplicate"]})
	if reward.has("xp"):
		report["bonus_xp"] = int(report.get("bonus_xp", 0)) + int(reward["xp"])
		_add_xp(p, int(reward["xp"]), report)


static func _add_credits(p: ProfileData, n: int) -> void:
	p.data["credits"] = maxi(0, p.credits() + n)


static func _add_xp(p: ProfileData, n: int, report: Dictionary) -> void:
	p.data["xp"] = p.xp() + maxi(n, 0)
	var lv: int = Progression.level_for(p.xp())["level"]
	while p.level() < lv:
		p.data["level"] = p.level() + 1
		(report["levels"] as Array).append(p.level())
		grant(p, Progression.level_rewards(p.level()), report)


## Statistics and history (before achievements are checked, which read them).
static func _record(p: ProfileData, r: Dictionary, now: int) -> void:
	var s: Dictionary = p.data["stats"]
	s["matches"] = int(s["matches"]) + 1
	if r["abandoned"]:
		s["abandoned"] = int(s["abandoned"]) + 1
	elif r["won"]:
		s["wins"] = int(s["wins"]) + 1
		if r["difficulty"] == "hard":
			s["hard_wins"] = int(s["hard_wins"]) + 1
	else:
		s["losses"] = int(s["losses"]) + 1
	s["conquered"] = int(s["conquered"]) + int(r["conquered"])
	s["gold_earned"] = float(s["gold_earned"]) + float(r["gold_earned"])
	s["troops_lost"] = float(s["troops_lost"]) + float(r["troops_lost"])
	s["built"] = int(s["built"]) + int(r["built"])
	s["attacks"] = int(s["attacks"]) + int(r["attacks"])
	s["eliminations"] = int(s["eliminations"]) + int(r["eliminations"])
	s["minutes"] = float(s["minutes"]) + float(r["minutes"])
	for pair: Array in [["by_map", String(r["map_id"])], ["by_difficulty", String(r["difficulty"])]]:
		var table: Dictionary = s[pair[0]]
		var e: Dictionary = table.get(pair[1], {"played": 0, "won": 0, "best_share": 0.0, "minutes": 0.0})
		e["played"] = int(e["played"]) + 1
		e["won"] = int(e["won"]) + (1 if r["won"] else 0)
		e["best_share"] = maxf(float(e["best_share"]), float(r["share"]))
		e["minutes"] = float(e["minutes"]) + float(r["minutes"])
		table[pair[1]] = e
	var h: Array = p.data["history"]
	h.push_front({"time": now, "match_id": r["match_id"], "map_id": r["map_id"], "difficulty": r["difficulty"],
		"won": r["won"], "abandoned": r["abandoned"], "minutes": r["minutes"], "share": r["share"], "rank": r["rank"],
		"conquered": r["conquered"]})
	var keep := int(MetaData.rewards()["anti_farm"]["history_keep"])
	if h.size() > keep:
		p.data["history"] = h.slice(0, keep)
