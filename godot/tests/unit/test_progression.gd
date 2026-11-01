extends TestCase
## Meta progression: data integrity, levels, rewards (win/loss/abandon, anti-AFK, anti-farm),
## idempotency, case odds and pity, duplicates, inventory, achievements, challenges, profile
## persistence, migration and corruption recovery.

const NOW := 1793000000


func _result(over: Dictionary = {}) -> Dictionary:
	var r := {"match_id": "m-%d" % randi(), "map_id": "europe", "map_category": "regional", "generated": false,
		"difficulty": "normal", "bots": 20, "fair": false, "won": true, "abandoned": false, "reason": "domination",
		"minutes": 25.0, "conquered": 40000, "peak_tiles": 50000, "share": 0.7, "gold_earned": 5000000.0,
		"troops_lost": 100000.0, "attacks": 30, "built": 6, "actions": 80, "eliminations": 4, "posts": 1, "rank": 1, "comeback": false}
	r.merge(over, true)
	return r


func test_meta_data_is_consistent() -> void:
	var errs := MetaData.validate()
	check(errs.is_empty(), "meta data errors: %s" % ", ".join(errs))
	var total := 0.0
	for r: String in MetaData.rarity()["odds"]:
		total += float(MetaData.rarity()["odds"][r])
	check_near(total, 100.0, 0.0001, "rarity odds sum to 100")


func test_level_curve() -> void:
	var prev := 0
	for L in range(1, 60):
		var n := Progression.xp_to_next(L)
		check(n >= prev, "curve does not decrease at %d" % L)
		prev = n
	var total := 0
	for L in range(1, 11):
		total += Progression.xp_to_next(L)
	check_eq(int(Progression.level_for(total)["level"]), 11, "level_for agrees with the curve")
	# Early levels are quick: one good match is about a level.
	var rep := RewardCalculator.compute(_result(), [], NOW)
	check(int(rep["xp"]) >= Progression.xp_to_next(1), "a won 25-minute match gives at least level 1->2 (%d xp)" % int(rep["xp"]))


func test_rewards_win_loss_abandon_afk() -> void:
	var win := RewardCalculator.compute(_result(), [], NOW)
	var loss := RewardCalculator.compute(_result({"won": false, "share": 0.1}), [], NOW)
	var ab := RewardCalculator.compute(_result({"won": false, "abandoned": true}), [], NOW)
	var afk := RewardCalculator.compute(_result({"won": false, "actions": 0}), [], NOW)
	var tiny := RewardCalculator.compute(_result({"minutes": 1.0}), [], NOW)
	check(int(win["credits"]) > int(loss["credits"]), "victory pays more than defeat")
	check(int(loss["credits"]) > 0 and int(loss["xp"]) > 0, "a defeat still rewards")
	check_eq(int(ab["credits"]), 0, "abandoned: no credits")
	check(int(ab["xp"]) > 0 and int(ab["xp"]) < int(loss["xp"]), "abandoned: partial XP")
	check(int(afk["credits"]) < int(loss["credits"]) * 0.5, "idle player earns much less (%d vs %d)" % [int(afk["credits"]), int(loss["credits"])])
	check_eq(int(tiny["xp"]) + int(tiny["credits"]), 0, "a 1-minute match pays nothing")
	var hard := RewardCalculator.compute(_result({"difficulty": "hard"}), [], NOW)
	check(int(hard["credits"]) > int(win["credits"]), "hard pays more")


func test_restart_farming_is_reduced() -> void:
	var history: Array = []
	for i in 4:
		history.append({"time": NOW - 600 * (i + 1), "minutes": 3.0, "won": true, "map_id": "europe", "difficulty": "normal"})
	var fresh := RewardCalculator.compute(_result({"minutes": 4.0}), [], NOW)
	var farmed := RewardCalculator.compute(_result({"minutes": 4.0}), history, NOW)
	check(int(farmed["credits"]) < int(fresh["credits"]) * 0.4, "repeated short wins pay far less (%d vs %d)" % [int(farmed["credits"]), int(fresh["credits"])])
	var old: Array = [{"time": NOW - 3 * 86400, "minutes": 3.0, "won": true, "map_id": "europe", "difficulty": "normal"}]
	check_eq(int(RewardCalculator.compute(_result({"minutes": 4.0}), old, NOW)["credits"]), int(fresh["credits"]), "old history does not penalise")


func test_reward_manager_is_idempotent() -> void:
	var p := ProfileData.fresh()
	var r := _result()
	var rep := RewardManager.apply_match(p, r, NOW)
	check(not rep.get("duplicate", false), "first payment")
	var credits := p.credits()
	var xp := p.xp()
	check(credits > 0 and xp > 0, "paid")
	check(RewardManager.apply_match(p, r, NOW + 5).get("duplicate", false), "second payment refused")
	check_eq(p.credits(), credits, "credits unchanged")
	check_eq(p.xp(), xp, "xp unchanged")
	check_eq(int(p.data["stats"]["matches"]), 1, "counted once")


func test_abandon_then_finish_pays_the_difference() -> void:
	var p := ProfileData.fresh()
	var full := ProfileData.fresh()
	var id := "same-match"
	RewardManager.apply_match(p, _result({"match_id": id, "won": false, "abandoned": true, "minutes": 12.0}), NOW)
	check(RewardManager.apply_match(p, _result({"match_id": id, "won": false, "abandoned": true, "minutes": 12.0}), NOW).get("duplicate", false),
		"abandoning again pays nothing")
	RewardManager.apply_match(p, _result({"match_id": id}), NOW + 60)
	RewardManager.apply_match(full, _result({"match_id": "other"}), NOW + 60)
	# Same total as a match finished in one go (achievements/first-win identical in both).
	check_eq(p.data["applied_matches"][id]["xp"], full.data["applied_matches"]["other"]["xp"], "xp total equals a straight finish")
	check_eq(int(p.data["stats"]["matches"]), 1, "one match in the statistics")


func test_level_up_and_milestones() -> void:
	var p := ProfileData.fresh()
	var report := {"levels": [], "cases": {}, "items": [], "achievements": []}
	var need := 0
	for L in range(1, 5):
		need += Progression.xp_to_next(L)
	RewardManager._add_xp(p, need, report)
	check_eq(p.level(), 5, "level 5")
	check_eq(report["levels"], [2, 3, 4, 5], "each level reported")
	check(p.case_count("starter") >= 2, "milestone 5 gives a case")
	check(int(p.data["skill_points"]) >= 4, "skill points per level")


func test_case_odds_match_the_table() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var counts := {}
	var n := 100000
	for i in n:
		var out := CaseSystem.roll("starter", {"epic": 0, "legendary": 0}, rng, {})
		counts[out["rarity"]] = int(counts.get(out["rarity"], 0)) + 1
	var odds := CaseSystem.odds("starter")
	for r: String in odds:
		var got := float(counts.get(r, 0)) / n * 100.0
		check(absf(got - float(odds[r])) < maxf(0.6, float(odds[r]) * 0.08), "%s: %.2f%% vs %s%%" % [r, got, str(odds[r])])
	var elite := CaseSystem.roll("elite", {"epic": 0, "legendary": 0}, rng, {})
	check(elite["rarity"] != "common", "elite has no commons")


func test_pity_guarantees() -> void:
	var p := ProfileData.fresh()
	p.data["cases"]["starter"] = 200
	var P: Dictionary = MetaData.rarity()["pity"]
	var since_epic := 0
	var worst := 0
	for i in 200:
		var out := CaseSystem.open_case(p, "starter")
		if out["rarity"] in ["epic", "legendary"]:
			worst = maxi(worst, since_epic + 1)
			since_epic = 0
		else:
			since_epic += 1
	worst = maxi(worst, since_epic)
	check(worst <= int(P["epic_or_better_after"]), "epic or better at least every %d opens (worst %d)" % [int(P["epic_or_better_after"]), worst])
	var forced := CaseSystem.roll("starter", {"epic": 0, "legendary": int(P["legendary_after"]) - 1}, RandomNumberGenerator.new(), {})
	check_eq(forced["rarity"], "legendary", "legendary pity")


func test_duplicates_and_crafting() -> void:
	var p := ProfileData.fresh()
	var g1 := Inventory.grant(p, "avatar_wolf")
	var g2 := Inventory.grant(p, "avatar_wolf")
	check(not g1["duplicate"] and g2["duplicate"], "second copy is a duplicate")
	check(p.fragments() > 0 and p.credits() > 0, "duplicate converted")
	p.data["fragments"] = 10000
	check(Inventory.craft(p, "avatar_dragon"), "craft with fragments")
	check(p.owns("avatar_dragon"), "crafted item owned")
	check(not Inventory.craft(p, "avatar_dragon"), "cannot craft an owned item")
	check(Inventory.equip(p, "avatar_dragon"), "equip")
	check_eq(p.equipped("avatar"), "avatar_dragon")
	check(not Inventory.equip(p, "emblem_crown"), "cannot equip what you do not own")
	var found := Inventory.list(p, {"search": MetaData.text(MetaData.item("avatar_dragon")["name"]).substr(0, 4)})
	check(found.any(func(it: Dictionary) -> bool: return it["id"] == "avatar_dragon"), "search finds it")
	var legendary := Inventory.list(p, {"rarity": "legendary"})
	check(legendary.all(func(it: Dictionary) -> bool: return it["rarity"] == "legendary"), "rarity filter")


func test_achievements_unlock_once_and_pay() -> void:
	var p := ProfileData.fresh()
	var rep := RewardManager.apply_match(p, _result({"difficulty": "hard"}), NOW)
	check((rep["achievements"] as Array).has("first_win"), "first win")
	check((rep["achievements"] as Array).has("hard_win"), "hard win")
	var rep2 := RewardManager.apply_match(p, _result({"difficulty": "hard"}), NOW + 3600)
	check(not (rep2["achievements"] as Array).has("first_win"), "not twice")


func test_weekly_challenges_are_stable_and_complete_once() -> void:
	var p := ProfileData.fresh()
	QuestSystem.refresh_week(p, NOW)
	var set1: Array = (p.data["quests"]["weekly"] as Array).duplicate()
	QuestSystem.refresh_week(p, NOW + 3600)
	check_eq(p.data["quests"]["weekly"], set1, "same week, same set")
	check_eq(set1.size(), int(MetaData.json("quests")["weekly_count"]))
	check(QuestSystem.week_id(NOW) != QuestSystem.week_id(NOW + 8 * 86400), "next week differs")
	var total_done := 0
	for i in 6:
		total_done += QuestSystem.on_match(p, _result({"difficulty": "hard", "map_category": "fictional", "built": 10}), NOW + i * 60).size()
	var seen := {}
	for id: String in (p.data["quests"]["done"] as Dictionary):
		seen[id] = true
	check(total_done >= 1, "something completed")
	check_eq(total_done, seen.size() + (p.data["quests"]["chain_done"] as Dictionary).size(), "each completed once")


func test_profile_persistence_backup_and_corruption() -> void:
	var path := "user://test_profile_store.json"
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var store := ProfileStore.new(path)
	var p := store.load_profile()
	check_eq(store.last_load, "new")
	Inventory.grant(p, "avatar_lion")
	Inventory.equip(p, "avatar_lion")
	p.data["credits"] = 777
	check(store.save_profile(p), "saved")
	p.data["credits"] = 778
	check(store.save_profile(p), "saved again (backup kept)")
	var q := ProfileStore.new(path).load_profile()
	check_eq(q.credits(), 778, "loaded")
	check_eq(q.equipped("avatar"), "avatar_lion", "equipment persisted")
	# Corrupt the main file: the backup is used.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var s2 := ProfileStore.new(path)
	var r := s2.load_profile()
	check_eq(s2.last_load, "restored_backup")
	check_eq(r.credits(), 777, "backup content")
	# Both broken: fresh profile, nothing thrown.
	for pth in [path, path + ".bak"]:
		var g := FileAccess.open(pth, FileAccess.WRITE)
		g.store_string("garbage")
		g.close()
	var s3 := ProfileStore.new(path)
	var fresh := s3.load_profile()
	check_eq(s3.last_load, "reset_corrupt")
	check_eq(fresh.level(), 1)
	var d := DirAccess.open("user://")
	for fn in d.get_files():
		if fn.begins_with("test_profile_store.json"):
			DirAccess.remove_absolute("user://" + fn)


func test_profile_migration_from_v0() -> void:
	var old := {"xp": 1200, "credits": 50, "items": ["avatar_wolf", "emblem_anchor"], "pity": 7, "applied_matches": ["a", "b"]}
	var p := ProfileData.from_dict(old)
	check_eq(int(p.data["version"]), ProfileData.CURRENT_VERSION)
	check(p.owns("avatar_wolf") and p.owns("emblem_anchor"), "items migrated")
	check(p.owns("avatar_recruit"), "defaults added")
	check_eq(int(p.data["pity"]["epic"]), 7, "pity migrated")
	check(bool(p.data["applied_matches"]["a"]["final"]), "applied list migrated")
	check(p.data.has("quests") and p.data.has("perks"), "new blocks added")


func test_cosmetics_do_not_touch_rules() -> void:
	# Two identical matches, one with a cosmetic display colour: same outcome tick by tick.
	var a := TestMaps.sim(TestMaps.rect(120, 80), 4, false, 3)
	var b := TestMaps.sim(TestMaps.rect(120, 80), 4, false, 3)
	b.st.set_display_color(1, Color("#4cf0c0"))
	for i in 300:
		a.step()
		b.step()
	check_eq(a.st.owner, b.st.owner, "same territory")
	check_eq(a.st.o_troops, b.st.o_troops, "same troops")
