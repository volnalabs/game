extends ScreenBase
## Encyclopedia: categories and articles on the left (with search), the article on the right.
## Open from the main menu, the pause menu or F1 in a match (as an overlay).

var start_article: String = ""
var _list: VBoxContainer
var _view: VBoxContainer
var _search: LineEdit
var _all: Array = []
var _current: String = ""


func _ready() -> void:
	var vs := get_viewport_rect().size
	var c := build_frame(tr("ENC_TITLE"), mini(int(vs.x) - 64, 1240))
	_all = Encyclopedia.articles()
	var row := UITheme.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(row)
	var left := UITheme.vbox(8)
	left.custom_minimum_size.x = 300
	row.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = tr("ENC_SEARCH")
	_search.text_changed.connect(func(_t: String) -> void: _fill_list())
	left.add_child(_search)
	var ls := ScrollContainer.new()
	ls.custom_minimum_size.y = maxf(300.0, vs.y - 280.0)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(ls)
	_list = UITheme.vbox(1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_list)
	var vp := UITheme.panel(20)
	vp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vp)
	var vsc := ScrollContainer.new()
	vsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vsc.custom_minimum_size.y = maxf(300.0, vs.y - 240.0)
	vp.add_child(vsc)
	_view = UITheme.vbox(10)
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vsc.add_child(_view)
	var r2 := UITheme.hbox(12)
	r2.add_child(back_button())
	c.add_child(r2)
	if not overlay:
		footer()
	_fill_list()
	show_article(start_article if start_article != "" else "ui_overview")


func _fill_list() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var q := _search.text.strip_edges().to_lower()
	for cat: String in Encyclopedia.categories():
		var items := _all.filter(func(a: Dictionary) -> bool:
			return a["category"] == cat and (q == "" or String(a["title"]).to_lower().contains(q)))
		if items.is_empty():
			continue
		var h := UITheme.section(tr("ENC_CAT_" + cat.to_upper()))
		h.custom_minimum_size.y = 30
		_list.add_child(h)
		for a: Dictionary in items:
			var id := String(a["id"])
			var b := UITheme.ghost_button(String(a["title"]), func() -> void: show_article(id), String(a["icon"]) if String(a["icon"]) != "" else "")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_pressed = id == _current
			b.set_meta("article", id)
			_list.add_child(b)


func show_article(id: String) -> void:
	_current = id
	for b in _list.get_children():
		if b is Button:
			(b as Button).button_pressed = b.get_meta("article", "") == id
	for ch in _view.get_children():
		ch.queue_free()
	var a := Encyclopedia.find(id)
	if a.is_empty():
		return
	var head := UITheme.hbox(12)
	if String(a["icon"]) != "":
		head.add_child(Icons.rect(String(a["icon"]), 40, UITheme.TEXT))
	head.add_child(UITheme.title(String(a["title"]), UITheme.T_H2))
	_view.add_child(head)
	match String(a["kind"]):
		"text":
			for para in String(a["body"]).split("\n\n"):
				_view.add_child(_para(para))
		"term":
			var h := Glossary.hint(String(a["term"]))
			_view.add_child(_para(String(h["text"])))
			for r: Array in h["rows"]:
				_view.add_child(UITheme.label(String(r[0]), UITheme.T_CAPTION, UITheme.TEXT_FAINT))
				_view.add_child(_para(String(r[1])))
		"building":
			var r := Encyclopedia.rules()
			var k: int = a["building"]
			_view.add_child(_para(BuildingInfo.short(r, k)))
			_view.add_child(UITheme.section(tr("BI_EFFECT")))
			for line in BuildingInfo.effects(r, k):
				_view.add_child(_para(line, UITheme.TEXT))
			_view.add_child(UITheme.separator())
			_view.add_child(UITheme.key_value(tr("BI_COST"), UITheme.num(r.building_cost(k, 0)), UITheme.GOLD))
			if r.building_supplies(k) > 0.0:
				_view.add_child(UITheme.key_value(tr("BI_SUPPLIES"), UITheme.num(r.building_supplies(k)), UITheme.SUPPLY))
			_view.add_child(UITheme.key_value(tr("BI_TIME"), "%d %s" % [ceili(float(r.building_ticks(k)) / float(r.tick_rate)), tr("SEC_SHORT")]))
			if r.building_radius(k) > 0.0:
				_view.add_child(UITheme.key_value(tr("BI_RADIUS"), tr("BI_TILES") % roundi(r.building_radius(k))))
			if r.building_requires(k) != "":
				var tname := MetaData.text(ResearchSystem.tech(r.building_requires(k))["name"])
				_view.add_child(UITheme.key_value(tr("BI_REQUIRES"), tname, UITheme.WARN))
			# The symbol at the sizes it appears on the map.
			var sizes := UITheme.hbox(14)
			for px in [12, 20, 32]:
				sizes.add_child(Icons.rect(Symbols.building_id(r, k), px, UITheme.TEXT))
			_view.add_child(UITheme.label(tr("ENC_ON_MAP"), UITheme.T_CAPTION, UITheme.TEXT_FAINT))
			_view.add_child(sizes)
		"tech":
			var t := ResearchSystem.tech(String(a["tech"]))
			_view.add_child(_para(MetaData.text(t["desc"])))
			_view.add_child(UITheme.key_value(tr("ENC_BRANCH"), tr("BRANCH_" + String(t["branch"]).to_upper())))
			_view.add_child(UITheme.key_value(tr("ENC_COST_RP"), "%d" % int(t["cost"]), UITheme.RESEARCH))
			var req := PackedStringArray()
			for q: String in t["requires"]:
				req.append(MetaData.text(ResearchSystem.tech(q)["name"]))
			_view.add_child(UITheme.key_value(tr("ENC_REQUIRES"), ", ".join(req) if not req.is_empty() else tr("ENC_NOTHING")))
			for ln: Dictionary in SkillTree.describe(t.get("modifiers", {})):
				_view.add_child(UITheme.label(String(ln["text"]), UITheme.T_BODY, UITheme.GOOD if ln["good"] else UITheme.BAD))
			for u: String in t.get("unlocks", []):
				var bk := Encyclopedia.rules().building_index(u)
				if bk >= 0:
					_view.add_child(UITheme.icon_label(Symbols.building_id(Encyclopedia.rules(), bk), tr("ENC_UNLOCKS") % BuildingInfo.title(Encyclopedia.rules(), bk)))


func _para(text: String, color: Color = UITheme.TEXT_DIM) -> Label:
	var l := UITheme.label(text, UITheme.T_BODY_L, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	return l
