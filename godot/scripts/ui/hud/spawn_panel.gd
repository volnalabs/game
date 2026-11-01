class_name HudSpawnPanel
extends PanelContainer
## Start selection: what the hovered / chosen tile gives (claimed land, reachable free land, coast,
## nearest states and danger) and the confirm step. Data from SpawnAdvisor.

var hud: GameHUD
var _title: Label
var _hint: Label
var _info: VBoxContainer
var _buttons: HBoxContainer
var _confirm: Button
var _shown_tile: int = -2
var _shown_pending: bool = false


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.SURFACE, 0.95), UITheme.R_L, UITheme.STROKE, 14))
	custom_minimum_size.x = 420
	var v := UITheme.vbox(6)
	add_child(v)
	var head := UITheme.hbox(8)
	head.add_child(Icons.rect("g_capital", 24, UITheme.ACCENT))
	_title = UITheme.label(tr("SPAWN_TITLE"), UITheme.T_TITLE, UITheme.ACCENT, true)
	head.add_child(_title)
	v.add_child(head)
	_hint = UITheme.label(tr("SPAWN_HINT"), UITheme.T_BODY, UITheme.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 392
	v.add_child(_hint)
	_info = UITheme.vbox(4)
	v.add_child(_info)
	_buttons = UITheme.hbox(8)
	_confirm = UITheme.accent_button(tr("SPAWN_CONFIRM"), func() -> void: hud.ctl.confirm_spawn(), 200, "ui_check")
	_buttons.add_child(_confirm)
	_buttons.add_child(UITheme.ghost_button(tr("CANCEL"), func() -> void: hud.ctl.cancel_spawn(), "ui_close"))
	v.add_child(_buttons)
	_buttons.visible = false


func refresh() -> void:
	var sim := hud.sim
	var pid := sim.player_id
	if sim.st.o_spawned[pid] == 1:
		_title.text = tr("SPAWN_TITLE")
		_hint.text = tr("SPAWN_COUNTDOWN") % maxf(0.0, float(sim.countdown_end - sim.st.tick) / 10.0) if sim.countdown_end > 0 else tr("SPAWN_WAIT")
		_info.visible = false
		_buttons.visible = false
		reset_size()
		return
	var pending: int = hud.ctl.spawn_pending
	var info: Dictionary = hud.ctl.spawn_info_pending if pending >= 0 else hud.ctl.spawn_info_hover
	_buttons.visible = pending >= 0
	_hint.text = tr("SPAWN_HINT_CONFIRM") if pending >= 0 else tr("SPAWN_HINT")
	var tile: int = info.get("tile", -1)
	if tile == _shown_tile and _shown_pending == (pending >= 0):
		return
	_shown_tile = tile
	_shown_pending = pending >= 0
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	_fill(info)
	reset_size()


func _fill(info: Dictionary) -> void:
	var sim := hud.sim
	_info.visible = not info.is_empty()
	if info.is_empty():
		return
	var reason := String(info["reason"])
	if reason != "":
		_info.add_child(UITheme.icon_label("ui_warning", tr("SPAWN_BAD_" + reason.to_upper()), UITheme.BAD))
		return
	_info.add_child(UITheme.icon_label("ui_check", tr("SPAWN_OK"), UITheme.GOOD))
	_info.add_child(UITheme.stat_row(tr("SPAWN_CLAIM"), tr("SPAWN_TILES") % (info["claim"] as PackedInt32Array).size(), UITheme.TEXT, "r_land"))
	_info.add_child(UITheme.stat_row(tr("SPAWN_FREE"), tr("SPAWN_TILES") % int(info["free"]), UITheme.TEXT, "ui_map"))
	_info.add_child(UITheme.stat_row(tr("SPAWN_COAST"), tr("YES") if info["coastal"] else tr("NO"), UITheme.TEXT, "g_landing"))
	var lvl: int = info["danger_level"]
	var dc: Color = [UITheme.GOOD, UITheme.WARN, UITheme.BAD][lvl]
	_info.add_child(UITheme.stat_row(tr("SPAWN_DANGER"), tr(["SPAWN_DANGER_LOW", "SPAWN_DANGER_MID", "SPAWN_DANGER_HIGH"][lvl]), dc, "ui_warning"))
	var near: Array = info["neighbours"]
	if near.is_empty():
		_info.add_child(UITheme.label(tr("SPAWN_NO_NEIGHBOURS"), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	else:
		_info.add_child(UITheme.caption(tr("SPAWN_NEIGHBOURS"), UITheme.TEXT_FAINT))
		for n: Dictionary in near:
			var id: int = n["id"]
			var row := UITheme.hbox(6)
			row.add_child(UITheme.flag_rect(hud.flag_of(id), 22, 14))
			var nm := UITheme.label(sim.st.o_name[id], UITheme.T_BODY)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(UITheme.icon_label("r_army", UITheme.num(float(n["troops"])), UITheme.TEXT_DIM, UITheme.T_CAPTION))
			row.add_child(UITheme.label(tr("SPAWN_DIST") % roundi(float(n["dist"])), UITheme.T_CAPTION, UITheme.TEXT_DIM))
			_info.add_child(row)
