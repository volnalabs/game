extends ScreenBase
## Profile: identity (name, avatar, frame, emblem, title), level, currencies, statistics by map and
## difficulty, recent matches and the rarest items.

var _name_edit: LineEdit


func _ready() -> void:
	var c := build_frame(tr("PROFILE_TITLE"), 1180)
	var p: ProfileData = Profile.data
	var row := UITheme.hbox(16)
	c.add_child(row)
	# Identity card.
	var id_card := UITheme.panel(18)
	id_card.custom_minimum_size = Vector2(380, 0)
	row.add_child(id_card)
	var iv := UITheme.vbox(10)
	id_card.add_child(iv)
	var head := UITheme.hbox(14)
	head.add_child(Cosmetics.avatar_widget(96))
	var nv := UITheme.vbox(4)
	_name_edit = LineEdit.new()
	_name_edit.text = String(p.data["name"])
	_name_edit.placeholder_text = tr("PROFILE_DEFAULT_NAME")
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size.x = 220
	_name_edit.text_submitted.connect(func(t: String) -> void: Profile.rename(t))
	_name_edit.focus_exited.connect(func() -> void: Profile.rename(_name_edit.text))
	nv.add_child(_name_edit)
	var title := Cosmetics.title()
	if title != "":
		nv.add_child(UITheme.label(title, UITheme.T_BODY, UITheme.ACCENT, true))
	var em := UITheme.hbox(6)
	em.add_child(Icons.rect(Cosmetics.emblem_icon(), 22, UITheme.TEXT))
	em.add_child(UITheme.label(MetaData.text(MetaData.item(p.equipped("emblem")).get("name", {})), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	nv.add_child(em)
	head.add_child(nv)
	iv.add_child(head)
	var lv := Progression.level_for(p.xp())
	iv.add_child(UITheme.label(tr("PROFILE_LEVEL") % p.level(), UITheme.T_TITLE, UITheme.TEXT, true))
	iv.add_child(UITheme.progress(float(lv["into"]) / float(lv["need"]), UITheme.XP, 8))
	iv.add_child(UITheme.label(tr("PROFILE_XP") % [int(lv["into"]), int(lv["need"])], UITheme.T_CAPTION, UITheme.TEXT_DIM))
	iv.add_child(UITheme.separator())
	iv.add_child(UITheme.stat_row(tr("CUR_CREDITS"), UITheme.num(float(p.credits())), UITheme.CREDITS, "r_credits"))
	iv.add_child(UITheme.stat_row(tr("CUR_FRAGMENTS"), UITheme.num(float(p.fragments())), UITheme.TEXT, "r_fragments"))
	iv.add_child(UITheme.stat_row(tr("CUR_SKILL_POINTS"), str(int(p.data["skill_points"])), UITheme.RESEARCH, "m_perks"))
	iv.add_child(UITheme.stat_row(tr("PROFILE_ITEMS"), "%d / %d" % [p.owned_ids().size(), MetaData.items().size()], UITheme.TEXT, "m_inventory"))
	iv.add_child(UITheme.stat_row(tr("PROFILE_ACHIEVEMENTS"), "%d / %d" % [(p.data["achievements"] as Dictionary).size(), MetaData.achievements().size()], UITheme.TEXT, "m_achievements"))
	var bh := UITheme.hbox(8)
	bh.add_child(UITheme.button(tr("MENU_INVENTORY"), func() -> void: App.goto(App.State.INVENTORY), 0, "m_inventory"))
	bh.add_child(UITheme.button(tr("MENU_ACHIEVEMENTS"), func() -> void: App.goto(App.State.ACHIEVEMENTS), 0, "m_achievements"))
	iv.add_child(bh)
	# Statistics and history.
	var right := UITheme.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var s: Dictionary = p.data["stats"]
	var tiles := UITheme.hbox(10)
	for e: Array in [["PROFILE_MATCHES", str(int(s["matches"])), "m_new_game"], ["PROFILE_WINS", str(int(s["wins"])), "g_victory"],
			["PROFILE_WINRATE", "%d%%" % roundi(100.0 * float(s["wins"]) / maxf(float(s["matches"]), 1.0)), "ui_chart"],
			["PROFILE_HOURS", "%.1f" % (float(s["minutes"]) / 60.0), "ui_clock"],
			["PROFILE_CONQUERED", UITheme.num(float(s["conquered"])), "g_attack"], ["PROFILE_ELIMS", str(int(s["eliminations"])), "g_skull"]]:
		var t := UITheme.card(10)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tv := UITheme.vbox(2)
		t.add_child(tv)
		tv.add_child(Icons.rect(e[2], 22, UITheme.ACCENT))
		tv.add_child(UITheme.label(e[1], UITheme.T_TITLE, UITheme.TEXT, true))
		tv.add_child(UITheme.caption(tr(e[0])))
		tiles.add_child(t)
	right.add_child(tiles)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 380)
	right.add_child(tabs)
	tabs.add_child(_table(tr("PROFILE_BY_MAP"), s["by_map"], func(k: String) -> String:
		var d := MapRegistry.get_map(k)
		return d.display_name() if d != null else (tr("RANDOM_WORLD") if k == "generated" else k)))
	tabs.add_child(_table(tr("PROFILE_BY_DIFFICULTY"), s["by_difficulty"], func(k: String) -> String: return tr("DIFF_" + k.to_upper())))
	tabs.add_child(_history(p))
	var row2 := UITheme.hbox(12)
	row2.add_child(back_button())
	c.add_child(row2)
	footer()


func _table(name_: String, table: Dictionary, label_of: Callable) -> Control:
	var sc := ScrollContainer.new()
	sc.name = name_
	var v := UITheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	if table.is_empty():
		v.add_child(UITheme.label(tr("PROFILE_NO_DATA"), UITheme.T_BODY, UITheme.TEXT_DIM))
		return sc
	var hdr := UITheme.hbox(8)
	for h in ["", "PROFILE_COL_PLAYED", "PROFILE_COL_WON", "PROFILE_COL_BEST", "PROFILE_COL_HOURS"]:
		var l := UITheme.caption(tr(h) if h != "" else "")
		l.custom_minimum_size.x = 110 if h != "" else 0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if h == "" else Control.SIZE_FILL
		hdr.add_child(l)
	v.add_child(hdr)
	for k: String in table:
		var e: Dictionary = table[k]
		var r := UITheme.hbox(8)
		var n := UITheme.label(String(label_of.call(k)), UITheme.T_BODY)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		for val in [str(int(e["played"])), str(int(e["won"])), "%.1f%%" % (float(e["best_share"]) * 100.0), "%.1f" % (float(e["minutes"]) / 60.0)]:
			var l := UITheme.label(val, UITheme.T_BODY, UITheme.TEXT_DIM)
			l.custom_minimum_size.x = 110
			r.add_child(l)
		v.add_child(r)
	return sc


func _history(p: ProfileData) -> Control:
	var sc := ScrollContainer.new()
	sc.name = tr("PROFILE_HISTORY")
	var v := UITheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var h: Array = p.data["history"]
	if h.is_empty():
		v.add_child(UITheme.label(tr("PROFILE_NO_DATA"), UITheme.T_BODY, UITheme.TEXT_DIM))
	for e: Dictionary in h:
		var r := UITheme.hbox(10)
		var won := bool(e["won"])
		var ab := bool(e.get("abandoned", false))
		r.add_child(Icons.rect("g_victory" if won else ("ui_close" if ab else "g_skull"), 18, UITheme.GOOD if won else (UITheme.TEXT_DIM if ab else UITheme.BAD)))
		r.add_child(UITheme.label(Time.get_datetime_string_from_unix_time(int(e["time"]), true).substr(0, 16), UITheme.T_CAPTION, UITheme.TEXT_DIM))
		var d := MapRegistry.get_map(String(e["map_id"]))
		var n := UITheme.label(d.display_name() if d != null else String(e["map_id"]), UITheme.T_BODY)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		r.add_child(UITheme.label(tr("DIFF_" + String(e["difficulty"]).to_upper()), UITheme.T_CAPTION, UITheme.TEXT_DIM))
		r.add_child(UITheme.label("%d %s" % [int(float(e["minutes"])), tr("MIN_SHORT")], UITheme.T_CAPTION, UITheme.TEXT_DIM))
		r.add_child(UITheme.label("#%d" % int(e.get("rank", 0)), UITheme.T_CAPTION, UITheme.TEXT_DIM))
		v.add_child(r)
	return sc
