class_name SkillTree
extends RefCounted
## Profile perks (data/meta/skill_tree.json): unlocking with skill points (level requirement,
## prerequisites, mutually exclusive choices), the active loadout (slots grow with level) and a
## free reset. The loadout reaches a match through MatchConfig.player_perks (none in Fair mode).


static func unlocked(p: ProfileData, id: String) -> bool:
	return (p.data["perks"]["unlocked"] as Array).has(id)


static func in_loadout(p: ProfileData, id: String) -> bool:
	return (p.data["perks"]["loadout"] as Array).has(id)


## Why a perk cannot be unlocked ("" = it can): owned, level, points, requires, excluded.
static func unlock_block(p: ProfileData, id: String) -> String:
	var d := MetaPerks.perk(id)
	if d.is_empty():
		return "unknown"
	if unlocked(p, id):
		return "owned"
	if p.level() < int(d["level"]):
		return "level"
	if int(p.data["skill_points"]) < int(d["cost"]):
		return "points"
	for r: String in d["requires"]:
		if not unlocked(p, r):
			return "requires"
	for x: String in d["excludes"]:
		if unlocked(p, x):
			return "excluded"
	return ""


static func unlock(p: ProfileData, id: String) -> bool:
	if unlock_block(p, id) != "":
		return false
	p.data["skill_points"] = int(p.data["skill_points"]) - int(MetaPerks.perk(id)["cost"])
	(p.data["perks"]["unlocked"] as Array).append(id)
	return true


static func equip(p: ProfileData, id: String) -> bool:
	if not unlocked(p, id) or in_loadout(p, id):
		return false
	var lo: Array = p.data["perks"]["loadout"]
	if lo.size() >= MetaPerks.slots(p.level()):
		return false
	lo.append(id)
	return true


static func unequip(p: ProfileData, id: String) -> bool:
	return (p.data["perks"]["loadout"] as Array).has(id) and _erase(p.data["perks"]["loadout"], id)


static func _erase(a: Array, v: Variant) -> bool:
	a.erase(v)
	return true


## Refunds every unlocked perk (free respec).
static func reset(p: ProfileData) -> void:
	var refund := 0
	for id: String in p.data["perks"]["unlocked"]:
		refund += int(MetaPerks.perk(id).get("cost", 0))
	p.data["skill_points"] = int(p.data["skill_points"]) + refund
	p.data["perks"]["unlocked"] = []
	p.data["perks"]["loadout"] = []


## Summed modifiers of the loadout (for the "what changes" panel).
static func loadout_modifiers(p: ProfileData) -> Dictionary:
	var out := {}
	for id: String in p.data["perks"]["loadout"]:
		var m := MetaPerks.modifiers(id)
		for s: String in m:
			out[s] = float(out.get(s, 0.0)) + float(m[s])
	return out


## "+5% gold income" style lines for a modifiers dictionary.
static func describe(mods: Dictionary) -> Array:
	var out: Array = []
	var keys := mods.keys()
	keys.sort()
	for s: String in keys:
		var v := float(mods[s])
		if is_zero_approx(v):
			continue
		var txt := ""
		if s.ends_with("_add"):
			txt = "%+d%%" % roundi(v * 100.0) if s == "retreat_keep_add" else "%+d" % roundi(v)
		else:
			txt = "%+d%%" % roundi(v * 100.0)
		# For costs, upkeep and attack losses lower is better; for defence_loss higher is better.
		var good := v > 0.0
		if s in ["upkeep_mult", "attack_loss_mult", "build_cost_mult"]:
			good = v < 0.0
		out.append({"stat": s, "text": "%s %s" % [txt, TranslationServer.translate("STAT_" + s.to_upper())], "good": good})
	return out
