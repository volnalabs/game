extends SceneTree
## UX review shots in a real match (organic territory from actual attacks, buildings placed by the
## normal build rules), in the states the HUD must handle, at several window sizes:
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/ux_shots_cli.gd -- <out_dir> [WxH,WxH,...]

var out_dir := "/tmp/ux"
var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080)]
var main: Node
var ctl: Node
var sim: Sim
var built: Dictionary = {}
var neighbour: int = 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		sizes.clear()
		for p in args[1].split(","):
			sizes.append(Vector2i(int(p.get_slice("x", 0)), int(p.get_slice("x", 1))))
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
	var seen_before: Array = (settings.seen_tips as Array).duplicate()
	var tips_before: bool = settings.show_tips
	settings.show_tips = false
	var prof := root.get_node("Profile")
	prof.store = ProfileStore.new("user://ux_shots_profile.json")
	prof.data = ProfileData.fresh()
	root.size = sizes[0]
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var app: Node = root.get_node("App")
	await _wait(5)
	app.select_map(root.get_node("MapRegistry").get_map("europe"))
	app.config.bots = 30
	app.config.tribes = 30
	app.config.seed = 11
	app.config.player_nation = -1
	app.start_new_match()
	await _wait(8)
	ctl = main._current
	while ctl.sim == null:
		await _wait(5)
	sim = ctl.sim
	await _prepare()
	for sz in sizes:
		root.size = sz
		await _wait(6)
		await _states("%dx%d" % [sz.x, sz.y], settings)
	settings.seen_tips = seen_before
	settings.show_tips = tips_before
	settings.save_settings()
	quit()


## A real game: start in central Europe, expand, research, build a varied economy.
func _prepare() -> void:
	var p := sim.player_id
	var mid := Vector2(sim.map.width * 0.52, sim.map.height * 0.55)
	var start := -1
	var best := INF
	for i in 6000:
		var t := sim.map.land_tiles[(i * 7919) % sim.map.land_count]
		var d := Vector2(t % sim.map.width, t / sim.map.width).distance_squared_to(mid)
		if d < best and sim.spawn.is_valid_start(t):
			best = d
			start = t
	ctl._left_click(start)
	ctl.confirm_spawn()
	while sim.phase == Sim.Phase.SPAWN:
		sim.step()
	sim.research.state[p] = {"done": ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"])), "current": "", "progress": {}}
	sim.mods.mark(p)
	for i in 1800:
		if i % 150 == 0:
			sim.submit(Commands.attack_target(p, 0, sim.st.o_troops[p] * 0.4))
		if i == 900 or i == 1400:
			for o in range(1, sim.st.owner_count + 1):
				if o != p and sim.st.o_alive[o] == 1 and sim.st.o_kind[o] == Rules.KIND_TRIBE and ctl.borders(p, o):
					sim.submit(Commands.attack_target(p, o, sim.st.o_troops[p] * 0.3))
					break
		sim.step()
	# Buildings through the normal rules (sites found by StructureSystem), spread over the land.
	var home: int = sim.st.o_spawn_tile[p]
	var tiles: Array[int] = []
	var t := sim.st.o_border_head[p]
	while t >= 0:
		tiles.append(t)
		t = sim.st.bnext[t]
	var c := sim.st.centroid(p)
	for k in [Rules.B_CITY, Rules.B_FACTORY, Rules.B_DEFENSE, Rules.B_RESEARCH, Rules.B_RADAR, Rules.B_ACADEMY, Rules.B_POWER, Rules.B_CITY, Rules.B_PORT, Rules.B_BUNKER]:
		sim.st.add_gold(p, 3000000.0)
		sim.st.add_supplies(p, 3000.0)
		var target := home
		if not tiles.is_empty():
			var bt: int = tiles[(built.size() * 37) % tiles.size()]
			var bp := Vector2(bt % sim.map.width, bt / sim.map.width)
			var q := c.lerp(bp, 0.55)
			target = sim.map.tile_at(int(q.x), int(q.y))
		var r := sim.structures.try_build(p, k, target)
		if r["ok"] and not built.has(k):
			built[k] = int(r["id"])
	for i in 140:
		sim.step()
	sim.st.set_troops(p, sim.st.o_cap[p] * 0.55)
	for o in range(1, sim.st.owner_count + 1):
		if o != p and sim.st.o_alive[o] == 1 and ctl.borders(p, o):
			neighbour = o
			if sim.st.o_kind[o] == Rules.KIND_NATION:
				break
	ctl.paused = true
	ctl.cam.focus(sim.st.centroid(p), ctl.cam.min_zoom * 4.0)
	await _wait(3)
	# The fast-forwarded ticks above are not part of what is shown: drop their transient effects.
	ctl.effects._marks.clear()
	ctl.effects.rings.clear()
	ctl.structures._pops.clear()


func _reset_view() -> void:
	ctl.close_build_mode()
	ctl.select_owner(0)
	ctl.select_structure(-1)
	ctl.hud.dock.open("")
	ctl.hud.tip_card.close()
	ctl.zones.show_all = false
	if ctl.menu_open:
		ctl.close_pause_menu()
	ctl.paused = true
	root.get_node("HintLayer").hide_hint()
	if ctl.hud.toasts.busy():
		ctl.hud.toasts._current.queue_free()
		ctl.hud.toasts._current = null
	ctl.cam.focus(sim.st.centroid(sim.player_id), ctl.cam.min_zoom * 4.0)


func _states(tag: String, settings: Node) -> void:
	_reset_view()
	await _shot(tag + "_01_normal")
	settings.show_tips = true
	settings.seen_tips = []
	ctl.hud.tip("expand")
	ctl.hud.refresh()
	await _shot(tag + "_02_tip")
	ctl.hud.tip_card.close()
	settings.show_tips = false
	ctl.hud.dock.open("economy")
	await _shot(tag + "_03_nav_open")
	_reset_view()
	if built.has(Rules.B_CITY):
		_focus_struct(built[Rules.B_CITY])
		ctl.select_structure(built[Rules.B_CITY])
		await _shot(tag + "_04_city_selected")
	if built.has(Rules.B_FACTORY):
		_focus_struct(built[Rules.B_FACTORY])
		ctl.select_structure(built[Rules.B_FACTORY])
		await _shot(tag + "_05_building_selected")
	_reset_view()
	ctl.open_build_mode()
	ctl.begin_build(Rules.B_DEFENSE)
	var near: int = sim.st.o_border_head[sim.player_id]
	ctl.hover_tile = near
	ctl._mouse_screen = ctl.cam.get_canvas_transform() * Vector2(near % sim.map.width + 0.5, near / sim.map.width + 0.5)
	await _wait(6)
	await _shot(tag + "_06_build_mode")
	_reset_view()
	if built.has(Rules.B_DEFENSE):
		_focus_struct(built[Rules.B_DEFENSE])
		ctl.select_structure(built[Rules.B_DEFENSE])
		await _shot(tag + "_07_zone_of_building")
	_reset_view()
	if neighbour > 0:
		ctl.select_owner(neighbour)
		await _shot(tag + "_08_attack_mode")
	_reset_view()
	ctl.hud.board._open = true
	ctl.hud.board._apply()
	await _shot(tag + "_09_ranking_open")
	ctl.hud.board._open = false
	ctl.hud.board._apply()
	ctl.open_pause_menu()
	await _shot(tag + "_10_pause")
	_reset_view()


func _focus_struct(sid: int) -> void:
	var s: StructureSystem.Structure = sim.structures.structs[sid]
	ctl.cam.focus(Vector2(s.tile % sim.map.width, s.tile / sim.map.width), ctl.cam.min_zoom * 5.0)
