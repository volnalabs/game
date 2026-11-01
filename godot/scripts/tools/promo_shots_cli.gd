extends SceneTree
## Promotional screenshots for the README and the release page: the main menu, a mid-game battle on
## the Europe map, diplomacy, a nuclear strike and a sea landing. The player's state is played by a
## hard AI during the warm-up so the map looks like a real match.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --path godot \
##     -s res://scripts/tools/promo_shots_cli.gd -- <out_dir>

var out_dir := "/tmp/promo"
var win := Vector2i(1920, 1080)
var main: Node
var ctl: Node
var sim: Sim


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


func _clear_toasts() -> void:
	if ctl.hud.toasts.busy():
		ctl.hud.toasts._current.queue_free()
		ctl.hud.toasts._current = null
	if ctl.hud.tip_card.visible:
		ctl.hud.tip_card.close()


func _steps(n: int, frames_every: int = 0) -> void:
	for i in n:
		sim.step()
		if frames_every > 0 and i % frames_every == 0:
			ctl._handle_events()
			await _wait(1)
	ctl._handle_events()
	ctl.renderer.apply_changes(sim.st.drain_changed_tiles())
	ctl.renderer.flush(1000.0)


func _put(owner: int, kind: int, t: int, level: int) -> void:
	var ss := sim.structures
	var s := StructureSystem.Structure.new()
	s.id = ss.structs.size()
	s.kind = kind
	s.owner = owner
	s.tile = t
	s.level = level
	s.active_levels = level
	ss.structs.append(s)
	sim.st.set_struct_at(t, s.id)
	ss._grid_add(s)
	sim.st.add_blevel(owner, kind, level)
	sim.st.add_bowned(owner, kind, level)
	ss.invalidate_caches()


func _run() -> void:
	var settings := root.get_node("Settings")
	settings.show_tips = false
	root.size = win
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(30)
	await _shot("menu")
	var app := root.get_node("App")
	var reg := root.get_node("MapRegistry")
	app.select_map(reg.get_map("europe"))
	app.config.bots = 30
	app.config.tribes = 0
	app.config.seed = 11
	app.config.player_nation = 1
	app.config.difficulty = "easy"
	app.start_new_match()
	await _wait(8)
	ctl = main._current
	while ctl.sim == null:
		await _wait(4)
	sim = ctl.sim
	ctl.paused = true
	var pid := sim.player_id
	# Spawn at the player's nation and let a hard AI play it during the warm-up.
	# The valid start nearest to the nation's own position on the map (Germany).
	var nd: Dictionary = sim.def.nations[app.config.player_nation]
	var want := Vector2(float(nd["x"]), float(nd["y"]))
	var sp := -1
	var best := INF
	for r in range(0, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t := sim.map.tile_at(int(want.x) + dx, int(want.y) + dy)
				if t >= 0 and sim.spawn.is_valid_start(t):
					var d := Vector2(t % sim.map.width, t / sim.map.width).distance_squared_to(want)
					if d < best:
						best = d
						sp = t
		if sp >= 0:
			break
	sim.apply_command(Commands.spawn(pid, sp))
	while sim.phase == Sim.Phase.SPAWN:
		sim.step()
	var helper := StrategicAI.new(pid, sim, sim.rng.fork(4242), "hard", "aggressive")
	sim.ai.brains.append(helper)
	sim.ai._by_id[pid] = helper
	# Warm-up; the player's state gets a reserve so it is a strong mid-game power in the shots.
	for k in 18:
		await _steps(100)
		if k % 3 == 0:
			sim.st.o_troops[pid] = maxf(sim.st.o_troops[pid], sim.st.o_cap[pid] * 0.6)
	print("player tiles ", sim.st.o_tiles[pid], " alive ", sim.st.o_alive[pid])
	sim.ai.brains.erase(helper)
	sim.ai._by_id.erase(pid)
	var cap_t := sim.st.o_spawn_tile[pid]
	var home := Vector2(cap_t % sim.map.width, cap_t / sim.map.width) if cap_t >= 0 and sim.st.owner[cap_t] == pid else sim.st.centroid(pid)
	# 1. A battle: the player attacks every neighbour.
	for o in range(1, sim.st.owner_count + 1):
		if o != pid and sim.st.o_alive[o] == 1 and ctl.borders(pid, o):
			sim.submit(Commands.attack_target(pid, o, sim.st.o_troops[pid] * 0.12))
	await _steps(25, 2)
	ctl.cam.focus(home, ctl.cam.min_zoom * 2.2)
	_clear_toasts()
	await _wait(20)
	await _shot("battle")
	# 2. Diplomacy: an ally, a pact, an offer waiting.
	var neigh: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if o != pid and sim.st.o_alive[o] == 1 and sim.st.o_kind[o] == Rules.KIND_NATION and ctl.borders(pid, o):
			neigh.append(o)
	if neigh.size() >= 3:
		sim.diplomacy._form(pid, neigh[0], DiplomacySystem.ALLIANCE)
		sim.diplomacy._form(pid, neigh[1], DiplomacySystem.NAP)
		sim.diplomacy.request(neigh[2], pid, DiplomacySystem.ALLIANCE)
		ctl.send_aid(neigh[0], "troops")
	await _steps(8, 1)
	_clear_toasts()
	ctl.hud.dock.open("diplomacy")
	await _wait(20)
	await _shot("diplomacy")
	ctl.hud.dock.open("")
	# 3. A nuclear strike on an enemy city.
	var all := ResearchSystem.techs().map(func(t: Dictionary) -> String: return String(t["id"]))
	sim.research.state[pid] = {"done": all, "current": "", "progress": {}}
	sim.mods.mark(pid)
	sim.st.add_gold(pid, 1e8)
	sim.st.add_supplies(pid, 1e6)
	var near_home := sim.map.tile_at(int(home.x), int(home.y))
	_put(pid, Rules.B_SILO, near_home, 3)
	var enemy := -1
	for o in neigh:
		if sim.diplomacy.can_attack(pid, o):
			enemy = o
	if enemy > 0:
		var tgt := LandingPlanner.key_tile(sim.naval, enemy)
		var w := sim.rules.weapon_index("tactical_nuke")
		print("nuke check ", sim.weapons.check(pid, w, tgt).get("reason", "ok"), " target owner ", sim.st.owner[tgt])
		sim.submit(Commands.launch(pid, "tactical_nuke", tgt))
		sim.step()
		ctl._handle_events()
		print("munitions in flight ", sim.weapons.munitions.size())
		ctl.cam.focus(Vector2(tgt % sim.map.width, tgt / sim.map.width), ctl.cam.min_zoom * 3.0)
		var flown := 0
		while flown < 400 and not sim.weapons.munitions.is_empty():
			sim.step()
			ctl._handle_events()
			flown += 1
			await _wait(1)
		ctl.renderer.apply_changes(sim.st.drain_changed_tiles())
		ctl.renderer.flush(1000.0)
		_clear_toasts()
		await _wait(8)
		await _shot("nuke")
		await _wait(150)
		await _shot("fallout")
		w = w
	# 4. A sea landing towards a state overseas.
	var overseas := -1
	for o in range(1, sim.st.owner_count + 1):
		if o != pid and sim.st.o_alive[o] == 1 and not ctl.borders(pid, o) and sim.diplomacy.can_attack(pid, o):
			var g := LandingPlanner.key_tile(sim.naval, o)
			if g >= 0 and LandingPlanner.plan(sim.naval, pid, g)["ok"]:
				overseas = o
				break
	if overseas > 0:
		var g2 := LandingPlanner.key_tile(sim.naval, overseas)
		sim.submit(Commands.boat(pid, g2, sim.st.o_troops[pid] * 0.2))
		await _steps(60, 2)
		var b: NavalSystem.Boat = null
		for bb in sim.naval.boats:
			if bb.alive and bb.owner == pid:
				b = bb
		if b != null:
			ctl.select_boat(b.id)
			ctl.cam.focus(b.position(), ctl.cam.min_zoom * 2.5)
		_clear_toasts()
		await _wait(20)
		await _shot("landing")
	quit()
