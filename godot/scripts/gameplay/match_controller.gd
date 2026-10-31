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


func _ready() -> void:
	_loading = _loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _create_sim():
		App.goto(App.State.MAIN_MENU)
		return
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


func _build_world() -> void:
	renderer = MapRenderer.new()
	add_child(renderer)
	renderer.setup(sim)
	structures = StructureLayer.new()
	add_child(structures)
	effects = EffectsLayer.new()
	add_child(effects)
	cam = MapCamera.new()
	add_child(cam)
	cam.make_current()
	cam.edge_scroll = Settings.edge_scroll
	cam.setup(Vector2(sim.map.width, sim.map.height))
	structures.sim = sim
	structures.cam = cam
	effects.sim = sim
	effects.cam = cam
	var ui := CanvasLayer.new()
	ui.layer = 1
	add_child(ui)
	labels = LabelLayer.new()
	labels.sim = sim
	labels.cam = cam
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
	_handle_events()
	_check_end()


func _handle_events() -> void:
	var pid := sim.player_id
	var st := sim.st
	for e in sim.events.drain():
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
			SimEvents.SPAWNED:
				if int(e["owner"]) == pid:
					effects.ring(int(e["tile"]), UITheme.ACCENT, 14.0)
			SimEvents.PHASE:
				if e.get("phase", "") == "playing" and sim.player_id > 0:
					App.goto(App.State.PLAYING)
					hud.log_line(tr("LOG_START"), UITheme.ACCENT)


func _check_end() -> void:
	if _ended:
		return
	if sim.phase == Sim.Phase.OVER:
		_ended = true
		var won := int(sim.result.get("winner", 0)) == sim.player_id and sim.player_id > 0
		App.goto(App.State.VICTORY if won else App.State.DEFEAT)
		hud.show_end(won, String(sim.result.get("reason", "domination")) if won else ("player_lost" if not sim.is_player_alive() else String(sim.result.get("reason", "domination"))))
	elif sim.phase == Sim.Phase.PLAYING and sim.player_id > 0 and not sim.is_player_alive() and not watching:
		_ended = true
		App.goto(App.State.DEFEAT)
		hud.show_end(false, "player_lost")


# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------

func _tile_at_mouse() -> int:
	var p := cam.get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	return sim.map.tile_at(int(floor(p.x)), int(floor(p.y)))


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseMotion:
		hover_tile = _tile_at_mouse()
		hover_owner = sim.st.owner[hover_tile] if hover_tile >= 0 else 0
		effects.spawn_hover = hover_tile if sim.phase == Sim.Phase.SPAWN and sim.player_id > 0 and sim.st.o_spawned[sim.player_id] == 0 else -1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_left_click(_tile_at_mouse())
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_press_pos = mb.position
			elif mb.position.distance_to(_press_pos) < 5.0:
				if build_kind >= 0:
					cancel_build()
				else:
					var t := _tile_at_mouse()
					select_owner(sim.st.owner[t] if t >= 0 else 0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_ESCAPE:
				if build_kind >= 0:
					cancel_build()
				elif menu_open:
					close_pause_menu()
				else:
					open_pause_menu()
			KEY_SPACE:
				set_speed(0.0 if not paused else maxf(speed, 1.0))
			KEY_1, KEY_2, KEY_3, KEY_4:
				begin_build(GameHUD.BUILD_KINDS[k - KEY_1])
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
				var sp := sim.st.o_spawn_tile[sim.player_id] if sim.player_id > 0 else -1
				if sp >= 0:
					cam.focus(Vector2(sp % sim.map.width, sp / sim.map.width))


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
		if sim.spawn.is_valid_start(t):
			sim.submit(Commands.spawn(pid, t))
		else:
			hud.toast(tr("REJECT_BAD_TILE"))
		return
	if not sim.is_player_alive() or sim.phase != Sim.Phase.PLAYING:
		select_owner(st.owner[t])
		return
	if build_kind >= 0:
		if st.owner[t] != pid:
			hud.toast(tr("REJECT_BUILD_OWN_LAND"))
			return
		sim.submit(Commands.build(pid, build_kind, t))
		if not Input.is_key_pressed(KEY_SHIFT):
			cancel_build()
		return
	if sim.map.land[t] == 0:
		return
	var o := st.owner[t]
	if o == pid:
		select_owner(pid)
		return
	if _borders(pid, o):
		sim.submit(Commands.attack_tile(pid, t, ratio))
	elif sim.map.coastal[t] == 1:
		sim.submit(Commands.boat_ratio(pid, t, ratio))
		hud.log_line(tr("LOG_BOAT_SENT") % (tr("FREE_LAND") if o == 0 else st.o_name[o]), UITheme.ACCENT)
	else:
		hud.toast(tr("REJECT_NO_BORDER"))


func _borders(a: int, b: int) -> bool:
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
	if String(sim.rules.b_kinds[kind].get("phase", "")) != "":
		hud.toast(tr("SOON"))
		return
	build_kind = kind
	hud.toast(tr("BUILD_MODE") % tr("B_" + sim.rules.b_ids[kind].to_upper()))
	hud.refresh()


func cancel_build() -> void:
	build_kind = -1
	hud.refresh()


func retreat(aid: int) -> void:
	sim.submit(Commands.retreat(sim.player_id, aid))


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
