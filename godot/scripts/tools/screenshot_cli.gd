extends SceneTree
## Drives the real game through its screens and saves screenshots (visual check without a person).
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/screenshot_cli.gd -- <out_dir> [map_id] [ticks]

var out_dir := "/tmp/shots"
var map_id := "earth"
var ticks := 1500
var main: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		map_id = args[1]
	if args.size() > 2:
		ticks = int(args[2])
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
	root.size = Vector2i(1600, 900)
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
	await _shot("05_spawn")
	var sim: Sim = ctl.sim
	var start := -1
	for i in 20000:
		var t := sim.map.land_tiles[(i * 7919) % sim.map.land_count]
		if sim.spawn.is_valid_start(t):
			start = t
			break
	sim.submit(Commands.spawn(sim.player_id, start))
	for i in 40:
		sim.step()
	# Play a while: the player expands and builds a city.
	sim.submit(Commands.attack_target(sim.player_id, 0, 15000.0))
	for i in ticks:
		sim.step()
		if i == ticks / 2:
			sim.st.add_gold(sim.player_id, 0.0)
			sim.submit(Commands.build(sim.player_id, Rules.B_CITY, sim.st.o_spawn_tile[sim.player_id]))
	ctl.cam.focus(Vector2(start % sim.map.width, start / sim.map.width), ctl.cam.min_zoom * 3.0)
	await _wait(10)
	await _shot("06_playing")
	ctl.select_owner(sim.player_id)
	ctl.hud._info_tab = "economy"
	await _wait(5)
	await _shot("07_economy_panel")
	ctl.hud._ai_debug = true
	var bot := sim.ai.brains[0].id
	ctl.hud._info_tab = "ai"
	ctl.select_owner(bot, true)
	await _wait(10)
	await _shot("08_ai_debug")
	ctl.cam.fit()
	ctl.open_pause_menu()
	await _wait(5)
	await _shot("09_pause")
	quit()
