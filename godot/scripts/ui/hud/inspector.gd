class_name HudInspector
extends PanelContainer
## Right inspector. For a selected state: header (flag, name, kind, personality) and one row of text
## tabs — overview, diplomacy (foreign nations: treaties, aid, help — DiplomacyPanel.actions), economy
## (own state or AI debug), army, buildings, threats (+ AI debug). Attacks on a foreign state live in
## the bottom attack bar, not here. For a selected building: what it
## is, what it does with exact numbers, its state and actions. Other states' economies are hidden
## unless AI debugging is on (fog of war applies to the player too).

var hud: GameHUD
var owner_id: int = 0
var tab: String = "overview"
var _head: HBoxContainer
var _tabs: HFlowContainer
## Selected building (structure id) or -1: the inspector then shows the building page.
var structure_id: int = -1
var _body: VBoxContainer
var _tab_buttons: Dictionary = {}
var _dirty: bool = true


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, 10, Color.TRANSPARENT, 12))
	custom_minimum_size.x = 300
	var v := UITheme.vbox(10)
	add_child(v)
	_head = UITheme.hbox(10)
	v.add_child(_head)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 0)
	_tabs.add_theme_constant_override("v_separation", 2)
	v.add_child(_tabs)
	for id: String in ["overview", "diplomacy", "economy", "army", "buildings", "threats", "ai"]:
		var tid := id
		var b := UITheme.ghost_button(tr("TABX_" + id.to_upper()), func() -> void: set_tab(tid))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 26
		b.add_theme_font_size_override("font_size", UITheme.T_CAPTION)
		for st_name: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var bg := Color.TRANSPARENT
			if st_name == "hover":
				bg = Color(1, 1, 1, 0.05)
			elif st_name != "normal":
				bg = Color(1, 1, 1, 0.09)
			var sb := UITheme.box(bg, UITheme.R_S, Color.TRANSPARENT, 0)
			sb.content_margin_left = 7
			sb.content_margin_right = 7
			b.add_theme_stylebox_override(st_name, sb)
		Hints.attach(b, {"title": tr("TABX_" + id.to_upper()), "text": tr("TABX_%s_HINT" % id.to_upper())})
		_tab_buttons[id] = b
		_tabs.add_child(b)
	v.add_child(UITheme.separator())
	_body = UITheme.vbox(6)
	v.add_child(_body)
	visible = false


func show_owner(id: int) -> void:
	owner_id = id
	structure_id = -1
	visible = id > 0 and not hud.ui_hidden
	_dirty = true
	if visible:
		refresh(true)
		Anim.slide_in(self, Vector2(16, 0), 0.16)


func set_tab(t: String) -> void:
	tab = t
	refresh(true)


## Shows the building page of structure `sid`.
func show_structure(sid: int) -> void:
	structure_id = sid
	visible = sid >= 0 and not hud.ui_hidden
	_dirty = true
	if visible:
		refresh(true)


func refresh(force: bool = false) -> void:
	if not visible:
		return
	if structure_id >= 0:
		if force or _dirty or not get_global_rect().has_point(get_viewport().get_mouse_position()):
			_dirty = false
			_structure_page()
		return
	if owner_id <= 0:
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
	var diplo_ok := not mine and sim.player_id > 0 and st.o_kind[id] != Rules.KIND_TRIBE
	(_tab_buttons["diplomacy"] as Button).visible = diplo_ok
	if tab == "diplomacy" and not diplo_ok:
		tab = "overview"
	var econ_ok := mine or hud.ai_debug
	(_tab_buttons["economy"] as Button).visible = econ_ok
	if tab == "economy" and not econ_ok:
		tab = "overview"
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == tab
	for c in _head.get_children():
		c.queue_free()
	_head.add_child(UITheme.flag_rect(hud.flag_of(id), 48, 32))
	var nv := UITheme.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(UITheme.label(st.o_name[id], UITheme.T_TITLE, ColorAccess.color(st.o_color[id]).lightened(0.35), true))
	var kind := tr("KIND_PLAYER") if mine else (tr("KIND_TRIBE") if st.o_kind[id] == Rules.KIND_TRIBE else tr("KIND_NATION"))
	var brain := sim.ai.brain_of(id)
	if brain != null and brain is StrategicAI:
		kind += " · " + tr("PERS_" + brain.personality_id.to_upper())
	nv.add_child(UITheme.label(kind, UITheme.T_CAPTION, UITheme.TEXT_DIM))
	_head.add_child(nv)
	var close := UITheme.icon_button("ui_close", "", func() -> void: hud.ctl.select_owner(0), 30)
	Hints.attach(close, {"title": tr("CLOSE"), "text": tr("PANEL_CLOSE_HINT")})
	_head.add_child(close)
	_tabs.visible = true
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"overview":
			_body.add_child(UITheme.stat_row(tr("INFO_LAND"), "%s (%.1f%%)" % [UITheme.num(float(st.o_tiles[id])), st.land_share(id) * 100.0], UITheme.TEXT, "r_land"))
			_body.add_child(UITheme.stat_row(tr("INFO_TROOPS"), UITheme.num(st.o_troops[id]), UITheme.ARMY, "r_army"))
			_body.add_child(UITheme.stat_row(tr("INFO_RANK"), "#%d" % hud.rank_of(id), UITheme.TEXT, "ui_trophy"))
			_body.add_child(UITheme.stat_row(tr("INFO_STATUS"), HudPanels.status_of(sim, id), UITheme.TEXT, "ui_flag"))
			if diplo_ok:
				var rel := sim.diplomacy.relation(sim.player_id, id)
				_body.add_child(UITheme.stat_row(tr("DIPLO_RELATION"), DiplomacyPanel.relation_line(sim, id), DiplomacyPanel.rel_color(rel), DiplomacyPanel.REL_ICON[rel]))
			if not mine:
				var ratio := st.o_troops[sim.player_id] / maxf(st.o_troops[id], 1.0)
				_body.add_child(UITheme.stat_row(tr("INFO_POWER_RATIO"), _ratio_text(ratio), UITheme.GOOD if ratio >= 1.0 else UITheme.BAD, "ui_swords"))
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
		"diplomacy":
			DiplomacyPanel.actions(hud, _body, id)
		"ai":
			_ai(id)


func _hidden() -> void:
	var l := UITheme.label(tr("INFO_HIDDEN"), UITheme.T_BODY, UITheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	_body.add_child(l)


## "×0.42", "×3.5", "×120" — fewer digits the further the ratio is from 1.
static func _ratio_text(r: float) -> String:
	if r >= 10.0:
		return "×%s" % UITheme.num(roundf(r))
	if r >= 1.0:
		return "×%.1f" % r
	return "×%.2f" % r


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
		match k:
			"target":
				vs = st.o_name[int(v)] if int(v) > 0 else tr("AI_NONE")
			"kind":
				vs = tr("AI_KIND_" + vs.to_upper())
			"difficulty":
				vs = tr("DIFF_" + vs.to_upper())
			"personality":
				vs = tr("PERS_" + vs.to_upper())
			"state":
				vs = tr("AI_STATE_" + vs.to_upper())
			"note":
				vs = (tr("AI_SAVING_FOR") % BuildingInfo.title(hud.sim.rules, hud.sim.rules.building_index(vs.get_slice(" ", 2)))) if vs.begins_with("saving for ") else (vs if vs != "" else tr("AI_NONE"))
		_body.add_child(UITheme.stat_row(tr("AI_K_" + k.to_upper()), vs))
	if d.has("threats"):
		for th: Array in d["threats"]:
			_body.add_child(UITheme.stat_row(tr("AI_THREAT"), "%s: %.2f" % [st.o_name[int(th[0])], float(th[1])], UITheme.WARN))
	var lines := PackedStringArray()
	for e in brain.log.last(10):
		lines.append(DecisionLog.format(e, func(o: int) -> String: return st.o_name[o] if o > 0 else ""))
	var t := UITheme.label("\n".join(lines), 11, UITheme.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 270
	_body.add_child(t)


## Building page: symbol, name, owner; what it does with exact numbers; state; actions.
func _structure_page() -> void:
	var sim := hud.sim
	if structure_id >= sim.structures.structs.size():
		return
	var s: StructureSystem.Structure = sim.structures.structs[structure_id]
	if not s.alive:
		hud.ctl.select_structure(-1)
		return
	for c in _head.get_children():
		c.queue_free()
	for c in _body.get_children():
		c.queue_free()
	_tabs.visible = false
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_3, UITheme.R_M, Color.TRANSPARENT, 6))
	plate.add_child(Icons.rect(Symbols.building_id(sim.rules, s.kind), 36))
	_head.add_child(plate)
	var nv := UITheme.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(UITheme.label(BuildingInfo.title(sim.rules, s.kind), UITheme.T_TITLE, UITheme.TEXT, true))
	var who := UITheme.hbox(6)
	var sw := ColorRect.new()
	sw.color = ColorAccess.color(sim.st.o_color[s.owner])
	sw.custom_minimum_size = Vector2(8, 8)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(sw)
	who.add_child(UITheme.label(sim.st.o_name[s.owner], UITheme.T_CAPTION, UITheme.TEXT_DIM))
	nv.add_child(who)
	_head.add_child(nv)
	var close := UITheme.icon_button("ui_close", "", func() -> void: hud.ctl.select_structure(-1), 30)
	Hints.attach(close, {"title": tr("CLOSE"), "text": tr("PANEL_CLOSE_HINT")})
	_head.add_child(close)
	var d := BuildingInfo.structure_hint(sim, s)
	var short := UITheme.label(String(d["text"]), UITheme.T_BODY, UITheme.TEXT_DIM)
	short.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	short.custom_minimum_size.x = 270
	_body.add_child(short)
	_body.add_child(UITheme.section(tr("BI_EFFECT")))
	for line in BuildingInfo.effects(sim.rules, s.kind):
		var l := UITheme.label(line, UITheme.T_BODY, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 270
		_body.add_child(l)
	_body.add_child(UITheme.separator())
	for r: Array in d["rows"]:
		if String(r[0]) == tr("BI_OWNER"):
			continue  # the owner is already under the title
		_body.add_child(UITheme.key_value(String(r[0]), String(r[1]), r[2] if r.size() > 2 else UITheme.TEXT))
	if s.done_tick > 0:
		var total := float(sim.rules.building_ticks(s.kind))
		_body.add_child(UITheme.progress(clampf(1.0 - float(s.done_tick - sim.st.tick) / total, 0.0, 1.0), UITheme.ACCENT, 6))
	var pid := sim.player_id
	if s.owner == pid and sim.rules.building_upgradable(s.kind) and s.done_tick == 0 and sim.phase == Sim.Phase.PLAYING:
		var reason := BuildingInfo.blocker(sim, s.kind, pid)
		var up := UITheme.accent_button(tr("BI_UPGRADE") % [s.level + 1, UITheme.num(sim.structures.cost(pid, s.kind))],
			func() -> void: hud.ctl.upgrade_structure(s.id), 0, "ui_plus")
		Hints.disable(up, reason)
		Hints.attach(up, func() -> Dictionary: return {"title": tr("BI_UPGRADE_TITLE"), "text": tr("BI_UPGRADE_HINT"), "reason": reason})
		_body.add_child(up)
		if reason != "":
			var rl := UITheme.label(reason, UITheme.T_CAPTION, UITheme.BAD)
			_body.add_child(rl)
	if s.owner != pid:
		_body.add_child(UITheme.button(tr("BI_SHOW_OWNER"), func() -> void: hud.ctl.select_owner(s.owner), 0, "ui_flag"))
