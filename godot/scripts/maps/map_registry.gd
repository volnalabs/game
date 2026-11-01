extends Node
## Autoload "MapRegistry": every map in res://data/maps/*/map.json. The UI lists maps from here —
## adding a map is adding a directory, nothing is hard-coded.

const MAPS_DIR := "res://data/maps"

var _maps: Array[MapDefinition] = []
var _by_id: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_maps.clear()
	_by_id.clear()
	var dirs := DirAccess.get_directories_at(MAPS_DIR)
	for sub in dirs:
		var base := MAPS_DIR.path_join(sub)
		var path := base.path_join("map.json")
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("MapRegistry: bad %s" % path)
			continue
		var def := MapDefinition.from_dict(parsed, base)
		_maps.append(def)
		_by_id[def.id] = def
	var order := {"real": 0, "fictional": 1, "regional": 2, "generated": 3}
	_maps.sort_custom(func(p: MapDefinition, q: MapDefinition) -> bool:
		var op: int = order.get(p.category, 9)
		var oq: int = order.get(q.category, 9)
		return op < oq or (op == oq and p.id < q.id))


func all() -> Array[MapDefinition]:
	return _maps


func get_map(id: String) -> MapDefinition:
	return _by_id.get(id)


func has_map(id: String) -> bool:
	return _by_id.has(id)
