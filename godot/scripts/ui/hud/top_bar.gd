class_name HudTopBar
extends PanelContainer
## Top bar: who you are (flag, state, title, rank), the resources with their names and rates, game
## time and speed, victory progress, menu. Every value has a plain-language hint (Glossary) with
## live numbers; clicking a resource opens its panel.

var hud: GameHUD
var _flag: TextureRect
var _name: Label
var _rank: Label
var _time: Label
var _speed: Dictionary = {}
var _res: Dictionary = {}
var _goal: ProgressBar
var _goal_l: Label
var _title: String = ""


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, UITheme.R_M, UITheme.STROKE, 6))
	var row := UITheme.hbox(10)
	add_child(row)
	# Identity.
	_flag = UITheme.flag_rect(null, 34, 22)
	row.add_child(_flag)
	var nv := UITheme.vbox(0)
	_name = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT, true)
	nv.add_child(_name)
	_rank = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	nv.add_child(_rank)
	nv.mouse_filter = Control.MOUSE_FILTER_PASS
	Hints.attach(nv, func() -> Dictionary: return Glossary.hint("rank"))
	row.add_child(nv)
	_title = Cosmetics.title()
	row.add_child(VSeparator.new())
	# Resources: caption above, symbol + value + rate below.
	for r: Array in [["gold", "r_gold", UITheme.GOLD, "economy"], ["supplies", "r_supplies", UITheme.SUPPLY, "economy"],
			["army", "r_army", UITheme.ARMY, "army"], ["research", "r_research", UITheme.RESEARCH, "research"]]:
		row.add_child(_resource(r[0], r[1], r[2], r[3]))
	row.add_child(UITheme.spacer())
	# Time and speed.
	var tv := UITheme.vbox(0)
	tv.add_child(UITheme.caption(tr("HUD_TIME")))
	var sp := UITheme.hbox(2)
	_time = UITheme.label("00:00", UITheme.T_BODY_L, UITheme.TEXT, true)
	_time.add_theme_font_override("font", UITheme.font_numbers)
	_time.custom_minimum_size.x = 48
	sp.add_child(_time)
	for s: float in [0.0, 1.0, 2.0, 4.0]:
		var b: Button
		if s == 0.0:
			b = UITheme.icon_button("ui_pause", "", func() -> void: hud.ctl.set_speed(s), 28, true)
			Hints.attach(b, {"title": tr("HUD_PAUSE_SHORT"), "text": MetaData.text(Glossary.data()["speed"]["what"]), "hotkey": tr("KEY_SPACE")})
		else:
			b = UITheme.ghost_button("×%d" % int(s), func() -> void: hud.ctl.set_speed(s))
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(32, 26)
			b.add_theme_font_size_override("font_size", UITheme.T_CAPTION + 1)
			Hints.attach(b, Glossary.hint("speed"))
		b.focus_mode = Control.FOCUS_NONE
		_speed[s] = b
		sp.add_child(b)
	tv.add_child(sp)
	row.add_child(tv)
	row.add_child(VSeparator.new())
	# Victory progress.
	var gv := UITheme.vbox(3)
	_goal_l = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	gv.add_child(_goal_l)
	_goal = UITheme.progress(0.0, UITheme.ACCENT, 6)
	_goal.custom_minimum_size.x = 120
	gv.add_child(_goal)
	gv.mouse_filter = Control.MOUSE_FILTER_PASS
	Hints.attach(gv, func() -> Dictionary: return Glossary.hint("victory", [[tr("HUD_GOAL_NOW"), "%.1f%%" % (hud.sim.st.land_share(hud.sim.player_id) * 100.0)],
		[tr("HUD_GOAL_NEED"), "%d%%" % roundi(hud.sim.config.victory.domination_share * 100.0)]]))
	row.add_child(gv)
	var menu := UITheme.icon_button("ui_menu", "", func() -> void: hud.ctl.open_pause_menu(), 34)
	Hints.attach(menu, {"title": tr("PAUSE_TITLE"), "text": tr("HUD_MENU_HINT"), "hotkey": "Esc"})
	row.add_child(menu)


## One resource: clickable (opens its panel), with a glossary hint holding live numbers. A panel
## (not a Button) so it sizes itself to its content.
func _resource(id: String, icon: String, color: Color, panel: String) -> Control:
	var b := PanelContainer.new()
	var normal := UITheme.box(Color.TRANSPARENT, UITheme.R_S, Color.TRANSPARENT, 3)
	b.add_theme_stylebox_override("panel", normal)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func() -> void: b.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.05), UITheme.R_S, Color.TRANSPARENT, 3)))
	b.mouse_exited.connect(func() -> void: b.add_theme_stylebox_override("panel", normal))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			hud.dock.open(panel))
	var v := UITheme.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(UITheme.caption(Glossary.term_name(id)))
	var h := UITheme.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(Icons.rect(icon, 18, color))
	var val := UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT, true)
	val.add_theme_font_override("font", UITheme.font_numbers)
	h.add_child(val)
	var rate := UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	rate.add_theme_font_override("font", UITheme.font_numbers)
	h.add_child(rate)
	v.add_child(h)
	b.add_child(v)
	Hints.attach(b, func() -> Dictionary: return Glossary.hint(id, _live_rows(id)))
	_res[id] = [val, rate]
	return b


func _live_rows(id: String) -> Array:
	var st := hud.sim.st
	var pid := hud.sim.player_id
	match id:
		"gold":
			return [[Glossary.term_name("income"), "+%s/%s" % [UITheme.num(st.o_income[pid] * 10.0), tr("PER_SEC")], UITheme.GOOD],
				[Glossary.term_name("upkeep"), "−%s/%s" % [UITheme.num(st.o_upkeep[pid] * 10.0), tr("PER_SEC")], UITheme.BAD]]
		"supplies":
			return [[tr("HUD_PER_SEC_IN"), "+%s/%s" % [UITheme.num(st.o_supply_income[pid] * 10.0), tr("PER_SEC")]]]
		"army":
			return [[Glossary.term_name("army_cap"), UITheme.num(st.o_cap[pid])],
				[tr("HUD_GROWTH"), "%s/%s" % [UITheme.num(st.o_growth[pid] * 10.0), tr("PER_SEC")]]]
		"research":
			var cur := hud.sim.research.current(pid)
			return [[tr("HUD_RESEARCHING"), MetaData.text(ResearchSystem.tech(cur).get("name", {})) if cur != "" else tr("RESEARCH_NONE_SHORT")],
				[tr("RESEARCH_RATE"), "%.1f %s" % [hud.sim.research.rate(pid) * 10.0, tr("RESEARCH_PER_SEC")]]]
	return []


func refresh() -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	if pid <= 0:
		return
	_flag.texture = hud.flag_of(pid)
	_name.text = st.o_name[pid]
	var rank := (tr("HUD_RANK") % hud.rank_of(pid)) if sim.is_player_alive() else tr("HUD_DEFEATED")
	_rank.text = (_title + " · " + rank) if _title != "" else rank
	var secs := int(sim.elapsed_seconds())
	_time.text = "%02d:%02d" % [secs / 60, secs % 60]
	for s: float in _speed:
		(_speed[s] as Button).button_pressed = (hud.ctl.paused and s == 0.0) or (not hud.ctl.paused and is_equal_approx(hud.ctl.speed, s))
	var net := (st.o_income[pid] - st.o_upkeep[pid]) * 10.0
	_put("gold", UITheme.num(st.o_gold[pid]), ("+" if net >= 0.0 else "") + UITheme.num(net), UITheme.GOOD if net >= 0.0 else UITheme.BAD)
	_put("supplies", UITheme.num(st.o_supplies[pid]), "+" + UITheme.num(st.o_supply_income[pid] * 10.0), UITheme.TEXT_DIM)
	_put("army", "%s / %s" % [UITheme.num(st.o_troops[pid]), UITheme.num(maxf(st.o_cap[pid], 1.0))],
		("+" if st.o_growth[pid] >= 0.0 else "") + UITheme.num(st.o_growth[pid] * 10.0), UITheme.GOOD if st.o_growth[pid] >= 0.0 else UITheme.BAD)
	var cur := sim.research.current(pid)
	if cur != "":
		_put("research", "%d%%" % int(100.0 * sim.research.progress(pid, cur) / float(ResearchSystem.tech(cur)["cost"])), "", UITheme.TEXT_DIM)
	else:
		_put("research", tr("RESEARCH_IDLE_SHORT"), "", UITheme.WARN)
		(_res["research"][0] as Label).add_theme_color_override("font_color", UITheme.WARN)
	var goal := sim.config.victory.domination_share
	var share := st.land_share(pid)
	_goal_l.text = tr("HUD_GOAL") % [share * 100.0, goal * 100.0]
	_goal.value = clampf(share / goal, 0.0, 1.0)


func _put(id: String, value: String, rate: String, rate_color: Color) -> void:
	var p: Array = _res[id]
	(p[0] as Label).text = value
	(p[0] as Label).add_theme_color_override("font_color", UITheme.TEXT)
	(p[1] as Label).text = rate
	(p[1] as Label).add_theme_color_override("font_color", rate_color)
