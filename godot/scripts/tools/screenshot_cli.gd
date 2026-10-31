extends SceneTree
## Drives the real game through its screens and saves screenshots (visual check without a person).
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/screenshot_cli.gd -- <out_dir> [map_id] [ticks] [WxH]

var out_dir := "/tmp/shots"
var map_id := "earth"
var ticks := 1500
var win := Vector2i(1600, 900)
var main: Node
var _tips_before: Array = []
var _show_tips_before := true


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		map_id = args[1]
	if args.size() > 2:
		ticks = int(args[2])
	if args.size() > 3 and args[3].contains("x"):
		win = Vector2i(int(args[3].get_slice("x", 0)), int(args[3].get_slice("x", 1)))
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _wait(3)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _run() -> void:
	root.size = win
	# Tips are shown as for a new player; the player's own tip settings are restored at the end.
	var settings := root.get_node("Settings")
	_tips_before = (settings.seen_tips as Array).duplicate()
	_show_tips_before = settings.show_tips
	settings.seen_tips = []
	settings.show_tips = true
	# A demo profile in its own file (never the player's real one).
	var prof := root.get_node_or_null("Profile")
	if prof != null:
		prof.store = ProfileStore.new("user://screenshot_profile.json")
		prof.data = ProfileData.fresh()
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var app: Node = root.get_node("App")
	await _wait(5)
	await _shot("01_main_menu")
	app.goto(app.State.MAP_SELECT)
	await _shot("02_map_select")
	var reg: Node = root.get_node("MapRegistry")
	app.select_map(reg.get_map(map_id))
	app.goto(app.State.MATCH_SETUP)
	await _shot("03_match_setup")
	app.goto(app.State.MAP_GENERATOR)
	await _wait(3)
	var gen: Node = main._current
	gen._generate()
	await _wait(10)
	await _shot("04_generator")
	app.select_map(reg.get_map(map_id))
	app.config.bots = 30
	app.config.tribes = 40
	app.config.seed = 7
	app.config.player_nation = 0
	app.start_new_match()
	await _wait(8)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(5)
	var sim: Sim = ctl.sim
	# Valid start closest to the map centre (keeps the camera inside the map).
	var start := -1
	var best := INF
	var mid := Vector2(sim.map.width, sim.map.height) * 0.5
	for i in 4000:
		var t := sim.map.land_tiles[(i * 7919) % sim.map.land_count]
		var d := Vector2(t % sim.map.width, t / sim.map.width).distance_squared_to(mid)
		if d < best and sim.spawn.is_valid_start(t):
			best = d
			start = t
	var sp := Vector2(start % sim.map.width, start / sim.map.width)
	ctl.cam.focus(sp, ctl.cam.min_zoom * 4.0)
	await _wait(3)
	ctl.hover_tile = start
	ctl._update_spawn_hover()
	await _shot("05_spawn")
	ctl._left_click(start)
	await _wait(3)
	await _shot("05b_spawn_confirm")
	ctl.confirm_spawn()
	while sim.phase == Sim.Phase.SPAWN:
		sim.step()
	# Play a while: the player expands and builds a city.
	sim.submit(Commands.attack_target(sim.player_id, 0, 15000.0))
	for i in ticks:
		sim.step()
		if i == ticks / 2:
			sim.st.add_gold(sim.player_id, 0.0)
			sim.submit(Commands.build(sim.player_id, Rules.B_CITY, sim.st.o_spawn_tile[sim.player_id]))
	# Attack every neighbour so the fronts are visible.
	for o in range(1, sim.st.owner_count + 1):
		if o != sim.player_id and sim.st.o_alive[o] == 1 and ctl.borders(sim.player_id, o):
			sim.submit(Commands.attack_target(sim.player_id, o, sim.st.o_troops[sim.player_id] * 0.15))
	sim.submit(Commands.attack_target(sim.player_id, 0, sim.st.o_troops[sim.player_id] * 0.1))
	for i in 15:
		sim.step()
		await _wait(2)
	ctl.cam.focus(sp, ctl.cam.min_zoom * 3.0)
	await _wait(30)
	await _shot("06_playing")
	ctl.hud.tip_card.close()
	# Every building type around the player's start, all researched (map symbols at three zooms).
	sim.research.state[sim.player_id] = {"done": ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"])),
		"current": "", "progress": {}}
	sim.mods.mark(sim.player_id)
	var home: int = sim.st.o_spawn_tile[sim.player_id]
	var hx: int = home % sim.map.width
	var hy: int = home / sim.map.width
	for y in range(hy - 45, hy + 45):
		for x in range(hx - 45, hx + 45):
			# A round grab around the start (a square one drew an unnatural rectangular state).
			if (x - hx) * (x - hx) + (y - hy) * (y - hy) > 45 * 45:
				continue
			var t := sim.map.tile_at(clampi(x, 0, sim.map.width - 1), clampi(y, 0, sim.map.height - 1))
			if sim.map.land[t] == 1 and sim.st.struct_at[t] < 0:
				sim.st.set_owner(t, sim.player_id)
	var built: Array[int] = []
	for k: int in ctl.hud.call("quick_kinds") + [Rules.B_RADAR, Rules.B_AIRBASE, Rules.B_ACADEMY, Rules.B_LOGISTICS, Rules.B_COMMAND, Rules.B_BUNKER, Rules.B_POWER, Rules.B_NAVAL_BASE, Rules.B_RESEARCH]:
		sim.st.add_gold(sim.player_id, 5000000.0)
		sim.st.add_supplies(sim.player_id, 5000.0)
		var r := sim.structures.try_build(sim.player_id, k, sim.map.tile_at(hx + (built.size() % 4) * 18 - 27, hy + (built.size() / 4) * 18 - 27))
		if r["ok"]:
			built.append(int(r["id"]))
	for i in 130:
		sim.st.tick += 1
		sim.structures.tick()
	var hp := Vector2(home % sim.map.width, home / sim.map.width)
	for zz: Array in [["06c_zoom_far", 1.4], ["06d_zoom_mid", 4.0], ["06e_zoom_near", 11.0]]:
		ctl.cam.focus(hp, ctl.cam.min_zoom * float(zz[1]))
		await _wait(6)
		await _shot(String(zz[0]))
	if not built.is_empty():
		ctl.select_structure(built[0])
		await _wait(6)
		await _shot("06f_city_selected")
		for sid in built.slice(1):
			ctl.select_structure(sid)
			await _wait(3)
			await _shot("06g_building_%s" % sim.rules.b_ids[sim.structures.structs[sid].kind])
		ctl.select_structure(-1)
		# Hover hint over a building.
		var hsp: Vector2 = ctl.cam.get_canvas_transform() * (Vector2(sim.structures.structs[built[0]].tile % sim.map.width, sim.structures.structs[built[0]].tile / sim.map.width) + Vector2(0.5, 0.5))
		ctl._mouse_screen = hsp
		ctl.hover_structure = -2
		ctl._update_structure_hover()
		await _wait(4)
		await _shot("06h_building_hover")
		root.get_node("HintLayer").hide_hint()
	ctl.cam.focus(hp, ctl.cam.min_zoom * 3.0)
	# A war between two states, selected: its fronts, losses and captures.
	var war: AttackSystem.Attack = null
	for a in sim.attacks.attacks:
		if a.alive and a.target > 0 and not a.landing and (war == null or a.troops > war.troops):
			war = a
	if war != null:
		ctl.select_owner(war.attacker)
		ctl.cam.focus(ctl.effects._fronts.get(war.id, {}).get("p", sim.st.centroid(war.attacker)), ctl.cam.min_zoom * 5.0)
		ctl.hud.inspector.set_tab("army")
		await _wait(80)
		await _shot("06b_war_fronts")
		ctl.select_owner(0)
	ctl.hud.dock.open("economy")
	await _wait(5)
	await _shot("07_economy_panel")
	ctl.open_build_mode()
	await _wait(5)
	await _shot("07b_build_panel")
	ctl.close_build_mode()
	sim.st.add_supplies(sim.player_id, 5000.0)
	sim.st.add_gold(sim.player_id, 1000000.0)
	sim.submit(Commands.build(sim.player_id, Rules.B_DEFENSE, sim.st.o_spawn_tile[sim.player_id]))
	sim.step()
	ctl.toggle_zones()
	ctl.cam.focus(hp, ctl.cam.min_zoom * 4.0)
	await _wait(3)
	ctl.begin_build(Rules.B_DEFENSE)
	var gt: int = sim.map.tile_at(int(hp.x) + 9, int(hp.y) + 9)
	ctl.hover_tile = gt
	ctl._mouse_screen = ctl.cam.get_canvas_transform() * Vector2(gt % sim.map.width + 0.5, gt / sim.map.width + 0.5)
	await _wait(10)
	await _shot("07c_build_ghost")
	ctl.cancel_build()
	ctl.toggle_zones()
	sim.research.state[sim.player_id] = {"done": ["trade_routes", "fortification", "doctrine"], "current": "electrification",
		"progress": {"electrification": 70.0}}
	sim.mods.mark(sim.player_id)
	ctl.hud.dock.open("research")
	await _wait(8)
	await _shot("07d_research")
	ctl.hud.dock.open("")
	ctl.hud.dock.open("")
	ctl.hud.ai_debug = true
	var bot := sim.ai.brains[0].id
	ctl.select_owner(bot, true)
	ctl.hud.inspector.set_tab("ai")
	await _wait(10)
	await _shot("08_ai_debug")
	ctl.cam.fit()
	ctl.open_pause_menu()
	await _wait(5)
	await _shot("09_pause")
	ctl.close_pause_menu()
	# Meta progression screens with a demo profile.
	prof = root.get_node("Profile")
	var res := MatchResult.from_sim(sim, false)
	res["won"] = true
	res["minutes"] = maxf(float(res["minutes"]), 24.0)
	res["actions"] = 90
	res["difficulty"] = "hard"
	prof.pay_match(res)
	for id in ["avatar_lion", "emblem_eagle", "frame_gold", "title_marshal", "color_amber", "plate_hex", "capture_rings", "victory_fireworks", "theme_royal"]:
		Inventory.grant(prof.data, id)
	prof.data.data["cases"]["elite"] = 3
	prof.data.data["credits"] = 5400
	app.goto(app.State.RESULTS)
	await _wait(140)
	await _shot("10_results")
	app.goto(app.State.PROFILE)
	await _wait(10)
	await _shot("11_profile")
	app.goto(app.State.PROGRESS)
	await _wait(10)
	await _shot("12_progress")
	app.goto(app.State.CASES)
	await _wait(10)
	await _shot("13_cases")
	var cs: Node = main._current
	cs.set("_selected", "elite")
	cs.call("_rebuild")
	cs.call("_open")
	await _wait(150)
	await _shot("13b_case_opened")
	prof.equip("avatar_lion")
	prof.equip("frame_gold")
	app.goto(app.State.INVENTORY)
	await _wait(10)
	await _shot("14_inventory")
	app.goto(app.State.ACHIEVEMENTS)
	await _wait(10)
	await _shot("15_achievements")
	prof.data.data["level"] = 12
	prof.data.data["skill_points"] = 9
	for id in ["eco_tax", "eco_industry", "mil_drill", "def_walls"]:
		SkillTree.unlock(prof.data, id)
	for id in ["eco_tax", "mil_drill"]:
		SkillTree.equip(prof.data, id)
	app.goto(app.State.SKILLS)
	await _wait(10)
	await _shot("15b_skill_tree")
	app.goto(app.State.MAIN_MENU)
	await _wait(20)
	await _shot("16_main_menu_profile")
	app.goto(app.State.ENCYCLOPEDIA)
	await _wait(5)
	main._current.call("show_article", "b_factory")
	await _wait(5)
	await _shot("17_encyclopedia_building")
	main._current.call("show_article", "g_supplies")
	await _wait(5)
	await _shot("17b_encyclopedia_term")
	app.goto(app.State.SETTINGS)
	await _wait(5)
	await _shot("18_settings")
	settings.seen_tips = _tips_before
	settings.show_tips = _show_tips_before
	settings.save_settings()
	quit()
