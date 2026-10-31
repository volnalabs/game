class_name HudCommandBar
extends PanelContainer
## Bottom command bar: attack strength (what one click on a neighbour sends), quick build slots with
## the buildings' symbols and prices, and labelled army / view actions.

var hud: GameHUD
var _ratio_buttons: Array[Button] = []
var _send: Label
var _build: Dictionary = {}
var _build_cost: Dictionary = {}
var _zones: Button
var _bh: HBoxContainer
var _quick: Array[int] = []


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, UITheme.R_M, UITheme.STROKE, 8))
	var row := UITheme.hbox(14)
	add_child(row)
	var rv := UITheme.vbox(3)
	var rh := UITheme.hbox(6)
	rh.add_child(UITheme.caption(tr("HUD_ATTACK_SHARE")))
	rh.add_child(UITheme.key_cap("Q"))
	rh.add_child(UITheme.key_cap("E"))
	rv.add_child(rh)
	var seg := UITheme.hbox(2)
	for r: float in GameHUD.RATIOS:
		var b := UITheme.ghost_button("%d%%" % int(r * 100.0), func() -> void: hud.ctl.set_ratio(r))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 28)
		Hints.attach(b, func() -> Dictionary: return Glossary.hint("attack_share",
			[[tr("HUD_SENDS"), UITheme.num(floorf(hud.sim.st.o_troops[hud.sim.player_id] * r))]]))
		_ratio_buttons.append(b)
		seg.add_child(b)
	rv.add_child(seg)
	_send = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	rv.add_child(_send)
	row.add_child(rv)
	row.add_child(VSeparator.new())
	var bv := UITheme.vbox(3)
	var bhh := UITheme.hbox(6)
	bhh.add_child(UITheme.caption(tr("DOCK_BUILD")))
	bhh.add_child(UITheme.key_cap("1–6"))
	bv.add_child(bhh)
	_bh = UITheme.hbox(4)
	_rebuild_quick()
	bv.add_child(_bh)
	row.add_child(bv)
	row.add_child(VSeparator.new())
	var ah := UITheme.hbox(0)
	var home := UITheme.rail_button("ui_home", tr("ACTION_HOME_SHORT"), func() -> void: hud.ctl.focus_home(), 62)
	Hints.attach(home, {"title": tr("ACTION_HOME"), "text": tr("ACTION_HOME_HINT"), "hotkey": "Home"})
	ah.add_child(home)
	var back := UITheme.rail_button("ui_back", tr("ACTION_RETREAT_SHORT"), func() -> void: hud.ctl.retreat_all(), 62)
	Hints.attach(back, {"title": tr("ACTION_RETREAT_ALL"), "text": tr("ACTION_RETREAT_HINT")})
	ah.add_child(back)
	_zones = UITheme.rail_button("ui_zones", tr("ACTION_ZONES_SHORT"), func() -> void: hud.ctl.toggle_zones(), 62, true)
	Hints.attach(_zones, Glossary.hint("zones"))
	ah.add_child(_zones)
	var hide := UITheme.rail_button("ui_eye_off", tr("ACTION_HIDE_SHORT"), func() -> void: hud.set_ui_hidden(true), 62)
	Hints.attach(hide, {"title": tr("ACTION_HIDE_UI"), "text": tr("ACTION_HIDE_HINT"), "hotkey": "Tab"})
	ah.add_child(hide)
	row.add_child(ah)


## Quick build slots: the first unlocked buildable kinds (keys 1..n), rebuilt when research
## unlocks more.
func _rebuild_quick() -> void:
	_quick = hud.quick_kinds()
	for c in _bh.get_children():
		_bh.remove_child(c)
		c.queue_free()
	_build.clear()
	_build_cost.clear()
	var keyn := 1
	for k in _quick:
		var kk := k
		var key := keyn
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(58, 52)
		b.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 1, 0.04), UITheme.R_M, Color.TRANSPARENT, 4))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.09), UITheme.R_M, Color.TRANSPARENT, 4))
		b.add_theme_stylebox_override("pressed", UITheme.box(Color(UITheme.ACCENT, 0.18), UITheme.R_M, UITheme.ACCENT, 4))
		b.add_theme_stylebox_override("disabled", UITheme.box(Color(1, 1, 1, 0.02), UITheme.R_M, Color.TRANSPARENT, 4))
		var v := UITheme.vbox(1)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := Icons.rect(Symbols.building_id(hud.sim.rules, k), 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var cl := UITheme.label("", 11, UITheme.GOLD)
		cl.add_theme_font_override("font", UITheme.font_numbers)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cl)
		b.add_child(v)
		b.pressed.connect(func() -> void:
			if hud.ctl.build_kind == kk:
				hud.ctl.cancel_build()
			else:
				hud.ctl.begin_build(kk))
		Hints.attach(b, func() -> Dictionary: return BuildingInfo.hint(hud.sim, kk, hud.sim.player_id, str(key)))
		_build[k] = b
		_build_cost[k] = cl
		_bh.add_child(b)
		keyn += 1


func refresh() -> void:
	if hud.quick_kinds() != _quick:
		_rebuild_quick()
	var sim := hud.sim
	var pid := sim.player_id
	for i in _ratio_buttons.size():
		_ratio_buttons[i].button_pressed = is_equal_approx(GameHUD.RATIOS[i], hud.ctl.ratio)
	_send.text = tr("ACTIONS_SEND") % UITheme.num(floorf(sim.st.o_troops[pid] * hud.ctl.ratio))
	var playing := sim.phase == Sim.Phase.PLAYING and sim.is_player_alive()
	if hud.ctl.get("zones") != null:
		_zones.set_pressed_no_signal((hud.ctl.zones as ZoneLayer).show_all)
	for k: int in _build:
		var b: Button = _build[k]
		var cost := sim.structures.cost(pid, k)
		var cl: Label = _build_cost[k]
		cl.text = UITheme.num(cost)
		var reason := BuildingInfo.blocker(sim, k, pid) if playing else tr("REJECT_NOT_PLAYING")
		cl.add_theme_color_override("font_color", UITheme.GOLD if reason == "" else UITheme.BAD)
		# Unaffordable kinds can still be placed in preview (the ghost explains why it is refused).
		b.disabled = not playing
		b.set_meta("reason", reason)
		b.modulate.a = 1.0 if reason == "" else 0.7
		b.button_pressed = hud.ctl.build_kind == k
