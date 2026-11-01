class_name NameGen
extends RefCounted
## Procedural state names from data/nations/name_pools.json, as {"ru": ..., "en": ...}.

static var _pools: Dictionary = {}


static func _load() -> void:
	if not _pools.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/nations/name_pools.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		_pools = parsed


static func _pick(rng: SimRng, key: String) -> Array:
	var arr: Array = _pools[key]
	return arr[rng.below(arr.size())]


static func make(rng: SimRng) -> Dictionary:
	_load()
	var parts: Array = [_pick(rng, "start")]
	if rng.chance(0.55):
		parts.append(_pick(rng, "middle"))
	parts.append(_pick(rng, "end"))
	var ru := ""
	var en := ""
	for p: Array in parts:
		ru += p[0]
		en += p[1]
	return {"ru": ru, "en": en}


static func make_tribe(rng: SimRng) -> Dictionary:
	_load()
	var base := make(rng)
	var pre := _pick(rng, "tribe_prefix")
	return {"ru": "%s %s" % [pre[0], base["ru"]], "en": "%s %s" % [pre[1], base["en"]]}


static func localized(d: Dictionary) -> String:
	var loc := TranslationServer.get_locale().substr(0, 2)
	return d.get(loc, d.get("en", ""))
