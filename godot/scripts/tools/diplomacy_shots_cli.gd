extends SceneTree
## Diplomacy review (Phase 2F): the Relations tab with an offer and a help request, the inspector's
## diplomacy actions for a neutral state and for an ally, a shipment on the map, a team match.
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/diplomacy_shots_cli.gd -- <out_dir> [WxH]

var out_dir := "/tmp/diplomacy"
var win := Vector2i(1600, 900)
var main: Node
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


func _advance(ticks: int, frames_per_tick: int = 1) -> void:
	for i in ticks:
		sim.step()
		ctl._handle_events()
		await _wait(frames_per_tick)


func _clear_toasts() -> void:
	if ctl.hud.toasts.busy():
		ctl.hud.toasts._current.queue_free()
		ctl.hud.toasts._current = null


## Five nations in a 3 + 2 grid; the player in the west.
func _start(teams: int) -> Array[int]:
	var app := root.get_node("App")
	var m := TestMaps.rect(300, 160)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(4, true, 21, 0)
	app.config.teams = teams
	app.start_new_match()
	await _wait(4)
	ctl = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(50, 80)))
	sim._start_playing()
	sim.ai.brains.clear()
	var pid := sim.player_id
	var ids: Array[int] = [pid]
	for o in range(1, sim.st.owner_count + 1):
		if o != pid and sim.st.o_kind[o] == Rules.KIND_NATION:
			ids.append(o)
	for y in 160:
		for x in 300:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				var o := ids[0]
				if x >= 100:
					o = ids[1] if y < 80 else ids[2]
				if x >= 200:
					o = ids[3] if y < 80 else ids[4]
				sim.st.set_owner(t, o)
	for o in ids:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 300000.0
		sim.st.add_gold(o, 5e6)
	ctl.renderer.refresh_palette()
	await _wait(6)
	ctl.cam.focus(Vector2(150, 80), 3.4)
	return ids


func _run() -> void:
	root.get_node("Settings").show_tips = false
	root.size = win
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(2)
	var ids: Array[int] = await _start(0)
	var pid := ids[0]
	var dip := sim.diplomacy
	# An alliance with the south-west neighbour, a pact with the far north-east, a war with the north.
	dip._form(pid, ids[2], DiplomacySystem.ALLIANCE)
	dip._form(pid, ids[3], DiplomacySystem.NAP)
	sim.st.add_troops(ids[1], -20000.0)
	sim.attacks.start(ids[1], pid, 20000.0)
	await _advance(12)
	# Offers and a help request waiting for the player.
	dip.request(ids[4], pid, DiplomacySystem.ALLIANCE)
	dip.ask_help(ids[2], pid, ids[4])
	await _advance(2)
	_clear_toasts()
	ctl.hud.dock.open("diplomacy")
	await _wait(8)
	await _shot("diplomacy_relations_tab")
	ctl.hud.dock.open("")
	# Inspector of a neutral state (the one at war with us).
	ctl.select_owner(ids[1])
	ctl.hud.inspector.set_tab("diplomacy")
	await _wait(6)
	await _shot("diplomacy_inspector_war")
	# Inspector of an ally; a shipment of troops on its way.
	ctl.send_aid(ids[2], "troops")
	await _advance(6)
	ctl.select_owner(ids[2])
	ctl.hud.inspector.set_tab("diplomacy")
	await _wait(6)
	_clear_toasts()
	await _shot("diplomacy_inspector_ally_convoy")
	# Overview tab shows the relation; the leaderboard marks treaties.
	ctl.hud.inspector.set_tab("overview")
	ctl.select_owner(0)
	ctl.hud.board._open = true
	ctl.hud.board._apply()
	await _wait(4)
	ctl.hud.board.refresh()
	await _wait(4)
	await _shot("diplomacy_leaderboard_marks")
	# A team match: the top bar shows the team's progress.
	ids = await _start(2)
	_clear_toasts()
	var mate := 0
	for o: int in sim.diplomacy.team:
		if o != sim.player_id and sim.diplomacy.same_team(o, sim.player_id):
			mate = o
	ctl.select_owner(mate)
	ctl.hud.inspector.set_tab("diplomacy")
	await _wait(8)
	await _shot("diplomacy_team_match")
	quit()
