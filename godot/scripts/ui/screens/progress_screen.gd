extends ScreenBase
## Progress: the level road (rewards of the next levels and milestones) and the challenges
## (weekly set, chains, one-time tasks) with their progress.


func _ready() -> void:
	var c := build_frame(tr("PROGRESS_TITLE"), 1180)
	var p: ProfileData = Profile.data
	QuestSystem.refresh_week(p, Profile.now())
	var lv := Progression.level_for(p.xp())
	var top := UITheme.panel(16)
	c.add_child(top)
	var tv := UITheme.vbox(8)
	top.add_child(tv)
	var hh := UITheme.hbox(12)
	hh.add_child(Icons.rect("r_xp", 32, UITheme.XP))
	hh.add_child(UITheme.label(tr("PROFILE_LEVEL") % p.level(), UITheme.T_H2, UITheme.TEXT, true))
	hh.add_child(UITheme.spacer())
	hh.add_child(UITheme.label(tr("PROFILE_XP") % [int(lv["into"]), int(lv["need"])], UITheme.T_BODY, UITheme.TEXT_DIM))
	tv.add_child(hh)
	tv.add_child(UITheme.progress(float(lv["into"]) / float(lv["need"]), UITheme.XP, 10))
	# Level road: the next 10 levels.
	var road := UITheme.hbox(8)
	for i in range(1, 11):
		var L := p.level() + i
		if L > Progression.max_level():
			break
		var r := Progression.level_rewards(L)
		var m := Progression.is_milestone(L)
		var cell := UITheme.card(8, UITheme.GOLD if m else Color.TRANSPARENT)
		cell.custom_minimum_size = Vector2(100, 96)
		var cv := UITheme.vbox(2)
		cell.add_child(cv)
		cv.add_child(UITheme.label(str(L), UITheme.T_TITLE, UITheme.GOLD if m else UITheme.TEXT, true))
		if r.has("credits"):
			cv.add_child(UITheme.icon_label("r_credits", UITheme.num(float(r["credits"])), UITheme.CREDITS, UITheme.T_CAPTION))
		for cid: String in r.get("cases", {}):
			cv.add_child(UITheme.icon_label("m_cases", "%s ×%d" % [MetaData.text(MetaData.case_def(cid)["name"]), int(r["cases"][cid])], UITheme.TEXT, UITheme.T_CAPTION))
		if r.has("skill_points"):
			cv.add_child(UITheme.icon_label("m_perks", "+%d" % int(r["skill_points"]), UITheme.RESEARCH, UITheme.T_CAPTION))
		road.add_child(cell)
	tv.add_child(road)
	# Challenges.
	var cols := UITheme.hbox(14)
	c.add_child(cols)
	var weekly := _column(tr("PROGRESS_WEEKLY") + "  ·  " + String(p.data["quests"]["week"]), "ui_clock")
	var other := _column(tr("PROGRESS_CHAINS"), "m_quests")
	cols.add_child(weekly)
	cols.add_child(other)
	for id in QuestSystem.active(p):
		var d := MetaData.quest(id)
		var target: VBoxContainer = weekly.get_meta("body") if d["kind"] == "weekly" else other.get_meta("body")
		target.add_child(_quest_card(p, d))
	var row := UITheme.hbox(12)
	row.add_child(back_button())
	c.add_child(row)
	footer()


func _column(title: String, icon: String) -> PanelContainer:
	var pn := UITheme.panel(14)
	pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pn.custom_minimum_size.y = 360
	var v := UITheme.vbox(8)
	pn.add_child(v)
	v.add_child(UITheme.section(title, icon))
	var body := UITheme.vbox(8)
	v.add_child(body)
	pn.set_meta("body", body)
	return pn


func _quest_card(p: ProfileData, d: Dictionary) -> Control:
	var id := String(d["id"])
	var done := QuestSystem.is_done(p, id)
	var card := UITheme.card(10, UITheme.GOOD if done else Color.TRANSPARENT)
	var v := UITheme.vbox(4)
	card.add_child(v)
	var h := UITheme.hbox(8)
	h.add_child(Icons.rect("ui_check" if done else "m_quests", 18, UITheme.GOOD if done else UITheme.ACCENT))
	var n := UITheme.label(MetaData.text(d["name"]), UITheme.T_BODY_L, UITheme.TEXT, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(ItemView.reward_line(d["reward"]))
	v.add_child(h)
	var pr := Conditions.progress(d["condition"], p, QuestSystem.accumulated(p, id))
	if done:
		pr = Vector2(pr.y, pr.y)
	v.add_child(UITheme.progress(pr.x / maxf(pr.y, 1.0), UITheme.GOOD if done else UITheme.ACCENT, 6))
	v.add_child(UITheme.label("%s / %s" % [UITheme.num(pr.x), UITheme.num(pr.y)], UITheme.T_CAPTION, UITheme.TEXT_DIM))
	return card
