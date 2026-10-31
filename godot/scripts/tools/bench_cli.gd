extends SceneTree
## Simulation and renderer benchmark: ms per tick (avg / p95 / max) and per system, for a map.
##   godot --headless --path godot -s res://scripts/tools/bench_cli.gd -- --map earth --bots 40 --tribes 60 --ticks 3000
## --map accepts a registry id or gen:<preset>:<S|M|L|XL>.


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _arg(args: PackedStringArray, name: String, def: String) -> String:
	var i := args.find("--" + name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var map_spec := _arg(args, "map", "earth")
	var bots := int(_arg(args, "bots", "40"))
	var tribes := int(_arg(args, "tribes", "60"))
	var ticks := int(_arg(args, "ticks", "3000"))
	var reg: Node = root.get_node("MapRegistry")
	var t0 := Time.get_ticks_msec()
	var md := AISimRunner.make_map(map_spec, 1, reg)
	var t_map := Time.get_ticks_msec() - t0
	var cfg := MatchConfig.new()
	cfg.has_player = false
	cfg.bots = bots
	cfg.tribes = tribes
	cfg.seed = 1
	cfg.victory.domination_share = 1.0
	cfg.victory.eliminate_all = false
	t0 = Time.get_ticks_msec()
	var sim := Sim.new(cfg, md[0], md[1])
	var t_sim := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(sim)
	var t_render := Time.get_ticks_msec() - t0
	sim.profiling = true
	var times := PackedFloat32Array()
	var upload := PackedFloat32Array()
	var sys := {}
	for i in ticks:
		var ts := Time.get_ticks_usec()
		sim.step()
		times.append((Time.get_ticks_usec() - ts) / 1000.0)
		for k in sim.profile:
			if k != "_last":
				sys[k] = float(sys.get(k, 0.0)) + float(sim.profile[k])
		sim.profile.clear()
		sim.events.drain()
		var tu := Time.get_ticks_usec()
		renderer.apply_changes(sim.st.drain_changed_tiles())
		renderer.flush(1000.0)
		upload.append((Time.get_ticks_usec() - tu) / 1000.0)
	var sorted := times.duplicate()
	sorted.sort()
	var usorted := upload.duplicate()
	usorted.sort()
	var avg := 0.0
	for v in times:
		avg += v
	avg /= times.size()
	var uavg := 0.0
	for v in upload:
		uavg += v
	uavg /= upload.size()
	print("map %s %dx%d (land %d), %d bots + %d tribes, %d ticks" % [map_spec, sim.map.width, sim.map.height, sim.map.land_count, bots, tribes, ticks])
	print("  load map %d ms, create sim %d ms, build renderer %d ms" % [t_map, t_sim, t_render])
	print("  sim step: avg %.2f ms, p95 %.2f ms, max %.2f ms  (budget at x1: 100 ms per tick)" % [avg, sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1]])
	print("  territory upload per tick: avg %.2f ms, p95 %.2f ms" % [uavg, usorted[int(usorted.size() * 0.95)]])
	var per := {}
	for k in sys:
		per[k] = snappedf(float(sys[k]) / ticks, 0.01)
	print("  per system avg ms: ", per)
	quit()
