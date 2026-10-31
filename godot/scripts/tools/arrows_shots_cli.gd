extends SceneTree
## Attack arrows review (Phase 2A.3-C): the player's land attacks, AI attacks, a retreat, a landing
## and many simultaneous attacks at three zooms, plus a hovered arrow with its card.
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/arrows_shots_cli.gd -- <out_dir> [WxH]

var out_dir := "/tmp/arrows"
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


## Steps the simulation while letting the effects layer follow the fronts frame by frame.
func _advance(ticks: int) -> void:
	for i in ticks:
		sim.step()
		await _wait(1)


func _run() -> void:
	root.get_node("Settings").show_tips = false
	root.size = win
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(2)
	var app := root.get_node("App")
	var m := TestMaps.rect(420, 240, true)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(7, true, 4, 0)
	app.start_new_match()
	await _wait(4)
	ctl = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(100, 120)))
	sim._start_playing()
	# A clear political map: the player in the west-centre, neighbours around, two states across the sea.
	var owners: Array[int] = [sim.player_id]
	for o in range(1, sim.st.owner_count + 1):
		if o != sim.player_id and owners.size() < 8:
			owners.append(o)
	var regions := [Rect2i(60, 70, 90, 100), Rect2i(2, 2, 206, 68), Rect2i(2, 170, 206, 68), Rect2i(2, 70, 58, 100),
		Rect2i(150, 70, 57, 100), Rect2i(214, 2, 204, 118), Rect2i(214, 120, 204, 118)]
	for i in regions.size():
		var r: Rect2i = regions[i]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var t := m.tile_at(x, y)
				if m.land[t] == 1:
					sim.st.set_owner(t, owners[i])
		sim.st.o_alive[owners[i]] = 1
		sim.st.o_troops[owners[i]] = 900000.0 if i == 0 else 60000.0
	ctl.renderer.refresh_palette()
	await _wait(4)
	var pid := sim.player_id
	# The player's attacks north and east, an AI attack on the player, AI wars elsewhere.
	sim.attacks.start(pid, owners[1], 260000.0)
	sim.attacks.start(pid, owners[4], 120000.0)
	sim.attacks.start(owners[3], pid, 30000.0)
	sim.attacks.start(owners[2], owners[3], 20000.0)
	sim.attacks.start(owners[5], owners[6], 60000.0)
	sim.attacks.start(owners[6], owners[5], 8000.0)
	# A landing across the strait onto the eastern state.
	sim.attacks.start(pid, owners[5], 90000.0, m.tile_at(216, 100))
	await _advance(70)
	# One of the player's attacks falls back.
	var east := sim.attacks.find(pid, owners[4])
	if east != null:
		sim.attacks.retreat(pid, east.id)
	await _advance(10)
	ctl.cam.focus(Vector2(150, 110), 3.0)
	await _wait(30)
	await _shot("arrows_normal")
	ctl.cam.focus(Vector2(210, 120), ctl.cam.min_zoom * 1.05)
	await _wait(20)
	await _shot("arrows_far")
	ctl.cam.focus(Vector2(140, 90), 8.0)
	await _wait(20)
	await _shot("arrows_near")
	# Hover the player's northern attack.
	ctl.cam.focus(Vector2(150, 110), 3.0)
	await _wait(10)
	var mine := -1
	for aid: int in ctl.effects.arrows:
		var aa := sim.attacks.get_by_id(aid)
		if aa != null and (aa.attacker == pid or aa.target == pid):
			mine = aid
			break
	if mine >= 0:
		var pts: PackedVector2Array = ctl.effects.arrows[mine]["pts"]
		ctl._mouse_screen = ctl.cam.get_canvas_transform() * AttackArrow.point_at(pts, 0.5)
		ctl._update_structure_hover()
		await _wait(6)
		await _shot("arrows_hover")
	root.get_node("HintLayer").hide_hint()
	# Many attacks at once: every pair of neighbours fights.
	for i in owners.size():
		for j in owners.size():
			if i != j and ctl.borders(owners[i], owners[j]):
				sim.attacks.start(owners[i], owners[j], 15000.0)
	await _advance(60)
	ctl.cam.focus(Vector2(150, 120), 2.2)
	await _wait(20)
	await _shot("arrows_many")
	quit()
