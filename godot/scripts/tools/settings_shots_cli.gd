extends SceneTree
## Settings v2 review (Phase 2G): the settings tabs (display with the colour preview, sound,
## controls with a rebinding notice) and one match in each colour-vision mode.
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/settings_shots_cli.gd -- <out_dir> [WxH]

var out_dir := "/tmp/settings"
var win := Vector2i(1600, 900)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1 and args[1].contains("x"):
		win = Vector2i(int(args[1].get_slice("x", 0)), int(args[1].get_slice("x", 1)))
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _wait(4)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _run() -> void:
	var settings := root.get_node("Settings")
	settings.show_tips = false
	settings.key_overrides = {}
	settings.color_mode = "deuteranopia"
	settings.apply()
	root.size = win
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(4)
	var app := root.get_node("App")
	app.goto(app.State.SETTINGS)
	await _wait(6)
	var scr: Node = main._current
	scr.show_tab("display")
	await _shot("settings_display")
	scr.show_tab("audio")
	await _shot("settings_audio")
	scr.bind("zones", KEY_B)
	await _shot("settings_controls")
	settings.key_overrides = {}
	settings.apply()
	# A match with many states, in each colour mode.
	var reg := root.get_node("MapRegistry")
	var md := AISimRunner.make_map("gen:continents:S", 31, reg)
	app.select_map(md[0], md[1])
	var cfg := MatchConfig.new()
	cfg.seed = 31
	cfg.bots = 12
	cfg.tribes = 10
	cfg.has_player = true
	app.config = cfg
	app.start_new_match()
	await _wait(6)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	var sim: Sim = ctl.sim
	var m: MapData = md[1]
	var t := m.land_tiles[m.land_tiles.size() / 2]
	sim.apply_command(Commands.spawn(sim.player_id, t))
	sim._start_playing()
	for i in 900:
		sim.step()
	ctl._handle_events()
	ctl.renderer.apply_changes(PackedInt32Array())
	ctl.renderer.full_refresh() if ctl.renderer.has_method("full_refresh") else null
	ctl.cam.focus(Vector2(m.width / 2.0, m.height / 2.0), 1.0)
	for mode: String in ColorAccess.MODES:
		settings.color_mode = mode
		settings.apply()
		await _wait(10)
		await _shot("map_" + mode)
	settings.color_mode = "off"
	settings.apply()
	quit()
