extends SceneTree
## Main menu review (Phase 2A.3-B): shoots the menu at 1280×720, 1366×768, 1600×900 and 1920×1080,
## without and with a saved match, plus a hover state. Run with a scratch data dir so real saves
## and settings are untouched:
##   XDG_DATA_HOME=/tmp/menuhome xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/menu_shots_cli.gd -- <out_dir>

const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080)]

var out_dir := "/tmp/menu"
var main: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _wait(6)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _menu(size: Vector2i) -> Node:
	root.size = size
	var app := root.get_node("App")
	app.goto(app.State.CREDITS)
	await _wait(2)
	app.goto(app.State.MAIN_MENU)
	await _wait(2)
	# Wait for the warmed-up living world and let the camera settle.
	var tries := 0
	while (MenuBackground._sim == null or MenuBackground._sim.st.tick < MenuBackground.WARM_TICKS) and tries < 400:
		await _wait(5)
		tries += 1
	await _wait(90)
	return main._current


func _run() -> void:
	root.get_node("Settings").show_tips = false
	for f in SaveManager.list():
		SaveManager.delete(String(f["path"]))
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(3)
	for size: Vector2i in SIZES:
		await _menu(size)
		await _shot("menu_%dx%d_nosave" % [size.x, size.y])
	# A real saved match (short AI game on a test map) for the "continue" card.
	var m := TestMaps.rect(160, 100)
	var sim := TestMaps.sim(m, 3, true, 5)
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(40, 40)))
	sim._start_playing()
	for i in 1200:
		sim.step()
	SaveManager.save(sim, "menu_review")
	for size: Vector2i in SIZES:
		var scr: Node = await _menu(size)
		await _shot("menu_%dx%d_save" % [size.x, size.y])
		if size == Vector2i(1600, 900):
			var tiles: Control = scr.groups["collection"]
			var b: Control = tiles.get_child(1)
			b.mouse_entered.emit()
			b.grab_focus()
			await _wait(20)
			await _shot("menu_%dx%d_hover" % [size.x, size.y])
	for f in SaveManager.list():
		SaveManager.delete(String(f["path"]))
	quit()
