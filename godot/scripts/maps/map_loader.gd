class_name MapLoader
extends RefCounted
## Builds MapData for a MapDefinition: loads terrain.png, or regenerates a generated world from
## its parameters. Results are cached per process (maps are read-only once built).

static var _cache: Dictionary = {}


static func load_map(def: MapDefinition) -> MapData:
	var key := def.id if not def.is_generated() else "gen:%d" % hash(def.generator)
	if _cache.has(key):
		return _cache[key]
	var data: MapData
	if def.is_generated():
		var params := GenParams.from_dict(def.generator)
		data = MapGenerator.new().generate(params).map
	else:
		var img := Image.load_from_file(def.terrain_path()) if not def.terrain_path().begins_with("res://") \
			else _load_res_image(def.terrain_path())
		if img == null:
			push_error("MapLoader: cannot read %s" % def.terrain_path())
			return null
		data = MapData.from_image(img, def.id, def.k_lin)
	_cache[key] = data
	return data


static func _load_res_image(path: String) -> Image:
	# Read the PNG bytes directly: imported textures may be compressed or have mipmaps, the
	# simulation needs the exact pixel bytes.
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img


static func clear_cache() -> void:
	_cache.clear()
