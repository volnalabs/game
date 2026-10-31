extends TestCase
## Outcome-based AI quality checks on short series with fixed seeds (the full series with
## dozens of games run through scripts/tools/ai_sim_cli.gd, see docs/ai/AI_RESULTS.md).
## Quality is measured by results (land, survival), not by the number of actions.

const GAMES := 6


func _series(mode: String, seed0: int) -> Dictionary:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var games: Array = []
	for g in GAMES:
		games.append(AISimRunner.run_game("gen:continents:S", seed0 + g, 8, mode, 7000, reg))
	return AISimRunner.summarize(games)


func test_strategic_ai_beats_the_legacy_ai() -> void:
	var s := _series("strategic_vs_legacy", 500)
	var a: Dictionary = s["strategic"]
	var b: Dictionary = s["legacy"]
	print("      strategic share %.3f surv %.2f | legacy share %.3f surv %.2f" % [a["avg_share"], a["survival"], b["avg_share"], b["survival"]])
	check(float(a["avg_share"]) > float(b["avg_share"]), "strategic AI holds more land on average")
	check(float(a["survival"]) >= float(b["survival"]), "and survives at least as often")


func test_hard_beats_easy_without_bonuses() -> void:
	var s := _series("hard_vs_easy", 600)
	var a: Dictionary = s["hard"]
	var b: Dictionary = s["easy"]
	print("      hard share %.3f wins %.2f | easy share %.3f wins %.2f" % [a["avg_share"], a["win_rate"], b["avg_share"], b["win_rate"]])
	check(float(a["avg_share"]) > float(b["avg_share"]), "hard bots hold more land")
	check(float(a["win_rate"]) > float(b["win_rate"]), "and win more often")


func test_personalities_play_differently() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var games: Array = []
	for g in 3:
		games.append(AISimRunner.run_game("gen:pangaea:S", 700 + g, 10, "personalities", 5000, reg))
	var s := AISimRunner.summarize(games)
	var agg: Dictionary = s["aggressive"]
	var dfn: Dictionary = s["defensive"]
	var eco: Dictionary = s["economic"]
	var war_share := func(d: Dictionary) -> float:
		var sh: Dictionary = d["state_shares"]
		return float(sh.get("war", 0.0)) + float(sh.get("prepare_war", 0.0))
	print("      war+prepare: aggressive %.2f defensive %.2f economic %.2f" % [war_share.call(agg), war_share.call(dfn), war_share.call(eco)])
	check(float(agg["attacks"]) / maxf(1.0, float(agg["bots"])) > float(dfn["attacks"]) / maxf(1.0, float(dfn["bots"])), "aggressive bots attack more than defensive ones")
	check(float(s["aggressive"]["strategy_entropy"]) > 1.0, "bots use several strategic states")
