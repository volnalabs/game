class_name ProfileData
extends RefCounted
## The persistent player profile (outside the simulation): identity, level and XP, currencies,
## inventory and equipment, cases, achievements, challenges, statistics and match history.
## Only RewardManager and the explicit player actions (equip, buy, open, craft, rename) change it.
## Versioned: migrate() upgrades any older file to CURRENT_VERSION.

const CURRENT_VERSION := 2

var data: Dictionary = {}


static func fresh() -> ProfileData:
	var p := ProfileData.new()
	var items: Dictionary = MetaData.json("items")
	var owned := {}
	for id: String in items["default_owned"]:
		owned[id] = 1
	p.data = {
		"version": CURRENT_VERSION,
		"created": int(Time.get_unix_time_from_system()),
		"name": "",
		"xp": 0,
		"level": 1,
		"credits": 0,
		"fragments": 0,
		"skill_points": 0,
		"owned": owned,
		"equipped": (items["default_equipped"] as Dictionary).duplicate(),
		"cases": {"starter": 1},
		"pity": {"epic": 0, "legendary": 0},
		"cases_opened": 0,
		"case_seed": int(Time.get_unix_time_from_system()) % 1000003 + 17,
		"achievements": {},
		"quests": {"week": "", "weekly": [], "progress": {}, "done": {}, "chain_done": {}},
		## match_id -> {"xp", "credits", "final"}: what each match has paid (idempotency).
		"applied_matches": {},
		"stats": {"matches": 0, "wins": 0, "losses": 0, "abandoned": 0, "conquered": 0, "gold_earned": 0.0,
			"troops_lost": 0.0, "built": 0, "attacks": 0, "eliminations": 0, "minutes": 0.0, "hard_wins": 0,
			"by_map": {}, "by_difficulty": {}},
		"history": [],
		"perks": {"unlocked": [], "loadout": []},
		"last_daily_win": "",
	}
	return p


## Brings an old profile dictionary to the current version (each step is one function).
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 1:
		# v0 (Phase 2 preview): flat {"xp", "credits", "items": [ids]}.
		var owned := {}
		for id: Variant in d.get("items", []):
			owned[String(id)] = 1
		d["owned"] = owned
		d.erase("items")
		d["version"] = 1
	if v < 2:
		# v2: challenges and perks blocks, separate pity counters.
		if not d.has("quests"):
			d["quests"] = {"week": "", "weekly": [], "progress": {}, "done": {}, "chain_done": {}}
		if not d.has("perks"):
			d["perks"] = {"unlocked": [], "loadout": []}
		var applied: Variant = d.get("applied_matches", {})
		if applied is Array:
			var m := {}
			for id: Variant in applied:
				m[String(id)] = {"xp": 0, "credits": 0, "final": true}
			d["applied_matches"] = m
		var pity: Variant = d.get("pity", 0)
		if not pity is Dictionary:
			d["pity"] = {"epic": int(pity), "legendary": int(pity)}
		d["version"] = 2
	return d


## Loads from a dictionary (after migration), filling anything missing with defaults.
static func from_dict(d: Dictionary) -> ProfileData:
	var p := fresh()
	var m := migrate(d.duplicate(true))
	for k: String in m:
		if p.data.has(k) and typeof(p.data[k]) == TYPE_DICTIONARY and typeof(m[k]) == TYPE_DICTIONARY:
			var base: Dictionary = p.data[k]
			for kk: String in m[k]:
				base[kk] = m[k][kk]
		else:
			p.data[k] = m[k]
	p.data["version"] = CURRENT_VERSION
	return p


func to_dict() -> Dictionary:
	return data.duplicate(true)


# -- Convenience accessors -----------------------------------------------------------------------

func level() -> int:
	return int(data["level"])


func xp() -> int:
	return int(data["xp"])


func credits() -> int:
	return int(data["credits"])


func fragments() -> int:
	return int(data["fragments"])


func owns(item_id: String) -> bool:
	return int((data["owned"] as Dictionary).get(item_id, 0)) > 0


func owned_ids() -> Array:
	return (data["owned"] as Dictionary).keys()


func equipped(category: String) -> String:
	return String((data["equipped"] as Dictionary).get(category, ""))


func case_count(case_id: String) -> int:
	return int((data["cases"] as Dictionary).get(case_id, 0))


func display_name() -> String:
	var n := String(data["name"])
	return n if n != "" else TranslationServer.translate("PROFILE_DEFAULT_NAME")
