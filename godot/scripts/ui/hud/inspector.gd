class_name HudInspector
extends PanelContainer
## Right inspector of the selected state: header (flag, name, kind, personality) and tabs —
## overview, economy, army, buildings, threats, actions (+ AI debug). Other states' economies are
## hidden unless AI debugging is on (fog of war applies to the player too).

var hud: GameHUD
var owner_id: int = 0
var tab: String = "overview"
var _head: HBoxContainer
var _tabs: HBoxContainer
var _body: VBoxContainer
var _tab_buttons: Dictionary = {}
var _dirty: bool = true


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, UITheme.R_L, UITheme.STROKE, 12))
	custom_minimum_size.x = 340
	var v := UITheme.vbox(10)
	add_child(v)
	_head = UITheme.hbox(10)
	v.add_child(_head)
	_tabs = UITheme.hbox(2)
	v.add_child(_tabs)
	for t in [["overview", "ui_info"], ["economy", "g_economy"], ["army", "r_army"], ["buildings", "ui_building"],
			["threats", "ui_warning"], ["actions", "g_target"], ["ai", "m_research"]]:
		var id: String = t[0]
		var b := UITheme.icon_button(t[1], tr("TAB_" + id.to_upper()), func() -> void: set_tab(id), 34, true)
		_tab_buttons[id] = b
		_tabs.add_child(b)
	v.add_child(UITheme.separator())
	_body = UITheme.vbox(6)
	v.add_child(_body)
	visible = false


func show_owner(id: int) -> void:
	owner_id = id
	visible = id > 0 and not hud.ui_hidden
	_dirty = true
	if visible:
		refresh(true)
		Anim.slide_in(self, Vector2(16, 0), 0.16)


func set_tab(t: String) -> void:
	tab = t
	refresh(true)


func refresh(force: bool = false) -> void:
	if not visible or owner_id <= 0:
		return
	if not force and not _dirty and get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	_dirty = false
	var sim := hud.sim
	var st := sim.st
	var id := owner_id
	if id > st.owner_count:
		return
	var mine := id == sim.player_id
	if tab == "ai" and not hud.ai_debug:
		tab = "overview"
	(_tab_buttons["ai"] as Button).visible = hud.ai_debug and not mine
	(_tab_buttons["actions"] as Button).visible = not mine
	if tab == "actions" and mine:
		tab = "overview"
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == tab
	for c in _head.get_children():
		c.queue_free()
	_head.add_child(UITheme.flag_rect(hud.flag_of(id), 48, 32))
	var nv := UITheme.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(UITheme.label(st.o_name[id], UITheme.T_TITLE, st.o_color[id].lightened(0.35), true))
	var kind := tr("KIND_PLAYER") if mine else (tr("KIND_TRIBE") if st.o_kind[id] == Rules.KIND_TRIBE else tr("KIND_NATION"))
	var brain := sim.ai.brain_of(id)
	if brain != null and brain is StrategicAI:
		kind += " · " + tr("PERS_" + brain.personality_id.to_upper())
	nv.add_child(UITheme.label(kind, UITheme.T_CAPTION, UITheme.TEXT_DIM))
	_head.add_child(nv)
	_head.add_child(UITheme.icon_button("ui_close", tr("CLOSE"), func() -> void: hud.ctl.select_owner(0), 30))
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"overview":
			_body.add_child(UITheme.stat_row(tr("INFO_LAND"), "%s (%.1f%%)" % [UITheme.num(float(st.o_tiles[id])), st.land_share(id) * 100.0], UITheme.TEXT, "r_land"))
			_body.add_child(UITheme.stat_row(tr("INFO_TROOPS"), UITheme.num(st.o_troops[id]), UITheme.ARMY, "r_army"))
			_body.add_child(UITheme.stat_row(tr("INFO_RANK"), "#%d" % hud.rank_of(id), UITheme.TEXT, "ui_trophy"))
			_body.add_child(UITheme.stat_row(tr("INFO_STATUS"), HudPanels.status_of(sim, id), UITheme.TEXT, "ui_flag"))
			if not mine:
				var ratio := st.o_troops[sim.player_id] / maxf(st.o_troops[id], 1.0)
				_body.add_child(UITheme.stat_row(tr("INFO_POWER_RATIO"), "×%.2f" % ratio, UITheme.GOOD if ratio >= 1.0 else UITheme.BAD, "ui_swords"))
		"economy":
			if mine or hud.ai_debug:
				HudPanels.economy_of(hud, _body, id)
			else:
				_hidden()
		"army":
			_body.add_child(UITheme.stat_row(tr("MIL_TROOPS"), UITheme.num(st.o_troops[id]), UITheme.ARMY))
			_body.add_child(UITheme.stat_row(tr("MIL_IN_ATTACKS"), UITheme.num(sim.attacks.troops_in_attacks(id))))
			_body.add_child(UITheme.stat_row(tr("MIL_BOATS"), "%d / %d" % [st.o_boats[id], sim.naval.max_boats(id)]))
			_body.add_child(UITheme.stat_row(tr("MIL_ATTACKS"), str(st.o_st_attacks[id])))
			_body.add_child(UITheme.stat_row(tr("MIL_CONQUERED"), UITheme.num(float(st.o_st_conquered[id]))))
			if mine or hud.ai_debug:
				_body.add_child(UITheme.stat_row(tr("MIL_CAP"), UITheme.num(st.o_cap[id])))
				_body.add_child(UITheme.stat_row(tr("MIL_GROWTH"), HudPanels._per_sec(st.o_growth[id])))
		"buildings":
			var any := false
			for k in sim.rules.b_kinds.size():
				var lv := st.blevel(id, k)
				if lv > 0:
					any = true
					var bid := sim.rules.b_ids[k]
					_body.add_child(UITheme.stat_row(tr("B_" + bid.to_upper()), str(lv), UITheme.TEXT, "b_" + bid))
			if not any:
				_body.add_child(UITheme.label(tr("NO_BUILDINGS"), UITheme.T_BODY, UITheme.TEXT_FAINT))
		"threats":
			var rows: Array = []
			for a in sim.attacks.attacks:
				if a.alive and a.target == id and a.attacker > 0:
					rows.append(UITheme.icon_label("g_attack", tr("INCOMING_LINE") % [st.o_name[a.attacker], UITheme.num(a.troops)], UITheme.BAD))
				elif a.alive and a.attacker == id and a.target > 0:
					rows.append(UITheme.icon_label("g_war", tr("OUTGOING_LINE") % [st.o_name[a.target], UITheme.num(a.troops)], UITheme.WARN))
			for r in rows:
				_body.add_child(r)
			if rows.is_empty():
				_body.add_child(UITheme.label(tr("NO_THREATS"), UITheme.T_BODY, UITheme.TEXT_FAINT))
		"actions":
			_actions(id)
		"ai":
			_ai(id)


func _hidden() -> void:
	var l := UITheme.label(tr("INFO_HIDDEN"), UITheme.T_BODY, UITheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	_body.add_child(l)


func _actions(id: int) -> void:
	var sim := hud.sim
	var pid := sim.player_id
	var send := floorf(sim.st.o_troops[pid] * hud.ctl.ratio)
	_body.add_child(UITheme.label(tr("ACTIONS_SEND") % UITheme.num(send), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	var borders: bool = hud.ctl.borders(pid, id)
	var atk := UITheme.accent_button(tr("ACTION_ATTACK"), func() -> void: hud.ctl.attack_owner(id), 0, "g_attack")
	atk.disabled = not borders or sim.phase != Sim.Phase.PLAYING
	atk.tooltip_text = "" if borders else tr("REJECT_NO_BORDER")
	_body.add_child(atk)
	var land := UITheme.button(tr("ACTION_LANDING"), func() -> void: hud.ctl.landing_on(id), 0, "g_landing")
	land.disabled = sim.phase != Sim.Phase.PLAYING
	_body.add_child(land)
	_body.add_child(UITheme.button(tr("ACTION_FOCUS"), func() -> void: hud.ctl.select_owner(id, true), 0, "ui_target"))


func _ai(id: int) -> void:
	var brain := hud.sim.ai.brain_of(id)
	if brain == null:
		_hidden()
		return
	var st := hud.sim.st
	var d := brain.debug_info()
	for k: String in d:
		if k in ["options", "threats"]:
			continue
		var v: Variant = d[k]
		var vs := ("%.2f" % v) if typeof(v) == TYPE_FLOAT else str(v)
		if k == "target":
			vs = st.o_name[int(v)] if int(v) > 0 else "—"
		_body.add_child(UITheme.stat_row(k, vs))
	if d.has("threats"):
		for th: Array in d["threats"]:
			_body.add_child(UITheme.stat_row(tr("AI_THREAT"), "%s: %.2f" % [st.o_name[int(th[0])], float(th[1])], UITheme.WARN))
	var lines := PackedStringArray()
	for e in brain.log.last(10):
		lines.append(DecisionLog.format(e, func(o: int) -> String: return st.o_name[o] if o > 0 else ""))
	var t := UITheme.label("\n".join(lines), 11, UITheme.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 310
	_body.add_child(t)
