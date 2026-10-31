extends ScreenBase
## Achievements by category; hidden ones stay "???" until unlocked; progress bars where countable.

var _grid: GridContainer
var _cat: String = ""


func _ready() -> void:
	var c := build_frame(tr("MENU_ACHIEVEMENTS"), 1180)
	var p: ProfileData = Profile.data
	var done := (p.data["achievements"] as Dictionary).size()
	var head := UITheme.hbox(12)
	head.add_child(UITheme.label(tr("ACH_COUNT") % [done, MetaData.achievements().size()], UITheme.T_BODY_L, UITheme.TEXT_DIM))
	head.add_child(UITheme.spacer())
	var tabs := UITheme.hbox(4)
	for cat in [""] + MetaData.json("achievements")["categories"]:
		var b := UITheme.ghost_button(tr("ACH_CAT_" + (cat.to_upper() if cat != "" else "ALL")), func() -> void: _show(cat))
		b.toggle_mode = true
		b.button_group = _group
		b.button_pressed = cat == ""
		tabs.add_child(b)
	head.add_child(tabs)
	c.add_child(head)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, maxf(320.0, get_viewport_rect().size.y - 260.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(_grid)
	_show("")
	var row := UITheme.hbox(12)
	row.add_child(back_button())
	c.add_child(row)
	footer()


var _group := ButtonGroup.new()


func _show(cat: String) -> void:
	_cat = cat
	for ch in _grid.get_children():
		ch.queue_free()
	var p: ProfileData = Profile.data
	for a: Dictionary in MetaData.achievements():
		if cat != "" and a["category"] != cat:
			continue
		_grid.add_child(_card(p, a))


func _card(p: ProfileData, a: Dictionary) -> Control:
	var got := AchievementSystem.unlocked(p, String(a["id"]))
	var secret := bool(a["hidden"]) and not got
	var card := UITheme.card(12, UITheme.GOLD if got else Color.TRANSPARENT)
	card.custom_minimum_size = Vector2(380, 0)
	var h := UITheme.hbox(12)
	card.add_child(h)
	h.add_child(Icons.rect("ui_lock" if secret else String(a["icon"]), 36, UITheme.GOLD if got else UITheme.TEXT_FAINT))
	var v := UITheme.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UITheme.label("???" if secret else MetaData.text(a["name"]), UITheme.T_BODY_L, UITheme.TEXT if got else UITheme.TEXT_DIM, true))
	var d := UITheme.label(tr("ACH_HIDDEN") if secret else MetaData.text(a["desc"]), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 280
	v.add_child(d)
	if got:
		v.add_child(UITheme.label(tr("ACH_UNLOCKED_ON") % Time.get_date_string_from_unix_time(int(p.data["achievements"][a["id"]])), UITheme.T_CAPTION, UITheme.GOOD))
	elif not secret:
		var cond: Dictionary = a["condition"]
		if cond["scope"] != "match":
			var pr := Conditions.progress(cond, p)
			v.add_child(UITheme.progress(pr.x / maxf(pr.y, 1.0), UITheme.ACCENT, 4))
		if not secret:
			v.add_child(ItemView.reward_line(a["reward"]))
	return card
