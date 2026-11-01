extends ScreenBase
## Skill tree: six branches of small sidegrade perks bought with skill points from levels; a
## limited loadout of active perks; the summed "what changes" for the next match. Fair mode
## matches ignore perks for everyone.

var _cols: HBoxContainer
var _side: VBoxContainer
var _points: Label


func _ready() -> void:
	var c := build_frame(tr("SKILLS_TITLE"), mini(int(get_viewport_rect().size.x) - 64, 1460))
	var head := UITheme.hbox(14)
	_points = UITheme.label("", UITheme.T_BODY_L, UITheme.RESEARCH, true)
	head.add_child(Icons.rect("m_perks", 22, UITheme.RESEARCH))
	head.add_child(_points)
	var note := UITheme.label(tr("SKILLS_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(note)
	head.add_child(UITheme.button(tr("SKILLS_RESET"), func() -> void:
		SkillTree.reset(Profile.data)
		Profile.save()
		_rebuild(), 0, "ui_restart"))
	c.add_child(head)
	var row := UITheme.hbox(14)
	c.add_child(row)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = maxf(340.0, get_viewport_rect().size.y - 250.0)
	row.add_child(sc)
	_cols = UITheme.hbox(10)
	sc.add_child(_cols)
	var sp := UITheme.panel(14)
	sp.custom_minimum_size.x = 300
	row.add_child(sp)
	_side = UITheme.vbox(8)
	sp.add_child(_side)
	var r2 := UITheme.hbox(12)
	r2.add_child(back_button())
	c.add_child(r2)
	footer()
	_rebuild()


func _rebuild() -> void:
	var p: ProfileData = Profile.data
	_points.text = tr("SKILLS_POINTS") % int(p.data["skill_points"])
	for ch in _cols.get_children():
		ch.queue_free()
	for br: String in MetaPerks.data()["branches"]:
		var col := UITheme.vbox(8)
		col.custom_minimum_size.x = 186
		col.add_child(UITheme.section(tr("BRANCH_" + br.to_upper()), HudPanels._branch_icon(br)))
		for d: Dictionary in MetaPerks.all():
			if d["branch"] == br:
				col.add_child(_perk_card(p, d))
		_cols.add_child(col)
	for ch in _side.get_children():
		ch.queue_free()
	var slots := MetaPerks.slots(p.level())
	var lo: Array = p.data["perks"]["loadout"]
	_side.add_child(UITheme.section(tr("SKILLS_LOADOUT") % [lo.size(), slots], "m_perks"))
	for id: String in lo:
		var h := UITheme.hbox(6)
		var n := UITheme.label(MetaData.text(MetaPerks.perk(id)["name"]), UITheme.T_BODY)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UITheme.icon_button("ui_close", tr("INV_UNEQUIP"), func() -> void:
			SkillTree.unequip(p, id)
			Profile.save()
			_rebuild(), 26))
		_side.add_child(h)
	if lo.is_empty():
		_side.add_child(UITheme.label(tr("SKILLS_EMPTY"), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	_side.add_child(UITheme.separator())
	_side.add_child(UITheme.section(tr("SKILLS_WHAT_CHANGES"), "ui_chart"))
	for ln: Dictionary in SkillTree.describe(SkillTree.loadout_modifiers(p)):
		_side.add_child(UITheme.label(String(ln["text"]), UITheme.T_BODY, UITheme.GOOD if ln["good"] else UITheme.BAD))
	var fair := UITheme.label(tr("SKILLS_FAIR_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_FAINT)
	fair.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fair.custom_minimum_size.x = 260
	_side.add_child(fair)


func _perk_card(p: ProfileData, d: Dictionary) -> Control:
	var id := String(d["id"])
	var owned := SkillTree.unlocked(p, id)
	var active := SkillTree.in_loadout(p, id)
	var block := SkillTree.unlock_block(p, id)
	var c := UITheme.card(8, UITheme.ACCENT if active else (UITheme.RESEARCH if owned else Color.TRANSPARENT))
	var v := UITheme.vbox(3)
	c.add_child(v)
	var h := UITheme.hbox(6)
	h.add_child(UITheme.label("T%d" % int(d["tier"]), UITheme.T_CAPTION, UITheme.TEXT_FAINT))
	var n := UITheme.label(MetaData.text(d["name"]), UITheme.T_BODY, UITheme.TEXT if owned else UITheme.TEXT_DIM, true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 120
	h.add_child(n)
	v.add_child(h)
	for ln: Dictionary in SkillTree.describe(d["modifiers"]):
		v.add_child(_wrap(UITheme.label(String(ln["text"]), UITheme.T_CAPTION, UITheme.GOOD if ln["good"] else UITheme.BAD)))
	if not (d["excludes"] as Array).is_empty():
		var xs := PackedStringArray()
		for x: String in d["excludes"]:
			xs.append(MetaData.text(MetaPerks.perk(x)["name"]))
		v.add_child(_wrap(UITheme.label(tr("SKILLS_EXCLUDES") % ", ".join(xs), UITheme.T_CAPTION, UITheme.WARN)))
	if active:
		v.add_child(UITheme.button(tr("INV_UNEQUIP"), func() -> void:
			SkillTree.unequip(p, id)
			Profile.save()
			_rebuild(), 0, "ui_close"))
	elif owned:
		var b := UITheme.accent_button(tr("INV_EQUIP"), func() -> void:
			SkillTree.equip(p, id)
			Profile.save()
			_rebuild(), 0, "ui_check")
		b.disabled = (p.data["perks"]["loadout"] as Array).size() >= MetaPerks.slots(p.level())
		v.add_child(b)
	elif block == "":
		v.add_child(UITheme.button(tr("SKILLS_UNLOCK") % int(d["cost"]), func() -> void:
			SkillTree.unlock(p, id)
			Profile.save()
			_rebuild(), 0, "ui_plus"))
	else:
		var why := tr("SKILLS_BLOCK_" + block.to_upper())
		if block == "level":
			why = why % int(d["level"])
		elif block == "points":
			why = why % int(d["cost"])
		v.add_child(_wrap(UITheme.label(why, UITheme.T_CAPTION, UITheme.TEXT_FAINT)))
	return c


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 160
	return l
