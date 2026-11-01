class_name Symbols
extends RefCounted
## VolnaLabs' own building and resource symbols (data/ui/symbols.json, AGPL-3.0, built by
## tools/symbols/make_symbols.py). The single source for every place a building or resource is shown:
## map, build menu, quick build, ghost, inspector, tooltips, encyclopedia. Three levels of detail:
## "far" (silhouette), "full", "near". White on transparent, tinted with modulate.

const PATH := "res://data/ui/symbols.json"
const LODS := ["far", "full", "near"]

static var _data: Dictionary = {}
static var _cache: Dictionary = {}


static func _load() -> void:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = (d as Dictionary)["symbols"] if d is Dictionary else {}


static func has(id: String) -> bool:
	_load()
	return _data.has(id)


static func ids() -> Array:
	_load()
	return _data.keys()


## Symbol id of a building kind (by index or id string).
static func building_id(rules: Rules, kind: int) -> String:
	return "b_" + rules.b_ids[kind]


## Level of detail for a symbol drawn `px` pixels tall on screen.
static func lod_for(px: float) -> String:
	if px < 14.0:
		return "far"
	if px <= 30.0:
		return "full"
	return "near"


## Texture of a symbol at `size` physical pixels (no UI scaling applied; cached).
static func tex_px(id: String, size: int, lod: String = "full") -> Texture2D:
	_load()
	size = maxi(8, size)
	var key := "%s/%s@%d" % [id, lod, size]
	if _cache.has(key):
		return _cache[key]
	var e: Dictionary = _data.get(id, {})
	if e.is_empty():
		return null
	var img := Image.new()
	img.load_svg_from_string(String(e.get(lod, e["full"])), float(size) / 24.0)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
