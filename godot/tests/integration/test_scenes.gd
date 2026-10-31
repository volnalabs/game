extends TestCase
## Every screen scene instantiates and builds its UI without script errors.


func test_menu_scenes_build() -> void:
	var root: Window = Engine.get_main_loop().root
	var app: Node = root.get_node("App")
	app.select_map(root.get_node("MapRegistry").get_map("pelagia"))
	for path in ["res://scenes/menus/main_menu.tscn", "res://scenes/menus/map_select.tscn",
			"res://scenes/menus/map_generator.tscn", "res://scenes/menus/match_setup.tscn",
			"res://scenes/menus/load_game.tscn", "res://scenes/menus/settings.tscn", "res://scenes/menus/credits.tscn"]:
		var scene: PackedScene = load(path)
		check(scene != null, path)
		var n := scene.instantiate()
		root.add_child(n)
		check(n.get_child_count() > 0, "%s built its UI" % path)
		n.free()


func test_meta_screens_build() -> void:
	var root: Window = Engine.get_main_loop().root
	var prof: Node = root.get_node("Profile")
	# Some content: a paid match, items, cases.
	var r := {"match_id": "scene-test", "map_id": "europe", "map_category": "regional", "generated": false, "difficulty": "hard",
		"bots": 20, "fair": false, "won": true, "abandoned": false, "reason": "domination", "minutes": 30.0, "conquered": 60000,
		"peak_tiles": 70000, "share": 0.72, "gold_earned": 9000000.0, "troops_lost": 1.0, "attacks": 20, "built": 8,
		"actions": 120, "eliminations": 6, "posts": 2, "rank": 1, "comeback": false}
	prof.pay_match(r)
	Inventory.grant(prof.data, "avatar_lion")
	prof.data.data["cases"]["elite"] = 2
	for path in ["profile_screen", "progress_screen", "cases_screen", "inventory_screen", "achievements_screen", "results_screen"]:
		var n: Control = (load("res://scripts/ui/screens/%s.gd" % path) as GDScript).new()
		root.add_child(n)
		await Engine.get_main_loop().process_frame
		check(n.get_child_count() > 0, "%s built its UI" % path)
		n.free()
	# Opening a case from the screen: result decided and saved before the animation.
	var cs: Control = (load("res://scripts/ui/screens/cases_screen.gd") as GDScript).new()
	root.add_child(cs)
	cs.set("_selected", "elite")
	var before: int = prof.data.case_count("elite")
	cs.call("_open")
	check_eq(prof.data.case_count("elite"), before - 1, "case consumed when opened")
	await Engine.get_main_loop().process_frame
	cs.free()


func test_hud_builds_for_a_match() -> void:
	var root: Window = Engine.get_main_loop().root
	var sim := TestMaps.sim(TestMaps.rect(100, 60), 2, true, 4)
	var hud := GameHUD.new()
	var fake := MatchStub.new()
	root.add_child(hud)
	hud.setup(fake, sim)
	hud.refresh()
	hud.show_end(true, "domination")
	check(hud.get_child_count() > 5, "HUD panels built")
	hud.free()
	fake.free()


class MatchStub:
	extends Node
	var paused := false
	var speed := 1.0
	var ratio := 0.2
	var build_kind := -1
	var selected_owner := 0
