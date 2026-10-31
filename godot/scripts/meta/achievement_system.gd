class_name AchievementSystem
extends RefCounted
## Unlocks achievements once (data/meta/achievements.json). Returns the newly unlocked ids; their
## rewards are paid by RewardManager.


static func unlocked(p: ProfileData, id: String) -> bool:
	return (p.data["achievements"] as Dictionary).has(id)


static func check(p: ProfileData, result: Dictionary, now: int) -> Array[String]:
	var out: Array[String] = []
	for a: Dictionary in MetaData.achievements():
		var id := String(a["id"])
		if unlocked(p, id):
			continue
		if Conditions.met(a["condition"], p, result):
			p.data["achievements"][id] = now
			out.append(id)
	return out
