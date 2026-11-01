class_name MetaData
extends RefCounted
## Meta progression data (data/meta/*.json), loaded once: levels, rewards, rarity, items, cases,
## achievements, quests. validate() lists every inconsistency (odds not summing to 100, unknown
## categories, broken references) — run by tests.

const DIR := "res://data/meta/"

static var _cache: Dictionary = {}


static func json(name: String) -> Dictionary:
	if not _cache.has(name):
		var f := FileAccess.open(DIR + name + ".json", FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		_cache[name] = d if d is Dictionary else {}
	return _cache[name]


static func levels() -> Dictionary:
	return json("levels")


static func rewards() -> Dictionary:
	return json("rewards")


static func rarity() -> Dictionary:
	return json("rarity")


static func rarity_order() -> Array:
	return rarity()["order"]


static func items() -> Array:
	return json("items")["items"]


static func item(id: String) -> Dictionary:
	var idx: Dictionary = _index("items", items())
	return idx.get(id, {})


static func categories() -> Array:
	return json("items")["categories"]


static func cases() -> Array:
	return json("cases")["cases"]


static func case_def(id: String) -> Dictionary:
	return _index("cases", cases()).get(id, {})


static func achievements() -> Array:
	return json("achievements")["achievements"]


static func achievement(id: String) -> Dictionary:
	return _index("achievements", achievements()).get(id, {})


static func quests() -> Array:
	return json("quests")["quests"]


static func quest(id: String) -> Dictionary:
	return _index("quests", quests()).get(id, {})


static func _index(key: String, arr: Array) -> Dictionary:
	var k := "_idx_" + key
	if not _cache.has(k):
		var d := {}
		for e: Dictionary in arr:
			d[String(e["id"])] = e
		_cache[k] = d
	return _cache[k]


## Localised text of a {"ru": ..., "en": ...} dictionary.
static func text(d: Variant) -> String:
	if d is Dictionary:
		var loc := TranslationServer.get_locale().substr(0, 2)
		return String((d as Dictionary).get(loc, (d as Dictionary).get("en", "")))
	return String(d)


## Every inconsistency in the meta data ([] when all is well).
static func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var order: Array = rarity_order()
	var odds: Dictionary = rarity()["odds"]
	if _sum(odds) != 100.0:
		errs.append("rarity odds sum to %s" % _sum(odds))
	var cats: Array = categories()
	var by_cat_rarity := {}
	for it: Dictionary in items():
		if not cats.has(it["category"]):
			errs.append("item %s: unknown category %s" % [it["id"], it["category"]])
		if not order.has(it["rarity"]):
			errs.append("item %s: unknown rarity %s" % [it["id"], it["rarity"]])
		by_cat_rarity["%s/%s" % [it["category"], it["rarity"]]] = true
		if it.has("icon") and not Icons.has(String(it["icon"])):
			errs.append("item %s: missing icon %s" % [it["id"], it["icon"]])
	for c: Dictionary in cases():
		var co: Dictionary = c["odds"]
		if _sum(co) != 100.0:
			errs.append("case %s odds sum to %s" % [c["id"], _sum(co)])
		for r: String in co:
			if float(co[r]) <= 0.0:
				continue
			var any := false
			for cat: String in c["categories"]:
				if by_cat_rarity.has("%s/%s" % [cat, r]):
					any = true
			if not any:
				errs.append("case %s: %s has no items" % [c["id"], r])
	for a: Dictionary in achievements():
		var rw: Dictionary = a["reward"]
		if rw.has("item") and item(String(rw["item"])).is_empty():
			errs.append("achievement %s: unknown reward item" % a["id"])
		for cid: String in rw.get("cases", {}):
			if case_def(cid).is_empty():
				errs.append("achievement %s: unknown case %s" % [a["id"], cid])
	for q: Dictionary in quests():
		if q.has("next") and quest(String(q["next"])).is_empty():
			errs.append("quest %s: unknown next" % q["id"])
	for id: String in json("items")["default_owned"]:
		if item(id).is_empty():
			errs.append("default item %s missing" % id)
	return errs


static func _sum(d: Dictionary) -> float:
	var s := 0.0
	for k: String in d:
		s += float(d[k])
	return s
