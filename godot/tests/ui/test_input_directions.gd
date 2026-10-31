extends TestCase
## Regression for "attacks to the left do not work": real mouse events are pushed through the
## viewport into the running game (scenes/main/main.tscn) and must produce an attack on the state
## that was clicked — in every direction, at several zoom levels, after camera pans, next to every
## map edge and on several map sizes, with the state panel open or closed.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _start(w: int, h: int) -> Node:
	root = Engine.get_main_loop().root
	root.size = Vector2i(1600, 900)
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	app = root.get_node("App")
	var m := TestMaps.rect(w, h)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(4, true, 3, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	return ctl


func _layout(ctl: Node, center: Vector2i, size: int) -> Dictionary:
	var sim: Sim = ctl.sim
	var m := sim.map
	var p := sim.player_id
	if sim.phase == Sim.Phase.SPAWN:
		sim.apply_command(Commands.spawn(p, m.tile_at(center.x, center.y)))
		sim._start_playing()
	for t in m.land_tiles:
		sim.st.set_owner(t, 0)
	var bots: Array = []
	for b in sim.ai.brains:
		bots.append(b.id)
	var offs := {"W": Vector2i(-size, 0), "E": Vector2i(size, 0), "N": Vector2i(0, -size), "S": Vector2i(0, size)}
	var owners := {}
	var k := 0
	_fill(sim, p, Rect2i(center - Vector2i(size / 2, size / 2), Vector2i(size, size)))
	for d: String in offs:
		var r := Rect2i(center + offs[d] - Vector2i(size / 2, size / 2), Vector2i(size, size))
		if _fill(sim, bots[k], r):
			owners[d] = [bots[k], center + offs[d]]
		k += 1
	sim.st.set_troops(p, 100000.0)
	return owners


func _fill(sim: Sim, who: int, r: Rect2i) -> bool:
	var any := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var t := sim.map.tile_at(x, y)
			if t >= 0 and sim.map.land[t] == 1:
				sim.st.set_owner(t, who)
				any = true
	return any


func _click(ctl: Node, world: Vector2) -> Dictionary:
	var sim: Sim = ctl.sim
	var sp: Vector2 = ctl.cam.get_canvas_transform() * (world + Vector2(0.5, 0.5))
	sim._commands.clear()
	var mv := InputEventMouseMotion.new()
	mv.position = sp
	mv.global_position = sp
	root.push_input(mv)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = sp
	ev.global_position = sp
	root.push_input(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	root.push_input(up)
	await _wait(1)
	for c in sim._commands:
		if c["type"] == Commands.ATTACK:
			return c
	return {}


func _check_all(ctl: Node, owners: Dictionary, label: String) -> void:
	var sim: Sim = ctl.sim
	for d: String in owners:
		var target: int = owners[d][0]
		var at: Vector2i = owners[d][1]
		var c: Dictionary = await _click(ctl, Vector2(at))
		check(not c.is_empty(), "%s: click %s produced an attack" % [label, d])
		if not c.is_empty():
			check_eq(sim.st.owner[int(c["tile"])], target, "%s: %s attack aims at the clicked state" % [label, d])


func test_all_directions_zooms_and_panel() -> void:
	var ctl: Node = await _start(300, 200)
	var owners := _layout(ctl, Vector2i(150, 100), 30)
	check_eq(owners.size(), 4)
	for panel in [false, true]:
		for z in [0.8, 3.0, 9.0]:
			ctl.cam.focus(Vector2(150, 100), z)
			ctl.select_owner(ctl.sim.player_id if panel else 0)
			await _wait(2)
			await _check_all(ctl, owners, "panel=%s zoom=%.1f" % [panel, z])


func test_after_camera_pans() -> void:
	var ctl: Node = await _start(300, 200)
	var owners := _layout(ctl, Vector2i(150, 100), 30)
	for pan in [Vector2(-40, 0), Vector2(40, 0), Vector2(0, -30), Vector2(0, 30)]:
		ctl.cam.focus(Vector2(150, 100) + pan, 3.0)
		await _wait(2)
		await _check_all(ctl, owners, "pan %s" % str(pan))


func test_next_to_every_map_edge_and_sizes() -> void:
	for size in [Vector2i(120, 80), Vector2i(300, 200), Vector2i(800, 400)]:
		var ctl: Node = await _start(size.x, size.y)
		var b := 12
		for c in [Vector2i(3 + b + b / 2, size.y / 2), Vector2i(size.x - 4 - b - b / 2, size.y / 2),
				Vector2i(size.x / 2, 3 + b + b / 2), Vector2i(size.x / 2, size.y - 4 - b - b / 2)]:
			var owners := _layout(ctl, c, b)
			ctl.cam.focus(Vector2(c), 4.0)
			await _wait(2)
			await _check_all(ctl, owners, "map %dx%d centre %s" % [size.x, size.y, str(c)])


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
