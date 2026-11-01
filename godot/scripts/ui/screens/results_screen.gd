extends ScreenBase
## Match results: outcome, the match statistics, the reward breakdown line by line (base, victory,
## time, conquest, multipliers for difficulty / participation / repeats), level progress, and
## everything unlocked (levels, achievements, challenges, cases, items).


func _ready() -> void:
	var c := build_frame(tr("RESULTS_TITLE"), 1180)
	var r: Dictionary = Profile.last_result
	var rep: Dictionary = Profile.last_report
	if r.is_empty() or rep.is_empty():
		c.add_child(UITheme.label(tr("RESULTS_NONE"), UITheme.T_BODY_L, UITheme.TEXT_DIM))
		c.add_child(back_button())
		footer()
		return
	var won := bool(r["won"])
	var head := UITheme.hbox(14)
	var ve := Cosmetics.victory_effect()
	var icon := String(ve.get("icon", "g_victory")) if won else ("ui_close" if r["abandoned"] else "g_skull")
	var icol := Color(String(ve.get("color", "#f2c14e"))) if won else UITheme.BAD
	var ic := Icons.rect(icon, 56, icol)
	head.add_child(ic)
	var hv := UITheme.vbox(2)
	hv.add_child(UITheme.title(tr("END_VICTORY") if won else (tr("RESULTS_ABANDONED") if r["abandoned"] else tr("END_DEFEAT")), UITheme.T_H1))
	var d := MapRegistry.get_map(String(r["map_id"]))
	hv.add_child(UITheme.label("%s · %s · %d %s" % [d.display_name() if d != null else tr("RANDOM_WORLD"), tr("DIFF_" + String(r["difficulty"]).to_upper()),
		int(float(r["minutes"])), tr("MIN_SHORT")], UITheme.T_BODY_L, UITheme.TEXT_DIM))
	head.add_child(hv)
	c.add_child(head)
	if won and not ve.is_empty():
		_burst(ic, icol)
	var row := UITheme.hbox(14)
	c.add_child(row)
	# Left: match statistics.
	var left := UITheme.panel(16)
	left.custom_minimum_size.x = 360
	row.add_child(left)
	var lv := UITheme.vbox(6)
	left.add_child(lv)
	lv.add_child(UITheme.section(tr("RESULTS_MATCH"), "ui_stats"))
	lv.add_child(UITheme.stat_row(tr("RESULTS_RANK"), "#%d" % int(r["rank"]), UITheme.TEXT, "ui_trophy"))
	lv.add_child(UITheme.stat_row(tr("END_LAND"), "%.1f%%" % (float(r["share"]) * 100.0), UITheme.TEXT, "r_land"))
	lv.add_child(UITheme.stat_row(tr("END_PEAK"), UITheme.num(float(r["peak_tiles"])), UITheme.TEXT, "ui_chart"))
	lv.add_child(UITheme.stat_row(tr("MIL_CONQUERED"), UITheme.num(float(r["conquered"])), UITheme.TEXT, "g_attack"))
	lv.add_child(UITheme.stat_row(tr("RESULTS_ELIMS"), str(int(r["eliminations"])), UITheme.TEXT, "g_skull"))
	lv.add_child(UITheme.stat_row(tr("MIL_ATTACKS"), str(int(r["attacks"])), UITheme.TEXT, "ui_swords"))
	lv.add_child(UITheme.stat_row(tr("RESULTS_BUILT"), str(int(r["built"])), UITheme.TEXT, "ui_building"))
	lv.add_child(UITheme.stat_row(tr("ECO_EARNED"), UITheme.num(float(r["gold_earned"])), UITheme.GOLD, "r_gold"))
	lv.add_child(UITheme.stat_row(tr("MIL_LOST"), UITheme.num(float(r["troops_lost"])), UITheme.TEXT, "r_army"))
	lv.add_child(UITheme.stat_row(tr("RESULTS_ACTIONS"), str(int(r["actions"])), UITheme.TEXT, "ui_target"))
	# Middle: reward breakdown.
	var mid := UITheme.panel(16)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var mv := UITheme.vbox(6)
	mid.add_child(mv)
	if rep.get("duplicate", false):
		mv.add_child(UITheme.label(tr("RESULTS_ALREADY"), UITheme.T_BODY, UITheme.TEXT_DIM))
	else:
		mv.add_child(UITheme.section(tr("RESULTS_REWARDS"), "ui_gift"))
		var hdr := UITheme.hbox(8)
		hdr.add_child(UITheme.spacer())
		hdr.add_child(_cell(Icons.rect("r_xp", 16, UITheme.XP)))
		hdr.add_child(_cell(Icons.rect("r_credits", 16, UITheme.CREDITS)))
		mv.add_child(hdr)
		for ln: Dictionary in rep["lines"]:
			var h := UITheme.hbox(8)
			var txt := tr(String(ln["key"]))
			if String(ln.get("arg", "")) != "":
				txt += " (%s)" % (UITheme.num(float(ln["arg"])) if String(ln["arg"]).is_valid_float() else String(ln["arg"]))
			var l := UITheme.label(txt, UITheme.T_BODY, UITheme.TEXT_DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			if ln.has("mult"):
				var m := float(ln["mult"])
				h.add_child(_cell(UITheme.label("×%.2f" % m, UITheme.T_BODY, UITheme.GOOD if m >= 1.0 else UITheme.WARN, true), 160))
			else:
				h.add_child(_cell(UITheme.label(_signed(int(ln["xp"])), UITheme.T_BODY, UITheme.XP)))
				h.add_child(_cell(UITheme.label(_signed(int(ln["credits"])), UITheme.T_BODY, UITheme.CREDITS)))
			mv.add_child(h)
		mv.add_child(UITheme.separator())
		var tot := UITheme.hbox(8)
		var tl := UITheme.label(tr("RESULTS_TOTAL"), UITheme.T_BODY_L, UITheme.TEXT, true)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tot.add_child(tl)
		tot.add_child(_cell(UITheme.label("+" + UITheme.num(float(rep["match_xp"])), UITheme.T_BODY_L, UITheme.XP, true)))
		tot.add_child(_cell(UITheme.label("+" + UITheme.num(float(rep["match_credits"])), UITheme.T_BODY_L, UITheme.CREDITS, true)))
		mv.add_child(tot)
		var part: Dictionary = rep["participation"]
		if float(part["credits"]) < 0.999:
			var note := UITheme.label(tr("RESULTS_PARTICIPATION_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_FAINT)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = 380
			mv.add_child(note)
		# Level bar: animated from the old XP to the new.
		mv.add_child(UITheme.separator())
		var lb := UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT, true)
		mv.add_child(lb)
		var bar := UITheme.progress(0.0, UITheme.XP, 10)
		mv.add_child(bar)
		_animate_level(lb, bar, int(rep["xp_before"]), int(rep["xp_after"]))
	# Right: unlocks.
	var right := UITheme.panel(16)
	right.custom_minimum_size.x = 320
	row.add_child(right)
	var rv := UITheme.vbox(6)
	right.add_child(rv)
	rv.add_child(UITheme.section(tr("RESULTS_UNLOCKED"), "ui_sparkles"))
	var any := false
	for L: int in rep.get("levels", []):
		rv.add_child(UITheme.icon_label("r_xp", tr("TOAST_LEVEL_UP") % L, UITheme.XP))
		any = true
	for id: String in rep.get("achievements", []):
		rv.add_child(UITheme.icon_label(String(MetaData.achievement(id)["icon"]), MetaData.text(MetaData.achievement(id)["name"]), UITheme.GOLD))
		any = true
	for id: String in rep.get("quests", []):
		rv.add_child(UITheme.icon_label("m_quests", MetaData.text(MetaData.quest(id)["name"]), UITheme.GOOD))
		any = true
	for cid: String in rep.get("cases", {}):
		rv.add_child(UITheme.icon_label("m_cases", "%s ×%d" % [MetaData.text(MetaData.case_def(cid)["name"]), int(rep["cases"][cid])], UITheme.ACCENT))
		any = true
	for e: Dictionary in rep.get("items", []):
		var it := MetaData.item(String(e["item"]))
		rv.add_child(UITheme.icon_label("ui_gift", MetaData.text(it["name"]), UITheme.rarity_color(String(it["rarity"]))))
		any = true
	if int(rep.get("skill_points", 0)) > 0:
		rv.add_child(UITheme.icon_label("m_perks", tr("RESULTS_SKILL_POINTS") % int(rep["skill_points"]), UITheme.RESEARCH))
		any = true
	if not any:
		rv.add_child(UITheme.label(tr("RESULTS_NOTHING_NEW"), UITheme.T_BODY, UITheme.TEXT_DIM))
	var btns := UITheme.hbox(10)
	btns.add_child(UITheme.button(tr("PAUSE_MAIN_MENU"), func() -> void: App.goto(App.State.MAIN_MENU), 0, "ui_home"))
	btns.add_child(UITheme.button(tr("MENU_PROGRESS"), func() -> void: App.goto(App.State.PROGRESS), 0, "m_quests"))
	if not (rep.get("cases", {}) as Dictionary).is_empty():
		btns.add_child(UITheme.button(tr("MENU_CASES"), func() -> void: App.goto(App.State.CASES), 0, "m_cases"))
	btns.add_child(UITheme.spacer())
	btns.add_child(UITheme.accent_button(tr("END_NEW_GAME"), func() -> void: App.goto(App.State.MAP_SELECT), 0, "m_new_game"))
	c.add_child(btns)
	footer()


func _cell(c: Control, w: int = 80) -> Control:
	c.custom_minimum_size.x = w
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return c


func _signed(v: int) -> String:
	return ("+" if v >= 0 else "") + UITheme.num(float(v))


func _animate_level(lb: Label, bar: ProgressBar, from_xp: int, to_xp: int) -> void:
	var set_xp := func(x: float) -> void:
		var lv := Progression.level_for(int(x))
		lb.text = tr("PROFILE_LEVEL") % int(lv["level"]) + "   " + tr("PROFILE_XP") % [int(lv["into"]), int(lv["need"])]
		bar.value = float(lv["into"]) / float(lv["need"])
	set_xp.call(float(from_xp))
	if not Anim.enabled():
		set_xp.call(float(to_xp))
		return
	var t := create_tween()
	t.tween_method(set_xp, float(from_xp), float(to_xp), 1.6).set_delay(0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Victory effect of the equipped item: rings pulse out of the icon.
func _burst(anchor: Control, col: Color) -> void:
	if not Anim.enabled():
		return
	for i in 3:
		var r := TextureRect.new()
		r.texture = Icons.tex(String(Cosmetics.victory_effect().get("icon", "g_victory")), 64)
		r.modulate = Color(col, 0.8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.add_child(r)
		r.position = Vector2.ZERO
		r.size = Vector2(56, 56)
		r.pivot_offset = Vector2(28, 28)
		var t := r.create_tween().set_parallel(true)
		t.tween_property(r, "scale", Vector2(3.0, 3.0), 1.2).set_delay(i * 0.35)
		t.tween_property(r, "modulate:a", 0.0, 1.2).set_delay(i * 0.35)
