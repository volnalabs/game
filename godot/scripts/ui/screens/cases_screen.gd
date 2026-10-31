extends ScreenBase
## Cases: earned or bought with Credits (never real money). Odds and pity are shown before
## opening; the result is decided first (Profile.open_case) and the reel animation only reveals it.

const REEL_LEN := 36
const REEL_WIN := 30
const CELL := 112

var _list: VBoxContainer
var _detail: VBoxContainer
var _credits: Label
static var _selected: String = "starter"
var _overlay: Control


func _ready() -> void:
	var c := build_frame(tr("MENU_CASES"), 1200)
	var head := UITheme.hbox(12)
	head.add_child(UITheme.label(tr("CASES_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	head.add_child(UITheme.spacer())
	head.add_child(Icons.rect("r_credits", 20, UITheme.CREDITS))
	_credits = UITheme.label("", UITheme.T_BODY_L, UITheme.CREDITS, true)
	head.add_child(_credits)
	c.add_child(head)
	var row := UITheme.hbox(14)
	c.add_child(row)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, maxf(360.0, get_viewport_rect().size.y - 260.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(sc)
	_list = UITheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var dp := UITheme.panel(16)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dp)
	_detail = UITheme.vbox(10)
	dp.add_child(_detail)
	var r2 := UITheme.hbox(12)
	r2.add_child(back_button())
	c.add_child(r2)
	footer()
	_rebuild()


func _rebuild() -> void:
	var p: ProfileData = Profile.data
	_credits.text = UITheme.num(float(p.credits()))
	for ch in _list.get_children():
		ch.queue_free()
	var md := CaseSystem.today_md()
	for cd: Dictionary in MetaData.cases():
		var id := String(cd["id"])
		var avail := CaseSystem.available(id, md)
		if not avail and p.case_count(id) == 0:
			continue
		var col := Color(String(cd["color"]))
		var card := UITheme.card(10, UITheme.ACCENT if id == _selected else Color.TRANSPARENT)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_selected = id
				_rebuild())
		var h := UITheme.hbox(12)
		card.add_child(h)
		h.add_child(ItemView._boxed(Icons.rect(String(cd["icon"]), 36, col), 56, col))
		var v := UITheme.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UITheme.label(MetaData.text(cd["name"]), UITheme.T_BODY_L, UITheme.TEXT, true))
		v.add_child(UITheme.icon_label("r_credits", UITheme.num(float(cd["price"])), UITheme.CREDITS, UITheme.T_CAPTION))
		var n := p.case_count(id)
		var bd := UITheme.badge("×%d" % n, UITheme.ACCENT if n > 0 else UITheme.TEXT_FAINT)
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bd)
		_list.add_child(card)
	_show_detail()


func _show_detail() -> void:
	for ch in _detail.get_children():
		ch.queue_free()
	var p: ProfileData = Profile.data
	var cd := MetaData.case_def(_selected)
	if cd.is_empty():
		return
	var col := Color(String(cd["color"]))
	var h := UITheme.hbox(12)
	h.add_child(Icons.rect(String(cd["icon"]), 48, col))
	var v := UITheme.vbox(2)
	v.add_child(UITheme.label(MetaData.text(cd["name"]), UITheme.T_H2, UITheme.TEXT, true))
	var d := UITheme.label(MetaData.text(cd["desc"]), UITheme.T_BODY, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 520
	v.add_child(d)
	h.add_child(v)
	_detail.add_child(h)
	# Odds before opening.
	_detail.add_child(UITheme.section(tr("CASES_ODDS"), "ui_chart"))
	var odds := CaseSystem.odds(_selected)
	var ob := UITheme.hbox(8)
	for r: String in MetaData.rarity_order():
		var cell := UITheme.card(8, UITheme.rarity_color(r))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UITheme.vbox(0)
		cell.add_child(cv)
		cv.add_child(UITheme.label(ItemView.rarity_name(r), UITheme.T_CAPTION, UITheme.rarity_color(r)))
		cv.add_child(UITheme.label("%s%%" % str(odds.get(r, 0)), UITheme.T_TITLE, UITheme.TEXT if float(odds.get(r, 0)) > 0.0 else UITheme.TEXT_FAINT, true))
		ob.add_child(cell)
	_detail.add_child(ob)
	var P: Dictionary = MetaData.rarity()["pity"]
	var pity: Dictionary = p.data["pity"]
	_detail.add_child(UITheme.label(tr("CASES_PITY") % [int(P["epic_or_better_after"]) - int(pity["epic"]), int(P["legendary_after"]) - int(pity["legendary"])],
		UITheme.T_CAPTION, UITheme.TEXT_DIM))
	_detail.add_child(UITheme.label(tr("CASES_DUPLICATES"), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	var bh := UITheme.hbox(10)
	var buy := UITheme.button(tr("CASES_BUY") % UITheme.num(float(cd["price"])), func() -> void:
		if Profile.buy_case(_selected):
			_rebuild(), 0, "r_credits")
	buy.disabled = p.credits() < int(cd["price"]) or not CaseSystem.available(_selected, CaseSystem.today_md())
	bh.add_child(buy)
	var open := UITheme.accent_button(tr("CASES_OPEN") % p.case_count(_selected), _open, 0, "m_case_open")
	open.disabled = p.case_count(_selected) <= 0
	bh.add_child(open)
	_detail.add_child(bh)
	# Possible contents.
	_detail.add_child(UITheme.section(tr("CASES_CONTENTS"), "m_inventory"))
	var gs := ScrollContainer.new()
	gs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gs.custom_minimum_size.y = maxf(160.0, get_viewport_rect().size.y - 560.0)
	gs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var g := HFlowContainer.new()
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	var cats: Array = cd["categories"]
	var order: Array = MetaData.rarity_order()
	var pool := MetaData.items().filter(func(it: Dictionary) -> bool: return cats.has(it["category"]) and float(odds.get(it["rarity"], 0)) > 0.0)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order.find(a["rarity"]) > order.find(b["rarity"]))
	for it: Dictionary in pool:
		var pv := ItemView.preview(it, 52)
		pv.tooltip_text = "%s · %s%s" % [MetaData.text(it["name"]), ItemView.rarity_name(String(it["rarity"])),
			(" · " + tr("INV_OWNED")) if p.owns(String(it["id"])) else ""]
		pv.mouse_filter = Control.MOUSE_FILTER_PASS
		if p.owns(String(it["id"])):
			pv.modulate = Color(1, 1, 1, 0.55)
		g.add_child(pv)
	gs.add_child(g)
	_detail.add_child(gs)


func _open() -> void:
	var out: Dictionary = Profile.open_case(_selected)
	if out.is_empty():
		return
	_show_opening(out)


## The opening: a reel of items scrolls and stops on the already-decided result, then the result
## card appears. Clicking skips the animation (the outcome is the same).
func _show_opening(out: Dictionary) -> void:
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.02, 0.03, 0.05, 0.9)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var vs := get_viewport_rect().size
	var cd := MetaData.case_def(_selected)
	var title := UITheme.title(MetaData.text(cd["name"]), UITheme.T_H2)
	title.position = Vector2(vs.x * 0.5 - 200, vs.y * 0.5 - 170)
	title.custom_minimum_size.x = 400
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(title)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(vs.x * 0.5 - 450, vs.y * 0.5 - CELL * 0.5 - 20)
	clip.size = Vector2(900, CELL + 40)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(clip)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	strip.position = Vector2(0, 20)
	clip.add_child(strip)
	# Decorative reel (its own RNG: it never influences the result).
	var deco := RandomNumberGenerator.new()
	deco.seed = Time.get_ticks_usec()
	var cats: Array = cd["categories"]
	var odds := CaseSystem.odds(_selected)
	var pool := MetaData.items().filter(func(it: Dictionary) -> bool: return cats.has(it["category"]) and float(odds.get(it["rarity"], 0)) > 0.0)
	for i in REEL_LEN:
		var it: Dictionary = MetaData.item(String(out["item"])) if i == REEL_WIN else pool[deco.randi() % pool.size()]
		strip.add_child(ItemView.preview(it, CELL))
	var marker := ColorRect.new()
	marker.color = UITheme.ACCENT
	marker.size = Vector2(3, CELL + 40)
	marker.position = Vector2(450 - 1.5, 0)
	clip.add_child(marker)
	var target := -(REEL_WIN * (CELL + 8) + CELL * 0.5 - 450.0) + deco.randf_range(-CELL * 0.35, CELL * 0.35)
	var t := create_tween()
	if Anim.enabled():
		t.tween_property(strip, "position:x", target, 4.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		strip.position.x = target
	t.tween_callback(func() -> void: _reveal(out))
	_overlay.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and t.is_running():
			t.kill()
			strip.position.x = target
			_reveal(out))


func _reveal(out: Dictionary) -> void:
	if _overlay == null or _overlay.has_meta("revealed"):
		return
	_overlay.set_meta("revealed", true)
	var it := MetaData.item(String(out["item"]))
	var rc := UITheme.rarity_color(String(it["rarity"]))
	var vs := get_viewport_rect().size
	var card := UITheme.panel(20)
	card.add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, UITheme.R_L, rc, 20))
	var v := UITheme.vbox(8)
	card.add_child(v)
	var pv := ItemView.preview(it, 120)
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	var n := UITheme.label(MetaData.text(it["name"]), UITheme.T_H2, rc, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var sub := UITheme.label("%s · %s" % [ItemView.rarity_name(String(it["rarity"])), ItemView.category_name(String(it["category"]))], UITheme.T_BODY, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	if out["duplicate"]:
		v.add_child(UITheme.icon_label("r_fragments", tr("CASES_DUPLICATE_GOT") % [int(out["fragments"]), int(out["credits"])], UITheme.TEXT, UITheme.T_BODY))
	elif String(out.get("pity_forced", "")) != "":
		v.add_child(UITheme.icon_label("ui_star", tr("CASES_PITY_HIT"), UITheme.GOLD, UITheme.T_BODY))
	var bh := UITheme.hbox(10)
	if not out["duplicate"]:
		bh.add_child(UITheme.accent_button(tr("INV_EQUIP"), func() -> void:
			Profile.equip(String(out["item"]))
			_close_overlay(), 0, "ui_check"))
	bh.add_child(UITheme.button(tr("CLOSE"), _close_overlay, 0, "ui_close"))
	v.add_child(bh)
	_overlay.add_child(card)
	card.reset_size()
	card.position = Vector2(vs.x * 0.5 - card.size.x * 0.5, vs.y * 0.5 + CELL * 0.5 + 40)
	Anim.pop(card, 0.7, 0.35)


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	App.refresh_screen()
