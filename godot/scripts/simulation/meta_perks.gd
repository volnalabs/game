class_name MetaPerks
extends RefCounted
## Read access to the perk definitions (data/meta/skill_tree.json) for the simulation and the
## skill tree screen. The simulation only sees perk ids handed over in MatchConfig.

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta/skill_tree.json"))
		_data = d if d is Dictionary else {"perks": [], "branches": [], "slots": {"base": 2, "per_levels": 10, "max": 5}}
		for p: Dictionary in _data["perks"]:
			_by_id[String(p["id"])] = p
	return _data


static func perk(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func modifiers(id: String) -> Dictionary:
	return perk(id).get("modifiers", {})


static func all() -> Array:
	return data()["perks"]


## Loadout slots at a profile level.
static func slots(level: int) -> int:
	var s: Dictionary = data()["slots"]
	return mini(int(s["base"]) + level / int(s["per_levels"]), int(s["max"]))
