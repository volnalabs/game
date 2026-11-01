class_name QuestSystem
extends RefCounted
## Offline challenges: weekly (3 from the pool chosen by the ISO week of the computer clock, so the
## set is stable within a week without any server), permanent chains and one-time tasks.


## ISO week id like "2026-W44".
static func week_id(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	# ISO week: the week with the year's first Thursday is week 1.
	var wd := (int(d["weekday"]) + 6) % 7
	var thursday := unix + (3 - wd) * 86400
	var td := Time.get_datetime_dict_from_unix_time(thursday)
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": td["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var week := int((thursday - jan1) / 86400 / 7) + 1
	return "%d-W%02d" % [int(td["year"]), week]


## Makes sure the weekly set belongs to the current week (resets its progress otherwise).
static func refresh_week(p: ProfileData, now: int) -> void:
	var q: Dictionary = p.data["quests"]
	var w := week_id(now)
	if q["week"] == w and not (q["weekly"] as Array).is_empty():
		return
	var pool: Array = []
	for d: Dictionary in MetaData.quests():
		if d["kind"] == "weekly":
			pool.append(String(d["id"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(w)
	var picked: Array = []
	var n := mini(int(MetaData.json("quests")["weekly_count"]), pool.size())
	while picked.size() < n:
		var id: String = pool[rng.randi() % pool.size()]
		if not picked.has(id):
			picked.append(id)
	q["week"] = w
	q["weekly"] = picked
	for id: String in (q["progress"] as Dictionary).keys():
		if MetaData.quest(id).get("kind", "") == "weekly":
			(q["progress"] as Dictionary).erase(id)
			(q["done"] as Dictionary).erase(id)


## Quests currently shown: weekly set + first unfinished step of each chain + one-time tasks.
static func active(p: ProfileData) -> Array[String]:
	var q: Dictionary = p.data["quests"]
	var out: Array[String] = []
	for id: String in q["weekly"]:
		out.append(id)
	var heads := {}
	for d: Dictionary in MetaData.quests():
		if d.has("next"):
			heads[String(d["next"])] = true
	for d: Dictionary in MetaData.quests():
		var id := String(d["id"])
		if d["kind"] == "chain" and not heads.has(id):
			var cur := id
			while cur != "" and (q["chain_done"] as Dictionary).has(cur):
				cur = String(MetaData.quest(cur).get("next", ""))
			if cur != "":
				out.append(cur)
		elif d["kind"] == "once" and not (q["done"] as Dictionary).has(id):
			out.append(id)
	return out


static func is_done(p: ProfileData, id: String) -> bool:
	var q: Dictionary = p.data["quests"]
	return (q["done"] as Dictionary).has(id) or (q["chain_done"] as Dictionary).has(id)


static func accumulated(p: ProfileData, id: String) -> float:
	return float((p.data["quests"]["progress"] as Dictionary).get(id, 0.0))


## Adds a match to every active quest; returns the ids completed now.
static func on_match(p: ProfileData, result: Dictionary, now: int) -> Array[String]:
	refresh_week(p, now)
	var q: Dictionary = p.data["quests"]
	var done: Array[String] = []
	for id in active(p):
		if is_done(p, id):
			continue
		var d := MetaData.quest(id)
		var c: Dictionary = d["condition"]
		var ok := false
		match String(c["scope"]):
			"count", "sum":
				if Conditions.match_where(result, c.get("where", {})):
					var add := Conditions.match_value(result, String(c["key"])) if c["scope"] == "sum" else 0.0
					if c["scope"] == "count":
						add = 1.0 if c["key"] == "matches" or Conditions.match_value(result, "won") > 0.0 else 0.0
					q["progress"][id] = accumulated(p, id) + add
				ok = accumulated(p, id) >= float(c["min"])
			_:
				ok = Conditions.met(c, p, result)
		if ok:
			if d["kind"] == "chain":
				q["chain_done"][id] = now
			else:
				q["done"][id] = now
			done.append(id)
	return done
