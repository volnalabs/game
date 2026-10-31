class_name HudLeaderboard
extends PanelContainer
## Ranking as a small pill ("Ranking · 12th"); a click opens the top 5 + you. It folds away
## by itself while the inspector is open, so the right column never stacks two panels.

var hud: GameHUD
var _rows: VBoxContainer
var _open: bool = false
var _compact: bool = false
var _head: Button


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, 10, Color.TRANSPARENT, 6))
	custom_minimum_size.x = 230
	var v := UITheme.vbox(4)
	add_child(v)
	_head = UITheme.ghost_button("", func() -> void:
		_open = not _open
		_apply(), "ui_trophy")
	_head.focus_mode = Control.FOCUS_NONE
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.add_theme_font_size_override("font_size", 13)
	Hints.attach(_head, {"title": tr("HUD_LEADERBOARD"), "text": tr("HUD_LB_HINT")})
	v.add_child(_head)
	_rows = UITheme.vbox(1)
	v.add_child(_rows)
	_apply()


## Folds the list while another panel needs the right column.
func set_compact(on: bool) -> void:
	if on != _compact:
		_compact = on
		_apply()


func _apply() -> void:
	_rows.visible = _open and not _compact
	refresh()


func refresh() -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	if pid > 0:
		_head.text = tr("HUD_LB_PILL") % hud.rank_of(pid) if sim.is_player_alive() else tr("HUD_LEADERBOARD")
	if not _rows.visible or not visible:
		return
	if get_global_rect().has_point(get_viewport().get_mouse_position()) and _rows.get_child_count() > 0:
		return
	for c in _rows.get_children():
		c.queue_free()
	var list: Array = []
	for o in range(1, st.owner_count + 1):
		if st.o_alive[o] == 1 and st.o_tiles[o] > 0:
			list.append(o)
	list.sort_custom(func(a: int, b: int) -> bool: return st.o_tiles[a] > st.o_tiles[b])
	var shown := list.slice(0, 5)
	if pid > 0 and st.o_alive[pid] == 1 and not shown.has(pid):
		shown.append(pid)
	for o: int in shown:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var mine := o == pid
		b.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 1, 0.05) if mine else Color.TRANSPARENT, UITheme.R_S, Color.TRANSPARENT, 3))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.07), UITheme.R_S, Color.TRANSPARENT, 3))
		b.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 1, 1, 0.1), UITheme.R_S, Color.TRANSPARENT, 3))
		var h := UITheme.hbox(8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 6
		h.offset_right = -6
		b.add_child(h)
		var sw := ColorRect.new()
		sw.color = st.o_color[o]
		sw.custom_minimum_size = Vector2(8, 8)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sw)
		var nm := UITheme.label("%d  %s" % [list.find(o) + 1, st.o_name[o]], 13, UITheme.TEXT if mine else UITheme.TEXT_DIM)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var pct := UITheme.label("%.1f%%" % (st.land_share(o) * 100.0), 12, UITheme.TEXT_FAINT)
		pct.add_theme_font_override("font", UITheme.font_numbers)
		h.add_child(pct)
		b.custom_minimum_size = Vector2(218, 24)
		b.pressed.connect(func() -> void: hud.ctl.select_owner(o, true))
		var oname := st.o_name[o]
		Hints.attach(b, func() -> Dictionary: return {"title": oname, "text": tr("HUD_LB_ROW_HINT"),
			"rows": [[tr("INFO_LAND"), "%.1f%%" % (st.land_share(o) * 100.0)], [tr("INFO_TROOPS"), UITheme.num(st.o_troops[o])]]})
		_rows.add_child(b)
