extends TestCase
## Phase 2F (interface): the Relations tab, offers with accept / decline, the inspector's diplomacy
## actions with reasons, shipments on the map, notifications, teams in the setup and the top bar.

var main: Node
var app: Node
var root: Window


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


## Player (west) and two nations (middle, east); AI off.
func _match(size: Vector2i, teams: int = 0) -> Node:
	root = Engine.get_main_loop().root
	root.size = size
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(240, 100)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(2, true, 17, 0)
	app.config.teams = teams
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
	var others: Array[int] = []
	for o in range(1, sim.st.owner_count + 1):
		if o != pid and sim.st.o_kind[o] == Rules.KIND_NATION:
			others.append(o)
	for y in 100:
		for x in 240:
			var t := m.tile_at(x, y)
			if m.land[t] == 1:
				sim.st.set_owner(t, pid if x < 80 else (others[0] if x < 160 else others[1]))
	for o: int in [pid, others[0], others[1]]:
		sim.st.o_alive[o] = 1
		sim.st.o_spawned[o] = 1
		sim.st.o_troops[o] = 200000.0
		sim.st.add_gold(o, 1e7)
	ctl.set_meta("b", others[0])
	ctl.set_meta("c", others[1])
	return ctl


func _buttons(c: Node, meta: String) -> Dictionary:
	var out := {}
	for b in c.find_children("*", "BaseButton", true, false):
		if b.has_meta(meta) and (b as Control).is_visible_in_tree():
			out[b.get_meta(meta)] = b
	return out


func _step(sim: Sim, ctl: Node, n: int = 1) -> void:
	for i in n:
		sim.step()
	ctl._handle_events()


func test_offer_appears_and_can_be_accepted() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var sim: Sim = ctl.sim
	var hud: GameHUD = ctl.hud
	var b: int = ctl.get_meta("b")
	check_eq(sim.diplomacy.request(b, sim.player_id, DiplomacySystem.ALLIANCE), "", "a nation offers an alliance")
	_step(sim, ctl)
	check(hud.log_lines.any(func(l: String) -> bool: return l.contains(sim.st.o_name[b])), "the offer is in the log")
	hud.dock.open("diplomacy")
	await _wait(3)
	var cards := hud.dock.panel.find_children("*", "PanelContainer", true, false).filter(func(c: Node) -> bool: return c.has_meta("diplo_request"))
	check_eq(cards.size(), 1, "the offer card is shown")
	var accept: Button = null
	for btn in (cards[0] as Node).find_children("*", "Button", true, false):
		if (btn as Button).text == tr("DIPLO_ACCEPT"):
			accept = btn
	check(accept != null, "with an Accept button")
	accept.pressed.emit()
	_step(sim, ctl)
	check(sim.diplomacy.allied(sim.player_id, b), "accepting forms the alliance")
	await _wait(3)
	var rows := _buttons(hud.dock.panel, "diplo_state")
	check(rows.has(b) and rows.has(int(ctl.get_meta("c"))), "every nation is listed")


func test_inspector_actions_explain_and_work() -> void:
	var ctl: Node = await _match(Vector2i(1280, 720))
	var sim: Sim = ctl.sim
	var hud: GameHUD = ctl.hud
	var pid := sim.player_id
	var b: int = ctl.get_meta("b")
	ctl.select_owner(b)
	hud.inspector.set_tab("diplomacy")
	await _wait(3)
	var acts := _buttons(hud.inspector, "diplo_action")
	check(acts.has("ask_alliance") and acts.has("ask_nap"), "propose alliance and pact")
	check(not acts.has("break"), "nothing to break yet")
	(acts["ask_alliance"] as Button).pressed.emit()
	_step(sim, ctl)
	check(not sim.diplomacy.pending(pid, b).is_empty(), "the offer is sent")
	hud.inspector.refresh(true)
	await _wait(2)
	acts = _buttons(hud.inspector, "diplo_action")
	var again: Button = acts["ask_alliance"]
	check(again.disabled and String(again.get_meta("reason", "")) != "", "asking again is disabled with a reason")
	# The nation accepts: ally actions appear.
	sim.diplomacy.reply(b, pid, true)
	_step(sim, ctl)
	hud.inspector.refresh(true)
	await _wait(2)
	acts = _buttons(hud.inspector, "diplo_action")
	for k in ["renew", "send_troops", "send_gold", "ask_help", "break"]:
		check(acts.has(k), "ally action %s shown" % k)
	for k: String in acts:
		var bt: Button = acts[k]
		check(not bt.disabled or String(bt.get_meta("reason", "")) != "", "%s: disabled actions say why" % k)
	check((acts["renew"] as Button).disabled, "renewal waits for the window")
	check((acts["ask_help"] as Button).disabled, "no help needed in peace")
	var troops := sim.st.o_troops[pid]
	(acts["send_troops"] as Button).pressed.emit()
	_step(sim, ctl)
	check_eq(sim.diplomacy.convoys.size(), 1, "a shipment leaves")
	check(sim.st.o_troops[pid] < troops, "the troops left the army")
	await _wait(2)
	check(ctl.convoys.visible and not sim.diplomacy.convoys.is_empty(), "the shipment is drawn on the map")
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	check(screen.encloses(hud.inspector.get_global_rect().grow(-1)), "the inspector fits 1280×720")
	# Breaking makes the player a traitor and shows in the log.
	hud.inspector.refresh(true)
	await _wait(2)
	acts = _buttons(hud.inspector, "diplo_action")
	(acts["break"] as Button).pressed.emit()
	_step(sim, ctl)
	check(not sim.diplomacy.allied(pid, b) and sim.diplomacy.is_traitor(pid), "broken: the player is a traitor")
	check(hud.log_lines.any(func(l: String) -> bool: return l.contains(sim.st.o_name[b])), "logged")


func test_attack_on_a_partner_is_refused_with_a_reason() -> void:
	var ctl: Node = await _match(Vector2i(1600, 900))
	var sim: Sim = ctl.sim
	var b: int = ctl.get_meta("b")
	sim.diplomacy._form(sim.player_id, b, DiplomacySystem.NAP)
	var reason := sim.apply_command(Commands.attack_target(sim.player_id, b, 1000.0))
	check_eq(reason, "pact", "the attack is refused")
	check(NavalOrders.reason_text(reason) != "REJECT_PACT" and NavalOrders.reason_text(reason) != "", "the refusal is explained")


func test_teams_in_setup_and_top_bar() -> void:
	root = Engine.get_main_loop().root
	app = root.get_node("App")
	var setup: Control = (load("res://scripts/ui/screens/match_setup.gd") as GDScript).new()
	root.add_child(setup)
	await _wait(2)
	var opt: OptionButton = setup.find_child("Teams", true, false)
	check(opt != null, "a Teams option in the new game settings")
	if opt != null:
		opt.select(1)
		opt.item_selected.emit(1)
		check_eq(int(setup.get("cfg").teams), 2, "two teams chosen")
	setup.queue_free()
	var ctl: Node = await _match(Vector2i(1600, 900), 2)
	var sim: Sim = ctl.sim
	var hud: GameHUD = ctl.hud
	hud.refresh()
	await _wait(2)
	check(hud.top._goal_l.text.begins_with(tr("HUD_GOAL_TEAM").get_slice("%", 0).strip_edges()), "the top bar shows the team's progress")
	var mate := 0
	for o: int in sim.diplomacy.team:
		if o != sim.player_id and sim.diplomacy.same_team(o, sim.player_id):
			mate = o
	check(mate > 0, "the player has a teammate")
	ctl.select_owner(mate)
	hud.inspector.set_tab("diplomacy")
	await _wait(2)
	check(not _buttons(hud.inspector, "diplo_action").has("break"), "a team cannot be left")


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	app.goto(app.State.MAIN_MENU)
