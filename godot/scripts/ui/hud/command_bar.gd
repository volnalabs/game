class_name HudCommandBar
extends PanelContainer
## The bottom bar shows only what the current situation needs:
##   normal — attack strength, "Build", and "Retreat" while attacks are running;
##   build  — building categories and tiles, one detail block for the chosen building, zones, close;
##   attack — a foreign state is selected: target, strength, troops sent, attack / landing / cancel;
##   naval  — a sea landing is being prepared: target, route (sea + overland), time, troops,
##            send / cancel (or why it is impossible);
##   boat   — one of the player's transports is selected: troops, destination, time left, recall;
##   weapon — aiming a weapon: cost, flight time, radius, estimated losses, interception risk, a
##            warning when our own land is in the zone, launch / cancel (or why not).

const MODES := ["normal", "build", "attack", "naval", "boat", "weapon"]

var hud: GameHUD
var mode: String = ""
var category: String = "economy"
var _boxes: Dictionary = {}
var _ratio_buttons: Array[Button] = []
var _send: Label
var _retreat: Button
# build
var _cat_buttons: Dictionary = {}
var _tiles: HBoxContainer
var _detail: VBoxContainer
var _zones: Button
var _tile_buttons: Dictionary = {}
var _shown_kind: int = -2
var _tiles_key: String = ""
# attack
var _target_flag: TextureRect
var _target_name: Label
var _target_line: Label
var _attack_btn: Button
var _landing_btn: Button
var _attack_ratio: Array[Button] = []
# naval order
var _nv_flag: TextureRect
var _nv_name: Label
var _nv_line: Label
var _nv_send: Button
var _nv_ratio: Array[Button] = []
# weapon aiming
var _wp_icon: TextureRect
var _wp_name: Label
var _wp_line: Label
var _wp_est: VBoxContainer
var _wp_fire: Button
# selected transport
var _bt_line: Label
var _bt_title: Label
var _bt_recall: Button


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, 10, Color.TRANSPARENT, 8))
	var v := UITheme.vbox(0)
	add_child(v)
	_boxes["normal"] = _build_normal()
	_boxes["build"] = _build_build()
	_boxes["attack"] = _build_attack()
	_boxes["naval"] = _build_naval()
	_boxes["boat"] = _build_boat()
	_boxes["weapon"] = _build_weapon()
	for m: String in MODES:
		v.add_child(_boxes[m])
	set_mode("normal")


func _ratio_strip(into: Array[Button]) -> HBoxContainer:
	var seg := UITheme.hbox(0)
	for r: float in GameHUD.RATIOS:
		var b := UITheme.ghost_button("%d%%" % int(r * 100.0), func() -> void: hud.ctl.set_ratio(r))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(42, 28)
		b.add_theme_font_size_override("font_size", 13)
		Hints.attach(b, func() -> Dictionary: return Glossary.hint("attack_share",
			[[tr("HUD_SENDS"), UITheme.num(floorf(hud.sim.st.o_troops[hud.sim.player_id] * r))]]))
		into.append(b)
		seg.add_child(b)
	return seg


func _build_normal() -> Control:
	var row := UITheme.hbox(16)
	var av := UITheme.vbox(0)
	var head := UITheme.hbox(6)
	head.add_child(UITheme.label(tr("HUD_ATTACK_SHARE"), 12, UITheme.TEXT_DIM))
	_send = UITheme.label("", 12, UITheme.TEXT_FAINT)
	_send.add_theme_font_override("font", UITheme.font_numbers)
	head.add_child(_send)
	av.add_child(head)
	av.add_child(_ratio_strip(_ratio_buttons))
	row.add_child(av)
	var build := UITheme.button(tr("BAR_BUILD"), func() -> void: hud.ctl.open_build_mode(), 0, "b_city")
	build.custom_minimum_size.y = 40
	build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(build, func() -> Dictionary: return {"title": tr("DOCK_BUILD_FULL"), "text": tr("BAR_BUILD_HINT"), "hotkey": Keys.label("build")})
	row.add_child(build)
	_retreat = UITheme.button(tr("ACTION_RETREAT_SHORT"), func() -> void: hud.ctl.retreat_all(), 0, "ui_back")
	_retreat.custom_minimum_size.y = 40
	_retreat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(_retreat, {"title": tr("ACTION_RETREAT_ALL"), "text": tr("ACTION_RETREAT_HINT")})
	row.add_child(_retreat)
	return row


func _build_build() -> Control:
	var v := UITheme.vbox(8)
	var head := UITheme.hbox(4)
	for cat: String in BuildingInfo.CATEGORIES:
		var c := cat
		var b := UITheme.ghost_button(tr("BCAT_" + cat.to_upper()), func() -> void:
			category = c
			_tiles_key = ""
			refresh())
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 28
		b.add_theme_font_size_override("font_size", 13)
		Hints.attach(b, {"title": tr("BCAT_" + cat.to_upper()), "text": tr("BCAT_%s_HINT" % cat.to_upper())})
		_cat_buttons[cat] = b
		head.add_child(b)
	head.add_child(UITheme.spacer())
	_zones = UITheme.ghost_button(tr("ACTION_ZONES_SHORT"), func() -> void: hud.ctl.toggle_zones(), "ui_zones")
	_zones.toggle_mode = true
	_zones.focus_mode = Control.FOCUS_NONE
	_zones.add_theme_font_size_override("font_size", 13)
	Hints.attach(_zones, Glossary.hint("zones"))
	head.add_child(_zones)
	var close := UITheme.ghost_button(tr("BAR_CLOSE"), func() -> void: hud.ctl.close_build_mode(), "ui_close")
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 13)
	Hints.attach(close, {"title": tr("BAR_CLOSE"), "text": tr("BAR_CLOSE_HINT"), "hotkey": "Esc"})
	head.add_child(close)
	v.add_child(head)
	var body := UITheme.hbox(14)
	_tiles = UITheme.hbox(4)
	body.add_child(_tiles)
	_detail = UITheme.vbox(2)
	_detail.custom_minimum_size = Vector2(260, 0)
	body.add_child(_detail)
	v.add_child(body)
	return v


func _build_attack() -> Control:
	var row := UITheme.hbox(14)
	_target_flag = UITheme.flag_rect(null, 34, 22)
	_target_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_target_flag)
	var tv := UITheme.vbox(0)
	_target_name = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT)
	_target_name.add_theme_font_override("font", UITheme.font_medium)
	tv.add_child(_target_name)
	_target_line = UITheme.label("", 12, UITheme.TEXT_DIM)
	_target_line.add_theme_font_override("font", UITheme.font_numbers)
	tv.add_child(_target_line)
	tv.custom_minimum_size.x = 190
	row.add_child(tv)
	var av := UITheme.vbox(0)
	av.add_child(UITheme.label(tr("HUD_ATTACK_SHARE"), 12, UITheme.TEXT_DIM))
	av.add_child(_ratio_strip(_attack_ratio))
	row.add_child(av)
	_attack_btn = UITheme.accent_button(tr("ACTION_ATTACK"), func() -> void: hud.ctl.attack_owner(hud.ctl.selected_owner), 0, "g_attack")
	_attack_btn.custom_minimum_size.y = 40
	_attack_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(_attack_btn, func() -> Dictionary: return {"title": tr("ACTION_ATTACK"), "text": tr("BAR_ATTACK_HINT"),
		"reason": String(_attack_btn.get_meta("reason", ""))})
	row.add_child(_attack_btn)
	_landing_btn = UITheme.button(tr("ACTION_LANDING"), func() -> void: hud.ctl.landing_on(hud.ctl.selected_owner), 0, "g_landing")
	_landing_btn.custom_minimum_size.y = 40
	_landing_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(_landing_btn, Glossary.hint("transport"))
	row.add_child(_landing_btn)
	var cancel := UITheme.ghost_button(tr("CANCEL"), func() -> void: hud.ctl.select_owner(0), "ui_close")
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(cancel, {"title": tr("CANCEL"), "text": tr("BAR_CANCEL_ATTACK_HINT"), "hotkey": "Esc"})
	row.add_child(cancel)
	return row


func _build_naval() -> Control:
	var row := UITheme.hbox(14)
	var ic := Icons.rect("g_landing", 26, UITheme.TEXT)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	_nv_flag = UITheme.flag_rect(null, 30, 20)
	_nv_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_nv_flag)
	var tv := UITheme.vbox(0)
	_nv_name = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT)
	_nv_name.add_theme_font_override("font", UITheme.font_medium)
	tv.add_child(_nv_name)
	_nv_line = UITheme.label("", 12, UITheme.TEXT_DIM)
	_nv_line.add_theme_font_override("font", UITheme.font_numbers)
	tv.add_child(_nv_line)
	tv.custom_minimum_size.x = 250
	row.add_child(tv)
	var av := UITheme.vbox(0)
	av.add_child(UITheme.label(tr("HUD_ATTACK_SHARE"), 12, UITheme.TEXT_DIM))
	av.add_child(_ratio_strip(_nv_ratio))
	row.add_child(av)
	_nv_send = UITheme.accent_button(tr("NAVAL_SEND"), func() -> void: hud.ctl.confirm_naval(), 0, "g_landing")
	_nv_send.custom_minimum_size.y = 40
	_nv_send.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(_nv_send, func() -> Dictionary: return {"title": tr("NAVAL_SEND"), "text": tr("NAVAL_SEND_HINT"), "hotkey": Keys.label("confirm")})
	row.add_child(_nv_send)
	var cancel := UITheme.ghost_button(tr("CANCEL"), func() -> void: hud.ctl.cancel_naval(), "ui_close")
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(cancel, {"title": tr("CANCEL"), "text": tr("NAVAL_CANCEL_HINT"), "hotkey": "Esc"})
	row.add_child(cancel)
	return row


func _build_weapon() -> Control:
	var row := UITheme.hbox(14)
	_wp_icon = TextureRect.new()
	_wp_icon.custom_minimum_size = Vector2(30, 30)
	_wp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_wp_icon)
	var tv := UITheme.vbox(1)
	_wp_name = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT)
	_wp_name.add_theme_font_override("font", UITheme.font_medium)
	tv.add_child(_wp_name)
	_wp_line = UITheme.label("", 12, UITheme.TEXT_DIM)
	_wp_line.add_theme_font_override("font", UITheme.font_numbers)
	tv.add_child(_wp_line)
	tv.custom_minimum_size.x = 250
	row.add_child(tv)
	_wp_est = UITheme.vbox(0)
	_wp_est.custom_minimum_size.x = 300
	_wp_est.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_wp_est)
	_wp_fire = UITheme.accent_button(tr("AIM_LAUNCH"), func() -> void: hud.ctl.fire_weapon(), 0, "ui_target")
	_wp_fire.custom_minimum_size.y = 40
	_wp_fire.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(_wp_fire, func() -> Dictionary: return {"title": tr("AIM_LAUNCH"), "text": tr("AIM_LAUNCH_HINT"), "hotkey": Keys.label("confirm"),
		"reason": String(_wp_fire.get_meta("reason", ""))})
	row.add_child(_wp_fire)
	var cancel := UITheme.ghost_button(tr("CANCEL"), func() -> void: hud.ctl.cancel_weapon(), "ui_close")
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(cancel, {"title": tr("CANCEL"), "text": tr("AIM_CANCEL_HINT"), "hotkey": "Esc"})
	row.add_child(cancel)
	return row


func _refresh_weapon() -> void:
	var sim := hud.sim
	var w: int = hud.ctl.weapon_aim
	if w < 0:
		return
	var r := sim.rules
	var wd := r.weapon(w)
	_wp_icon.texture = Icons.tex(WeaponInfo.symbol(r, w), 30)
	_wp_name.text = WeaponInfo.title(r, w)
	var pv: Dictionary = hud.ctl.weapon_preview
	var c: Dictionary = pv.get("check", {})
	var flight := 0
	if c.get("ok", false):
		flight = ceili(float(int(c["delay"]) + int(c["flight"])) / float(r.tick_rate))
	_wp_line.text = tr("AIM_LINE") % [UITheme.num(float(wd["cost"])), UITheme.num(float(wd["supplies"])), flight, roundi(float(wd["radius"]))]
	for ch in _wp_est.get_children():
		_wp_est.remove_child(ch)
		ch.queue_free()
	var reason := ""
	if pv.is_empty():
		_wp_est.add_child(UITheme.label(tr("AIM_PICK"), 12, UITheme.TEXT_DIM))
		reason = tr("AIM_PICK")
	elif not c.get("ok", false):
		reason = WeaponInfo.reason_text(sim, w, String(c.get("reason", "")))
		var l := UITheme.label(reason, 12, UITheme.BAD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 270
		_wp_est.add_child(l)
	else:
		for ln: Array in WeaponInfo.estimate_lines(sim, sim.player_id, pv.get("est", {})):
			var l := UITheme.label(String(ln[0]), 12, ln[1])
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 300
			_wp_est.add_child(l)
	_wp_fire.disabled = reason != ""
	_wp_fire.set_meta("reason", reason)


func _build_boat() -> Control:
	var row := UITheme.hbox(14)
	var ic := Icons.rect("g_landing", 26, UITheme.TEXT)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv := UITheme.vbox(0)
	_bt_title = UITheme.label(tr("BOAT_TITLE"), UITheme.T_BODY_L, UITheme.TEXT)
	_bt_title.add_theme_font_override("font", UITheme.font_medium)
	tv.add_child(_bt_title)
	_bt_line = UITheme.label("", 12, UITheme.TEXT_DIM)
	_bt_line.add_theme_font_override("font", UITheme.font_numbers)
	tv.add_child(_bt_line)
	tv.custom_minimum_size.x = 280
	row.add_child(tv)
	_bt_recall = UITheme.button(tr("BOAT_RECALL"), func() -> void: hud.ctl.recall_boat(), 0, "ui_back")
	_bt_recall.custom_minimum_size.y = 40
	_bt_recall.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(_bt_recall, {"title": tr("BOAT_RECALL"), "text": tr("BOAT_RECALL_HINT")})
	row.add_child(_bt_recall)
	var close := UITheme.ghost_button(tr("BAR_CLOSE"), func() -> void: hud.ctl.select_boat(-1), "ui_close")
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Hints.attach(close, {"title": tr("BAR_CLOSE"), "text": tr("BOAT_CLOSE_HINT"), "hotkey": "Esc"})
	row.add_child(close)
	return row


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	for k: String in _boxes:
		(_boxes[k] as Control).visible = k == m
	_tiles_key = ""
	_shown_kind = -2
	reset_size()


func refresh() -> void:
	var sim := hud.sim
	var pid := sim.player_id
	if pid <= 0:
		return
	var st := sim.st
	match mode:
		"normal":
			for i in _ratio_buttons.size():
				_ratio_buttons[i].button_pressed = is_equal_approx(GameHUD.RATIOS[i], hud.ctl.ratio)
			_send.text = "≈ " + UITheme.num(floorf(st.o_troops[pid] * hud.ctl.ratio))
			_retreat.visible = sim.attacks.outgoing(pid).any(func(a: AttackSystem.Attack) -> bool: return a.retreat_at == 0)
		"build":
			_refresh_build()
		"attack":
			var o: int = hud.ctl.selected_owner
			if o <= 0 or o > st.owner_count:
				return
			for i in _attack_ratio.size():
				_attack_ratio[i].button_pressed = is_equal_approx(GameHUD.RATIOS[i], hud.ctl.ratio)
			_target_flag.texture = hud.flag_of(o)
			_target_name.text = st.o_name[o]
			_target_line.text = tr("BAR_TARGET_LINE") % [UITheme.num(floorf(st.o_troops[pid] * hud.ctl.ratio)), UITheme.num(st.o_troops[o])]
			var borders: bool = hud.ctl.borders(pid, o)
			_attack_btn.visible = borders
			# Treaties: an ally, a pact partner or a teammate cannot be attacked (the reason says how to change that).
			var why := ""
			var block := sim.diplomacy.block_reason(pid, o)
			if block != "":
				why = NavalOrders.reason_text(block)
			elif sim.phase != Sim.Phase.PLAYING or not sim.is_player_alive():
				why = tr("REJECT_NOT_PLAYING")
			Hints.disable(_attack_btn, why)
			if block != "":
				_target_line.text = why
			_landing_btn.visible = not borders
			Hints.disable(_landing_btn, NavalOrders.reason_text(block) if block != "" else "")
		"naval":
			_refresh_naval()
		"boat":
			_refresh_boat()
		"weapon":
			_refresh_weapon()
	reset_size()


func _refresh_naval() -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var plan: Dictionary = hud.ctl.naval_plan
	if plan.is_empty():
		return
	for i in _nv_ratio.size():
		_nv_ratio[i].button_pressed = is_equal_approx(GameHUD.RATIOS[i], hud.ctl.ratio)
	var go: int = plan.get("goal_owner", 0)
	_nv_flag.texture = hud.flag_of(go) if go > 0 else null
	_nv_flag.visible = go > 0
	_nv_name.text = tr("NAVAL_TITLE") % (st.o_name[go] if go > 0 else tr("FREE_LAND"))
	var send := floorf(st.o_troops[pid] * hud.ctl.ratio)
	if plan["ok"]:
		_nv_line.text = tr("NAVAL_LINE") % [UITheme.num(send), roundi(float(plan["sea_len"])), int(plan["land_len"]),
			ceili(float(plan["eta_ticks"]) / 10.0)]
		_nv_line.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		_nv_line.text = NavalOrders.reason_text(String(plan["reason"]))
		_nv_line.add_theme_color_override("font_color", UITheme.BAD)
	var reason := NavalOrders.blocker(sim, pid, plan, send)
	_nv_send.disabled = reason != ""
	_nv_send.set_meta("reason", reason)


func _refresh_boat() -> void:
	var sim := hud.sim
	var st := sim.st
	var b := NavalOrders.boat_by_id(sim, int(hud.ctl.selected_boat))
	if b == null:
		hud.ctl.select_boat(-1)
		return
	var go := st.owner[b.goal_tile] if b.goal_tile >= 0 else st.owner[b.target_tile]
	_bt_title.text = tr("BOAT_RETURNING") if b.returning else tr("BOAT_TITLE")
	var left := ceili(maxf(0.0, b.length - b.progress) / maxf(0.01, float(sim.rules.n["boat_speed_tiles_per_tick"]) / sim.rules.k_lin) / 10.0)
	_bt_line.text = tr("BOAT_SEL_LINE") % [UITheme.num(b.troops), st.o_name[go] if go > 0 else tr("FREE_LAND"), left]
	_bt_recall.disabled = b.returning


func _refresh_build() -> void:
	var sim := hud.sim
	var pid := sim.player_id
	for c: String in _cat_buttons:
		(_cat_buttons[c] as Button).button_pressed = c == category
	_zones.set_pressed_no_signal((hud.ctl.zones as ZoneLayer).show_all if hud.ctl.get("zones") != null else false)
	var kinds: Array[int] = []
	for k in GameHUD.build_kinds(sim.rules):
		if BuildingInfo.category(sim.rules, k) == category:
			kinds.append(k)
	var key := category + str(kinds)
	if key != _tiles_key:
		_tiles_key = key
		for c in _tiles.get_children():
			_tiles.remove_child(c)
			c.queue_free()
		_tile_buttons.clear()
		for k in kinds:
			_tiles.add_child(_tile(k))
	var quick := hud.quick_kinds()
	for k: int in _tile_buttons:
		var b: Button = _tile_buttons[k]
		var reason := BuildingInfo.blocker(sim, k, pid)
		var locked := not sim.structures.unlocked(pid, k)
		b.disabled = locked or sim.phase != Sim.Phase.PLAYING
		b.set_meta("reason", reason)
		b.button_pressed = hud.ctl.build_kind == k
		b.modulate.a = 0.55 if locked else 1.0
		var price: Label = b.get_meta("price")
		price.text = UITheme.num(sim.structures.cost(pid, k))
		price.add_theme_color_override("font_color", UITheme.TEXT_DIM if reason == "" or locked else UITheme.BAD)
		(b.get_meta("key") as Control).visible = quick.has(k)
	var shown: int = hud.ctl.build_kind if hud.ctl.build_kind >= 0 else (kinds[0] if not kinds.is_empty() else -1)
	_fill_detail(shown)


func _tile(k: int) -> Button:
	var sim := hud.sim
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(92, 74)
	b.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE_2, UITheme.R_M, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_3, UITheme.R_M, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(UITheme.ACCENT, 0.22), UITheme.R_M, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("disabled", UITheme.box(Color(UITheme.SURFACE_2, 0.6), UITheme.R_M, Color.TRANSPARENT, 4))
	var v := UITheme.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := Icons.rect(Symbols.building_id(sim.rules, k), 28, Color("#f2efe8"))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var title := BuildingInfo.title(sim.rules, k)
	var n := UITheme.label(title, 12 if title.length() <= 12 else 11, UITheme.TEXT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	n.custom_minimum_size.x = 82
	v.add_child(n)
	var ph := UITheme.hbox(3)
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var price := UITheme.label("", 11, UITheme.TEXT_DIM)
	price.add_theme_font_override("font", UITheme.font_numbers)
	ph.add_child(price)
	v.add_child(ph)
	b.add_child(v)
	var quick_i := hud.quick_kinds().find(k)
	var key := UITheme.key_cap(str(quick_i + 1) if quick_i >= 0 else "")
	key.position = Vector2(4, 4)
	b.add_child(key)
	b.set_meta("price", price)
	b.set_meta("key", key)
	var kk := k
	b.pressed.connect(func() -> void:
		if hud.ctl.build_kind == kk:
			hud.ctl.cancel_build()
		else:
			hud.ctl.begin_build(kk))
	b.mouse_entered.connect(func() -> void: _fill_detail(kk))
	b.mouse_exited.connect(func() -> void: _shown_kind = -2)
	Hints.attach(b, func() -> Dictionary: return {"title": BuildingInfo.title(sim.rules, kk),
		"text": BuildingInfo.short(sim.rules, kk), "reason": String(b.get_meta("reason", ""))})
	_tile_buttons[k] = b
	return b


## The one detail block: what the building is for, its effect, price, time, radius, and the reason
## when it cannot be built; placement keys while placing.
func _fill_detail(k: int) -> void:
	if k == _shown_kind:
		return
	_shown_kind = k
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	if k < 0:
		return
	var sim := hud.sim
	var pid := sim.player_id
	var r := sim.rules
	_detail.add_child(UITheme.label(BuildingInfo.title(r, k), UITheme.T_BODY, UITheme.TEXT, true))
	var eff := BuildingInfo.effects(r, k)
	var d := UITheme.label(eff[0] if not eff.is_empty() else BuildingInfo.short(r, k), 12, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 250
	_detail.add_child(d)
	var facts := PackedStringArray()
	facts.append("%s %s" % [UITheme.num(sim.structures.cost(pid, k)), tr("BAR_GOLD_SHORT")])
	if r.building_supplies(k) > 0.0:
		facts.append("%s %s" % [UITheme.num(r.building_supplies(k)), tr("BAR_SUPPLIES_SHORT")])
	facts.append("%d %s" % [ceili(float(r.building_ticks(k)) / float(r.tick_rate)), tr("SEC_SHORT")])
	if r.building_radius(k) > 0.0:
		facts.append(tr("BI_TILES_R") % roundi(r.building_radius(k)))
	var fl := UITheme.label(" · ".join(facts), 12, UITheme.TEXT_FAINT)
	fl.add_theme_font_override("font", UITheme.font_numbers)
	_detail.add_child(fl)
	var reason := BuildingInfo.blocker(sim, k, pid)
	if reason != "":
		var rl := UITheme.label(reason, 12, UITheme.BAD)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.custom_minimum_size.x = 250
		_detail.add_child(rl)
	elif hud.ctl.build_kind == k:
		_detail.add_child(UITheme.label(tr("BAR_PLACE_KEYS"), 12, UITheme.TEXT_FAINT))
