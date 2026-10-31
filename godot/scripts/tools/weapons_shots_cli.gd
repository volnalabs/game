extends SceneTree
## Weapons review (Phase 2E): the arsenal panel, aiming (valid, with SAM cover, near our border,
## impossible), missiles in flight with interceptors, impacts, a nuclear burst, fallout, MIRV
## warheads and an EMP.
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/weapons_shots_cli.gd -- <out_dir> [WxH]

var out_dir := "/tmp/weapons"
var win := Vector2i(1600, 900)
var ctl: Node
var sim: Sim


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


func _advance(ticks: int, frames_per_tick: int = 2) -> void:
	for i in ticks:
		sim.step()
		ctl._handle_events()
		await _wait(frames_per_tick)


func _put(owner: int, kind: int, x: int, y: int, level: int = 1) -> void:
	var ss := sim.structures
	var s := StructureSystem.Structure.new()
	s.id = ss.structs.size()
	s.kind = kind
	s.owner = owner
	s.tile = sim.map.tile_at(x, y)
	s.level = level
	s.active_levels = level
	ss.structs.append(s)
	sim.st.set_struct_at(s.tile, s.id)
	ss._grid_add(s)
	sim.st.add_blevel(owner, kind, level)
	sim.st.add_bowned(owner, kind, level)
	ss.invalidate_caches()


func _clear_toasts() -> void:
	if ctl.hud.toasts.busy():
		ctl.hud.toasts._current.queue_free()
		ctl.hud.toasts._current = null


func _run() -> void:
	root.get_node("Settings").show_tips = false
	root.size = win
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(2)
	var app := root.get_node("App")
	var m := TestMaps.rect(300, 160)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(3, true, 8, 0)
	app.start_new_match()
	await _wait(4)
	ctl = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(60, 80)))
	sim._start_playing()
	sim.ai.brains.clear()
	var pid := sim.player_id
	var others: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if o != pid:
			others.append(o)
	var e: int = others[0]
	var f: int = others[1]
	for y in 160:
		for x in 300:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, pid if x < 120 else (e if y < 95 else f))
	var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
	for o in range(1, sim.st.owner_count + 1):
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 400000.0
		sim.st.add_gold(o, 1e9)
		sim.st.add_supplies(o, 1e6)
		sim.research.state[o] = {"done": all, "current": "", "progress": {}}
		sim.mods.mark(o)
	_put(pid, Rules.B_SILO, 70, 60, 3)
	_put(pid, Rules.B_SILO, 90, 110, 3)
	_put(pid, Rules.B_AIRBASE, 100, 40, 2)
	_put(pid, Rules.B_DEFENSE, 112, 80)
	_put(pid, Rules.B_CITY, 50, 80, 2)
	_put(e, Rules.B_CITY, 200, 45, 2)
	_put(e, Rules.B_FACTORY, 230, 60, 1)
	_put(e, Rules.B_SAM, 190, 55, 2)
	_put(e, Rules.B_RADAR, 195, 62)
	_put(f, Rules.B_CITY, 210, 125, 2)
	_put(f, Rules.B_PORT, 160, 140, 1)
	ctl.renderer.refresh_palette()
	await _wait(6)
	ctl.cam.focus(Vector2(150, 80), 3.0)
	# 1. Arsenal panel.
	ctl.hud.dock.open("arsenal")
	await _wait(8)
	await _shot("weapons_arsenal")
	ctl.hud.dock.open("")
	# 2. Aiming a missile at a city under SAM cover.
	ctl.begin_weapon(sim.rules.weapon_index("missile"))
	ctl._update_aim(m.tile_at(200, 45))
	await _wait(8)
	await _shot("weapons_aim_missile")
	# 3. A tactical nuke too close to our own border (friendly warning).
	ctl.cancel_weapon()
	ctl.begin_weapon(sim.rules.weapon_index("tactical_nuke"))
	ctl._update_aim(m.tile_at(135, 80))
	await _wait(8)
	await _shot("weapons_aim_nuke_friendly")
	# 4. Artillery out of range.
	ctl.cancel_weapon()
	ctl.begin_weapon(sim.rules.weapon_index("artillery"))
	ctl._update_aim(m.tile_at(220, 120))
	await _wait(8)
	await _shot("weapons_aim_out_of_range")
	ctl.cancel_weapon()
	_clear_toasts()
	# 5. A salvo: missiles at the defended city (interceptors), an air strike and a cluster.
	for i in 3:
		sim.submit(Commands.launch(pid, "missile", m.tile_at(198 + i * 3, 45)))
	sim.submit(Commands.launch(pid, "air_strike", m.tile_at(170, 30)))
	sim.submit(Commands.launch(pid, "cluster", m.tile_at(215, 120)))
	await _advance(16)
	await _shot("weapons_in_flight")
	await _advance(20, 1)
	await _shot("weapons_interceptions")
	await _advance(25, 2)
	await _shot("weapons_impacts")
	# 6. A tactical nuke on the southern state: flash, then fallout.
	sim.submit(Commands.launch(pid, "tactical_nuke", m.tile_at(230, 125)))
	ctl.cam.focus(Vector2(200, 110), 3.2)
	var nuke_at := -1
	for i in 120:
		sim.step()
		for ev in sim.events.drain():
			ctl.weapons_fx.on_event(ev)
			if String(ev["type"]) == SimEvents.NUKE_DETONATED:
				nuke_at = i
		await _wait(1)
		if nuke_at >= 0:
			break
	await _wait(6)
	await _shot("weapons_nuke_flash")
	await _wait(150)
	await _shot("weapons_fallout")
	# 7. MIRV warheads and an EMP.
	sim.submit(Commands.launch(pid, "mirv", m.tile_at(230, 40)))
	sim.submit(Commands.launch(pid, "emp", m.tile_at(190, 55)))
	ctl.cam.focus(Vector2(200, 60), 2.6)
	for i in 160:
		sim.step()
		var split := false
		for ev in sim.events.drain():
			ctl.weapons_fx.on_event(ev)
			if String(ev["type"]) == SimEvents.MIRV_SPLIT:
				split = true
		await _wait(1)
		if split:
			break
	await _advance(4, 2)
	await _shot("weapons_mirv_warheads")
	await _advance(30, 1)
	await _shot("weapons_after_mirv")
	quit()
