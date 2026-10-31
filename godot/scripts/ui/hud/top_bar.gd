class_name HudTopBar
extends PanelContainer
## Top bar: state flag and name, rank, match time, speed control, resources, victory progress.

var hud: GameHUD
var _flag: TextureRect
var _name: Label
var _rank: Label
var _time: Label
var _speed: Dictionary = {}
var _gold: Label
var _gold_rate: Label
var _sup: Label
var _army: Label
var _army_rate: Label
var _goal: ProgressBar
var _goal_l: Label


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, UITheme.R_L, UITheme.STROKE, 8))
	var row := UITheme.hbox(14)
	add_child(row)
	_flag = UITheme.flag_rect(null, 40, 26)
	row.add_child(_flag)
	var nv := UITheme.vbox(0)
	_name = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT, true)
	nv.add_child(_name)
	_rank = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	nv.add_child(_rank)
	row.add_child(nv)
	row.add_child(VSeparator.new())
	row.add_child(Icons.rect("ui_clock", 18, UITheme.TEXT_DIM))
	_time = UITheme.label("00:00", UITheme.T_BODY_L, UITheme.TEXT, true)
	_time.custom_minimum_size.x = 56
	row.add_child(_time)
	var sp := UITheme.hbox(2)
	for s: float in [0.0, 0.5, 1.0, 2.0, 4.0]:
		var b: Button
		if s == 0.0:
			b = UITheme.icon_button("ui_pause", tr("HUD_SPEED_TIP"), func() -> void: hud.ctl.set_speed(0.0), 32, true)
		else:
			b = UITheme.ghost_button("×%s" % (str(s) if s < 1.0 else str(int(s))), func() -> void: hud.ctl.set_speed(s))
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(40, 32)
			b.tooltip_text = tr("HUD_SPEED_TIP")
		_speed[s] = b
		sp.add_child(b)
	row.add_child(sp)
	row.add_child(UITheme.spacer())
	_gold = _pill(row, "r_gold", UITheme.GOLD, tr("HUD_GOLD_TIP"))
	_gold_rate = _rate(row)
	_sup = _pill(row, "r_supplies", UITheme.SUPPLY, tr("HUD_SUPPLIES_TIP"))
	_army = _pill(row, "r_army", UITheme.ARMY, tr("HUD_ARMY_TIP"))
	_army_rate = _rate(row)
	row.add_child(VSeparator.new())
	var gv := UITheme.vbox(3)
	_goal_l = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	gv.add_child(_goal_l)
	_goal = UITheme.progress(0.0, UITheme.ACCENT, 6)
	_goal.custom_minimum_size.x = 170
	gv.add_child(_goal)
	gv.tooltip_text = tr("HUD_GOAL_TIP")
	gv.mouse_filter = Control.MOUSE_FILTER_PASS
	var gh := UITheme.hbox(6)
	gh.add_child(Icons.rect("g_victory", 20, UITheme.ACCENT))
	gh.add_child(gv)
	row.add_child(gh)
	row.add_child(UITheme.icon_button("ui_menu", tr("PAUSE_TITLE"), func() -> void: hud.ctl.open_pause_menu(), 34))


func _pill(row: HBoxContainer, icon: String, color: Color, tip: String) -> Label:
	var h := UITheme.hbox(5)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(Icons.rect(icon, 20, color))
	var l := UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT, true)
	h.add_child(l)
	row.add_child(h)
	return l


func _rate(row: HBoxContainer) -> Label:
	var l := UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	row.add_child(l)
	return l


func refresh() -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	if pid <= 0:
		return
	_flag.texture = hud.flag_of(pid)
	_name.text = st.o_name[pid]
	_rank.text = (tr("HUD_RANK") % hud.rank_of(pid)) if sim.is_player_alive() else tr("HUD_DEFEATED")
	var secs := int(sim.elapsed_seconds())
	_time.text = "%02d:%02d" % [secs / 60, secs % 60]
	for s: float in _speed:
		(_speed[s] as Button).button_pressed = (hud.ctl.paused and s == 0.0) or (not hud.ctl.paused and is_equal_approx(hud.ctl.speed, s))
	_gold.text = UITheme.num(st.o_gold[pid])
	var net := st.o_income[pid] - st.o_upkeep[pid]
	_gold_rate.text = "%s%s/%s" % ["+" if net >= 0.0 else "", UITheme.num(net * 10.0), tr("PER_SEC")]
	_gold_rate.add_theme_color_override("font_color", UITheme.GOOD if net >= 0.0 else UITheme.BAD)
	_sup.text = UITheme.num(st.o_supplies[pid])
	_army.text = "%s / %s" % [UITheme.num(st.o_troops[pid]), UITheme.num(maxf(st.o_cap[pid], 1.0))]
	_army_rate.text = "%s%s/%s" % ["+" if st.o_growth[pid] >= 0.0 else "", UITheme.num(st.o_growth[pid] * 10.0), tr("PER_SEC")]
	var goal := sim.config.victory.domination_share
	var share := st.land_share(pid)
	_goal_l.text = tr("HUD_GOAL") % [share * 100.0, goal * 100.0]
	_goal.value = clampf(share / goal, 0.0, 1.0)
