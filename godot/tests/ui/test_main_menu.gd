extends TestCase
## Phase 2A.3-B: the map-centred main menu — with and without a save, at four resolutions; every
## action reachable, labelled and inside the screen without overlaps; hover reacts; transitions work;
## the AGPL §7 notice stays visible.

const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080)]

var main: Node
var app: Node
var root: Window
var _save_path: String = ""


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _boot() -> void:
	root = Engine.get_main_loop().root
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)


func _menu(size: Vector2i) -> Node:
	root.size = size
	app.goto(app.State.CREDITS)
	await _wait(1)
	app.goto(app.State.MAIN_MENU)
	await _wait(4)
	return main._current


func _buttons(scr: Node) -> Array[Button]:
	var out: Array[Button] = []
	for n in scr.find_children("*", "Button", true, false):
		if (n as Button).is_visible_in_tree():
			out.append(n)
	return out


func _check_layout(scr: Node, size: Vector2i, tag: String) -> void:
	var bs := _buttons(scr)
	check(bs.size() >= 10, "%s: all actions present (%d)" % [tag, bs.size()])
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	for i in bs.size():
		var r := bs[i].get_global_rect()
		check(screen.encloses(r), "%s: %s inside the screen" % [tag, bs[i].text])
		check(bs[i].text.strip_edges() != "" or bs[i].has_meta("label") or bs[i].has_meta("hint"), "%s: button labelled" % tag)
		for j in range(i + 1, bs.size()):
			check(not r.intersects(bs[j].get_global_rect()), "%s: %s / %s do not overlap" % [tag, bs[i].text, bs[j].text])
	var notice := false
	for l in scr.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text.contains("OpenFront and Contributors"):
			notice = screen.encloses((l as Label).get_global_rect())
	check(notice, "%s: the AGPL §7 notice is visible" % tag)


func _primary(scr: Node) -> Array[Button]:
	var out: Array[Button] = []
	for b in _buttons(scr):
		if b.has_meta("menu_primary"):
			out.append(b)
	return out


func test_without_a_save() -> void:
	_boot()
	for f in SaveManager.list():
		# Never touch real saves: this test only runs when there are none.
		return
	for size: Vector2i in SIZES:
		var scr: Node = await _menu(size)
		_check_layout(scr, size, "no save %s" % str(size))
		var prim := _primary(scr)
		check_eq(prim.size(), 1, "only New match is primary without a save")
		if prim.size() == 1:
			check_eq(prim[0].text, tr("MENU_NEW_GAME_LONG"), "the primary action starts a new match")


func test_with_a_save() -> void:
	_boot()
	var m := TestMaps.rect(120, 80)
	var sim := TestMaps.sim(m, 2, true, 4)
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(30, 30)))
	sim._start_playing()
	for i in 50:
		sim.step()
	_save_path = SaveManager.save(sim, "menu_test")
	check(_save_path != "", "save written")
	for size: Vector2i in SIZES:
		var scr: Node = await _menu(size)
		_check_layout(scr, size, "save %s" % str(size))
		var texts := _primary(scr).map(func(b: Button) -> String: return b.text)
		check(texts.has(tr("MENU_CONTINUE")), "Continue offered when a save exists")
		check(texts.has(tr("MENU_NEW_GAME_LONG")), "New match still available")
	SaveManager.delete(_save_path)
	_save_path = ""


func test_hover_and_transitions() -> void:
	_boot()
	var settings := root.get_node("Settings")
	var anim: bool = settings.ui_animations
	settings.ui_animations = false
	var scr: Node = await _menu(Vector2i(1600, 900))
	var tiles: Control = scr.groups["collection"]
	check(tiles.get_child_count() >= 5, "collection tiles: progress, skills, cases, inventory, achievements")
	var t: Button = tiles.get_child(0)
	t.mouse_entered.emit()
	await _wait(1)
	check(t.scale.x > 1.0, "hover lifts the tile")
	t.mouse_exited.emit()
	await _wait(1)
	check(is_equal_approx(t.scale.x, 1.0), "the tile settles back")
	settings.ui_animations = anim
	# New match opens map selection; a collection tile opens its screen; back returns.
	var ng: Button = null
	for b in _primary(scr):
		if b.text == tr("MENU_NEW_GAME_LONG"):
			ng = b
	check(ng != null, "New match button")
	if ng != null:
		ng.pressed.emit()
		await _wait(2)
		check_eq(app.state, app.State.MAP_SELECT, "New match opens the map selection")
	scr = await _menu(Vector2i(1600, 900))
	(scr.groups["collection"].get_child(0) as Button).pressed.emit()
	await _wait(2)
	check_eq(app.state, app.State.PROGRESS, "the first tile opens progress")
	scr = await _menu(Vector2i(1600, 900))
	var nav: Control = scr.groups["nav"]
	(nav.get_child(0) as Button).pressed.emit()
	await _wait(2)
	check_eq(app.state, app.State.ENCYCLOPEDIA, "the first navigation entry opens the encyclopedia")


func test_living_map_runs() -> void:
	_boot()
	await _menu(Vector2i(1280, 720))
	check(MenuBackground._sim != null, "the menu world exists")
	var t0: int = MenuBackground._sim.st.tick
	await _wait(10)
	check(MenuBackground._sim.st.tick > t0, "the world is alive")


func test_cleanup() -> void:
	if _save_path != "":
		SaveManager.delete(_save_path)
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
