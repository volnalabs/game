class_name GameHUD
extends Control
## In-game interface (docs/ui/UI_DESIGN.md). Layout:
##   top bar — state, time, speed, gold, supplies, army, victory progress, menu;
##   left dock — icon rail opening collapsible panels (state, army, economy, build, log);
##   right column — leaderboard and the inspector of the selected state (tabs);
##   bottom command bar — attack share, quick build, army actions;
##   toasts, spawn banner, pause and victory / defeat modals.
## The HUD reads the simulation and acts only through the MatchController.

const RATIOS := [0.1, 0.2, 0.35, 0.5, 0.75, 1.0]

var ctl: Node
var sim: Sim
var top: HudTopBar
var dock: HudDock
var inspector: HudInspector
var board: HudLeaderboard
var command: HudCommandBar
var toasts: ToastStack
var log_lines: Array[String] = []
var ai_debug: bool = false
var _t: float = 0.0
var _spawn_banner: PanelContainer
var _spawn_l: Label
var _pause: Control
var _end: Control
var _end_title: Label
var _end_body: VBoxContainer
var _end_actions: HBoxContainer
var ui_hidden: bool = false


## Buildable kinds shown in the build menus (kinds of a later phase are hidden, never "soon").
static func build_kinds(rules: Rules) -> Array[int]:
	var out: Array[int] = []
	for k in rules.b_kinds.size():
		if String(rules.b_kinds[k].get("phase", "")) == "":
			out.append(k)
	return out


func setup(controller: Node, sim_: Sim) -> void:
	ctl = controller
	sim = sim_
	ai_debug = Settings.show_ai_debug
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.theme()
	top = HudTopBar.new(self)
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	dock = HudDock.new(self)
	add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	dock.position.y = 74
	var right := UITheme.vbox(8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_top = 74
	board = HudLeaderboard.new(self)
	right.add_child(board)
	inspector = HudInspector.new(self)
	right.add_child(inspector)
	command = HudCommandBar.new(self)
	add_child(command)
	command.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)
	command.grow_horizontal = Control.GROW_DIRECTION_BOTH
	command.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts = ToastStack.new()
	add_child(toasts)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 80
	_build_spawn_banner()
	_build_pause()
	_build_end()
	refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		refresh()


func refresh() -> void:
	if sim == null:
		return
	top.refresh()
	command.refresh()
	board.refresh()
	dock.refresh()
	inspector.refresh()
	_spawn_banner.visible = sim.phase == Sim.Phase.SPAWN and not ui_hidden
	if _spawn_banner.visible:
		var pid := sim.player_id
		if sim.st.o_spawned[pid] == 1 and sim.countdown_end > 0:
			_spawn_l.text = tr("SPAWN_COUNTDOWN") % maxf(0.0, float(sim.countdown_end - sim.st.tick) / 10.0)
		else:
			_spawn_l.text = tr("SPAWN_HINT")


func set_ui_hidden(on: bool) -> void:
	ui_hidden = on
	for c: Control in [top, dock, board, inspector, command]:
		c.visible = not on
	if not on:
		inspector.visible = ctl.selected_owner > 0


# ---------------------------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------------------------

func toast(text: String, color: Color = UITheme.WARN, icon: String = "ui_info") -> void:
	toasts.push(text, color, icon)


func log_line(text: String, color: Color = UITheme.TEXT) -> void:
	var secs := int(sim.elapsed_seconds())
	log_lines.append("[color=#7d8a98]%02d:%02d[/color] [color=#%s]%s[/color]" % [secs / 60, secs % 60, color.to_html(false), text])
	if log_lines.size() > 120:
		log_lines.pop_front()
	dock.log_changed()


func show_owner(id: int) -> void:
	inspector.show_owner(id)


func toggle_ai_debug() -> void:
	ai_debug = not ai_debug
	inspector.refresh(true)
	toast(tr("AI_DEBUG_ON") if ai_debug else tr("AI_DEBUG_OFF"), UITheme.ACCENT, "ui_eye")


func rank_of(id: int) -> int:
	var st := sim.st
	var r := 1
	for o in range(1, st.owner_count + 1):
		if o != id and st.o_alive[o] == 1 and st.o_tiles[o] > st.o_tiles[id]:
			r += 1
	return r


func flag_of(id: int) -> Texture2D:
	return UITheme.flag_texture(sim.st.o_flag[id], id * 7919 + sim.config.seed, sim.st.o_color[id])


# ---------------------------------------------------------------------------------------------
# Spawn banner and modals
# ---------------------------------------------------------------------------------------------

func _build_spawn_banner() -> void:
	_spawn_banner = UITheme.panel(16)
	add_child(_spawn_banner)
	var v := UITheme.vbox(4)
	_spawn_banner.add_child(v)
	v.add_child(UITheme.icon_label("g_capital", tr("SPAWN_TITLE"), UITheme.ACCENT, UITheme.T_TITLE))
	_spawn_l = UITheme.label(tr("SPAWN_HINT"), UITheme.T_BODY, UITheme.TEXT_DIM)
	v.add_child(_spawn_l)
	_spawn_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_spawn_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_spawn_banner.offset_top = 76
	_spawn_banner.offset_bottom = 76


func _modal() -> Array:
	var o := ColorRect.new()
	o.color = Color(0.02, 0.03, 0.05, 0.72)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(o)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(cc)
	var p := UITheme.panel(24)
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, UITheme.R_L, UITheme.STROKE_STRONG, 24))
	cc.add_child(p)
	o.visible = false
	return [o, p]


func _build_pause() -> void:
	var m := _modal()
	_pause = m[0]
	var v := UITheme.vbox(10)
	v.custom_minimum_size.x = 360
	(m[1] as PanelContainer).add_child(v)
	v.add_child(UITheme.title(tr("PAUSE_TITLE"), UITheme.T_H2))
	v.add_child(UITheme.accent_button(tr("PAUSE_CONTINUE"), func() -> void: ctl.close_pause_menu(), 0, "ui_play"))
	v.add_child(UITheme.button(tr("PAUSE_SAVE"), func() -> void: ctl.save_game(), 0, "ui_save"))
	v.add_child(UITheme.button(tr("PAUSE_LOAD"), func() -> void: ctl.load_last(), 0, "ui_load"))
	v.add_child(UITheme.button(tr("PAUSE_SETTINGS"), func() -> void: ctl.open_settings(), 0, "ui_settings"))
	v.add_child(UITheme.button(tr("PAUSE_RESTART"), func() -> void: ctl.restart(), 0, "ui_restart"))
	v.add_child(UITheme.button(tr("PAUSE_MAIN_MENU"), func() -> void: ctl.quit_to_menu(), 0, "ui_home"))
	var keys := UITheme.label(tr("PAUSE_KEYS"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size.x = 360
	v.add_child(keys)


func _build_end() -> void:
	var m := _modal()
	_end = m[0]
	var v := UITheme.vbox(12)
	v.custom_minimum_size.x = 560
	(m[1] as PanelContainer).add_child(v)
	_end_title = UITheme.title("", UITheme.T_H1)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_end_title)
	_end_body = UITheme.vbox(6)
	v.add_child(_end_body)
	_end_actions = UITheme.hbox(10)
	v.add_child(_end_actions)


func show_pause(on: bool) -> void:
	_pause.visible = on
	if on:
		Anim.fade_in(_pause)


func show_end(victory: bool, reason: String) -> void:
	_end.visible = true
	Anim.fade_in(_end)
	_end_title.text = tr("END_VICTORY") if victory else tr("END_DEFEAT")
	_end_title.add_theme_color_override("font_color", UITheme.GOOD if victory else UITheme.BAD)
	for c in _end_body.get_children():
		c.queue_free()
	var st := sim.st
	var pid := sim.player_id
	_end_body.add_child(UITheme.label(tr("END_REASON_" + reason.to_upper()), UITheme.T_BODY_L, UITheme.TEXT_DIM))
	var secs := int(sim.elapsed_seconds())
	_end_body.add_child(UITheme.stat_row(tr("END_TIME"), "%02d:%02d" % [secs / 60, secs % 60], UITheme.TEXT, "ui_clock"))
	_end_body.add_child(UITheme.stat_row(tr("END_LAND"), "%.1f%%" % (st.land_share(pid) * 100.0), UITheme.TEXT, "r_land"))
	_end_body.add_child(UITheme.stat_row(tr("END_PEAK"), UITheme.num(float(st.o_st_peak_tiles[pid])), UITheme.TEXT, "ui_chart"))
	_end_body.add_child(UITheme.stat_row(tr("MIL_CONQUERED"), UITheme.num(float(st.o_st_conquered[pid])), UITheme.TEXT, "g_attack"))
	_end_body.add_child(UITheme.stat_row(tr("MIL_ATTACKS"), str(st.o_st_attacks[pid]), UITheme.TEXT, "ui_swords"))
	_end_body.add_child(UITheme.stat_row(tr("MIL_LOST"), UITheme.num(st.o_st_troops_lost[pid]), UITheme.TEXT, "g_skull"))
	_end_body.add_child(UITheme.stat_row(tr("ECO_EARNED"), UITheme.num(st.o_st_gold_earned[pid]), UITheme.GOLD, "r_gold"))
	var w := int(sim.result.get("winner", 0))
	if w > 0:
		_end_body.add_child(UITheme.stat_row(tr("END_WINNER"), st.o_name[w], st.o_color[w].lightened(0.3), "g_victory"))
	for c in _end_actions.get_children():
		c.queue_free()
	_end_actions.add_child(UITheme.button(tr("END_WATCH"), func() -> void: ctl.continue_watching(), 0, "ui_eye"))
	_end_actions.add_child(UITheme.spacer())
	if ctl.has_method("show_results"):
		_end_actions.add_child(UITheme.accent_button(tr("END_RESULTS"), func() -> void: ctl.show_results(), 0, "m_progress"))
	_end_actions.add_child(UITheme.button(tr("END_NEW_GAME"), func() -> void: ctl.new_game(), 0, "m_new_game"))
	_end_actions.add_child(UITheme.button(tr("PAUSE_MAIN_MENU"), func() -> void: ctl.quit_to_menu(), 0, "ui_home"))


func hide_end() -> void:
	_end.visible = false


func is_modal_open() -> bool:
	return _pause.visible or _end.visible
