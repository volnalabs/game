extends TestCase
## Phase 2A.3-D (view side): ship silhouette and size by zoom; ships turn to their heading and move
## along the route; the landing preview shows exactly what the simulation does; the bottom bar has a
## landing mode and a selected-transport mode with recall; many ships stay cheap to draw.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func test_ship_silhouette_and_size() -> void:
	var h := ShipPainter.hull()
	check(h.size() >= 12, "hull is a smooth outline")
	var max_x := -INF
	var min_x := INF
	for p in h:
		max_x = maxf(max_x, p.x)
		min_x = minf(min_x, p.x)
	check(is_equal_approx(max_x, 0.5), "a single pointed bow at the front")
	var stern_pts := 0
	for p in h:
		if is_equal_approx(p.x, min_x):
			stern_pts += 1
	check(stern_pts >= 2, "a squared stern (flat back)")
	check(Geometry2D.triangulate_polygon(h).size() > 0, "hull is a valid polygon")
	var prev := 0.0
	for z: float in [0.3, 1.0, 3.0, 6.0, 12.0, 40.0]:
		var px := EffectsLayer.ship_px(z)
		check(px >= 18.0 and px <= 60.0, "ship %.0f px on screen at zoom %.1f" % [px, z])
		check(px >= prev, "ship grows with zoom")
		prev = px


func _match() -> Node:
	root = Engine.get_main_loop().root
	root.size = Vector2i(1600, 900)
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(200, 100, true)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(2, true, 12, 0)
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
	var e := 1 if sim.player_id != 1 else 2
	for y in 100:
		for x in 200:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, sim.player_id if x < 100 else e)
	sim.st.o_alive[e] = 1
	sim.st.o_spawned[e] = 1
	sim.st.o_troops[sim.player_id] = 300000.0
	sim.st.add_supplies(sim.player_id, 1000.0)
	ctl.set_meta("enemy", e)
	return ctl


func test_preview_send_select_recall() -> void:
	var ctl: Node = await _match()
	var sim: Sim = ctl.sim
	var hud: GameHUD = ctl.hud
	var pid := sim.player_id
	var goal := sim.map.tile_at(160, 50)
	# A click on enemy land without a common border prepares the landing (no boat yet).
	ctl._left_click(goal)
	await _wait(1)
	check(not ctl.naval_plan.is_empty() and ctl.naval_plan["ok"], "the click prepares a landing")
	check_eq(hud.mode(), "naval", "the bottom bar switches to the landing")
	check_eq(hud.command.mode, "naval", "landing bar shown")
	check(sim.naval.boats.is_empty(), "nothing sent before confirmation")
	var preview_beach: int = ctl.naval_plan["beach"]
	ctl.cam.focus(Vector2(100, 50), 3.0)
	await _wait(3)
	# Confirm: the simulation sends the transport to the very beach of the preview.
	ctl._left_click(goal)
	sim.step()
	await _wait(2)
	check(ctl.naval_plan.is_empty(), "preview closed after sending")
	check_eq(sim.naval.boats.size(), 1, "one transport at sea")
	var b: NavalSystem.Boat = sim.naval.boats[0]
	check_eq(b.target_tile, preview_beach, "the simulation uses the previewed beach")
	# The ship turns to its heading and moves along the route over the frames.
	var fx: EffectsLayer = ctl.effects
	var p0 := b.position()
	for i in 6:
		sim.step()
		await _wait(4)
	check(b.position().distance_to(p0) > 2.0, "the ship moves along its route")
	check(fx.ships.has(b.id), "the ship is drawn")
	if fx.ships.has(b.id):
		var rot: float = fx.ships[b.id]["rot"]
		check(absf(angle_difference(rot, b.heading().angle())) < 0.35, "the ship faces its course")
		# Clicking the ship selects it; the bar offers recall.
		var sp: Vector2 = ctl.cam.get_canvas_transform() * (fx.ships[b.id]["pos"] as Vector2)
		check_eq(fx.pick_boat(sp, pid), b.id, "the ship is picked under the cursor")
		ctl.select_boat(b.id)
		await _wait(1)
		check_eq(hud.command.mode, "boat", "selected transport bar")
		ctl.recall_boat()
		sim.step()
		await _wait(1)
		check(b.returning, "recall turns the transport round")
	# Esc-like cancel of a prepared landing.
	ctl.preview_naval(goal)
	ctl.cancel_naval()
	check(ctl.naval_plan.is_empty(), "a prepared landing can be cancelled")


func test_refusal_is_explained_in_the_preview() -> void:
	var ctl: Node = await _match()
	var sim: Sim = ctl.sim
	ctl.preview_naval(sim.map.tile_at(100, 50))
	await _wait(1)
	check(not ctl.naval_plan["ok"], "water cannot be a target")
	var reason := NavalOrders.blocker(sim, sim.player_id, ctl.naval_plan, 1000.0)
	check(reason != "", "the bar explains why it cannot be sent")


func test_many_ships_draw_cheaply() -> void:
	var ctl: Node = await _match()
	var sim: Sim = ctl.sim
	sim.rules.n["max_boats"] = 80
	var pid := sim.player_id
	sim.st.add_supplies(pid, 10000.0)
	for i in 60:
		sim.submit(Commands.boat(pid, sim.map.tile_at(150 + (i % 10) * 4, 5 + (i / 10) * 15), 1000.0))
	sim.step()
	ctl.cam.focus(Vector2(100, 50), 2.0)
	await _wait(2)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		await _wait(1)
	var per_frame := float(Time.get_ticks_usec() - t0) / 10.0
	print("      %d ships, %.1f ms per frame" % [sim.naval.boats.size(), per_frame / 1000.0])
	check(sim.naval.boats.size() >= 40, "many ships at sea")
	check(per_frame < 100000.0, "frames stay fast with many ships")
	sim.rules.n["max_boats"] = 3


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
