class_name SaveManager
extends RefCounted
## Saves the simulation STATE (not the scene): VLSV magic, format version, a JSON header (map
## reference — registry id, or generator parameters + terrain hash —, match config, summary) and
## the ZSTD-compressed var_to_bytes of Sim.to_dict(). Older formats are upgraded by SaveFormat.

const SAVE_DIR := "user://saves"
const MAGIC := "VLSV"


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func save(sim: Sim, slot: String) -> String:
	ensure_dir()
	var path := SAVE_DIR.path_join(slot.validate_filename() + ".vsave")
	var pid := sim.player_id
	var header := {
		"version": SaveFormat.VERSION,
		"game_version": ProjectSettings.get_setting("application/config/version", "0.1.0"),
		"created": Time.get_datetime_string_from_system(false, true),
		"slot": slot,
		"map": {"id": sim.def.id, "name": sim.def.names, "generator": sim.def.generator,
			"terrain_hash": sim.map.terrain_hash, "def": sim.def.to_dict() if sim.def.is_generated() else {}},
		"config": sim.config.to_dict(),
		"tick": sim.st.tick,
		"summary": {"player": sim.st.o_name[pid] if pid > 0 else "", "tiles": sim.st.o_tiles[pid] if pid > 0 else 0,
			"elapsed": sim.elapsed_seconds()},
	}
	var body := var_to_bytes(sim.to_dict())
	var packed := body.compress(FileAccess.COMPRESSION_ZSTD)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write %s" % path)
		return ""
	var hb := JSON.stringify(header).to_utf8_buffer()
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(SaveFormat.VERSION)
	f.store_32(hb.size())
	f.store_buffer(hb)
	f.store_64(body.size())
	f.store_64(packed.size())
	f.store_buffer(packed)
	f.close()
	return path


static func read_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != MAGIC:
		return {}
	var _version := f.get_32()
	var hlen := f.get_32()
	var parsed: Variant = JSON.parse_string(f.get_buffer(hlen).get_string_from_utf8())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## {"header", "state"} with migrations applied, or {} on error.
static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != MAGIC:
		return {}
	var version := f.get_32()
	var hlen := f.get_32()
	var header: Dictionary = JSON.parse_string(f.get_buffer(hlen).get_string_from_utf8())
	var raw_size := f.get_64()
	var packed_size := f.get_64()
	var body := f.get_buffer(packed_size).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	var state: Variant = bytes_to_var(body)
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	var out := SaveFormat.migrate(version, header, state)
	return out


static func list() -> Array[Dictionary]:
	ensure_dir()
	var out: Array[Dictionary] = []
	for fname in DirAccess.get_files_at(SAVE_DIR):
		if fname.ends_with(".vsave"):
			var path := SAVE_DIR.path_join(fname)
			var h := read_header(path)
			if not h.is_empty():
				h["path"] = path
				out.append(h)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("created", "")) > String(b.get("created", "")))
	return out


static func delete(path: String) -> void:
	DirAccess.remove_absolute(path)


## Rebuilds map definition, terrain and config of a save. {} when the map is unavailable.
static func restore_match(data: Dictionary) -> Dictionary:
	var header: Dictionary = data["header"]
	var m: Dictionary = header["map"]
	var cfg := MatchConfig.from_dict(header["config"])
	var def: MapDefinition
	var map: MapData
	var gen: Dictionary = m.get("generator", {})
	if not gen.is_empty():
		def = MapDefinition.from_dict(m["def"])
		var res := MapGenerator.new().generate(GenParams.from_dict(gen))
		map = res.map
	else:
		var reg: Node = Engine.get_main_loop().root.get_node_or_null("MapRegistry")
		def = reg.get_map(m["id"]) if reg != null else null
		if def == null:
			return {}
		map = MapLoader.load_map(def)
	if map == null or map.terrain_hash != int(m.get("terrain_hash", map.terrain_hash)):
		push_warning("SaveManager: the map changed since this save was made")
	return {"config": cfg, "def": def, "map": map, "state": data["state"]}
