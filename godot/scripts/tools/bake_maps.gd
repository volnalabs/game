extends SceneTree
## Bakes the authored fictional maps: data/map_specs/<id>.json -> data/maps/<id>/{terrain.png,
## preview.png, map.json} through the world generator.
##   godot --headless --path godot -s res://scripts/tools/bake_maps.gd [-- <id>]


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	for f in DirAccess.get_files_at("res://data/map_specs"):
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_specs/" + f))
		if only != "" and d["id"] != only:
			continue
		bake(d)
	quit()


func bake(d: Dictionary) -> void:
	var p := GenParams.new()
	p.apply_preset("continents")
	p.seed = int(d["seed"])
	p.width = int(d["width"])
	p.height = int(d["height"])
	p.size_name = "custom"
	p.land_percent = float(d["land_percent"])
	p.roughness = float(d["roughness"])
	p.mountains = float(d["mountains"])
	p.river_density = float(d["river_density"])
	p.start_positions = int(d["start_positions"])
	p.inland_seas = int(d.get("inland_seas", 0))
	p.spec = d["spec"]
	p.climate = d.get("climate", {})
	var res := MapGenerator.new().generate(p)
	var id: String = d["id"]
	var dir := "res://data/maps/" + id
	DirAccess.make_dir_recursive_absolute(dir)
	res.map.to_image().save_png(dir + "/terrain.png")
	TerrainColors.preview(res.map).save_png(dir + "/preview.png")
	var f := FileAccess.open(dir + "/terrain.png.import", FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"keep\"\n")
	f.close()
	var nations: Array = []
	for k in res.nations.size():
		var nd: Dictionary = res.nations[k]
		nd["id"] = "%s_%d" % [id, k]
		nations.append(nd)
	var out := {
		"id": id, "category": "fictional", "name": d["name"], "description": d["description"],
		"features": d["features"], "width": p.width, "height": p.height, "k_lin": 1.0,
		"recommended_bots": d["recommended_bots"], "max_bots": nations.size(), "nations": nations,
		"balance": {"tribes_default": 40}, "stats": res.stats,
		"source": "VolnaLabs original (data/map_specs/%s.json, baked by scripts/tools/bake_maps.gd)" % id,
		"license": "AGPL-3.0",
	}
	var mf := FileAccess.open(dir + "/map.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(out, "\t"))
	mf.close()
	print("%s: %dx%d land=%d continents=%d islands=%d starts=%d fairness=%.2f (%d ms)" % [id, p.width, p.height,
		res.map.land_count, res.stats["continents"], res.stats["islands"], nations.size(), res.stats["fairness"], res.stats["ms"]])
