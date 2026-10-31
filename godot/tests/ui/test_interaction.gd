extends TestCase
## Phase 2B interaction: two-step spawn with analysis, build ghost + tooltip from the real
## preview, zone overlay toggle and legend, combat effects driven by simulation state.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _start() -> Node:
	root = Engine.get_main_loop().root
	root.size = Vector2i(1600, 900)
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(200, 120)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(4, true, 5, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	return ctl


func test_spawn_needs_confirmation() -> void:
	var ctl: Node = await _start()
	var sim: Sim = ctl.sim
	var p := sim.player_id
	check_eq(sim.phase, Sim.Phase.SPAWN, "spawn phase")
	var t := sim.map.tile_at(100, 60)
	if not sim.spawn.is_valid_start(t):
		for c in sim.map.land_tiles:
			if sim.spawn.is_valid_start(c):
				t = c
				break
	sim._commands.clear()
	ctl._left_click(t)
	check_eq(ctl.spawn_pending, t, "first click chooses")
	check(sim._commands.is_empty(), "no command before confirmation")
	var info: Dictionary = ctl.spawn_info_pending
	check_eq(String(info["reason"]), "", "valid start")
	var claim: PackedInt32Array = info["claim"]
	check(claim.size() > 0, "claimed land listed")
	# The preview lists exactly the tiles the spawn will take.
	var expect := PackedInt32Array()
	for d in sim.spawn.disk_tiles(t):
		if sim.map.land[d] == 1 and sim.st.owner[d] == 0:
			expect.append(d)
	check_eq(claim, expect, "claim preview == SpawnSystem disk")
	await _wait(2)
	check(ctl.hud.spawn_panel.visible, "spawn panel shown")
	ctl.cancel_spawn()
	check_eq(ctl.spawn_pending, -1, "cancel")
	ctl._left_click(t)
	ctl._left_click(t)
	check_eq(sim._commands.size(), 1, "second click confirms")
	check_eq(String(sim._commands[0]["type"]), Commands.SPAWN)
	# Refusals are explained.
	var water := -1
	for i in sim.map.size:
		if sim.map.land[i] == 0:
			water = i
			break
	if water >= 0:
		check_eq(String(SpawnAdvisor.new(sim).analyze(water)["reason"]), "not_land")
	sim.step()
	var own := -1
	for i in sim.map.size:
		if sim.st.owner[i] > 0 and sim.st.owner[i] != p:
			own = i
			break
	if own >= 0:
		check_eq(String(SpawnAdvisor.new(sim).analyze(own)["reason"]), "taken")


func test_build_ghost_and_tip_follow_the_preview() -> void:
	var ctl: Node = await _start()
	var sim: Sim = ctl.sim
	var p := sim.player_id
	var t := sim.map.tile_at(100, 60)
	sim.apply_command(Commands.spawn(p, t))
	sim._start_playing()
	for y in range(40, 80):
		for x in range(80, 120):
			sim.st.set_owner(sim.map.tile_at(x, y), p)
	sim.st.add_gold(p, 10000000.0)
	sim.st.add_supplies(p, 10000.0)
	ctl.begin_build(Rules.B_DEFENSE)
	ctl.hover_tile = t
	ctl._mouse_screen = Vector2(800, 450)
	await _wait(2)
	check(ctl.ghost.cursor == t, "ghost follows the cursor tile")
	check(bool(ctl.ghost.preview["ok"]), "valid site")
	check(ctl.hud.build_tip.visible, "tooltip shown")
	check(ctl.zones.visible_zones(), "zones of the kind being placed are shown")
	sim._commands.clear()
	ctl._left_click(t)
	check_eq(sim._commands.size(), 1, "valid click builds")
	sim.step()
	# Same spot again: too close now — refused locally with the reason, no command.
	ctl.begin_build(Rules.B_FACTORY)
	ctl.hover_tile = t
	await _wait(2)
	var pv: Dictionary = ctl.ghost.preview
	sim._commands.clear()
	if not pv["ok"]:
		ctl._left_click(t)
		check(sim._commands.is_empty(), "invalid click does not build")
	ctl.cancel_build()
	await _wait(2)
	check(not ctl.hud.build_tip.visible, "tooltip hidden after cancel")
	check(ctl.ghost.cursor < 0, "ghost cleared")


func test_zone_toggle_and_legend() -> void:
	var ctl: Node = await _start()
	var was: bool = ctl.zones.show_all
	ctl.toggle_zones()
	await _wait(1)
	ctl.hud.refresh()
	check_eq(ctl.zones.show_all, not was, "toggled")
	check_eq(ctl.hud.zone_legend.visible, not was, "legend follows the overlay")
	ctl.toggle_zones()
	check_eq(ctl.zones.show_all, was, "restored")


func test_effects_follow_attacks_and_events() -> void:
	var ctl: Node = await _start()
	var sim: Sim = ctl.sim
	var p := sim.player_id
	sim.apply_command(Commands.spawn(p, sim.map.tile_at(60, 60)))
	sim._start_playing()
	var bot: int = sim.ai.brains[0].id
	for y in range(30, 90):
		for x in range(20, 100):
			sim.st.set_owner(sim.map.tile_at(x, y), p)
		for x in range(100, 180):
			sim.st.set_owner(sim.map.tile_at(x, y), bot)
	sim.st.set_troops(p, 200000.0)
	sim.apply_command(Commands.attack_target(p, bot, 100000.0))
	for i in 10:
		sim.step()
		await _wait(1)
	var a: AttackSystem.Attack = sim.attacks.find(p, bot)
	check(a != null and a.alive, "attack running")
	if a != null:
		var f: Dictionary = ctl.effects._fronts.get(a.id, {})
		check(not f.is_empty(), "front tracked")
		if not f.is_empty():
			check((f["p"] as Vector2).x > 95.0, "front is on the attacked side (x=%.1f)" % (f["p"] as Vector2).x)
	ctl.effects.on_event({"type": SimEvents.STRUCT_DESTROYED, "tile": sim.map.tile_at(60, 60), "kind": 0, "owner": p, "id": 0})
	check(ctl.effects._marks.size() > 0, "destroyed building marked")


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
