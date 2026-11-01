extends TestCase
## The redesigned UI: every dock tab and inspector tab builds, panels close and hide, the HUD fits
## small and large windows without overlaps, the main menu lays its items out, and the map select
## grid adapts its column count to the window.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _boot(size: Vector2i) -> void:
	root = Engine.get_main_loop().root
	root.size = size
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)


func _match(size: Vector2i) -> Node:
	_boot(size)
	var m := TestMaps.rect(200, 120)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(4, true, 4, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	var sim: Sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(100, 60)))
	sim._start_playing()
	for i in 30:
		sim.step()
	return ctl


func _inside(c: Control, size: Vector2i, what: String) -> void:
	var r := c.get_global_rect()
	check(r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= size.x + 0.5 and r.end.y <= size.y + 0.5,
		"%s inside the %dx%d window (%s)" % [what, size.x, size.y, str(r)])


func test_dock_tabs_open_close_and_build() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var hud: GameHUD = ctl.hud
	for id in ["state", "army", "economy", "research", "log"]:
		hud.dock.open(id)
		await _wait(2)
		check(hud.dock.panel.visible, "%s panel visible" % id)
		check(hud.dock.panel.body.get_child_count() > 0, "%s panel has content" % id)
		_inside(hud.dock.panel, root.size, "%s panel" % id)
	hud.dock.open("")
	await _wait(1)
	check(not hud.dock.panel.visible, "dock closes")


func test_inspector_tabs_for_player_and_bot() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var hud: GameHUD = ctl.hud
	hud.ai_debug = true
	var bot: int = ctl.sim.ai.brains[0].id
	for who in [ctl.sim.player_id, bot]:
		ctl.select_owner(who)
		await _wait(1)
		check(hud.inspector.visible, "inspector opens for %d" % who)
		for t in ["overview", "economy", "army", "buildings", "threats", "ai"]:
			hud.inspector.set_tab(t)
			hud.inspector.refresh(true)
			await _wait(1)
			check(hud.inspector._body.get_child_count() > 0, "inspector tab %s has content for %d" % [t, who])
	ctl.select_owner(0)
	await _wait(1)
	check(not hud.inspector.visible, "inspector closes with no selection")


func test_hide_ui_and_restore() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var hud: GameHUD = ctl.hud
	hud.set_ui_hidden(true)
	for c: Control in [hud.top, hud.dock, hud.board, hud.command]:
		check(not c.visible, "%s hidden" % c.get_class())
	hud.set_ui_hidden(false)
	for c: Control in [hud.top, hud.dock, hud.board, hud.command]:
		check(c.visible, "%s restored" % c.get_class())


func test_hud_fits_small_and_large_windows() -> void:
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var ctl: Node = await _match(size)
		var hud: GameHUD = ctl.hud
		hud.dock.open("research")
		ctl.open_build_mode()
		await _wait(3)
		_inside(hud.top, size, "top bar")
		_inside(hud.command, size, "command bar")
		_inside(hud.board, size, "leaderboard")
		_inside(hud.dock, size, "dock")
		check(not hud.command.get_global_rect().intersects(hud.dock.rail.get_global_rect()), "command bar clear of the dock rail")
		check(not hud.top.get_global_rect().intersects(hud.dock.get_global_rect()), "top bar clear of the dock")
		hud.dock.open("")


func test_main_menu_items_are_laid_out() -> void:
	_boot(Vector2i(1280, 720))
	app.goto(app.State.MAIN_MENU)
	await _wait(30)
	var buttons: Array[Button] = []
	for n in main._current.find_children("*", "Button", true, false):
		if n.is_visible_in_tree():
			buttons.append(n)
	check(buttons.size() >= 5, "menu has its entries")
	for i in buttons.size():
		_inside(buttons[i], root.size, "menu entry %s" % buttons[i].text)
		for j in range(i + 1, buttons.size()):
			check(not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect()),
				"menu entries %s / %s do not overlap" % [buttons[i].text, buttons[j].text])


func test_map_select_adapts_columns() -> void:
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		_boot(size)
		app.goto(app.State.MAP_SELECT)
		await _wait(3)
		var scr: Node = main._current
		check(scr._grid.columns >= 2, "at least two columns")
		_inside(scr._scroll, size, "map grid")
		check(scr._grid.get_global_rect().size.x <= scr._scroll.get_global_rect().size.x + 1.0, "no horizontal overflow at %s" % str(size))
	check(true)


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
