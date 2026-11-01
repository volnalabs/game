class_name AIProfile
extends RefCounted
## Loads AI personalities (data/ai/personalities.json) and difficulty levels (data/ai/difficulty.json).

static var _pers: Dictionary = {}
static var _order: Array = []
static var _diff: Dictionary = {}
static var _dip: Dictionary = {}


static func _load() -> void:
	if not _pers.is_empty():
		return
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai/personalities.json"))
	_pers = p["personalities"]
	_order = p["order"]
	_dip = p.get("diplomacy", {})
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai/difficulty.json"))
	_diff = d["levels"]


static func personality(id: String) -> Dictionary:
	_load()
	return _pers.get(id, _pers["balanced"])


static func personality_ids() -> Array:
	_load()
	return _order


static func difficulty(id: String) -> Dictionary:
	_load()
	return _diff.get(id, _diff["normal"])


static func difficulty_ids() -> Array:
	return ["easy", "normal", "hard"]


## Thresholds and weights of the diplomatic AI (personalities.json "diplomacy").
static func diplomacy() -> Dictionary:
	_load()
	return _dip
