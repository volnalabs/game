class_name Progression
extends RefCounted
## Level curve (data/meta/levels.json): XP needed for each level and milestone rewards.


static func xp_to_next(level: int) -> int:
	var d := MetaData.levels()
	var v := float(d["base"]) + float(d["step"]) * pow(float(maxi(level - 1, 0)), float(d["power"]))
	return int(round(v / 10.0)) * 10


static func max_level() -> int:
	return int(MetaData.levels()["max_level"])


## Level and progress for a total XP amount: {"level", "into" (XP into the level), "need"}.
static func level_for(total_xp: int) -> Dictionary:
	var lvl := 1
	var left := total_xp
	while lvl < max_level() and left >= xp_to_next(lvl):
		left -= xp_to_next(lvl)
		lvl += 1
	return {"level": lvl, "into": left, "need": xp_to_next(lvl)}


static func is_milestone(level: int) -> bool:
	return level % int(MetaData.levels()["milestone_every"]) == 0


## Rewards for reaching `level`: every level gives skill points; milestones add credits and cases.
static func level_rewards(level: int) -> Dictionary:
	var d := MetaData.levels()
	var r := {"skill_points": int(d["level_skill_points"])}
	if is_milestone(level):
		var m: Dictionary = d["milestone_rewards"].get(str(level), d["milestone_rewards"]["default"])
		r = m.duplicate(true)
	return r
