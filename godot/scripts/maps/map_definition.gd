class_name MapDefinition
extends RefCounted
## One playable map as described by data/maps/<id>/map.json (docs/maps/MAP_SYSTEM.md), or by
## generator parameters for a procedurally generated world.

var id: String = ""
var dir: String = ""
var category: String = ""
var names: Dictionary = {}
var descriptions: Dictionary = {}
var features: PackedStringArray = PackedStringArray()
var width: int = 0
var height: int = 0
var k_lin: float = 1.0
var recommended_bots: Vector2i = Vector2i(8, 24)
var max_bots: int = 0
var nations: Array = []
var balance: Dictionary = {}
var stats: Dictionary = {}
var source: String = ""
var license: String = ""
## Non-empty for generated worlds: the GenParams dictionary that rebuilds the terrain.
var generator: Dictionary = {}


static func from_dict(d: Dictionary, base_dir: String = "") -> MapDefinition:
	var m := MapDefinition.new()
	m.id = d.get("id", "")
	m.dir = base_dir
	m.category = d.get("category", "")
	m.names = d.get("name", {})
	m.descriptions = d.get("description", {})
	m.features = PackedStringArray(d.get("features", []))
	m.width = int(d.get("width", 0))
	m.height = int(d.get("height", 0))
	m.k_lin = float(d.get("k_lin", 1.0))
	var rb: Array = d.get("recommended_bots", [8, 24])
	m.recommended_bots = Vector2i(int(rb[0]), int(rb[1]))
	m.nations = d.get("nations", [])
	m.max_bots = int(d.get("max_bots", m.nations.size()))
	m.balance = d.get("balance", {})
	m.stats = d.get("stats", {})
	m.source = d.get("source", "")
	m.license = d.get("license", "")
	m.generator = d.get("generator", {})
	return m


func to_dict() -> Dictionary:
	return {
		"id": id, "category": category, "name": names, "description": descriptions,
		"features": Array(features), "width": width, "height": height, "k_lin": k_lin,
		"recommended_bots": [recommended_bots.x, recommended_bots.y], "max_bots": max_bots,
		"nations": nations, "balance": balance, "stats": stats, "source": source, "license": license,
		"generator": generator,
	}


func display_name(locale: String = "") -> String:
	return _pick(names, locale)


func description(locale: String = "") -> String:
	return _pick(descriptions, locale)


static func _pick(d: Dictionary, locale: String) -> String:
	if locale == "":
		locale = TranslationServer.get_locale().substr(0, 2)
	if d.has(locale):
		return d[locale]
	if d.has("en"):
		return d["en"]
	return d.values()[0] if d.size() > 0 else ""


static func nation_name(nation: Dictionary, locale: String = "") -> String:
	var nm: Variant = nation.get("name", "")
	if typeof(nm) == TYPE_DICTIONARY:
		return _pick(nm, locale)
	return str(nm)


func terrain_path() -> String:
	return dir.path_join("terrain.png")


func preview_path() -> String:
	return dir.path_join("preview.png")


func is_generated() -> bool:
	return not generator.is_empty()
