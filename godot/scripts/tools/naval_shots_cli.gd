extends SceneTree
## Ships and sea landings review (Phase 2A.3-D): the landing preview towards an inland target, the
## transport sailing (three zooms), a selected transport with its recall bar, the landing and the
## advance inland, and many transports at once.
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/naval_shots_cli.gd -- <out_dir> [WxH]

var out_dir := "/tmp/naval"
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


func _advance(ticks: int) -> void:
	for i in ticks:
		sim.step()
		ctl._handle_events()
		await _wait(2)


func _run() -> void:
	root.get_node("Settings").show_tips = false
	root.size = win
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(2)
	var app := root.get_node("App")
	# Two islands with a wide sea between them.
	var w := 260
	var h := 150
	var terr := PackedByteArray()
	terr.resize(w * h)
	var elev := PackedByteArray()
	elev.resize(w * h)
	for y in h:
		for x in w:
			var water := x < 3 or y < 3 or x >= w - 3 or y >= h - 3 or (x > 95 and x < 140) or (x > 140 and y > 120)
			terr[y * w + x] = Rules.T_DEEP if water else Rules.T_PLAINS
			elev[y * w + x] = 0 if water else 60
	var m := MapData.from_arrays("naval_review", w, h, terr, elev)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(3, true, 6, 0)
	app.start_new_match()
	await _wait(4)
	ctl = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(50, 75)))
	sim._start_playing()
	sim.ai.brains.clear()
	var pid := sim.player_id
	var others: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if o != pid:
			others.append(o)
	for y in h:
		for x in w:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, pid if x < 96 else (others[0] if y < 70 else others[1]))
	for o in range(1, sim.st.owner_count + 1):
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 80000.0
	sim.st.o_troops[pid] = 600000.0
	sim.st.add_supplies(pid, 5000.0)
	sim.st.add_gold(others[0], 1e7)
	sim.st.add_supplies(others[0], 1e5)
	sim.structures.try_build(others[0], Rules.B_CITY, m.tile_at(200, 40))
	for i in 30:
		sim.st.tick += 1
		sim.structures.tick()
	ctl.renderer.refresh_palette()
	await _wait(4)
	# 1. Preview of a landing towards the enemy city deep inland.
	ctl.cam.focus(Vector2(140, 60), 3.2)
	ctl.preview_naval(m.tile_at(200, 40))
	await _wait(20)
	await _shot("naval_preview")
	# An impossible target (water) for the refusal.
	ctl.preview_naval(m.tile_at(120, 40))
	await _wait(10)
	await _shot("naval_preview_refused")
	ctl.preview_naval(m.tile_at(200, 40))
	ctl.confirm_naval()
	if ctl.hud.toasts.busy():
		ctl.hud.toasts._current.queue_free()
		ctl.hud.toasts._current = null
	await _advance(14)
	await _shot("naval_sailing")
	var b: NavalSystem.Boat = null
	for bb in sim.naval.boats:
		if bb.owner == pid:
			b = bb
	if b != null:
		ctl.cam.focus(b.position(), 9.0)
		await _wait(10)
		await _shot("naval_ship_near")
		ctl.cam.focus(b.position(), ctl.cam.min_zoom * 1.05)
		await _wait(10)
		await _shot("naval_ship_far")
		ctl.cam.focus(b.position(), 4.0)
		ctl.select_boat(b.id)
		await _wait(10)
		await _shot("naval_selected")
		ctl.select_boat(-1)
	await _advance(110)
	ctl.cam.focus(Vector2(170, 50), 3.2)
	await _advance(60)
	await _shot("naval_landed_advance")
	# Many transports: the player and both rivals send landings at once.
	sim.rules.n["max_boats"] = 12
	for i in 6:
		sim.submit(Commands.boat(pid, m.tile_at(150 + i * 15, 20 + i * 15), 5000.0))
	for i in 5:
		sim.st.add_supplies(others[1], 100.0)
		sim.submit(Commands.boat(others[1], m.tile_at(40, 20 + i * 25), 5000.0))
	await _advance(12)
	ctl.cam.focus(Vector2(120, 75), 2.2)
	await _wait(10)
	await _shot("naval_many")
	quit()
