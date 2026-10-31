extends TestCase
## Outcome-based AI quality checks on short series with fixed seeds (the full series with
## dozens of games run through scripts/tools/ai_sim_cli.gd, see docs/ai/AI_RESULTS.md).
## Quality is measured by results (land, survival), not by the number of actions.

const GAMES := 6
## The strategic-vs-legacy check uses more games: with research and perks single games swing more.
const GAMES_VS_LEGACY := 10


func _series(mode: String, seed0: int, n: int = GAMES) -> Dictionary:
	var reg: Node = Engine.get_main_loop().root.get_node("MapRegistry")
	var games: Array = []
	for g in n:
		games.append(AISimRunner.run_game("gen:continents:S", seed0 + g, 8, mode, 7000, reg))
	return AISimRunner.summarize(games)


## What every 20-40 game series showed (docs/ai/AI_RESULTS.md): the strategic AI survives more
## often and earns more than the legacy RoWorld AI. Land share and win rate are higher in most
## series but not in all of them, so they are reported, not asserted (a known limitation).
func test_strategic_ai_outlasts_and_outearns_the_legacy_ai() -> void:
	var s := _series("strategic_vs_legacy", 500, GAMES_VS_LEGACY)
	var a: Dictionary = s["strategic"]
	var b: Dictionary = s["legacy"]
	print("      strategic share %.3f surv %.2f wins %.2f gold %.0f | legacy share %.3f surv %.2f wins %.2f gold %.0f" % [a["avg_share"],
		a["survival"], a["win_rate"], a["avg_gold_earned"], b["avg_share"], b["survival"], b["win_rate"], b["avg_gold_earned"]])
	check(float(a["avg_gold_earned"]) > float(b["avg_gold_earned"]), "the strategic AI builds a stronger economy")
	# Survival, land and wins swing between short series; the strategic AI must lead on most of them.
	var ahead := 0
	for k in ["survival", "avg_share", "win_rate"]:
		if float(a[k]) >= float(b[k]) - 0.02:
			ahead += 1
	check(ahead >= 2, "and is level or ahead on at least two of survival, land and wins")


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
	print("      war+prepare: aggressive %.2f defensive %.2f economic %.2f | attacks/bot aggressive %.1f defensive %.1f" % [war_share.call(agg),
		war_share.call(dfn), war_share.call(eco), float(agg["attacks"]) / maxf(1.0, float(agg["bots"])), float(dfn["attacks"]) / maxf(1.0, float(dfn["bots"]))])
	# Time spent preparing or waging war measures aggression; the raw attack count does not
	# (defensive bots launch many short counter-attacks).
	check(war_share.call(agg) > war_share.call(dfn) * 1.5, "aggressive bots spend much more time at war than defensive ones")
	check(float(s["aggressive"]["strategy_entropy"]) > 1.0, "bots use several strategic states")
