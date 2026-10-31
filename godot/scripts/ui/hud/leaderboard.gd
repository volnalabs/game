class_name HudLeaderboard
extends PanelContainer
## Compact, collapsible leaderboard (top 8 + the player); rows select and focus a state.

var hud: GameHUD
var _rows: VBoxContainer
var _collapsed: bool = false
var _toggle: Button


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, UITheme.R_L, UITheme.STROKE, 10))
	custom_minimum_size.x = 300
	var v := UITheme.vbox(6)
	add_child(v)
	var head := UITheme.hbox(6)
	head.add_child(UITheme.section(tr("HUD_LEADERBOARD"), "ui_trophy"))
	head.add_child(UITheme.spacer())
	_toggle = UITheme.icon_button("ui_up", tr("COLLAPSE"), func() -> void: _set_collapsed(not _collapsed), 26)
	head.add_child(_toggle)
	v.add_child(head)
	_rows = UITheme.vbox(2)
	v.add_child(_rows)


func _set_collapsed(on: bool) -> void:
	_collapsed = on
	_rows.visible = not on
	_toggle.icon = Icons.tex("ui_down" if on else "ui_up", 14)


func refresh() -> void:
	if _collapsed or not visible:
		return
	if get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	for c in _rows.get_children():
		c.queue_free()
	var sim := hud.sim
	var st := sim.st
	var list: Array = []
	for o in range(1, st.owner_count + 1):
		if st.o_alive[o] == 1 and st.o_tiles[o] > 0:
			list.append(o)
	list.sort_custom(func(a: int, b: int) -> bool: return st.o_tiles[a] > st.o_tiles[b])
	var shown := list.slice(0, 8)
	if sim.player_id > 0 and st.o_alive[sim.player_id] == 1 and not shown.has(sim.player_id):
		shown.append(sim.player_id)
	for o: int in shown:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var mine := o == sim.player_id
		b.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.ACCENT, 0.12) if mine else Color.TRANSPARENT, UITheme.R_S, Color.TRANSPARENT, 3))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.06), UITheme.R_S, Color.TRANSPARENT, 3))
		b.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 1, 1, 0.1), UITheme.R_S, Color.TRANSPARENT, 3))
		var h := UITheme.hbox(6)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(h)
		var sw := ColorRect.new()
		sw.color = st.o_color[o]
		sw.custom_minimum_size = Vector2(4, 16)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sw)
		var nm := UITheme.label("%d  %s" % [list.find(o) + 1, st.o_name[o]], UITheme.T_CAPTION + 1, UITheme.ACCENT if mine else UITheme.TEXT)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(UITheme.label("%.1f%%" % (st.land_share(o) * 100.0), UITheme.T_CAPTION, UITheme.TEXT_DIM))
		b.custom_minimum_size = Vector2(280, 22)
		b.pressed.connect(func() -> void: hud.ctl.select_owner(o, true))
		_rows.add_child(b)
