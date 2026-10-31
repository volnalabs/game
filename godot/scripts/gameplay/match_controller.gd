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
	speed = Settings.default_speed
	if sim.phase == Sim.Phase.SPAWN:
		App.goto(App.State.SPAWN_SELECT)
		_focus_player_nation()
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
	zones = ZoneLayer.new()
	add_child(zones)
	structures = StructureLayer.new()
	add_child(structures)
	ghost = GhostLayer.new()
	add_child(ghost)
	effects = EffectsLayer.new()
	add_child(effects)
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
	_check_end()


func _handle_events() -> void:
	var pid := sim.player_id
	var st := sim.st
	effects.focus_owner = selected_owner
	for e in sim.events.drain():
		effects.on_event(e)
		match String(e["type"]):
			SimEvents.ATTACK_STARTED:
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
					hud.toast(tr("REJECT_" + String(e["reason"]).to_upper()))
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
					App.goto(App.State.PLAYING)
					hud.log_line(tr("LOG_START"), UITheme.ACCENT)


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
		var won := int(sim.result.get("winner", 0)) == sim.player_id and sim.player_id > 0
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
		hover_owner = sim.st.owner[hover_tile] if hover_tile >= 0 else 0
		_update_spawn_hover()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_left_click(tile_at_screen(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_press_pos = mb.position
			elif mb.position.distance_to(_press_pos) < 5.0:
				if build_kind >= 0:
					cancel_build()
				else:
					var t := tile_at_screen(mb.position)
					select_owner(sim.st.owner[t] if t >= 0 else 0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_ENTER, KEY_KP_ENTER:
				if spawn_pending >= 0:
					confirm_spawn()
			KEY_ESCAPE:
				if spawn_pending >= 0:
					cancel_spawn()
				elif hud.ui_hidden:
					hud.set_ui_hidden(false)
				elif build_kind >= 0:
					cancel_build()
				elif menu_open:
					close_pause_menu()
				else:
					open_pause_menu()
			KEY_SPACE:
				set_speed(0.0 if not paused else maxf(speed, 1.0))
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var kinds := hud.quick_kinds()
				if k - KEY_1 < kinds.size():
					begin_build(kinds[k - KEY_1])
			KEY_TAB:
				hud.set_ui_hidden(not hud.ui_hidden)
			KEY_Q:
				_step_ratio(-1)
			KEY_E:
				_step_ratio(1)
			KEY_F3:
				hud.toggle_ai_debug()
			KEY_F5:
				save_game()
			KEY_EQUAL, KEY_KP_ADD:
				set_speed(minf(speed * 2.0, 4.0))
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_speed(maxf(speed * 0.5, 0.5))
			KEY_HOME:
				focus_home()
			KEY_Z:
				toggle_zones()


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
	if borders(pid, o):
		sim.submit(Commands.attack_tile(pid, t, ratio))
	elif sim.map.coastal[t] == 1:
		sim.submit(Commands.boat_ratio(pid, t, ratio))
		hud.log_line(tr("LOG_BOAT_SENT") % (tr("FREE_LAND") if o == 0 else st.o_name[o]), UITheme.ACCENT)
	else:
		hud.toast(tr("REJECT_NO_BORDER"))


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
	hud.toast(tr("BUILD_MODE") % tr("B_" + sim.rules.b_ids[kind].to_upper()), UITheme.ACCENT, "b_" + sim.rules.b_ids[kind])
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


## Naval landing on state `id`'s coast nearest to our own coast.
func landing_on(id: int) -> void:
	var st := sim.st
	var pid := sim.player_id
	var c := st.centroid(pid)
	var best := -1
	var bd := INF
	for t in sim.map.coast_tiles:
		if st.owner[t] == id:
			var d := Vector2(t % st.W, t / st.W).distance_squared_to(c)
			if d < bd:
				bd = d
				best = t
	if best < 0:
		hud.toast(tr("REJECT_NOT_COAST"))
		return
	sim.submit(Commands.boat_ratio(pid, best, ratio))
	hud.log_line(tr("LOG_BOAT_SENT") % st.o_name[id], UITheme.ACCENT)


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
