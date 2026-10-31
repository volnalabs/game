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
