class_name HudPanels
extends RefCounted
## Builders of the HUD panels (left dock and inspector tabs). Each fills a container from the
## current simulation state.


static func _per_sec(v: float) -> String:
	return "%s%s/%s" % ["+" if v >= 0.0 else "", UITheme.num(v * 10.0), TranslationServer.translate("PER_SEC")]


static func state(hud: GameHUD, body: VBoxContainer) -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var head := UITheme.hbox(10)
	head.add_child(UITheme.flag_rect(hud.flag_of(pid), 54, 36))
	var nv := UITheme.vbox(2)
	nv.add_child(UITheme.label(st.o_name[pid], UITheme.T_TITLE, UITheme.TEXT, true))
	nv.add_child(UITheme.label(tr_("HUD_RANK") % hud.rank_of(pid), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	head.add_child(nv)
	body.add_child(head)
	body.add_child(UITheme.section(tr_("SEC_TERRITORY"), "r_land"))
	body.add_child(UITheme.stat_row(tr_("INFO_LAND"), "%s (%.1f%%)" % [UITheme.num(float(st.o_tiles[pid])), st.land_share(pid) * 100.0]))
	body.add_child(UITheme.stat_row(tr_("END_PEAK"), UITheme.num(float(st.o_st_peak_tiles[pid]))))
	body.add_child(UITheme.stat_row(tr_("INFO_STATUS"), status_of(sim, pid)))
	body.add_child(UITheme.section(tr_("SEC_BUILDINGS"), "ui_building"))
	var any := false
	for k in sim.rules.b_kinds.size():
		var lv := st.blevel(pid, k)
		var owned := st.bowned(pid, k)
		if owned > 0:
			any = true
			var id := sim.rules.b_ids[k]
			var row := UITheme.stat_row(tr_("B_" + id.to_upper()), "%d%s" % [lv, (" (+%d)" % (owned - lv)) if owned > lv else ""], UITheme.TEXT, "b_" + id)
			body.add_child(row)
	if not any:
		body.add_child(UITheme.label(tr_("NO_BUILDINGS"), UITheme.T_BODY, UITheme.TEXT_FAINT))


static func army(hud: GameHUD, body: VBoxContainer) -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var cap := maxf(st.o_cap[pid], 1.0)
	body.add_child(UITheme.section(tr_("SEC_ARMY"), "r_army"))
	body.add_child(UITheme.stat_row(tr_("MIL_TROOPS"), UITheme.num(st.o_troops[pid]), UITheme.ARMY))
	body.add_child(UITheme.progress(st.o_troops[pid] / cap, UITheme.ARMY.darkened(0.2), 6))
	body.add_child(UITheme.stat_row(tr_("MIL_CAP"), UITheme.num(cap)))
	body.add_child(UITheme.stat_row(tr_("MIL_GROWTH"), _per_sec(st.o_growth[pid]), UITheme.GOOD if st.o_growth[pid] >= 0.0 else UITheme.BAD))
	body.add_child(UITheme.stat_row(tr_("MIL_IN_ATTACKS"), UITheme.num(sim.attacks.troops_in_attacks(pid))))
	var hint := UITheme.label(tr_("HUD_ARMY_TIP"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 320
	body.add_child(hint)
	body.add_child(UITheme.section(tr_("HUD_ATTACKS"), "g_attack"))
	var any := false
	for a in sim.attacks.attacks:
		if not a.alive:
			continue
		if a.attacker == pid:
			any = true
			var c := UITheme.card(8)
			var h := UITheme.hbox(8)
			c.add_child(h)
			h.add_child(Icons.rect("g_landing" if a.landing else "g_attack", 18, UITheme.GOOD))
			var tn: String = tr_("FREE_LAND") if a.target == 0 else st.o_name[a.target]
			var v := UITheme.vbox(0)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(UITheme.label(tn, UITheme.T_BODY, UITheme.TEXT, true))
			v.add_child(UITheme.label(tr_("ATTACK_LINE") % [UITheme.num(a.troops), a.taken], UITheme.T_CAPTION, UITheme.TEXT_DIM))
			h.add_child(v)
			if a.retreat_at == 0:
				var aid := a.id
				h.add_child(UITheme.icon_button("ui_back", tr_("HUD_RETREAT_TIP"), func() -> void: hud.ctl.retreat(aid), 32))
			else:
				h.add_child(UITheme.badge(tr_("HUD_RETREATING"), UITheme.WARN))
			body.add_child(c)
		elif a.target == pid:
			any = true
			var c2 := UITheme.card(8, Color(UITheme.BAD, 0.5))
			c2.add_child(UITheme.icon_label("g_defense", tr_("INCOMING_LINE") % [st.o_name[a.attacker], UITheme.num(a.troops)], UITheme.BAD))
			body.add_child(c2)
	for b in sim.naval.boats:
		if b.alive and b.owner == pid:
			any = true
			body.add_child(UITheme.icon_label("g_landing", tr_("BOAT_LINE") % UITheme.num(b.troops), UITheme.ACCENT))
	if not any:
		body.add_child(UITheme.label(tr_("HUD_NO_ATTACKS"), UITheme.T_BODY, UITheme.TEXT_FAINT))
	body.add_child(UITheme.section(tr_("SEC_TOTALS"), "ui_stats"))
	body.add_child(UITheme.stat_row(tr_("MIL_ATTACKS"), str(st.o_st_attacks[pid])))
	body.add_child(UITheme.stat_row(tr_("MIL_CONQUERED"), UITheme.num(float(st.o_st_conquered[pid]))))
	body.add_child(UITheme.stat_row(tr_("MIL_LOST"), UITheme.num(st.o_st_troops_lost[pid])))


static func economy(hud: GameHUD, body: VBoxContainer) -> void:
	economy_of(hud, body, hud.sim.player_id)


static func economy_of(hud: GameHUD, body: VBoxContainer, id: int) -> void:
	var sim := hud.sim
	var st := sim.st
	var r := sim.rules
	var cities := st.blevel(id, Rules.B_CITY)
	var base := float(r.e["gold_base"]) + float(r.e["gold_value_mult"]) * sqrt(maxf(st.o_value[id] * r.k_area, 0.0))
	body.add_child(UITheme.section(tr_("SEC_TREASURY"), "r_gold"))
	body.add_child(UITheme.stat_row(tr_("ECO_GOLD"), UITheme.num(st.o_gold[id]), UITheme.GOLD))
	body.add_child(UITheme.stat_row(tr_("ECO_SUPPLIES"), "%s (%s)" % [UITheme.num(st.o_supplies[id]), _per_sec(st.o_supply_income[id])], UITheme.SUPPLY))
	body.add_child(UITheme.section(tr_("SEC_INCOME"), "g_economy"))
	body.add_child(UITheme.stat_row(tr_("ECO_TERRITORY"), _per_sec(base)))
	body.add_child(UITheme.stat_row(tr_("ECO_CITIES"), _per_sec(float(cities) * float(r.e["gold_city"]))))
	body.add_child(UITheme.stat_row(tr_("ECO_TRADE"), _per_sec(st.o_port_trade[id])))
	body.add_child(UITheme.stat_row(tr_("ECO_FACTORIES"), "+%d%%" % int(minf(float(st.blevel(id, Rules.B_FACTORY)) * float(r.e["factory_income_bonus"]), r.e["factory_income_bonus_max"]) * 100.0)))
	body.add_child(UITheme.stat_row(tr_("ECO_INCOME"), _per_sec(st.o_income[id]), UITheme.GOOD))
	body.add_child(UITheme.stat_row(tr_("ECO_UPKEEP"), _per_sec(-st.o_upkeep[id]), UITheme.BAD))
	var net := st.o_income[id] - st.o_upkeep[id]
	body.add_child(UITheme.stat_row(tr_("ECO_NET"), _per_sec(net), UITheme.GOOD if net >= 0.0 else UITheme.BAD))
	if net < 0.0:
		var w := UITheme.label(tr_("HUD_UPKEEP_TIP"), UITheme.T_CAPTION, UITheme.WARN)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size.x = 300
		body.add_child(w)
	body.add_child(UITheme.section(tr_("SEC_TOTALS"), "ui_stats"))
	body.add_child(UITheme.stat_row(tr_("ECO_EARNED"), UITheme.num(st.o_st_gold_earned[id])))
	body.add_child(UITheme.stat_row(tr_("ECO_SPENT"), UITheme.num(st.o_st_gold_spent[id] + st.o_st_upkeep_paid[id])))


static func build(hud: GameHUD, body: VBoxContainer) -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var playing := sim.phase == Sim.Phase.PLAYING and sim.is_player_alive()
	for k in GameHUD.build_kinds(sim.rules):
		var id := sim.rules.b_ids[k]
		var cost := sim.structures.cost(pid, k)
		var sup := sim.rules.building_supplies(k)
		var afford := sim.structures.can_afford(pid, k)
		var c := UITheme.card(10, UITheme.ACCENT if hud.ctl.build_kind == k else Color.TRANSPARENT)
		var h := UITheme.hbox(10)
		c.add_child(h)
		var ic := PanelContainer.new()
		ic.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.05), UITheme.R_M, Color.TRANSPARENT, 6))
		ic.add_child(Icons.rect("b_" + id, 30, UITheme.TEXT))
		h.add_child(ic)
		var v := UITheme.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UITheme.label(tr_("B_" + id.to_upper()), UITheme.T_BODY_L, UITheme.TEXT, true))
		var d := UITheme.label(tr_("B_%s_TIP" % id.to_upper()), UITheme.T_CAPTION, UITheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 200
		v.add_child(d)
		var price := UITheme.hbox(10)
		price.add_child(UITheme.icon_label("r_gold", UITheme.num(cost), UITheme.GOLD if st.o_gold[pid] >= cost else UITheme.BAD, UITheme.T_CAPTION))
		if sup > 0.0:
			price.add_child(UITheme.icon_label("r_supplies", UITheme.num(sup), UITheme.SUPPLY if st.o_supplies[pid] >= sup else UITheme.BAD, UITheme.T_CAPTION))
		price.add_child(UITheme.icon_label("ui_clock", "%d %s" % [sim.rules.building_ticks(k) / 10, tr_("SEC_SHORT")], UITheme.TEXT_DIM, UITheme.T_CAPTION))
		v.add_child(price)
		var unlocked := sim.structures.unlocked(pid, k)
		if not unlocked:
			var req := ResearchSystem.tech(sim.rules.building_requires(k))
			v.add_child(UITheme.icon_label("ui_lock", tr_("BUILD_REQUIRES") % MetaData.text(req.get("name", {})), UITheme.WARN, UITheme.T_CAPTION))
			c.modulate.a = 0.7
		h.add_child(v)
		var kk := k
		var b := UITheme.button(tr_("BUILD"), func() -> void: hud.ctl.begin_build(kk), 0, "ui_plus")
		b.disabled = not playing or not afford or not unlocked
		h.add_child(b)
		body.add_child(c)


static func events(hud: GameHUD, body: VBoxContainer) -> void:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.custom_minimum_size.x = 320
	t.add_theme_font_size_override("normal_font_size", UITheme.T_CAPTION + 1)
	var lines := hud.log_lines.duplicate()
	lines.reverse()
	t.text = "\n".join(lines) if not lines.is_empty() else tr_("LOG_EMPTY")
	body.add_child(t)


static func status_of(sim: Sim, id: int) -> String:
	var st := sim.st
	if st.o_alive[id] == 0:
		return tr_("STATUS_DEAD")
	var out := 0
	var inc := 0
	for a in sim.attacks.attacks:
		if a.alive and a.attacker == id and a.target != 0:
			out += 1
		if a.alive and a.target == id:
			inc += 1
	if inc > 0:
		return tr_("STATUS_INVADED") % inc
	if out > 0:
		return tr_("STATUS_AT_WAR") % out
	return tr_("STATUS_PEACE")


static func tr_(k: String) -> String:
	return TranslationServer.translate(k)


## Research: the current research with its progress, RP per second, then every branch with its
## technologies (researched / available / locked by prerequisites) and what each one does.
static func research(hud: GameHUD, body: VBoxContainer) -> void:
	var sim := hud.sim
	var pid := sim.player_id
	if pid <= 0:
		return
	var rs := sim.research
	var rate := rs.rate(pid) * float(sim.rules.tick_rate)
	var head := UITheme.card(10)
	var hv := UITheme.vbox(4)
	head.add_child(hv)
	hv.add_child(UITheme.stat_row(tr_("RESEARCH_RATE"), "%.1f %s" % [rate, tr_("RESEARCH_PER_SEC")], UITheme.RESEARCH, "r_research"))
	var cur := rs.current(pid)
	if cur != "":
		var t := ResearchSystem.tech(cur)
		var p := rs.progress(pid, cur)
		hv.add_child(UITheme.label(MetaData.text(t["name"]), UITheme.T_BODY_L, UITheme.TEXT, true))
		hv.add_child(UITheme.progress(p / float(t["cost"]), UITheme.RESEARCH, 6))
		var left := (float(t["cost"]) - p) / maxf(rate, 0.01)
		hv.add_child(UITheme.label(tr_("RESEARCH_ETA") % [int(p), int(t["cost"]), int(left / 60.0), int(left) % 60], UITheme.T_CAPTION, UITheme.TEXT_DIM))
	else:
		hv.add_child(UITheme.label(tr_("RESEARCH_IDLE"), UITheme.T_BODY, UITheme.WARN))
	body.add_child(head)
	for br: String in ResearchSystem.tree()["branches"]:
		body.add_child(UITheme.section(tr_("BRANCH_" + br.to_upper()), _branch_icon(br)))
		for t: Dictionary in ResearchSystem.techs():
			if t["branch"] != br:
				continue
			body.add_child(_tech_card(hud, t))


static func _branch_icon(br: String) -> String:
	return {"economy": "g_economy", "military": "g_military", "defense": "g_defense", "logistics": "g_logistics",
		"strategic": "g_strategic", "intelligence": "g_intel", "diplomacy": "g_diplomacy"}.get(br, "r_research")


static func _tech_card(hud: GameHUD, t: Dictionary) -> Control:
	var sim := hud.sim
	var pid := sim.player_id
	var rs := sim.research
	var id := String(t["id"])
	var done := rs.has_tech(pid, id)
	var avail := rs.available(pid, id)
	var cur := rs.current(pid) == id
	var c := UITheme.card(8, UITheme.RESEARCH if cur else (UITheme.GOOD if done else Color.TRANSPARENT))
	var v := UITheme.vbox(3)
	c.add_child(v)
	var h := UITheme.hbox(6)
	h.add_child(Icons.rect("ui_check" if done else ("r_research" if avail else "ui_lock"), 16,
		UITheme.GOOD if done else (UITheme.RESEARCH if avail else UITheme.TEXT_FAINT)))
	var n := UITheme.label(MetaData.text(t["name"]), UITheme.T_BODY, UITheme.TEXT if done or avail else UITheme.TEXT_DIM, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	if not done:
		h.add_child(UITheme.label("%d RP" % int(t["cost"]), UITheme.T_CAPTION, UITheme.RESEARCH))
	v.add_child(h)
	var d := UITheme.label(MetaData.text(t["desc"]), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 280
	v.add_child(d)
	if not done and not avail:
		var names := PackedStringArray()
		for r: String in t["requires"]:
			if not rs.has_tech(pid, r):
				names.append(MetaData.text(ResearchSystem.tech(r)["name"]))
		v.add_child(UITheme.label(tr_("RESEARCH_NEEDS") % ", ".join(names), UITheme.T_CAPTION, UITheme.WARN))
	var p := rs.progress(pid, id)
	if p > 0.0 and not done:
		v.add_child(UITheme.progress(p / float(t["cost"]), UITheme.RESEARCH, 4))
	if avail and not cur and sim.phase == Sim.Phase.PLAYING and sim.is_player_alive():
		v.add_child(UITheme.button(tr_("RESEARCH_START"), func() -> void: hud.ctl.start_research(id), 0, "r_research"))
	return c
