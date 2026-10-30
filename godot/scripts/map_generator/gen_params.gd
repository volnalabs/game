class_name GenParams
extends RefCounted
## Parameters of a generated world. The same parameters (seed included) always produce the same
## map, byte for byte.

const PRESETS_PATH := "res://data/maps/generator_presets.json"

var seed: int = 1
var preset: String = "continents"
var size_name: String = "M"
var width: int = 1200
var height: int = 600
var continents: int = 4
var islands: int = 14
var land_percent: float = 0.36
var inland_seas: int = 1
var river_density: float = 0.5
var roughness: float = 0.55
var mountains: float = 0.55
var symmetry: String = "none"
var start_positions: int = 24
## Authored shapes (fictional maps): {"blobs": [...], "ridges": [...], "seas": [...], "channels": [...]}.
var spec: Dictionary = {}
var climate: Dictionary = {}

static var _presets: Dictionary = {}


static func presets() -> Dictionary:
	if _presets.is_empty():
		_presets = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_PATH))
	return _presets


static func preset_ids() -> Array:
	return presets()["order"]


static func from_preset(preset_id: String, seed_value: int, size: String = "M") -> GenParams:
	var p := GenParams.new()
	p.seed = seed_value
	p.apply_preset(preset_id)
	p.set_size(size)
	return p


func apply_preset(preset_id: String) -> void:
	var all: Dictionary = presets()["presets"]
	if not all.has(preset_id):
		preset_id = "continents"
	preset = preset_id
	var d: Dictionary = all[preset_id]
	continents = int(d["continents"])
	islands = int(d["islands"])
	land_percent = float(d["land_percent"])
	inland_seas = int(d["inland_seas"])
	river_density = float(d["river_density"])
	roughness = float(d["roughness"])
	mountains = float(d["mountains"])
	symmetry = d["symmetry"]
	start_positions = int(d["start_positions"])


func set_size(name: String) -> void:
	var sizes: Dictionary = presets()["sizes"]
	if not sizes.has(name):
		name = "M"
	size_name = name
	width = int(sizes[name][0])
	height = int(sizes[name][1])


func layout() -> String:
	var all: Dictionary = presets()["presets"]
	return all.get(preset, all["continents"])["layout"]


func to_dict() -> Dictionary:
	return {"seed": seed, "preset": preset, "size_name": size_name, "width": width, "height": height,
		"continents": continents, "islands": islands, "land_percent": land_percent, "inland_seas": inland_seas,
		"river_density": river_density, "roughness": roughness, "mountains": mountains, "symmetry": symmetry,
		"start_positions": start_positions, "spec": spec, "climate": climate}


static func from_dict(d: Dictionary) -> GenParams:
	var p := GenParams.new()
	p.apply_preset(d.get("preset", "continents"))
	p.seed = int(d.get("seed", 1))
	p.size_name = d.get("size_name", "M")
	p.width = int(d.get("width", 1200))
	p.height = int(d.get("height", 600))
	p.continents = int(d.get("continents", p.continents))
	p.islands = int(d.get("islands", p.islands))
	p.land_percent = float(d.get("land_percent", p.land_percent))
	p.inland_seas = int(d.get("inland_seas", p.inland_seas))
	p.river_density = float(d.get("river_density", p.river_density))
	p.roughness = float(d.get("roughness", p.roughness))
	p.mountains = float(d.get("mountains", p.mountains))
	p.symmetry = d.get("symmetry", p.symmetry)
	p.start_positions = int(d.get("start_positions", p.start_positions))
	p.spec = d.get("spec", {})
	p.climate = d.get("climate", {})
	return p
