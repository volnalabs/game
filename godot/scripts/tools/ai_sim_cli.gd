extends SceneTree
## AI Simulation mode: series of headless AI-vs-AI matches with fixed seeds.
##   godot --headless --path godot -s res://scripts/tools/ai_sim_cli.gd -- \
##       --games 20 --map gen:continents:S --bots 8 --mode strategic_vs_legacy --seed 1 --ticks 9000
## Modes: mixed, strategic_vs_legacy, hard_vs_easy, personalities (see AISimRunner).
## Writes the full report to user://ai_sim/<mode>_<seed>.json and prints a summary.


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _arg(args: PackedStringArray, name: String, def: String) -> String:
	var i := args.find("--" + name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(_arg(args, "games", "10"))
	var map_spec := _arg(args, "map", "gen:continents:S")
	var bots := int(_arg(args, "bots", "8"))
	var mode := _arg(args, "mode", "mixed")
	var seed0 := int(_arg(args, "seed", "1"))
	var ticks := int(_arg(args, "ticks", "9000"))
	var tribes := int(_arg(args, "tribes", "0"))
	var domination := float(_arg(args, "domination", "0.6"))
	var teams := int(_arg(args, "teams", "0"))
	var reg: Node = root.get_node("MapRegistry")
	var results: Array = []
	print("AI simulation: %d games, map %s, %d bots, mode %s, seeds %d..%d, max %d ticks" % [games, map_spec, bots, mode, seed0, seed0 + games - 1, ticks])
	for g in games:
		var r := AISimRunner.run_game(map_spec, seed0 + g, bots, mode, ticks, reg, tribes, domination, teams)
		results.append(r)
		print("  game %2d seed %d: %s (%s) after %d ticks, winner %s [%s], %.1f s" % [g + 1, r["seed"], "over" if r["over"] else "limit",
			r["reason"], r["ticks"], _name(r), r["winner_group"], float(r["ms"]) / 1000.0])
		print("      diplomacy: ", r["diplomacy"], (" team %d won" % int(r["team_winner"])) if int(r["team_winner"]) > 0 else "")
	var summary := AISimRunner.summarize(results)
	print("\nGroup summary:")
	print("  %-14s %6s %6s %8s %8s %9s %8s %8s %8s %8s" % ["group", "wins", "surv", "share", "life", "atk/won", "succ", "gold+", "upkeep", "entropy"])
	for k: String in summary:
		var s: Dictionary = summary[k]
		print("  %-14s %5.0f%% %5.0f%% %7.1f%% %8.0f %4d/%-4d %7.0f%% %8s %8s %8.2f" % [k, float(s["win_rate"]) * 100.0, float(s["survival"]) * 100.0,
			float(s["avg_share"]) * 100.0, float(s["avg_lifetime"]), int(s["attacks"]), int(s["attacks_won"]), float(s["attack_success"]) * 100.0,
			UITheme.num(float(s["avg_gold_earned"])), UITheme.num(float(s["avg_upkeep"])), float(s["strategy_entropy"])])
		print("      states: ", s["state_shares"])
		print("      decisions: ", s["decisions"])
	DirAccess.make_dir_recursive_absolute("user://ai_sim")
	var path := "user://ai_sim/%s_%d.json" % [mode, seed0]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"games": results, "summary": summary}, "\t"))
	f.close()
	print("\nreport: ", ProjectSettings.globalize_path(path))
	quit()


func _name(r: Dictionary) -> String:
	for b: Dictionary in r["bots"]:
		if int(b["id"]) == int(r["winner"]):
			return "%s/%s" % [b["name"], b["personality"]]
	return "?"
