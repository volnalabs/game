class_name Conditions
extends RefCounted
## Shared evaluator for achievement and challenge conditions:
## {"scope": "match"|"lifetime"|"profile"|"count"|"sum", "key": ..., "min": ..., "where": {...}}.


## Value of `key` for one match result (booleans count as 0/1).
static func match_value(result: Dictionary, key: String) -> float:
	var v: Variant = result.get(key, 0)
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


## Whether a match passes the "where" filters.
static func match_where(result: Dictionary, where: Dictionary) -> bool:
	for k: String in where:
		var w: Variant = where[k]
		match k:
			"difficulty":
				if result.get("difficulty") != w:
					return false
			"category":
				if result.get("map_category") != w:
					return false
			"generated", "fair", "comeback":
				if bool(result.get(k, false)) != bool(w):
					return false
			"bots_min":
				if int(result.get("bots", 0)) < int(w):
					return false
			"minutes_max":
				if float(result.get("minutes", 0.0)) > float(w):
					return false
			"posts_min":
				if int(result.get("posts", 0)) < int(w):
					return false
			"attacks_max":
				if int(result.get("attacks", 0)) > int(w):
					return false
	return true


static func lifetime_value(p: ProfileData, key: String) -> float:
	var s: Dictionary = p.data["stats"]
	match key:
		"maps_played":
			return float((s["by_map"] as Dictionary).size())
		"maps_won":
			var n := 0
			for m: String in s["by_map"]:
				if int(s["by_map"][m].get("won", 0)) > 0:
					n += 1
			return float(n)
	return float(s.get(key, 0))


static func profile_value(p: ProfileData, key: String) -> float:
	match key:
		"level":
			return float(p.level())
		"items_owned":
			return float(p.owned_ids().size())
		"cases_opened":
			return float(p.data["cases_opened"])
	return 0.0


## Achievement-style check (match / lifetime / profile scopes) after `result` was recorded.
static func met(c: Dictionary, p: ProfileData, result: Dictionary) -> bool:
	var mn := float(c.get("min", 1))
	match String(c["scope"]):
		"match":
			if result.is_empty() or not match_where(result, c.get("where", {})):
				return false
			return match_value(result, String(c["key"])) >= mn
		"lifetime":
			return lifetime_value(p, String(c["key"])) >= mn
		"profile":
			return profile_value(p, String(c["key"])) >= mn
	return false


## Progress (current, target) of a condition, for progress bars.
static func progress(c: Dictionary, p: ProfileData, accumulated: float = 0.0) -> Vector2:
	var mn := float(c.get("min", 1))
	match String(c["scope"]):
		"lifetime":
			return Vector2(minf(lifetime_value(p, String(c["key"])), mn), mn)
		"profile":
			return Vector2(minf(profile_value(p, String(c["key"])), mn), mn)
		"count", "sum":
			return Vector2(minf(accumulated, mn), mn)
	return Vector2(0, mn)
