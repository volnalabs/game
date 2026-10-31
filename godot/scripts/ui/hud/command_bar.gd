class_name HudCommandBar
extends PanelContainer
## Bottom command bar: attack share (with the troops a click will send), quick build slots with
## their prices, and army / view actions.

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
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, UITheme.R_L, UITheme.STROKE, 10))
	var row := UITheme.hbox(16)
	add_child(row)
	var rv := UITheme.vbox(4)
	rv.add_child(UITheme.section(tr("HUD_ATTACK_SHARE"), "g_attack"))
	var seg := UITheme.hbox(2)
	for r: float in GameHUD.RATIOS:
		var b := UITheme.ghost_button("%d%%" % int(r * 100.0), func() -> void: hud.ctl.set_ratio(r))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(48, 30)
		b.tooltip_text = tr("HUD_RATIO_TIP")
		_ratio_buttons.append(b)
		seg.add_child(b)
	rv.add_child(seg)
	_send = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	rv.add_child(_send)
	row.add_child(rv)
	row.add_child(VSeparator.new())
	var bv := UITheme.vbox(4)
	bv.add_child(UITheme.section(tr("DOCK_BUILD"), "ui_building"))
	_bh = UITheme.hbox(4)
	_rebuild_quick()
	bv.add_child(_bh)
	row.add_child(bv)
	row.add_child(VSeparator.new())
	var av := UITheme.vbox(4)
	av.add_child(UITheme.section(tr("HUD_ACTIONS"), "ui_adjust"))
	var ah := UITheme.hbox(2)
	ah.add_child(UITheme.icon_button("ui_home", tr("ACTION_HOME"), func() -> void: hud.ctl.focus_home(), 36))
	ah.add_child(UITheme.icon_button("ui_back", tr("ACTION_RETREAT_ALL"), func() -> void: hud.ctl.retreat_all(), 36))
	_zones = UITheme.icon_button("ui_zones", tr("ACTION_ZONES"), func() -> void: hud.ctl.toggle_zones(), 36, true)
	ah.add_child(_zones)
	ah.add_child(UITheme.icon_button("ui_eye_off", tr("ACTION_HIDE_UI"), func() -> void: hud.set_ui_hidden(true), 36))
	av.add_child(ah)
	row.add_child(av)



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
		var id := hud.sim.rules.b_ids[k]
		var kk := k
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(64, 58)
		b.tooltip_text = "%s\n%s\n%s" % [tr("B_" + id.to_upper()), tr("B_%s_TIP" % id.to_upper()), tr("HUD_BUILD_KEY") % keyn]
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE_2, UITheme.R_M, UITheme.STROKE, 4))
		b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_3, UITheme.R_M, UITheme.STROKE_STRONG, 4))
		b.add_theme_stylebox_override("pressed", UITheme.box(UITheme.ACCENT.darkened(0.55), UITheme.R_M, UITheme.ACCENT, 4))
		b.add_theme_stylebox_override("disabled", UITheme.box(Color(0.07, 0.09, 0.12, 0.7), UITheme.R_M, Color(1, 1, 1, 0.03), 4))
		var v := UITheme.vbox(2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := Icons.rect("b_" + id, 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var cl := UITheme.label("", 11, UITheme.GOLD)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cl)
		b.add_child(v)
		b.pressed.connect(func() -> void:
			if hud.ctl.build_kind == kk:
				hud.ctl.cancel_build()
			else:
				hud.ctl.begin_build(kk))
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
		(_build_cost[k] as Label).text = UITheme.num(cost)
		(_build_cost[k] as Label).add_theme_color_override("font_color", UITheme.GOLD if sim.st.o_gold[pid] >= cost else UITheme.BAD)
		# Unaffordable kinds can still be placed in preview (the ghost explains why it is refused).
		b.disabled = not playing
		b.modulate.a = 1.0 if sim.structures.can_afford(pid, k) else 0.6
		b.button_pressed = hud.ctl.build_kind == k
