extends TestCase
## Phase 2E (interface): arsenal panel, aiming mode with a preview that matches the simulation,
## refusals explained, friendly-fire warning, launch and cancel, layout at 1280×720.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _put(sim: Sim, owner: int, kind: int, tile: int, level: int = 1) -> void:
	var ss := sim.structures
	var s := StructureSystem.Structure.new()
	s.id = ss.structs.size()
	s.kind = kind
	s.owner = owner
	s.tile = tile
	s.level = level
	s.active_levels = level
	ss.structs.append(s)
	sim.st.set_struct_at(tile, s.id)
	ss._grid_add(s)
	sim.st.add_blevel(owner, kind, level)
	sim.st.add_bowned(owner, kind, level)
	ss.invalidate_caches()


func _match(size: Vector2i, techs: bool) -> Node:
	root = Engine.get_main_loop().root
	root.size = size
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(200, 100)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(2, true, 13, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	var sim: Sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(40, 50)))
	sim._start_playing()
	sim.ai.brains.clear()
	var pid := sim.player_id
	var e := 1 if pid != 1 else 2
	for y in 100:
		for x in 200:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, pid if x < 100 else e)
	for o: int in [pid, e]:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 300000.0
		sim.st.add_gold(o, 1e9)
		sim.st.add_supplies(o, 1e6)
	if techs:
		var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
		sim.research.state[pid] = {"done": all, "current": "", "progress": {}}
		sim.mods.mark(pid)
		_put(sim, pid, Rules.B_SILO, m.tile_at(50, 50), 2)
	ctl.set_meta("enemy", e)
	return ctl


func test_arsenal_panel_explains_locked_weapons() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900), false)
	var hud: GameHUD = ctl.hud
	hud.dock.open("arsenal")
	await _wait(3)
	var aims: Array[Button] = []
	for b in hud.dock.panel.find_children("*", "Button", true, false):
		if (b as Button).has_meta("weapon"):
			aims.append(b)
	check_eq(aims.size(), ctl.sim.rules.w_list.size(), "a row per weapon")
	for b in aims:
		check(b.disabled and String(b.get_meta("reason", "")) != "", "%s is locked and says why" % b.get_meta("weapon"))
	ctl.begin_weapon(ctl.sim.rules.weapon_index("missile"))
	check_eq(ctl.weapon_aim, -1, "a locked weapon cannot be aimed")


func test_aiming_preview_matches_the_simulation_and_launches() -> void:
	var ctl: Node = await _match(Vector2i(1280, 720), true)
	var sim: Sim = ctl.sim
	var hud: GameHUD = ctl.hud
	var pid := sim.player_id
	var e: int = ctl.get_meta("enemy")
	var w := sim.rules.weapon_index("missile")
	ctl.begin_weapon(w)
	await _wait(1)
	check_eq(hud.mode(), "weapon", "aiming mode")
	check_eq(hud.command.mode, "weapon", "aiming bar")
	var target := sim.map.tile_at(150, 50)
	ctl._update_aim(target)
	await _wait(2)
	var pv: Dictionary = ctl.weapon_preview
	check(pv["check"]["ok"], "valid target")
	var est: Dictionary = sim.weapons.estimate(pid, w, target)
	check_eq(int((pv["est"]["tiles"] as Dictionary).get(e, 0)), int((est["tiles"] as Dictionary).get(e, 0)), "preview = simulation estimate")
	check(not hud.command._wp_fire.disabled, "launch enabled")
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	check(screen.encloses(hud.command.get_global_rect()), "the aiming bar fits 1280×720")
	# Own land: refused with a reason.
	ctl._update_aim(sim.map.tile_at(30, 50))
	await _wait(1)
	check(hud.command._wp_fire.disabled and String(hud.command._wp_fire.get_meta("reason", "")) != "", "own land refused with a reason")
	# Near our border a big blast warns about friendly land.
	ctl.cancel_weapon()
	ctl.begin_weapon(sim.rules.weapon_index("tactical_nuke"))
	ctl._update_aim(sim.map.tile_at(105, 50))
	await _wait(1)
	check(int(ctl.weapon_preview["est"]["own_tiles"]) > 0, "friendly tiles counted")
	var warned := false
	for l in hud.command._wp_est.get_children():
		if (l as Label).text.contains(tr("WPN_EST_FRIENDLY").get_slice("%", 0).strip_edges()):
			warned = true
	check(warned, "the bar warns about our own land")
	ctl.cancel_weapon()
	check_eq(hud.mode(), "normal", "cancel leaves aiming")
	# First click marks, second click launches.
	ctl.begin_weapon(w)
	ctl._aim_click(target)
	check_eq(ctl.weapon_target, target, "first click marks the target")
	check(sim.weapons.munitions.is_empty(), "nothing launched yet")
	ctl._aim_click(target)
	sim.step()
	check_eq(sim.weapons.munitions.size(), 1, "second click launches")
	check_eq(sim.weapons.munitions[0].to_tile, target, "at the marked tile")
	check_eq(ctl.weapon_aim, -1, "aiming ends after the launch")


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
