extends TestCase
## Phase 2A.1 UX rules: one symbol per building used everywhere; nothing unexplained (every button
## has a label or a hint, disabled actions say why, resources have glossary entries); layout fits
## 1280×720 … 1920×1080; text contrast; tips; encyclopedia; building hover and selection.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _match(size: Vector2i) -> Node:
	root = Engine.get_main_loop().root
	root.size = size
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(200, 120)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(4, true, 6, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	var sim: Sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(60, 60)))
	sim._start_playing()
	for y in range(20, 100):
		for x in range(20, 110):
			sim.st.set_owner(m.tile_at(x, y), sim.player_id)
	await _wait(2)
	return ctl


func _explained(b: BaseButton) -> bool:
	if b is Button and (b as Button).text.strip_edges() != "":
		return true
	return b.has_meta("hint") or b.has_meta("label") or b.tooltip_text != ""


func test_every_building_has_one_symbol_in_all_lods() -> void:
	var r := Rules.for_k(1.0)
	for k in r.building_count():
		var sid := Symbols.building_id(r, k)
		check(Symbols.has(sid), "%s has a symbol" % sid)
		for lod: String in Symbols.LODS:
			check(Symbols.tex_px(sid, 24, lod) != null, "%s %s" % [sid, lod])
		# Icons (menus, hints, inspector) resolve to the very same symbol texture.
		check(Icons.tex(sid, 24) == Symbols.tex_px(sid, 24, "full"), "%s: Icons uses the symbol" % sid)
		check(BuildingInfo.short(r, k) != "B_%s_SHORT" % r.b_ids[k].to_upper(), "%s has a plain description" % sid)
		check(not BuildingInfo.effects(r, k).is_empty(), "%s has effect lines" % sid)
	for res in ["r_gold", "r_supplies", "r_army", "r_research", "r_land", "r_upkeep"]:
		check(Symbols.has(res), "%s symbol" % res)


func test_glossary_covers_every_hud_value() -> void:
	for term in ["gold", "income", "upkeep", "supplies", "army", "army_cap", "research", "territory", "attack_share", "victory",
			"rank", "speed", "radius", "build_time", "cost", "tech", "zones", "transport"]:
		check(Glossary.has(term), "glossary: %s" % term)
		var h := Glossary.hint(term)
		check(String(h.get("text", "")) != "", "%s explained" % term)


func test_every_hud_button_is_explained_and_disabled_ones_say_why() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var hud: GameHUD = ctl.hud
	for tab in ["state", "army", "economy", "research", "log"]:
		hud.dock.open(tab)
		await _wait(2)
		for b in hud.find_children("*", "BaseButton", true, false):
			if (b as BaseButton).is_visible_in_tree():
				check(_explained(b), "%s: button %s has a label or hint" % [tab, b.get_path()])
	hud.dock.open("")
	ctl.open_build_mode()
	var locked := 0
	for cat in BuildingInfo.CATEGORIES:
		hud.command.category = cat
		hud.command._tiles_key = ""
		hud.refresh()
		await _wait(2)
		for b in hud.command.find_children("*", "BaseButton", true, false):
			if (b as BaseButton).is_visible_in_tree():
				check(_explained(b), "build bar: button %s has a label or hint" % b.get_path())
		for k: int in hud.command._tile_buttons:
			var bb: Button = hud.command._tile_buttons[k]
			if bb.disabled:
				locked += 1
				check(String(bb.get_meta("reason", "")) != "", "disabled building explains why")
	check(locked > 0, "locked buildings are listed with a reason")
	ctl.close_build_mode()


func test_layout_fits_target_resolutions() -> void:
	for size in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		var ctl: Node = await _match(size)
		var hud: GameHUD = ctl.hud
		hud.dock.open("research")
		ctl.open_build_mode()
		await _wait(4)
		var rects := {"top": hud.top.get_global_rect(), "dock": hud.dock.get_global_rect(), "command": hud.command.get_global_rect(),
			"board": hud.board.get_global_rect()}
		for k: String in rects:
			var r: Rect2 = rects[k]
			check(r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= size.x + 0.5 and r.end.y <= size.y + 0.5,
				"%s inside %s (%s)" % [k, str(size), str(r)])
		check(not rects["top"].intersects(rects["dock"]), "top bar / dock at %s" % str(size))
		check(not rects["top"].intersects(rects["board"]), "top bar / ranking at %s" % str(size))
		check(not rects["command"].intersects(hud.dock.rail.get_global_rect()), "command bar / dock rail at %s" % str(size))
		check(not rects["command"].intersects(rects["board"]), "command bar / ranking at %s" % str(size))
		hud.dock.open("")


func _contrast(fg: Color, bg: Color) -> float:
	var lum := func(c: Color) -> float:
		var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
		return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)
	var a: float = lum.call(fg)
	var b: float = lum.call(bg)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


func test_text_contrast() -> void:
	# Surfaces are semi-transparent: measure on the surface blended over the darkest backdrop.
	for surf: Color in [UITheme.SURFACE, UITheme.SURFACE_2]:
		var bg := UITheme.BG.lerp(Color(surf, 1.0), surf.a)
		check(_contrast(UITheme.TEXT, bg) >= 7.0, "text contrast %.1f" % _contrast(UITheme.TEXT, bg))
		check(_contrast(UITheme.TEXT_DIM, bg) >= 4.5, "secondary text contrast %.1f" % _contrast(UITheme.TEXT_DIM, bg))
		check(_contrast(UITheme.TEXT_FAINT, bg) >= 3.0, "faint text contrast %.1f" % _contrast(UITheme.TEXT_FAINT, bg))


func test_tips_once_and_can_be_disabled() -> void:
	var s: Node = Engine.get_main_loop().root.get_node("Settings")
	var seen: Array = (s.seen_tips as Array).duplicate()
	var on: bool = s.show_tips
	Tips.reset()
	check(Tips.should_show("build"), "new player sees the tip")
	Tips.mark_seen("build")
	check(not Tips.should_show("build"), "only once")
	check(Tips.should_show("research"), "others still pending")
	Tips.disable_all()
	check(not Tips.should_show("research"), "tips can be switched off")
	s.seen_tips = seen
	s.save_settings()
	s.show_tips = on


func test_encyclopedia_builds_every_article() -> void:
	var r: Window = Engine.get_main_loop().root
	var scr: Control = (load("res://scripts/ui/screens/encyclopedia_screen.gd") as GDScript).new()
	r.add_child(scr)
	await _wait(1)
	var arts := Encyclopedia.articles()
	check(arts.size() > 40, "articles: %d" % arts.size())
	var cats := {}
	for a: Dictionary in arts:
		cats[a["category"]] = true
		scr.call("show_article", String(a["id"]))
		check(scr.get("_view").get_child_count() >= 2, "article %s has content" % a["id"])
	for c in ["interface", "economy", "buildings", "army", "research", "victory"]:
		check(cats.has(c), "category %s" % c)
	scr.free()


func test_building_hover_and_selection() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var sim: Sim = ctl.sim
	var p := sim.player_id
	sim.st.add_gold(p, 1000000.0)
	var r := sim.structures.try_build(p, Rules.B_CITY, sim.map.tile_at(60, 60))
	check(r["ok"], "built")
	for i in sim.rules.building_ticks(Rules.B_CITY) + 1:
		sim.st.tick += 1
		sim.structures.tick()
	var s: StructureSystem.Structure = sim.structures.structs[int(r["id"])]
	ctl.cam.focus(Vector2(s.tile % sim.map.width, s.tile / sim.map.width), ctl.cam.min_zoom * 6.0)
	await _wait(3)
	var sp: Vector2 = ctl.cam.get_canvas_transform() * Vector2(s.tile % sim.map.width + 0.5, s.tile / sim.map.width + 0.5)
	check_eq(ctl.structures.pick(sp), s.id, "the building is under its symbol")
	check_eq(ctl.structures.pick(sp + Vector2(200, 200)), -1, "nothing far away")
	ctl._mouse_screen = sp
	ctl._update_structure_hover()
	await _wait(1)
	check(Engine.get_main_loop().root.get_node("HintLayer").is_showing(), "hover shows the building hint")
	ctl.select_structure(s.id)
	await _wait(2)
	check(ctl.hud.inspector.visible and ctl.hud.inspector.structure_id == s.id, "selection opens the building page")
	ctl.select_structure(-1)
	check_eq(ctl.hud.inspector.structure_id, -1, "deselected")


func test_hud_shows_one_context_at_a_time() -> void:
	var ctl: Node = await _match(Vector2i(1280, 720))
	var hud: GameHUD = ctl.hud
	var sim: Sim = ctl.sim
	ctl.select_owner(0)
	await _wait(1)
	check_eq(hud.mode(), "normal", "nothing selected: normal mode")
	check_eq(hud.command.mode, "normal", "normal bottom bar")
	check(not hud.build_tip.visible, "no placement tip outside build mode")
	hud.dock.open("economy")
	ctl.open_build_mode()
	await _wait(1)
	check_eq(hud.command.mode, "build", "build bar replaces the normal bar")
	check(not hud.dock.panel.visible, "build mode closes the side panel")
	(hud.dock._buttons["economy"] as Button).pressed.emit()
	await _wait(1)
	check(hud.dock.panel.visible and ctl.build_open == false, "a side panel closes build mode")
	hud.dock.open("")
	var other := -1
	for o in range(1, sim.st.owner_count + 1):
		if o != sim.player_id and sim.st.o_alive[o] == 1:
			other = o
			break
	if other > 0:
		ctl.paused = true
		ctl.select_owner(other)
		await _wait(1)
		check_eq(hud.command.mode, "attack", "a foreign state switches to the attack bar even while paused")
		check(hud.board._rows.visible == false, "the ranking folds while the inspector is open")
		ctl.select_owner(0)
		await _wait(1)
		check_eq(hud.command.mode, "normal", "deselecting returns to the normal bar")


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	Engine.get_main_loop().root.get_node("HintLayer").hide_hint()
	app.goto(app.State.MAIN_MENU)
