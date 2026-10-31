extends ScreenBase
## Main menu over a living world map: navigation on the left, profile and last match on the right.

var _compact: bool = false


func _ready() -> void:
	_compact = get_viewport_rect().size.y < 820.0
	build_backdrop(true, 0.62)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56 if side in ["left", "right"] else (24 if _compact else 44))
	add_child(margin)
	var row := UITheme.hbox(40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var nav := UITheme.vbox(2 if _compact else 6)
	nav.custom_minimum_size.x = 380
	row.add_child(nav)
	var logo := UITheme.title("VOLNA", UITheme.T_H1 if _compact else UITheme.T_DISPLAY)
	nav.add_child(logo)
	var sub := UITheme.caption(tr("GAME_SUBTITLE"), UITheme.ACCENT)
	sub.add_theme_font_size_override("font_size", UITheme.T_BODY)
	nav.add_child(sub)
	nav.add_child(_gap(6 if _compact else 18))
	var cont := _continue_path()
	_section(nav, tr("MENU_SEC_PLAY"))
	_item(nav, "m_new_game", tr("MENU_NEW_GAME"), func() -> void: App.goto(App.State.MAP_SELECT), true)
	if cont != "":
		_item(nav, "ui_play", tr("MENU_CONTINUE"), func() -> void: App.load_match(cont))
	_item(nav, "ui_load", tr("MENU_LOAD"), func() -> void: App.goto(App.State.LOAD_GAME))
	_item(nav, "ui_world", tr("MENU_GENERATOR"), func() -> void: App.goto(App.State.MAP_GENERATOR))
	for e: Dictionary in App.menu_extras:
		if e.get("section", "") == "play":
			_item(nav, e["icon"], tr(e["label"]), e["action"])
	var prog: Array = App.menu_extras.filter(func(e: Dictionary) -> bool: return e.get("section", "") == "progress")
	if not prog.is_empty():
		_section(nav, tr("MENU_SEC_PROGRESS"))
		for e: Dictionary in prog:
			_item(nav, e["icon"], tr(e["label"]), e["action"])
	_section(nav, tr("MENU_SEC_GAME"))
	for e: Dictionary in App.menu_extras:
		if e.get("section", "") == "info":
			_item(nav, e["icon"], tr(e["label"]), e["action"])
	_item(nav, "ui_settings", tr("MENU_SETTINGS"), func() -> void: App.goto(App.State.SETTINGS))
	_item(nav, "ui_license", tr("MENU_CREDITS"), func() -> void: App.goto(App.State.CREDITS))
	_item(nav, "ui_quit", tr("MENU_QUIT"), func() -> void: get_tree().quit())
	row.add_child(UITheme.spacer())
	var side := UITheme.vbox(14)
	side.custom_minimum_size.x = 360
	side.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(side)
	for card: Callable in App.menu_cards:
		var c: Control = card.call()
		if c != null:
			side.add_child(c)
	if cont != "":
		side.add_child(_last_match_card(cont))
	footer()
	var i := 0
	for c in nav.get_children():
		if c is Control:
			Anim.slide_in(c, Vector2(-24, 0), 0.25, 0.02 * i)
			i += 1


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _section(nav: VBoxContainer, text: String) -> void:
	nav.add_child(_gap(2 if _compact else 8))
	nav.add_child(UITheme.caption(text, UITheme.TEXT_FAINT))


func _item(nav: VBoxContainer, icon: String, text: String, cb: Callable, primary: bool = false) -> void:
	var b := UITheme.accent_button(text, cb, 0, icon) if primary else UITheme.ghost_button(text, cb, icon)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, (36 if primary else 30) if _compact else (44 if primary else 38))
	b.add_theme_font_size_override("font_size", (UITheme.T_BODY if _compact else UITheme.T_BODY_L) + (2 if primary else 0))
	nav.add_child(b)


func _continue_path() -> String:
	var saves := SaveManager.list()
	return String(saves[0]["path"]) if not saves.is_empty() else ""


func _last_match_card(path: String) -> Control:
	var h := SaveManager.read_header(path)
	var c := UITheme.card(14)
	var v := UITheme.vbox(6)
	c.add_child(v)
	v.add_child(UITheme.section(tr("MENU_LAST_MATCH"), "ui_clock"))
	var mname: Dictionary = h.get("map", {}).get("name", {})
	v.add_child(UITheme.label(MapDefinition._pick(mname, "") if not mname.is_empty() else "?", UITheme.T_TITLE, UITheme.TEXT, true))
	var sm: Dictionary = h.get("summary", {})
	v.add_child(UITheme.label(tr("LOAD_INFO") % [h.get("created", ""), sm.get("player", ""), int(sm.get("tiles", 0)),
		int(float(sm.get("elapsed", 0.0)) / 60.0)], UITheme.T_CAPTION, UITheme.TEXT_DIM))
	v.add_child(UITheme.accent_button(tr("MENU_CONTINUE"), func() -> void: App.load_match(path), 0, "ui_play"))
	return c
