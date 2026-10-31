class_name GameHUD
extends Control
## In-game interface. Reads the simulation, sends player intent through the MatchController.
## Panels: top bar (time, domination goal, rank, speed), bottom bar (army, attack share, gold,
## supplies, upkeep, buildings), leaderboard, attacks, event log, state panel (overview /
## economy / military / AI debug), spawn banner, toasts, pause menu, victory / defeat screen.

const RATIOS := [0.1, 0.2, 0.35, 0.5, 0.75, 1.0]
const BUILD_KINDS := [Rules.B_CITY, Rules.B_PORT, Rules.B_FACTORY, Rules.B_DEFENSE, Rules.B_SAM, Rules.B_SILO]

var ctl: Node
var sim: Sim
var _t: float = 0.0

var _time_l: Label
var _goal_bar: ProgressBar
var _goal_l: Label
var _rank_l: Label
var _flag: TextureRect
var _name_l: Label
var _speed_btns: Dictionary = {}
var _troops_l: Label
var _troops_bar: ProgressBar
var _gold_l: Label
var _sup_l: Label
var _upkeep_l: Label
var _ratio_btns: Array[Button] = []
var _build_btns: Dictionary = {}
var _board: VBoxContainer
var _attacks: VBoxContainer
var _log: RichTextLabel
var _log_lines: Array[String] = []
var _info_panel: PanelContainer
var _info_body: VBoxContainer
var _info_tab: String = "overview"
var _spawn_banner: PanelContainer
var _spawn_l: Label
var _toast: Label
var _toast_t: float = 0.0
var _pause: Control
var _end: Control
var _end_title: Label
var _end_body: VBoxContainer
var _ai_debug: bool = false


func setup(controller: Node, sim_: Sim) -> void:
	ctl = controller
	sim = sim_
	_ai_debug = Settings.show_ai_debug
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.theme()
	_build_top()
	_build_bottom()
	_build_right()
	_build_log()
	_build_info()
	_build_spawn_banner()
	_build_toast()
	_build_pause()
	_build_end()
	refresh()


# ---------------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------------

func _anchor(c: Control, preset: int, offset: Vector2 = Vector2.ZERO) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 10)
	match preset:
		Control.PRESET_TOP_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_BOTTOM:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_TOP:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.offset_left += offset.x
	c.offset_right += offset.x
	c.offset_top += offset.y
	c.offset_bottom += offset.y


func _build_top() -> void:
	var p := UITheme.panel(8)
	add_child(p)
	var h := UITheme.hbox(14)
	p.add_child(h)
	_flag = TextureRect.new()
	_flag.custom_minimum_size = Vector2(36, 24)
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	h.add_child(_flag)
	_name_l = UITheme.label("", 17, UITheme.TEXT, true)
	h.add_child(_name_l)
	_rank_l = UITheme.label("", 15, UITheme.ACCENT_2)
	h.add_child(_rank_l)
	h.add_child(VSeparator.new())
	_time_l = UITheme.label("00:00", 17, UITheme.TEXT, true)
	h.add_child(_time_l)
	var g := UITheme.vbox(2)
	_goal_l = UITheme.label("", 12, UITheme.TEXT_DIM)
	g.add_child(_goal_l)
	_goal_bar = ProgressBar.new()
	_goal_bar.custom_minimum_size = Vector2(220, 10)
	_goal_bar.show_percentage = false
	_goal_bar.max_value = 1.0
	g.add_child(_goal_bar)
	h.add_child(g)
	h.add_child(VSeparator.new())
	for s: float in [0.0, 0.5, 1.0, 2.0, 4.0]:
		var b := UITheme.button("❚❚" if s == 0.0 else "×%s" % (str(s) if s < 1.0 else str(int(s))), func() -> void: ctl.set_speed(s))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 30)
		b.tooltip_text = tr("HUD_SPEED_TIP")
		_speed_btns[s] = b
		h.add_child(b)
	h.add_child(UITheme.button("☰", func() -> void: ctl.open_pause_menu()))
	_anchor(p, Control.PRESET_CENTER_TOP)


func _build_bottom() -> void:
	var p := UITheme.panel(10)
	add_child(p)
	var h := UITheme.hbox(18)
	p.add_child(h)
	var army := UITheme.vbox(2)
	army.custom_minimum_size.x = 240
	army.add_child(UITheme.label(tr("HUD_ARMY"), 12, UITheme.TEXT_DIM))
	_troops_l = UITheme.label("", 17, UITheme.TEXT, true)
	army.add_child(_troops_l)
	_troops_bar = ProgressBar.new()
	_troops_bar.custom_minimum_size = Vector2(230, 8)
	_troops_bar.show_percentage = false
	_troops_bar.max_value = 1.0
	army.add_child(_troops_bar)
	army.tooltip_text = tr("HUD_ARMY_TIP")
	army.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(army)
	var rv := UITheme.vbox(2)
	rv.add_child(UITheme.label(tr("HUD_ATTACK_SHARE"), 12, UITheme.TEXT_DIM))
	var rh := UITheme.hbox(4)
	for r: float in RATIOS:
		var b := UITheme.button("%d%%" % int(r * 100.0), func() -> void: ctl.set_ratio(r))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(50, 30)
		b.tooltip_text = tr("HUD_RATIO_TIP")
		_ratio_btns.append(b)
		rh.add_child(b)
	rv.add_child(rh)
	h.add_child(rv)
	var eco := UITheme.vbox(2)
	eco.custom_minimum_size.x = 200
	_gold_l = UITheme.label("", 16, UITheme.ACCENT_2, true)
	_gold_l.tooltip_text = tr("HUD_GOLD_TIP")
	_gold_l.mouse_filter = Control.MOUSE_FILTER_PASS
	eco.add_child(_gold_l)
	_sup_l = UITheme.label("", 14, Color("#9ad1ff"))
	_sup_l.tooltip_text = tr("HUD_SUPPLIES_TIP")
	_sup_l.mouse_filter = Control.MOUSE_FILTER_PASS
	eco.add_child(_sup_l)
	_upkeep_l = UITheme.label("", 13, UITheme.TEXT_DIM)
	_upkeep_l.tooltip_text = tr("HUD_UPKEEP_TIP")
	_upkeep_l.mouse_filter = Control.MOUSE_FILTER_PASS
	eco.add_child(_upkeep_l)
	h.add_child(eco)
	var bh := UITheme.hbox(4)
	for i in BUILD_KINDS.size():
		var k: int = BUILD_KINDS[i]
		var b := UITheme.button("", func() -> void: ctl.begin_build(k))
		b.custom_minimum_size = Vector2(92, 52)
		b.add_theme_font_size_override("font_size", 13)
		_build_btns[k] = b
		bh.add_child(b)
	h.add_child(bh)
	_anchor(p, Control.PRESET_CENTER_BOTTOM)


func _build_right() -> void:
	var col := UITheme.vbox(8)
	col.custom_minimum_size.x = 290
	add_child(col)
	var lp := UITheme.panel(10)
	var lv := UITheme.vbox(3)
	lp.add_child(lv)
	lv.add_child(UITheme.label(tr("HUD_LEADERBOARD"), 14, UITheme.TEXT_DIM, true))
	_board = UITheme.vbox(2)
	lv.add_child(_board)
	col.add_child(lp)
	var ap := UITheme.panel(10)
	var av := UITheme.vbox(3)
	ap.add_child(av)
	av.add_child(UITheme.label(tr("HUD_ATTACKS"), 14, UITheme.TEXT_DIM, true))
	_attacks = UITheme.vbox(2)
	av.add_child(_attacks)
	col.add_child(ap)
	_anchor(col, Control.PRESET_TOP_RIGHT, Vector2(0, 56))


func _build_log() -> void:
	var p := UITheme.panel(8)
	p.custom_minimum_size = Vector2(420, 170)
	add_child(p)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(400, 150)
	_log.add_theme_font_size_override("normal_font_size", 13)
	p.add_child(_log)
	_anchor(p, Control.PRESET_BOTTOM_LEFT, Vector2(0, -96))


func _build_info() -> void:
	_info_panel = UITheme.panel(12)
	_info_panel.custom_minimum_size = Vector2(330, 0)
	add_child(_info_panel)
	var v := UITheme.vbox(6)
	_info_panel.add_child(v)
	var tabs := UITheme.hbox(4)
	for t in ["overview", "economy", "military", "ai"]:
		var b := UITheme.button(tr("TAB_" + t.to_upper()), func() -> void:
			_info_tab = t
			_refresh_info())
		b.add_theme_font_size_override("font_size", 12)
		tabs.add_child(b)
	tabs.add_child(UITheme.button("✖", func() -> void: ctl.select_owner(0)))
	v.add_child(tabs)
	_info_body = UITheme.vbox(4)
	v.add_child(_info_body)
	_anchor(_info_panel, Control.PRESET_TOP_LEFT, Vector2(0, 56))
	_info_panel.visible = false


func _build_spawn_banner() -> void:
	_spawn_banner = UITheme.panel(14)
	add_child(_spawn_banner)
	var v := UITheme.vbox(4)
	_spawn_banner.add_child(v)
	v.add_child(UITheme.label(tr("SPAWN_TITLE"), 22, UITheme.ACCENT, true))
	_spawn_l = UITheme.label(tr("SPAWN_HINT"), 15)
	v.add_child(_spawn_l)
	_anchor(_spawn_banner, Control.PRESET_CENTER_TOP, Vector2(0, 70))


func _build_toast() -> void:
	_toast = UITheme.label("", 17, UITheme.WARN, true)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_toast)
	_anchor(_toast, Control.PRESET_CENTER_TOP, Vector2(0, 140))


func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0, 0, 0, 0.55)
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(o)
	return o


func _build_pause() -> void:
	_pause = _overlay()
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(cc)
	var p := UITheme.panel(20)
	cc.add_child(p)
	var v := UITheme.vbox(10)
	v.custom_minimum_size.x = 340
	p.add_child(v)
	v.add_child(UITheme.title(tr("PAUSE_TITLE"), 28))
	v.add_child(UITheme.accent_button(tr("PAUSE_CONTINUE"), func() -> void: ctl.close_pause_menu()))
	v.add_child(UITheme.button(tr("PAUSE_SAVE"), func() -> void: ctl.save_game()))
	v.add_child(UITheme.button(tr("PAUSE_LOAD"), func() -> void: ctl.load_last()))
	v.add_child(UITheme.button(tr("PAUSE_RESTART"), func() -> void: ctl.restart()))
	v.add_child(UITheme.button(tr("PAUSE_MAIN_MENU"), func() -> void: ctl.quit_to_menu()))
	var keys := UITheme.label(tr("PAUSE_KEYS"), 12, UITheme.TEXT_DIM)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(keys)
	_pause.visible = false


func _build_end() -> void:
	_end = _overlay()
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end.add_child(cc)
	var p := UITheme.panel(24)
	cc.add_child(p)
	var v := UITheme.vbox(12)
	v.custom_minimum_size.x = 560
	p.add_child(v)
	_end_title = UITheme.title("", 40)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_end_title)
	_end_body = UITheme.vbox(4)
	v.add_child(_end_body)
	var row := UITheme.hbox(10)
	row.add_child(UITheme.button(tr("END_WATCH"), func() -> void: ctl.continue_watching()))
	row.add_child(UITheme.spacer())
	row.add_child(UITheme.button(tr("END_NEW_GAME"), func() -> void: ctl.new_game()))
	row.add_child(UITheme.accent_button(tr("PAUSE_MAIN_MENU"), func() -> void: ctl.quit_to_menu()))
	v.add_child(row)
	_end.visible = false


# ---------------------------------------------------------------------------------------------
# Updates
# ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t -= delta
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _t <= 0.0:
		_t = 0.2
		refresh()


func refresh() -> void:
	if sim == null:
		return
	var st := sim.st
	var pid := sim.player_id
	var alive := sim.is_player_alive()
	_name_l.text = st.o_name[pid] if pid > 0 else ""
	_flag.texture = UITheme.flag_texture(st.o_flag[pid], pid * 7919 + sim.config.seed, st.o_color[pid]) if pid > 0 else null
	var secs := int(sim.elapsed_seconds())
	_time_l.text = "%02d:%02d" % [secs / 60, secs % 60]
	var goal := sim.config.victory.domination_share
	var share := st.land_share(pid) if pid > 0 else 0.0
	_goal_l.text = tr("HUD_GOAL") % [share * 100.0, goal * 100.0]
	_goal_bar.value = clampf(share / goal, 0.0, 1.0)
	_rank_l.text = "#%d" % _rank(pid) if alive else tr("HUD_DEFEATED")
	for s: float in _speed_btns:
		(_speed_btns[s] as Button).button_pressed = (ctl.paused and s == 0.0) or (not ctl.paused and is_equal_approx(ctl.speed, s))
	var troops := st.o_troops[pid]
	var cap := maxf(st.o_cap[pid], 1.0)
	_troops_l.text = "%s / %s  (%s%s/%s)" % [UITheme.num(troops), UITheme.num(cap), "+" if st.o_growth[pid] >= 0.0 else "",
		UITheme.num(st.o_growth[pid] * 10.0), tr("PER_SEC")]
	_troops_bar.value = troops / cap
	var net := st.o_income[pid] - st.o_upkeep[pid]
	_gold_l.text = "%s %s  (%s%s/%s)" % [tr("HUD_GOLD"), UITheme.num(st.o_gold[pid]), "+" if net >= 0 else "", UITheme.num(net * 10.0), tr("PER_SEC")]
	_sup_l.text = "%s %s  (+%s/%s)" % [tr("HUD_SUPPLIES"), UITheme.num(st.o_supplies[pid]), UITheme.num(st.o_supply_income[pid] * 10.0), tr("PER_SEC")]
	_upkeep_l.text = tr("HUD_UPKEEP") % UITheme.num(st.o_upkeep[pid] * 10.0)
	_upkeep_l.add_theme_color_override("font_color", UITheme.BAD if net < 0.0 else UITheme.TEXT_DIM)
	for i in _ratio_btns.size():
		_ratio_btns[i].button_pressed = is_equal_approx(RATIOS[i], ctl.ratio)
	for k: int in _build_btns:
		var b: Button = _build_btns[k]
		var later := String(sim.rules.b_kinds[k].get("phase", "")) != ""
		var cost := sim.structures.cost(pid, k)
		b.text = "%s\n%s" % [tr("B_" + sim.rules.b_ids[k].to_upper()), tr("SOON") if later else UITheme.num(cost)]
		b.disabled = later or not alive or sim.phase != Sim.Phase.PLAYING or not sim.structures.can_afford(pid, k)
		b.tooltip_text = tr("B_%s_TIP" % sim.rules.b_ids[k].to_upper()) + ("" if later else "\n" + tr("HUD_BUILD_KEY") % (BUILD_KINDS.find(k) + 1))
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.13, 0.42, 0.48) if ctl.build_kind == k else Color(0.16, 0.21, 0.27), 8, UITheme.BORDER))
	_refresh_board()
	_refresh_attacks()
	_spawn_banner.visible = sim.phase == Sim.Phase.SPAWN
	if sim.phase == Sim.Phase.SPAWN:
		if st.o_spawned[pid] == 1 and sim.countdown_end > 0:
			_spawn_l.text = tr("SPAWN_COUNTDOWN") % maxf(0.0, float(sim.countdown_end - st.tick) / 10.0)
		else:
			_spawn_l.text = tr("SPAWN_HINT")
	if _info_panel.visible:
		_refresh_info()


func _rank(id: int) -> int:
	var st := sim.st
	var r := 1
	for o in range(1, st.owner_count + 1):
		if o != id and st.o_alive[o] == 1 and st.o_tiles[o] > st.o_tiles[id]:
			r += 1
	return r


func _refresh_board() -> void:
	for c in _board.get_children():
		c.queue_free()
	var st := sim.st
	var rows: Array = []
	for o in range(1, st.owner_count + 1):
		if st.o_alive[o] == 1 and st.o_tiles[o] > 0:
			rows.append(o)
	rows.sort_custom(func(a: int, b: int) -> bool: return st.o_tiles[a] > st.o_tiles[b])
	var shown := rows.slice(0, 10)
	if sim.player_id > 0 and st.o_alive[sim.player_id] == 1 and not shown.has(sim.player_id):
		shown.append(sim.player_id)
	for o: int in shown:
		var h := UITheme.hbox(6)
		var sw := ColorRect.new()
		sw.color = st.o_color[o]
		sw.custom_minimum_size = Vector2(10, 14)
		h.add_child(sw)
		var nm := UITheme.label("%d. %s" % [rows.find(o) + 1, st.o_name[o]], 13, UITheme.ACCENT if o == sim.player_id else UITheme.TEXT)
		nm.clip_text = true
		nm.custom_minimum_size.x = 150
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		h.add_child(UITheme.label("%.1f%%" % (st.land_share(o) * 100.0), 13, UITheme.TEXT_DIM))
		h.add_child(UITheme.label(UITheme.num(st.o_troops[o]), 13, UITheme.TEXT_DIM))
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				ctl.select_owner(o, true))
		_board.add_child(h)


func _refresh_attacks() -> void:
	for c in _attacks.get_children():
		c.queue_free()
	var pid := sim.player_id
	var any := false
	for a in sim.attacks.attacks:
		if not a.alive:
			continue
		if a.attacker == pid:
			any = true
			var h := UITheme.hbox(6)
			var tn: String = tr("FREE_LAND") if a.target == 0 else sim.st.o_name[a.target]
			var l := UITheme.label("⚔ %s  %s" % [tn, UITheme.num(a.troops)], 13, UITheme.GOOD)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			h.add_child(l)
			if a.retreat_at == 0:
				var aid := a.id
				var b := UITheme.button("↩", func() -> void: ctl.retreat(aid))
				b.tooltip_text = tr("HUD_RETREAT_TIP")
				h.add_child(b)
			else:
				h.add_child(UITheme.label(tr("HUD_RETREATING"), 12, UITheme.TEXT_DIM))
			_attacks.add_child(h)
		elif a.target == pid:
			any = true
			_attacks.add_child(UITheme.label("🛡 %s  %s" % [sim.st.o_name[a.attacker], UITheme.num(a.troops)], 13, UITheme.BAD))
	for b in sim.naval.boats:
		if b.alive and b.owner == pid:
			any = true
			_attacks.add_child(UITheme.label("⛵ %s" % UITheme.num(b.troops), 13, UITheme.ACCENT))
	if not any:
		_attacks.add_child(UITheme.label(tr("HUD_NO_ATTACKS"), 12, UITheme.TEXT_DIM))


func show_owner(id: int) -> void:
	_info_panel.visible = id > 0
	if _info_tab == "ai" and not (_ai_debug and id != sim.player_id):
		_info_tab = "overview"
	_refresh_info()


func toggle_ai_debug() -> void:
	_ai_debug = not _ai_debug
	if _ai_debug:
		_info_tab = "ai"
	_refresh_info()
	toast(tr("AI_DEBUG_ON") if _ai_debug else tr("AI_DEBUG_OFF"))


func _kv(k: String, v: String, c: Color = UITheme.TEXT) -> Control:
	var h := UITheme.hbox(6)
	var kl := UITheme.label(k, 13, UITheme.TEXT_DIM)
	kl.custom_minimum_size.x = 150
	h.add_child(kl)
	var vl := UITheme.label(v, 13, c)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.custom_minimum_size.x = 150
	h.add_child(vl)
	return h


func _refresh_info() -> void:
	for c in _info_body.get_children():
		c.queue_free()
	var id: int = ctl.selected_owner
	if id <= 0 or id > sim.st.owner_count:
		_info_panel.visible = false
		return
	var st := sim.st
	var mine := id == sim.player_id
	var head := UITheme.hbox(8)
	var fl := TextureRect.new()
	fl.texture = UITheme.flag_texture(st.o_flag[id], id * 7919 + sim.config.seed, st.o_color[id])
	fl.custom_minimum_size = Vector2(42, 28)
	fl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fl.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	head.add_child(fl)
	head.add_child(UITheme.label(st.o_name[id], 19, st.o_color[id].lightened(0.3), true))
	_info_body.add_child(head)
	var kind_s := tr("KIND_PLAYER") if mine else (tr("KIND_TRIBE") if st.o_kind[id] == Rules.KIND_TRIBE else tr("KIND_NATION"))
	var brain := sim.ai.brain_of(id)
	if brain != null and brain is StrategicAI:
		kind_s += " · " + tr("PERS_" + brain.personality_id.to_upper()) + " · " + tr("DIFF_" + brain.difficulty_id.to_upper())
	_info_body.add_child(UITheme.label(kind_s + ("" if st.o_alive[id] == 1 else " · " + tr("STATUS_DEAD")), 13, UITheme.ACCENT))
	match _info_tab:
		"overview":
			_info_body.add_child(_kv(tr("INFO_LAND"), "%s (%.1f%%)" % [UITheme.num(float(st.o_tiles[id])), st.land_share(id) * 100.0]))
			_info_body.add_child(_kv(tr("INFO_TROOPS"), UITheme.num(st.o_troops[id])))
			_info_body.add_child(_kv(tr("INFO_RANK"), "#%d" % _rank(id)))
			var bs := PackedStringArray()
			for k in Rules.BUILDING_KINDS:
				var lv := st.blevel(id, k)
				if lv > 0:
					bs.append("%s %d" % [tr("B_" + sim.rules.b_ids[k].to_upper()), lv])
			_info_body.add_child(_kv(tr("INFO_BUILDINGS"), ", ".join(bs) if bs.size() > 0 else "—"))
			_info_body.add_child(_kv(tr("INFO_STATUS"), _status_of(id)))
		"economy":
			if not mine and not _ai_debug:
				_info_body.add_child(UITheme.label(tr("INFO_HIDDEN"), 13, UITheme.TEXT_DIM))
			else:
				var r := sim.rules
				var cities := st.blevel(id, Rules.B_CITY)
				var base := float(r.e["gold_base"]) + float(r.e["gold_value_mult"]) * sqrt(maxf(st.o_value[id], 0.0))
				_info_body.add_child(_kv(tr("ECO_GOLD"), UITheme.num(st.o_gold[id]), UITheme.ACCENT_2))
				_info_body.add_child(_kv(tr("ECO_TERRITORY"), "+%s/%s" % [UITheme.num(base * 10.0), tr("PER_SEC")]))
				_info_body.add_child(_kv(tr("ECO_CITIES"), "+%s/%s" % [UITheme.num(float(cities) * float(r.e["gold_city"]) * 10.0), tr("PER_SEC")]))
				_info_body.add_child(_kv(tr("ECO_TRADE"), "+%s/%s" % [UITheme.num(st.o_port_trade[id] * 10.0), tr("PER_SEC")]))
				_info_body.add_child(_kv(tr("ECO_FACTORIES"), "+%d%%" % int(minf(float(st.blevel(id, Rules.B_FACTORY)) * float(r.e["factory_income_bonus"]), r.e["factory_income_bonus_max"]) * 100.0)))
				_info_body.add_child(_kv(tr("ECO_INCOME"), "+%s/%s" % [UITheme.num(st.o_income[id] * 10.0), tr("PER_SEC")], UITheme.GOOD))
				_info_body.add_child(_kv(tr("ECO_UPKEEP"), "-%s/%s" % [UITheme.num(st.o_upkeep[id] * 10.0), tr("PER_SEC")], UITheme.BAD))
				_info_body.add_child(_kv(tr("ECO_SUPPLIES"), "%s (+%s/%s)" % [UITheme.num(st.o_supplies[id]), UITheme.num(st.o_supply_income[id] * 10.0), tr("PER_SEC")]))
				_info_body.add_child(_kv(tr("ECO_EARNED"), UITheme.num(st.o_st_gold_earned[id])))
				_info_body.add_child(_kv(tr("ECO_SPENT"), UITheme.num(st.o_st_gold_spent[id] + st.o_st_upkeep_paid[id])))
		"military":
			_info_body.add_child(_kv(tr("MIL_TROOPS"), UITheme.num(st.o_troops[id])))
			if mine or _ai_debug:
				_info_body.add_child(_kv(tr("MIL_CAP"), UITheme.num(st.o_cap[id])))
				_info_body.add_child(_kv(tr("MIL_GROWTH"), "%s/%s" % [UITheme.num(st.o_growth[id] * 10.0), tr("PER_SEC")]))
			_info_body.add_child(_kv(tr("MIL_IN_ATTACKS"), UITheme.num(sim.attacks.troops_in_attacks(id))))
			_info_body.add_child(_kv(tr("MIL_BOATS"), "%d / %d" % [st.o_boats[id], sim.naval.max_boats()]))
			_info_body.add_child(_kv(tr("MIL_ATTACKS"), str(st.o_st_attacks[id])))
			_info_body.add_child(_kv(tr("MIL_CONQUERED"), UITheme.num(float(st.o_st_conquered[id]))))
			_info_body.add_child(_kv(tr("MIL_LOST"), UITheme.num(st.o_st_troops_lost[id])))
		"ai":
			if brain == null or not _ai_debug:
				_info_body.add_child(UITheme.label(tr("AI_DEBUG_HINT"), 13, UITheme.TEXT_DIM))
			else:
				var d := brain.debug_info()
				for k: String in d:
					if k in ["options", "threats"]:
						continue
					var v: Variant = d[k]
					var vs := ("%.2f" % v) if typeof(v) == TYPE_FLOAT else str(v)
					if k == "target":
						vs = st.o_name[int(v)] if int(v) > 0 else "—"
					_info_body.add_child(_kv(k, vs))
				if d.has("threats"):
					for th: Array in d["threats"]:
						_info_body.add_child(_kv(tr("AI_THREAT"), "%s: %.2f" % [st.o_name[int(th[0])], float(th[1])], UITheme.WARN))
				var lines := PackedStringArray()
				for e in brain.log.last(10):
					lines.append(DecisionLog.format(e, func(o: int) -> String: return st.o_name[o] if o > 0 else ""))
				var t := UITheme.label("\n".join(lines), 11, UITheme.TEXT_DIM)
				t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				t.custom_minimum_size.x = 310
				_info_body.add_child(t)


func _status_of(id: int) -> String:
	var st := sim.st
	if st.o_alive[id] == 0:
		return tr("STATUS_DEAD")
	var out := 0
	var inc := 0
	for a in sim.attacks.attacks:
		if a.alive and a.attacker == id and a.target != 0:
			out += 1
		if a.alive and a.target == id:
			inc += 1
	if inc > 0:
		return tr("STATUS_INVADED") % inc
	if out > 0:
		return tr("STATUS_AT_WAR") % out
	return tr("STATUS_PEACE")


# ---------------------------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------------------------

func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.5
	_toast.modulate.a = 1.0


func log_line(text: String, color: Color = UITheme.TEXT) -> void:
	var secs := int(sim.elapsed_seconds())
	_log_lines.append("[color=#7d8a98]%02d:%02d[/color] [color=#%s]%s[/color]" % [secs / 60, secs % 60, color.to_html(false), text])
	if _log_lines.size() > 60:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)


func show_pause(on: bool) -> void:
	_pause.visible = on


func show_end(victory: bool, reason: String) -> void:
	_end.visible = true
	_end_title.text = tr("END_VICTORY") if victory else tr("END_DEFEAT")
	_end_title.add_theme_color_override("font_color", UITheme.GOOD if victory else UITheme.BAD)
	for c in _end_body.get_children():
		c.queue_free()
	var st := sim.st
	var pid := sim.player_id
	_end_body.add_child(UITheme.label(tr("END_REASON_" + reason.to_upper()), 16, UITheme.TEXT_DIM))
	var secs := int(sim.elapsed_seconds())
	_end_body.add_child(_kv(tr("END_TIME"), "%02d:%02d" % [secs / 60, secs % 60]))
	_end_body.add_child(_kv(tr("END_LAND"), "%.1f%%" % (st.land_share(pid) * 100.0)))
	_end_body.add_child(_kv(tr("END_PEAK"), UITheme.num(float(st.o_st_peak_tiles[pid]))))
	_end_body.add_child(_kv(tr("MIL_CONQUERED"), UITheme.num(float(st.o_st_conquered[pid]))))
	_end_body.add_child(_kv(tr("MIL_ATTACKS"), str(st.o_st_attacks[pid])))
	_end_body.add_child(_kv(tr("MIL_LOST"), UITheme.num(st.o_st_troops_lost[pid])))
	_end_body.add_child(_kv(tr("ECO_EARNED"), UITheme.num(st.o_st_gold_earned[pid])))
	var w := int(sim.result.get("winner", 0))
	if w > 0:
		_end_body.add_child(_kv(tr("END_WINNER"), st.o_name[w], st.o_color[w].lightened(0.3)))


func hide_end() -> void:
	_end.visible = false
