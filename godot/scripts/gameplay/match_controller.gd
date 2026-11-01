extends Node
## Runs one match: builds the Sim (new or from a save), the map view and the HUD; steps the
## simulation at a fixed 10 ticks per second (x speed) independently of the frame rate; turns
## mouse and keyboard input into commands; reports events; handles pause, saves and the end.

const TICK := 0.1
const MAX_STEPS_PER_FRAME := 4
const FRAME_SIM_BUDGET_USEC := 12000

var sim: Sim
var renderer: MapRenderer
var cam: MapCamera
var structures: StructureLayer
var zones: ZoneLayer
var ghost: GhostLayer
var effects: EffectsLayer
var labels: LabelLayer
var hud: GameHUD
var speed: float = 1.0
var paused: bool = false
var menu_open: bool = false
var ratio: float = 0.2
var build_kind: int = -1
## Build mode: the bottom bar shows the buildings; build_kind is the one being placed (-1 = none).
var build_open: bool = false
var selected_owner: int = 0
var hover_owner: int = 0
var hover_tile: int = -1
var watching: bool = false
var _acc: float = 0.0
var _press_pos: Vector2 = Vector2.ZERO
var _loading: Control
var _ended: bool = false
var _last_save: String = ""
var step_ms: float = 0.0
var _ghost_tile: int = -2
var _ghost_t: float = 0.0
var _mouse_screen: Vector2 = Vector2.ZERO
## Spawn selection: the chosen (not yet confirmed) start tile and the analyses shown for it and
## for the tile under the cursor.
var spawn_pending: int = -1
var spawn_info_pending: Dictionary = {}
var spawn_info_hover: Dictionary = {}
var _advisor: SpawnAdvisor
## Building under the cursor and the selected building (structure ids, -1 = none).
var hover_arrow: int = -1
var weapons_fx: WeaponLayer
var fallout: FalloutLayer
var convoys: ConvoyLayer
## Sea landing being prepared (LandingPlanner result + "tile"), {} = none.
var naval_plan: Dictionary = {}
## The player's transport selected on the map (boat id), -1 = none.
var selected_boat: int = -1
## Weapon being aimed (index in rules.w_list), -1 = none; locked target tile; live preview
## {"tile", "check", "est"} for the locked target or the tile under the cursor.
var weapon_aim: int = -1
var weapon_target: int = -1
var weapon_preview: Dictionary = {}
var hover_structure: int = -1
var selected_structure: int = -1
## Reward bookkeeping: paid once at the end (or as abandoned when leaving early).
var _paid: bool = false
var _min_share_late: float = 1.0


func _ready() -> void:
	_loading = _loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _create_sim():
		App.goto(App.State.MAIN_MENU)
		return
	_apply_cosmetics()
	_build_world()
	_loading.queue_free()
	Audio.start_ambience()
	speed = Settings.default_speed
	if sim.phase == Sim.Phase.SPAWN:
		App.goto(App.State.SPAWN_SELECT)
		_focus_player_nation()
		hud.tip("spawn")
	else:
		App.goto(App.State.PLAYING)


func _loading_screen() -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var l := UITheme.title(tr("LOADING"), 30)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	bg.add_child(l)
	return bg


func _create_sim() -> bool:
	if App.load_path != "":
		var data := SaveManager.read(App.load_path)
		if data.is_empty():
			return false
		var m := SaveManager.restore_match(data)
		if m.is_empty():
			return false
		App.config = m["config"]
		App.map_def = m["def"]
		App.map_data = m["map"] if (m["def"] as MapDefinition).is_generated() else null
		sim = Sim.new(m["config"], m["def"], m["map"])
		sim.from_dict(m["state"])
		_last_save = App.load_path
		App.load_path = ""
		return true
	var def := App.map_def
	if def == null:
		return false
	var map: MapData = App.map_data if App.map_data != null else MapLoader.load_map(def)
	if map == null:
		return false
	sim = Sim.new(App.config, def, map)
	return true


## Equipped cosmetics that touch the match view (display colour of the player's state).
func _apply_cosmetics() -> void:
	var c := Cosmetics.player_color()
	if c.a > 0.0 and sim.player_id > 0 and sim.st.tick == 0:
		sim.st.set_display_color(sim.player_id, c)


func _build_world() -> void:
	renderer = MapRenderer.new()
	renderer.map_style = Cosmetics.map_style()
	add_child(renderer)
	renderer.setup(sim)
	fallout = FalloutLayer.new()
	add_child(fallout)
	fallout.setup(sim)
	zones = ZoneLayer.new()
	add_child(zones)
	structures = StructureLayer.new()
	add_child(structures)
	ghost = GhostLayer.new()
	add_child(ghost)
	effects = EffectsLayer.new()
	add_child(effects)
	weapons_fx = WeaponLayer.new()
	add_child(weapons_fx)
	convoys = ConvoyLayer.new()
	add_child(convoys)
	# Beyond the map edge: deep ocean, not a black void.
	RenderingServer.set_default_clear_color(TerrainColors.styled(TerrainColors.BASE[0], renderer.map_style).darkened(0.25))
	cam = MapCamera.new()
	add_child(cam)
	cam.make_current()
	cam.edge_scroll = Settings.edge_scroll
	cam.setup(Vector2(sim.map.width, sim.map.height))
	structures.sim = sim
	structures.cam = cam
	structures.player_shape = Cosmetics.plate_shape()
	zones.sim = sim
	zones.cam = cam
	zones.show_all = Settings.show_zones
	ghost.sim = sim
	ghost.cam = cam
	effects.player_capture = Cosmetics.capture_effect()
	effects.sim = sim
	effects.cam = cam
	weapons_fx.sim = sim
	weapons_fx.cam = cam
	_apply_display()
	Settings.changed.connect(_apply_display)
	convoys.sim = sim
	convoys.cam = cam
	var ui := CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	labels = LabelLayer.new()
	labels.sim = sim
	labels.cam = cam
	labels.effects = effects
	labels.player_emblem = Cosmetics.emblem_icon()
	ui.add_child(labels)
	hud = GameHUD.new()
	ui.add_child(hud)
	hud.setup(self, sim)
	hud.log_line(tr("LOG_WELCOME") % sim.def.display_name(), UITheme.ACCENT)


## Display settings that can change during a match: effects quality, colour-vision mode, edge scroll.
func _apply_display() -> void:
	effects.quality = Settings.effects_quality
	weapons_fx.quality = Settings.effects_quality
	cam.edge_scroll = Settings.edge_scroll
	renderer.refresh_palette()


func _focus_player_nation() -> void:
	var n := sim.config.player_nation
	if n >= 0 and n < sim.def.nations.size():
		var nd: Dictionary = sim.def.nations[n]
		cam.focus(Vector2(float(nd["x"]), float(nd["y"])), cam.min_zoom * 4.0)


# ---------------------------------------------------------------------------------------------
# Loop
# ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	if not paused and not menu_open:
		_acc += minf(delta, 0.25) * speed
		var steps := 0
		var t0 := Time.get_ticks_usec()
		# Fixed 10 Hz steps; at high speed stop early when the frame's simulation budget is used
		# (the match then runs slightly slower than requested instead of dropping frames).
		while _acc >= TICK and steps < MAX_STEPS_PER_FRAME:
			sim.step()
			_acc -= TICK
			steps += 1
			if Time.get_ticks_usec() - t0 > FRAME_SIM_BUDGET_USEC:
				break
		if steps > 0:
			step_ms = float(Time.get_ticks_usec() - t0) / 1000.0 / steps
		if _acc > TICK * MAX_STEPS_PER_FRAME:
			_acc = 0.0
	renderer.apply_changes(sim.st.drain_changed_tiles())
	renderer.flush(4.0)
	renderer.set_highlight(selected_owner, hover_owner)
	_update_ghost(delta)
	_handle_events()
	_track_for_rewards()
	_situational_tips()
	_check_end()


## Messages about weapons: what flies at us, nuclear launches, interceptions, results of strikes.
func _weapon_news(e: Dictionary) -> void:
	var pid := sim.player_id
	if pid <= 0:
		return
	var st := sim.st
	match String(e["type"]):
		SimEvents.WEAPON_LAUNCHED:
			var w := sim.rules.weapon_index(String(e["weapon"]))
			var wname := WeaponInfo.title(sim.rules, w)
			if int(e["target_owner"]) == pid:
				hud.toast(tr("LOG_WPN_INCOMING") % [st.o_name[int(e["owner"])], wname], UITheme.BAD, "w_missile")
				hud.log_line(tr("LOG_WPN_INCOMING") % [st.o_name[int(e["owner"])], wname], UITheme.BAD)
			elif e.get("nuclear", false) and int(e["owner"]) != pid:
				hud.log_line(tr("LOG_WPN_NUKE_LAUNCH") % st.o_name[int(e["owner"])], UITheme.WARN)
		SimEvents.INTERCEPTED:
			var wname := WeaponInfo.title(sim.rules, sim.rules.weapon_index(String(e["weapon"])))
			if int(e["by"]) == pid:
				hud.log_line(tr("LOG_WPN_INTERCEPTED_BY_US") % wname, UITheme.GOOD)
			elif int(e["owner"]) == pid:
				hud.log_line(tr("LOG_WPN_OURS_INTERCEPTED") % wname, UITheme.WARN)
		SimEvents.WEAPON_IMPACT:
			var killed: Dictionary = e["killed"]
			var wname := WeaponInfo.title(sim.rules, sim.rules.weapon_index(String(e["weapon"])))
			if int(e["owner"]) == pid:
				var total := 0.0
				for o: int in killed:
					if o != pid:
						total += float(killed[o])
				hud.log_line(tr("LOG_WPN_HIT") % [wname, UITheme.num(total), int(e["structures"])], UITheme.ACCENT)
			elif killed.has(pid):
				hud.log_line(tr("LOG_WPN_HIT_US") % [wname, UITheme.num(float(killed[pid]))], UITheme.BAD)
		SimEvents.NUKE_DETONATED:
			var lost: Dictionary = e["lost"]
			for o: int in lost:
				if o == pid or int(e["owner"]) == pid:
					hud.log_line(tr("LOG_WPN_NUKE_HIT") % [st.o_name[o], UITheme.num(float(lost[o]))], UITheme.BAD if o == pid else UITheme.ACCENT)
		SimEvents.STRUCT_DISABLED:
			if int(e["owner"]) == pid:
				hud.log_line(tr("LOG_WPN_DISABLED") % tr("B_" + sim.rules.b_ids[int(e["kind"])].to_upper()), UITheme.WARN)


func _handle_events() -> void:
	var pid := sim.player_id
	var st := sim.st
	effects.focus_owner = selected_owner
	for e in sim.events.drain():
		effects.on_event(e)
		weapons_fx.on_event(e)
		_weapon_news(e)
		_diplo_news(e)
		Audio.on_event(e, pid)
		match String(e["type"]):
			SimEvents.ATTACK_STARTED:
				if int(e["target"]) == pid and int(e["attacker"]) > 0 and st.o_kind[int(e["attacker"])] != Rules.KIND_TRIBE:
					hud.tip("incoming")
				if int(e["target"]) == pid:
					hud.log_line(tr("LOG_ATTACKED") % [st.o_name[int(e["attacker"])], UITheme.num(float(e["troops"]))], UITheme.BAD)
			SimEvents.ELIMINATED:
				var who := int(e["owner"])
				var by := int(e["by"])
				var c := UITheme.BAD if who == pid else UITheme.TEXT_DIM
				hud.log_line(tr("LOG_ELIMINATED") % [st.o_name[who], st.o_name[by] if by > 0 else "?"], c)
				if st.o_spawn_tile[who] >= 0:
					effects.ring(st.o_spawn_tile[who], st.o_color[by] if by > 0 else Color.WHITE, 30.0)
			SimEvents.ANNEXED:
				if int(e["by"]) == pid:
					hud.log_line(tr("LOG_ANNEXED") % st.o_name[int(e["victim"])], UITheme.GOOD)
			SimEvents.BOAT_LAUNCHED:
				if int(e["target_owner"]) == pid:
					hud.log_line(tr("LOG_BOAT_INCOMING") % [st.o_name[int(e["owner"])], UITheme.num(float(e["troops"]))], UITheme.WARN)
			SimEvents.BOAT_LANDED:
				if int(e["owner"]) == pid or int(e["target_owner"]) == pid:
					effects.ring(int(e["tile"]), st.o_color[int(e["owner"])], 10.0)
					if int(e["owner"]) == pid:
						hud.log_line(tr("LOG_LANDED"), UITheme.GOOD)
			SimEvents.BUILD_DONE:
				structures.pop(int(e["id"]))
				if int(e["owner"]) == pid:
					hud.log_line(tr("LOG_BUILT") % tr("B_" + sim.rules.b_ids[int(e["kind"])].to_upper()), UITheme.GOOD)
					effects.ring(int(e["tile"]), UITheme.GOOD, 6.0)
			SimEvents.STRUCT_CAPTURED:
				if int(e["from"]) == pid or int(e["to"]) == pid:
					var lost := int(e["from"]) == pid
					hud.log_line((tr("LOG_STRUCT_LOST") if lost else tr("LOG_STRUCT_TAKEN")) % tr("B_" + sim.rules.b_ids[int(e["kind"])].to_upper()),
						UITheme.BAD if lost else UITheme.GOOD)
					effects.ring(int(e["tile"]), UITheme.BAD if lost else UITheme.GOOD, 8.0)
			SimEvents.COMMAND_REJECTED:
				if int(e["owner"]) == pid:
					hud.toast(NavalOrders.reason_text(String(e["reason"])))
			SimEvents.BOAT_RETURNED:
				if int(e["owner"]) == pid:
					hud.log_line(tr("LOG_BOAT_RETURNED"), UITheme.TEXT_DIM)
			SimEvents.BOAT_REROUTED:
				if int(e["owner"]) == pid:
					hud.log_line(tr("LOG_BOAT_REROUTED"), UITheme.WARN)
			SimEvents.BOAT_FAILED:
				if int(e["owner"]) == pid and e.has("troops"):
					hud.log_line(tr("LOG_BOAT_NO_LANDING"), UITheme.WARN)
			SimEvents.RESEARCH_DONE:
				if int(e["owner"]) == pid:
					var tname := MetaData.text(ResearchSystem.tech(String(e["tech"])).get("name", {}))
					hud.toast(tr("RESEARCH_DONE_TOAST") % tname, UITheme.RESEARCH, "r_research")
					hud.log_line(tr("RESEARCH_DONE_TOAST") % tname, UITheme.RESEARCH)
					hud.dock.mark_dirty()
			SimEvents.SPAWNED:
				if int(e["owner"]) == pid:
					effects.ring(int(e["tile"]), UITheme.ACCENT, 14.0)
			SimEvents.PHASE:
				if e.get("phase", "") == "playing" and sim.player_id > 0:
					if hud.tip_card.current == "spawn":
						hud.tip_card.close()
					hud.tip("resources")
					hud.tip("expand")
					App.goto(App.State.PLAYING)
					hud.log_line(tr("LOG_START"), UITheme.ACCENT)


## Situational tips (research idle, money trouble, first landing).
func _situational_tips() -> void:
	var pid := sim.player_id
	if pid <= 0 or sim.phase != Sim.Phase.PLAYING or not sim.is_player_alive() or sim.st.tick % 20 != 0:
		return
	if sim.elapsed_seconds() > 40.0 and sim.research.current(pid) == "":
		hud.tip("research")
	if sim.st.o_income[pid] < sim.st.o_upkeep[pid] and sim.st.o_gold[pid] < 20000.0:
		hud.tip("low_gold")


func _track_for_rewards() -> void:
	if sim.phase == Sim.Phase.PLAYING and sim.is_player_alive() and sim.elapsed_seconds() > 600.0 and sim.st.tick % 10 == 0:
		_min_share_late = minf(_min_share_late, sim.st.land_share(sim.player_id))


## Pays the match to the profile once (RewardManager is idempotent per match_id as well).
func _pay(abandoned: bool) -> Dictionary:
	if _paid or sim == null or sim.player_id <= 0 or sim.config.match_id == "":
		return {}
	if sim.st.o_spawned[sim.player_id] == 0:
		return {}
	_paid = true
	var prof := get_node_or_null("/root/Profile")
	if prof == null:
		return {}
	return prof.pay_match(MatchResult.from_sim(sim, abandoned, {"min_share_late": _min_share_late}))


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(UITheme.BG)
	Audio.stop_ambience()
	# Leaving a running match (menu, new game, load, restart) counts as abandoned.
	if not _paid and sim != null and sim.phase == Sim.Phase.PLAYING:
		_pay(true)


func show_results() -> void:
	App.goto(App.State.RESULTS)


func _check_end() -> void:
	if _ended:
		return
	if sim.phase == Sim.Phase.OVER:
		_ended = true
		_pay(false)
		var won := sim.won(sim.player_id)
		App.goto(App.State.VICTORY if won else App.State.DEFEAT)
		hud.show_end(won, String(sim.result.get("reason", "domination")) if won else ("player_lost" if not sim.is_player_alive() else String(sim.result.get("reason", "domination"))))
	elif sim.phase == Sim.Phase.PLAYING and sim.player_id > 0 and not sim.is_player_alive() and not watching:
		_ended = true
		_pay(false)
		App.goto(App.State.DEFEAT)
		hud.show_end(false, "player_lost")


# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------

## Map tile under a screen position (the event's own position, in viewport coordinates).
func tile_at_screen(screen_pos: Vector2) -> int:
	var p := cam.get_canvas_transform().affine_inverse() * screen_pos
	return sim.map.tile_at(int(floor(p.x)), int(floor(p.y)))


func _tile_at_mouse() -> int:
	return tile_at_screen(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseMotion:
		_mouse_screen = (event as InputEventMouseMotion).position
		hover_tile = tile_at_screen(_mouse_screen)
		if weapon_aim >= 0 and weapon_target < 0:
			_update_aim(hover_tile)
		_update_structure_hover()
		hover_owner = sim.st.owner[hover_tile] if hover_tile >= 0 else 0
		_update_spawn_hover()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# A click on a building (outside build mode) selects the building.
			var sid := structures.pick(mb.position) if build_kind < 0 and sim.phase == Sim.Phase.PLAYING else -1
			var bid := effects.pick_boat(mb.position, sim.player_id) if sid < 0 and build_kind < 0 and naval_plan.is_empty() else -1
			if sid >= 0:
				select_structure(sid)
			elif bid >= 0:
				select_boat(bid)
			else:
				_left_click(tile_at_screen(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_press_pos = mb.position
			elif mb.position.distance_to(_press_pos) < 5.0:
				if build_kind >= 0:
					cancel_build()
				elif build_open:
					close_build_mode()
				elif weapon_aim >= 0:
					cancel_weapon()
				elif not naval_plan.is_empty():
					cancel_naval()
				elif selected_boat >= 0:
					select_boat(-1)
				else:
					var t := tile_at_screen(mb.position)
					select_owner(sim.st.owner[t] if t >= 0 else 0)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Esc is fixed (cancel / menu); everything else goes through the rebindable actions (Keys).
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_escape()
			return
		var act := func(id: String) -> bool: return event.is_action_pressed(Keys.action(id))
		if act.call("confirm"):
			if spawn_pending >= 0:
				confirm_spawn()
			elif weapon_aim >= 0:
				fire_weapon()
			elif not naval_plan.is_empty():
				confirm_naval()
		elif act.call("pause"):
			set_speed(0.0 if not paused else maxf(speed, 1.0))
		elif act.call("toggle_ui"):
			hud.set_ui_hidden(not hud.ui_hidden)
		elif act.call("ratio_down"):
			_step_ratio(-1)
		elif act.call("ratio_up"):
			_step_ratio(1)
		elif act.call("ai_debug"):
			hud.toggle_ai_debug()
		elif act.call("save"):
			save_game()
		elif act.call("speed_up"):
			set_speed(minf(speed * 2.0, 4.0))
		elif act.call("speed_down"):
			set_speed(maxf(speed * 0.5, 0.5))
		elif act.call("home"):
			focus_home()
		elif act.call("encyclopedia"):
			open_encyclopedia()
		elif act.call("zones"):
			toggle_zones()
		elif act.call("build"):
			if build_open:
				close_build_mode()
			else:
				open_build_mode()
		else:
			for n in 6:
				if act.call("quick_%d" % (n + 1)):
					var kinds := hud.quick_kinds()
					if n < kinds.size():
						begin_build(kinds[n])
					break


func _escape() -> void:
	if spawn_pending >= 0:
		cancel_spawn()
	elif weapon_aim >= 0:
		cancel_weapon()
	elif not naval_plan.is_empty():
		cancel_naval()
	elif selected_boat >= 0:
		select_boat(-1)
	elif selected_structure >= 0:
		select_structure(-1)
	elif hud.ui_hidden:
		hud.set_ui_hidden(false)
	elif build_kind >= 0:
		cancel_build()
	elif build_open:
		close_build_mode()
	elif selected_owner > 0:
		select_owner(0)
	elif menu_open:
		close_pause_menu()
	else:
		open_pause_menu()


func _left_click(t: int) -> void:
	if t < 0 or menu_open:
		return
	var st := sim.st
	var pid := sim.player_id
	if pid <= 0:
		return
	if sim.phase == Sim.Phase.SPAWN:
		if st.o_spawned[pid] == 1:
			return
		# Two steps: the first click chooses, a second click on the same place (or Confirm) starts.
		if spawn_pending >= 0 and sim.map.dist2(spawn_pending, t) <= 4:
			confirm_spawn()
			return
		var info := _spawn_advisor().analyze(t)
		if String(info["reason"]) != "":
			hud.toast(tr("SPAWN_BAD_" + String(info["reason"]).to_upper()), UITheme.BAD, "ui_warning")
			return
		spawn_pending = t
		spawn_info_pending = info
		effects.spawn_pending = info
		hud.refresh()
		return
	if not sim.is_player_alive() or sim.phase != Sim.Phase.PLAYING:
		select_owner(st.owner[t])
		return
	if build_kind >= 0:
		var pv := sim.structures.preview(pid, build_kind, t)
		if not pv["ok"]:
			hud.toast(BuildTip.reason_text(pv, sim.rules), UITheme.BAD, "ui_warning")
			return
		sim.submit(Commands.build(pid, build_kind, t))
		_ghost_tile = -2
		if not Input.is_key_pressed(KEY_SHIFT):
			cancel_build()
		return
	if sim.map.land[t] == 0:
		return
	var o := st.owner[t]
	if o == pid:
		select_owner(pid)
		return
	if weapon_aim >= 0:
		_aim_click(t)
		return
	# A second click on the prepared landing's goal confirms it.
	if not naval_plan.is_empty() and sim.map.dist2(t, int(naval_plan["tile"])) <= 9:
		confirm_naval()
		return
	if borders(pid, o):
		cancel_naval()
		sim.submit(Commands.attack_tile(pid, t, ratio))
	else:
		# Not reachable over land: prepare a sea landing towards exactly this tile.
		preview_naval(t)


func borders(a: int, b: int) -> bool:
	var st := sim.st
	var owner := st.owner
	var land := sim.map.land
	var W := st.W
	var t := st.o_border_head[a]
	while t >= 0:
		var x := t % W
		if (x > 0 and owner[t - 1] == b and land[t - 1] == 1) or (x < W - 1 and owner[t + 1] == b and land[t + 1] == 1) \
				or (t >= W and owner[t - W] == b and land[t - W] == 1) or (t + W < st.N and owner[t + W] == b and land[t + W] == 1):
			return true
		t = st.bnext[t]
	return false


func _step_ratio(d: int) -> void:
	var i := GameHUD.RATIOS.find(ratio)
	set_ratio(GameHUD.RATIOS[clampi(i + d, 0, GameHUD.RATIOS.size() - 1)])


# ---------------------------------------------------------------------------------------------
# Actions (HUD)
# ---------------------------------------------------------------------------------------------

func set_speed(s: float) -> void:
	if s <= 0.0:
		paused = true
	else:
		paused = false
		speed = s
	hud.refresh()


func set_ratio(r: float) -> void:
	ratio = r
	hud.refresh()


func begin_build(kind: int) -> void:
	if not GameHUD.build_kinds(sim.rules).has(kind):
		return
	build_kind = kind
	build_open = true
	select_structure(-1)
	if selected_owner > 0 and selected_owner != sim.player_id:
		select_owner(0)
	hud.dock.open("")  # one context at a time: the build bar replaces side panels
	hud.tip("build")
	hud.refresh()


## Opens the build bar (categories and buildings) without picking a building yet.
func open_build_mode() -> void:
	if sim.phase != Sim.Phase.PLAYING:
		return
	build_open = true
	select_structure(-1)
	if selected_owner > 0 and selected_owner != sim.player_id:
		select_owner(0)
	hud.dock.open("")  # one context at a time: the build bar replaces side panels
	hud.refresh()


func close_build_mode() -> void:
	build_kind = -1
	build_open = false
	hud.refresh()


func cancel_build() -> void:
	build_kind = -1
	hud.refresh()


func _spawn_advisor() -> SpawnAdvisor:
	if _advisor == null:
		_advisor = SpawnAdvisor.new(sim)
	return _advisor


func _update_spawn_hover() -> void:
	var choosing := sim.phase == Sim.Phase.SPAWN and sim.player_id > 0 and sim.st.o_spawned[sim.player_id] == 0
	if not choosing:
		if not effects.spawn_hover.is_empty():
			effects.spawn_hover = {}
			spawn_info_hover = {}
		return
	if hover_tile == int(spawn_info_hover.get("tile", -2)):
		return
	spawn_info_hover = _spawn_advisor().analyze(hover_tile) if hover_tile >= 0 else {}
	effects.spawn_hover = spawn_info_hover
	hud.refresh()


func confirm_spawn() -> void:
	if spawn_pending < 0 or sim.phase != Sim.Phase.SPAWN:
		return
	if not sim.spawn.is_valid_start(spawn_pending):
		hud.toast(tr("SPAWN_BAD_TAKEN"), UITheme.BAD, "ui_warning")
		cancel_spawn()
		return
	sim.submit(Commands.spawn(sim.player_id, spawn_pending))
	cancel_spawn()


func cancel_spawn() -> void:
	spawn_pending = -1
	spawn_info_pending = {}
	effects.spawn_pending = {}
	hud.refresh()


func start_research(tech_id: String) -> void:
	sim.submit(Commands.research(sim.player_id, tech_id))
	hud.toast(tr("RESEARCH_STARTED") % MetaData.text(ResearchSystem.tech(tech_id).get("name", {})), UITheme.RESEARCH, "r_research")
	hud.dock.mark_dirty()


func select_structure(sid: int) -> void:
	selected_structure = sid
	structures.selected = sid
	zones.selected_structure = sid
	if sid >= 0:
		Hints.hide()
		hud.inspector.show_structure(sid)
	elif hud.inspector.structure_id >= 0:
		hud.inspector.show_owner(selected_owner)


## Orders the next level of one of the player's buildings (same order as building on its tile).
func upgrade_structure(sid: int) -> void:
	var s: StructureSystem.Structure = sim.structures.structs[sid]
	var pv := sim.structures.preview(sim.player_id, s.kind, s.tile)
	if not pv["ok"] or int(pv["upgrade"]) != sid:
		hud.toast(BuildTip.reason_text(pv, sim.rules) if not pv["ok"] else tr("BI_UPGRADE_BUSY"), UITheme.BAD, "ui_warning")
		return
	sim.submit(Commands.build(sim.player_id, s.kind, s.tile))
	hud.inspector.show_structure(sid)


## Hint card for the building under the cursor (name, purpose, main effect, key figures).
func _update_structure_hover() -> void:
	var sid := -1
	var aid := -1
	var allowed := build_kind < 0 and not menu_open and sim.phase == Sim.Phase.PLAYING and not hud.ui_hidden
	if allowed:
		sid = structures.pick(_mouse_screen)
		if sid < 0:
			aid = effects.pick_arrow(_mouse_screen)
	if sid == hover_structure and aid == hover_arrow:
		return
	hover_structure = sid
	hover_arrow = aid
	structures.hovered = sid
	effects.hovered_arrow = aid
	if sid >= 0:
		var s: StructureSystem.Structure = sim.structures.structs[sid]
		var r := structures.plate_radius() * cam.zoom.x
		Hints.show_at(Rect2(_mouse_screen - Vector2(r, r), Vector2(r, r) * 2.0), BuildingInfo.structure_brief(sim, s))
	elif aid >= 0:
		var info := effects.arrow_info(aid)
		if not info.is_empty():
			Hints.show_at(Rect2(_mouse_screen - Vector2(8, 8), Vector2(16, 16)), info)
	else:
		Hints.hide()


func toggle_zones() -> void:
	zones.show_all = not zones.show_all
	Settings.show_zones = zones.show_all
	Settings.save_settings()
	zones.queue_redraw()
	hud.refresh()


## Build placement preview under the cursor: recomputed when the tile changes and a few times a
## second (gold and supplies change), drawn by the ghost layer and described by the build tip.
func _update_ghost(delta: float) -> void:
	zones.focus_kind = build_kind
	zones.extra_owner = selected_owner
	var active := build_kind >= 0 and hover_tile >= 0 and sim.phase == Sim.Phase.PLAYING and not menu_open
	if not active:
		if _ghost_tile != -2:
			ghost.clear()
			hud.build_tip.visible = false
			_ghost_tile = -2
		return
	_ghost_t -= delta
	if hover_tile != _ghost_tile or _ghost_t <= 0.0 or int(ghost.preview.get("kind", -1)) != build_kind:
		_ghost_tile = hover_tile
		_ghost_t = 0.25
		ghost.set_preview(hover_tile, sim.structures.preview(sim.player_id, build_kind, hover_tile))
	hud.build_tip.show_preview(ghost.preview, sim, _mouse_screen)


# ---- diplomacy (DiplomacyPanel) ----

## Player diplomacy: action "request" (kind), "reply" (accept), "break" or "extend" towards `id`.
func diplo(action: String, id: int, kind: String = "", accept: bool = false) -> void:
	sim.submit(Commands.diplo(sim.player_id, action, id, kind, accept))
	_diplo_changed()


## Sends the attack share of troops or gold to an ally.
func send_aid(id: int, kind: String) -> void:
	var st := sim.st
	var pid := sim.player_id
	var amount := floorf((st.o_troops[pid] if kind == "troops" else st.o_gold[pid]) * ratio)
	sim.submit(Commands.send(pid, id, kind, amount))
	_diplo_changed()


## Asks ally `id` for help against whoever attacks us hardest.
func ask_help(id: int) -> void:
	var enemy := DiplomacyPanel.main_enemy(sim)
	if enemy > 0:
		sim.submit(Commands.help(sim.player_id, id, enemy))
	_diplo_changed()


func answer_help(asker: int, accept: bool) -> void:
	var pid := sim.player_id
	sim.submit(Commands.help_answer(pid, asker, accept, floorf(sim.st.o_troops[pid] * ratio) if accept else 0.0))
	_diplo_changed()


func _diplo_changed() -> void:
	hud.dock.mark_dirty()
	hud.inspector.refresh(true)


## Log lines and toasts for diplomacy that concerns the player.
func _diplo_news(e: Dictionary) -> void:
	var pid := sim.player_id
	if pid <= 0:
		return
	var st := sim.st
	var nm := func(o: int) -> String: return st.o_name[o] if o > 0 and o <= st.owner_count else "?"
	var touched := true
	match String(e["type"]):
		SimEvents.DIPLO_REQUEST:
			if int(e["to"]) == pid:
				var msg := tr("LOG_DIPLO_OFFER") % [nm.call(int(e["from"])), DiplomacyPanel.rel_name(String(e["kind"]))]
				hud.toast(msg, UITheme.ACCENT, "ui_users")
				hud.log_line(msg, UITheme.ACCENT)
				hud.tip("diplomacy")
		SimEvents.DIPLO_FORMED:
			var a := int(e["a"])
			var b := int(e["b"])
			if a == pid or b == pid:
				var msg2 := tr("LOG_DIPLO_FORMED") % [nm.call(b if a == pid else a), DiplomacyPanel.rel_name(String(e["kind"]))]
				hud.toast(msg2, UITheme.GOOD, "ui_users")
				hud.log_line(msg2, UITheme.GOOD)
		SimEvents.DIPLO_DECLINED:
			if int(e["from"]) == pid:
				var expired := String(e.get("reason", "")) == "expired"
				hud.log_line((tr("LOG_DIPLO_EXPIRED") if expired else tr("LOG_DIPLO_DECLINED")) % nm.call(int(e["to"])), UITheme.TEXT_DIM)
		SimEvents.DIPLO_ENDED:
			var a2 := int(e["a"])
			var b2 := int(e["b"])
			if a2 == pid or b2 == pid:
				var other := b2 if a2 == pid else a2
				var breaker := int(e.get("breaker", 0))
				var reason := String(e.get("reason", ""))
				if reason == "nuked":
					hud.log_line(tr("LOG_DIPLO_NUKED") % nm.call(other), UITheme.BAD)
				elif breaker == pid:
					hud.log_line(tr("LOG_DIPLO_YOU_BROKE") % nm.call(other), UITheme.WARN)
				elif breaker > 0:
					hud.toast(tr("LOG_DIPLO_BROKEN") % nm.call(other), UITheme.BAD, "ui_warning")
					hud.log_line(tr("LOG_DIPLO_BROKEN") % nm.call(other), UITheme.BAD)
				elif reason != "eliminated":
					hud.log_line(tr("LOG_DIPLO_ENDED") % nm.call(other), UITheme.TEXT_DIM)
		SimEvents.DIPLO_EXPIRING:
			if int(e["a"]) == pid or int(e["b"]) == pid:
				var o2 := int(e["b"]) if int(e["a"]) == pid else int(e["a"])
				hud.toast(tr("LOG_DIPLO_EXPIRING") % nm.call(o2), UITheme.WARN, "ui_clock")
				hud.log_line(tr("LOG_DIPLO_EXPIRING") % nm.call(o2), UITheme.WARN)
		SimEvents.DIPLO_RENEWED:
			if int(e["a"]) == pid or int(e["b"]) == pid:
				hud.log_line(tr("LOG_DIPLO_RENEWED") % nm.call(int(e["b"]) if int(e["a"]) == pid else int(e["a"])), UITheme.GOOD)
		SimEvents.DIPLO_EXTEND_ASKED:
			if int(e["to"]) == pid:
				hud.log_line(tr("LOG_DIPLO_EXTEND_ASKED") % nm.call(int(e["from"])), UITheme.ACCENT)
		SimEvents.TRAITOR:
			if int(e["id"]) != pid:
				hud.log_line(tr("LOG_TRAITOR") % [nm.call(int(e["id"])), nm.call(int(e["victim"]))], UITheme.WARN)
		SimEvents.CONVOY_ARRIVED:
			var what := (tr("CONVOY_TROOPS") if String(e["kind"]) == "troops" else tr("CONVOY_GOLD")) % UITheme.num(float(e["amount"]))
			if bool(e.get("returned", false)) and int(e["from"]) == pid:
				hud.log_line(tr("LOG_CONVOY_BACK"), UITheme.WARN)
			elif int(e["to"]) == pid and int(e["from"]) != pid:
				hud.toast(tr("LOG_CONVOY_IN") % [nm.call(int(e["from"])), what], UITheme.GOOD, "ui_packages")
				hud.log_line(tr("LOG_CONVOY_IN") % [nm.call(int(e["from"])), what], UITheme.GOOD)
			elif int(e["from"]) == pid:
				hud.log_line(tr("LOG_CONVOY_OUT") % nm.call(int(e["to"])), UITheme.TEXT_DIM)
		SimEvents.HELP_REQUEST:
			if int(e["to"]) == pid:
				var msg3 := tr("LOG_HELP_ASKED") % [nm.call(int(e["from"])), nm.call(int(e["enemy"]))]
				hud.toast(msg3, UITheme.WARN, "ui_swords")
				hud.log_line(msg3, UITheme.WARN)
		SimEvents.HELP_ANSWER:
			if int(e["from"]) == pid:
				if bool(e["accepted"]):
					hud.log_line(tr("LOG_HELP_YES") % [nm.call(int(e["to"])), nm.call(int(e["enemy"]))], UITheme.GOOD)
				else:
					hud.log_line(tr("LOG_HELP_NO") % nm.call(int(e["to"])), UITheme.TEXT_DIM)
		SimEvents.CONVOY_SENT:
			pass
		_:
			touched = false
	if touched:
		hud.dock.mark_dirty()


func retreat(aid: int) -> void:
	sim.submit(Commands.retreat(sim.player_id, aid))


func retreat_all() -> void:
	for a in sim.attacks.outgoing(sim.player_id):
		if a.retreat_at == 0:
			retreat(a.id)


func focus_home() -> void:
	var pid := sim.player_id
	if pid <= 0 or sim.st.o_tiles[pid] <= 0:
		return
	cam.focus(sim.st.centroid(pid))


## Attack state `id` from the inspector with the current share (a tile on the shared border).
func attack_owner(id: int) -> void:
	var st := sim.st
	var pid := sim.player_id
	var t := st.o_border_head[pid]
	var W := st.W
	while t >= 0:
		var x := t % W
		for nb: int in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W]:
			if nb >= 0 and nb < st.N and st.owner[nb] == id and sim.map.land[nb] == 1:
				sim.submit(Commands.attack_tile(pid, nb, ratio))
				return
		t = st.bnext[t]
	hud.toast(tr("REJECT_NO_BORDER"))


## Starts aiming weapon `w` (or says why it cannot be used now).
func begin_weapon(w: int) -> void:
	if sim.phase != Sim.Phase.PLAYING or w < 0:
		return
	var reason := WeaponInfo.blocker(sim, w, sim.player_id)
	if reason != "":
		hud.toast(reason, UITheme.BAD, "ui_warning")
		return
	if build_open:
		close_build_mode()
	cancel_naval()
	select_structure(-1)
	select_boat(-1)
	hud.dock.open("")
	weapon_aim = w
	weapon_target = -1
	weapon_preview = {}
	weapons_fx.aim = {}
	if hover_tile >= 0:
		_update_aim(hover_tile)
	hud.refresh()


func cancel_weapon() -> void:
	if weapon_aim < 0:
		return
	weapon_aim = -1
	weapon_target = -1
	weapon_preview = {}
	weapons_fx.aim = {}
	hud.refresh()


## Live preview at tile `t`: the launch check and the estimated effect (same code as the impact).
func _update_aim(t: int) -> void:
	if weapon_aim < 0 or t < 0:
		return
	if int(weapon_preview.get("tile", -1)) == t:
		return
	var pid := sim.player_id
	var c := sim.weapons.check(pid, weapon_aim, t)
	var est := {} if sim.map.land[t] == 0 else sim.weapons.estimate(pid, weapon_aim, t)
	weapon_preview = {"tile": t, "check": c, "est": est, "locked": weapon_target == t}
	weapons_fx.aim = {"weapon": weapon_aim, "tile": t, "check": c, "est": est, "locked": weapon_target == t}
	hud.command.refresh()


## First click marks the target, a second click on it (or Enter / Launch) fires.
func _aim_click(t: int) -> void:
	if weapon_target >= 0 and sim.map.dist2(t, weapon_target) <= 4:
		fire_weapon()
		return
	weapon_target = t
	weapon_preview = {}
	_update_aim(t)
	var c: Dictionary = weapon_preview.get("check", {})
	if not c.get("ok", false):
		hud.toast(WeaponInfo.reason_text(sim, weapon_aim, String(c.get("reason", ""))), UITheme.BAD, "ui_warning")


## Launches at the marked target (or the tile under the cursor).
func fire_weapon() -> void:
	if weapon_aim < 0:
		return
	var t := weapon_target if weapon_target >= 0 else hover_tile
	if t < 0:
		return
	var c := sim.weapons.check(sim.player_id, weapon_aim, t)
	if not c["ok"]:
		hud.toast(WeaponInfo.reason_text(sim, weapon_aim, String(c["reason"])), UITheme.BAD, "ui_warning")
		return
	sim.submit(Commands.launch(sim.player_id, String(sim.rules.weapon(weapon_aim)["id"]), t))
	if Input.is_key_pressed(KEY_SHIFT) and not sim.weapons.is_nuclear(weapon_aim):
		weapon_target = -1
		weapon_preview = {}
	else:
		cancel_weapon()


## "Landing" against state `id`: prepares a sea landing towards its most important place.
func landing_on(id: int) -> void:
	if id <= 0:
		return
	preview_naval(NavalOrders.default_goal(sim, id))


## Plans a sea landing towards tile `t` (same planner as the simulation) and shows the preview:
## route, beach, overland direction, troops, time — or why it is impossible.
func preview_naval(t: int) -> void:
	var p := LandingPlanner.plan(sim.naval, sim.player_id, t)
	p["tile"] = t
	naval_plan = p
	selected_boat = -1
	effects.naval_plan = p
	if not p["ok"]:
		hud.toast(NavalOrders.reason_text(String(p["reason"])), UITheme.BAD, "ui_warning")
	else:
		hud.tip("landing")
	hud.refresh()


func cancel_naval() -> void:
	if naval_plan.is_empty():
		return
	naval_plan = {}
	effects.naval_plan = {}
	hud.refresh()


## Sends the prepared landing with the current attack share.
func confirm_naval() -> void:
	if naval_plan.is_empty():
		return
	var pid := sim.player_id
	var send := floorf(sim.st.o_troops[pid] * ratio)
	var reason := NavalOrders.blocker(sim, pid, naval_plan, send)
	if reason != "":
		hud.toast(reason, UITheme.BAD, "ui_warning")
		return
	var t: int = naval_plan["tile"]
	var go: int = naval_plan["goal_owner"]
	sim.submit(Commands.boat_ratio(pid, t, ratio))
	hud.log_line(tr("LOG_BOAT_SENT") % (tr("FREE_LAND") if go == 0 else sim.st.o_name[go]), UITheme.ACCENT)
	cancel_naval()


func select_boat(id: int) -> void:
	selected_boat = id
	effects.selected_boat = id
	if id >= 0:
		cancel_naval()
		select_structure(-1)
		if selected_owner > 0 and selected_owner != sim.player_id:
			selected_owner = 0
			hud.show_owner(0)
	hud.refresh()


func recall_boat() -> void:
	if selected_boat >= 0:
		sim.submit(Commands.cancel_boat(sim.player_id, selected_boat))
		hud.log_line(tr("LOG_BOAT_RECALLED"), UITheme.ACCENT)
		hud.refresh()


## Encyclopedia as an overlay on top of the match (the match pauses while it is open).
func open_encyclopedia(article: String = "") -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var s: Control = (load("res://scripts/ui/screens/encyclopedia_screen.gd") as GDScript).new()
	s.set("overlay", true)
	s.set("start_article", article)
	var was_paused := paused
	paused = true
	layer.add_child(s)
	s.tree_exited.connect(func() -> void:
		layer.queue_free()
		paused = was_paused)


func open_settings() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var s: Control = (load("res://scenes/menus/settings.tscn") as PackedScene).instantiate()
	s.set("overlay", true)
	layer.add_child(s)
	s.tree_exited.connect(layer.queue_free)


func select_owner(id: int, focus: bool = false) -> void:
	selected_owner = id
	selected_structure = -1
	structures.selected = -1
	zones.selected_structure = -1
	hud.show_owner(id)
	if focus and id > 0:
		var c := sim.st.centroid(id)
		cam.focus(c)


func open_pause_menu() -> void:
	if _ended and not watching:
		return
	menu_open = true
	hud.show_pause(true)
	App.goto(App.State.PAUSED)


func close_pause_menu() -> void:
	menu_open = false
	hud.show_pause(false)
	App.goto(App.State.SPAWN_SELECT if sim.phase == Sim.Phase.SPAWN else App.State.PLAYING)


func save_game() -> void:
	var slot := "%s_%s" % [sim.def.id, Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")]
	_last_save = SaveManager.save(sim, slot)
	hud.toast(tr("SAVED") if _last_save != "" else tr("SAVE_FAILED"))
	hud.log_line(tr("SAVED"), UITheme.ACCENT)


func load_last() -> void:
	var saves := SaveManager.list()
	if saves.is_empty():
		hud.toast(tr("LOAD_EMPTY"))
		return
	App.goto(App.State.LOAD_GAME)


func restart() -> void:
	App.start_new_match()


func new_game() -> void:
	App.goto(App.State.MAP_SELECT)


func quit_to_menu() -> void:
	App.goto(App.State.MAIN_MENU)


func continue_watching() -> void:
	watching = true
	hud.hide_end()
	if sim.phase != Sim.Phase.OVER:
		App.goto(App.State.PLAYING)
