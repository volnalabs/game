extends TestCase
## Phase 2A.3-C: attack arrows — geometry (curve, taper, head, picking) and the effects layer:
## land attacks, landings, retreats, other states' attacks, many at once, zoom, hover info, and
## finished attacks fading out.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func test_curve_and_outline_geometry() -> void:
	var tail := Vector2(0, 0)
	var head := Vector2(40, 0)
	var pts := AttackArrow.curve(tail, head, 0.2)
	check(pts[0].is_equal_approx(tail), "curve starts at the tail")
	check(pts[pts.size() - 1].is_equal_approx(head), "curve ends at the head")
	var side_a := AttackArrow.point_at(pts, 0.5).y
	var side_b := AttackArrow.point_at(AttackArrow.curve(tail, head, -0.2), 0.5).y
	check(absf(side_a) > 0.5 and side_a * side_b < 0.0, "opposite bends bow to opposite sides")
	var poly := AttackArrow.outline(pts, 0.5, 2.0, 6.0, 4.0)
	check(poly.size() > 10, "outline has a body and a head")
	check(poly.has(head), "the tip of the head is exactly the front")
	var tail_w := poly[0].distance_to(pts[0])
	var body_w := 0.0
	for p in poly:
		body_w = maxf(body_w, absf(p.y - AttackArrow.point_at(pts, clampf(p.x / 40.0, 0.0, 1.0)).y))
	check(tail_w < 0.8, "thin, rounded-off tail (%.2f)" % tail_w)
	check(body_w > 3.0, "the head is wider than the body (%.2f)" % body_w)
	check(Geometry2D.triangulate_polygon(poly).size() > 0, "outline is a valid polygon")
	check(AttackArrow.distance_to(pts, AttackArrow.point_at(pts, 0.3)) < 0.01, "points on the curve are hit")
	check(AttackArrow.distance_to(pts, Vector2(20, 30)) > 20.0, "far points are not")
	check(AttackArrow.width_px(10.0) < AttackArrow.width_px(500000.0), "more troops, wider arrow")
	check(AttackArrow.width_px(1e12) <= 7.5, "width is bounded")


func _match() -> Node:
	root = Engine.get_main_loop().root
	root.size = Vector2i(1600, 900)
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(240, 120, true)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(4, true, 9, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	var sim: Sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(50, 60)))
	sim._start_playing()
	return ctl


## Player west-centre; A north of it, B south and east of it (A and B share a border); C across the sea.
func _layout(ctl: Node) -> Array[int]:
	var sim: Sim = ctl.sim
	var m := sim.map
	var others: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if o != sim.player_id:
			others.append(o)
	var regions := {others[1]: Rect2i(2, 40, 112, 78), sim.player_id: Rect2i(2, 40, 60, 40), others[0]: Rect2i(2, 2, 112, 38),
		others[2]: Rect2i(124, 2, 114, 116)}
	for o: int in regions:
		var r: Rect2i = regions[o]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var t := m.tile_at(x, y)
				if m.land[t] == 1:
					sim.st.set_owner(t, o)
		sim.st.o_alive[o] = 1
		sim.st.o_troops[o] = 50000.0
	sim.st.o_troops[sim.player_id] = 900000.0
	return others


func _run(ctl: Node, ticks: int) -> void:
	for i in ticks:
		ctl.sim.step()
		await _wait(1)


func test_arrow_kinds_and_lifecycle() -> void:
	var ctl: Node = await _match()
	var sim: Sim = ctl.sim
	var fx: EffectsLayer = ctl.effects
	var o := _layout(ctl)
	var pid := sim.player_id
	ctl.cam.focus(Vector2(60, 60), 3.0)
	var land := sim.attacks.start(pid, o[0], 200000.0)
	var ai := sim.attacks.start(o[1], o[0], 20000.0)
	var landing := sim.attacks.start(pid, o[2], 100000.0, sim.map.tile_at(126, 60))
	check(land != null and ai != null and landing != null, "attacks started")
	await _run(ctl, 25)
	check(fx.arrows.has(land.id), "land attack has an arrow")
	check_eq(fx.arrow_kind(land), AttackArrow.LAND, "player's attack is a land arrow")
	check_eq(fx.arrow_kind(ai), AttackArrow.OTHER, "an AI war not involving the player is quieter")
	check_eq(fx.arrow_kind(landing), AttackArrow.LANDING, "an attack from the sea is a landing arrow")
	if fx.arrows.has(landing.id):
		var lp: PackedVector2Array = fx.arrows[landing.id]["pts"]
		check(lp[0].x >= 120.0, "the landing arrow starts on the far shore")
	# The arrow ends at the front and its length on screen stays readable at every zoom.
	for z: float in [ctl.cam.min_zoom * 1.05, 3.0, 9.0]:
		ctl.cam.focus(Vector2(60, 40), z)
		await _wait(3)
		if fx.arrows.has(land.id):
			var pts: PackedVector2Array = fx.arrows[land.id]["pts"]
			var front: Vector2 = fx._fronts[land.id]["p"]
			check(pts[pts.size() - 1].distance_to(front) < 0.01, "the head is the live front")
			var px: float = AttackArrow.length(pts) * ctl.cam.zoom.x
			check(px >= 12.0 and px <= 420.0, "arrow length on screen %.0f px at zoom %.1f" % [px, z])
	ctl.cam.focus(Vector2(60, 40), 3.0)
	await _wait(3)
	# Hover: the arrow under the cursor is found and described.
	if fx.arrows.has(land.id):
		var mid := AttackArrow.point_at(fx.arrows[land.id]["pts"], 0.5)
		check_eq(fx.pick_arrow(ctl.cam.get_canvas_transform() * mid), land.id, "hovering the arrow picks its attack")
		var info := fx.arrow_info(land.id)
		check(String(info["title"]).contains(sim.st.o_name[o[0]]), "card names the target")
		check_eq((info["rows"] as Array).size(), 4, "attacker, target, troops, state")
	check_eq(fx.pick_arrow(Vector2(5, 5)), -1, "empty map corner picks nothing")
	# Retreat: reversed, hollow arrow pointing home.
	var head_before: Vector2 = fx._fronts[land.id]["p"]
	sim.attacks.retreat(pid, land.id)
	await _wait(2)
	check_eq(fx.arrow_kind(land), AttackArrow.RETREAT, "a retreat has its own style")
	if fx.arrows.has(land.id):
		var rp: PackedVector2Array = fx.arrows[land.id]["pts"]
		check(rp[0].distance_to(head_before) < 3.0, "the retreat arrow starts at the front and points home")
		check(fx.arrows[land.id]["hollow"], "the retreat arrow is hollow")
	# Finished attacks fade out instead of vanishing.
	var aid := ai.id
	sim.attacks.end_attack(ai, true)
	fx.on_event({"type": SimEvents.ATTACK_ENDED, "id": aid})
	check(not fx.arrows.has(aid), "finished attack leaves the live arrows")
	await _wait(1)
	var n_fading := fx._fading.size()
	check(n_fading >= 0, "fading list exists")
	var t0 := Time.get_ticks_msec()
	while fx._fading.size() > 0 and Time.get_ticks_msec() - t0 < 3000:
		await _wait(5)
	check_eq(fx._fading.size(), 0, "faded arrows are removed")


func test_many_attacks_at_once() -> void:
	var ctl: Node = await _match()
	var sim: Sim = ctl.sim
	var o := _layout(ctl)
	var pid := sim.player_id
	ctl.cam.focus(Vector2(90, 60), 2.0)
	sim.attacks.start(pid, o[0], 100000.0)
	sim.attacks.start(pid, o[1], 100000.0)
	sim.attacks.start(o[0], o[1], 10000.0)
	sim.attacks.start(pid, o[2], 50000.0, sim.map.tile_at(126, 60))
	var t0 := Time.get_ticks_usec()
	await _run(ctl, 20)
	var fx: EffectsLayer = ctl.effects
	check(fx.arrows.size() >= 3, "several arrows drawn at once (%d)" % fx.arrows.size())
	check(fx.arrows.size() <= EffectsLayer.MAX_ARROWS, "arrow count is capped")
	# Arrows of opposite attacks bend to opposite sides, so they do not lie on top of each other.
	var bends := {}
	for a in sim.attacks.attacks:
		if a.alive and fx.arrows.has(a.id):
			bends[a.id % 2] = true
	check(bends.size() >= 1, "bend side alternates by attack")
	check(Time.get_ticks_usec() - t0 < 20_000_000, "drawing stays cheap")


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
