extends ScreenBase
## Inventory: every cosmetic item (owned and locked) with category tabs, search, rarity filter and
## sort; selecting an item shows what it changes, and equips / unequips or crafts it.

var _grid: GridContainer
var _detail: VBoxContainer
var _search: LineEdit
var _cat: String = ""
var _rarity: String = ""
var _sort: String = "rarity"
var _owned_only: bool = false
static var _selected: String = ""
var _frag: Label


func _ready() -> void:
	var vs := get_viewport_rect().size
	var c := build_frame(tr("MENU_INVENTORY"), mini(int(vs.x) - 64, 1400))
	var bar := UITheme.hbox(8)
	c.add_child(bar)
	var cats := OptionButton.new()
	cats.add_item(tr("CAT_ALL"))
	for cat: String in MetaData.categories():
		cats.add_item(ItemView.category_name(cat))
	cats.item_selected.connect(func(i: int) -> void:
		_cat = "" if i == 0 else String(MetaData.categories()[i - 1])
		_rebuild())
	bar.add_child(cats)
	var rar := OptionButton.new()
	rar.add_item(tr("RARITY_ALL"))
	for r: String in MetaData.rarity_order():
		rar.add_item(ItemView.rarity_name(r))
	rar.item_selected.connect(func(i: int) -> void:
		_rarity = "" if i == 0 else String(MetaData.rarity_order()[i - 1])
		_rebuild())
	bar.add_child(rar)
	var sort := OptionButton.new()
	for s in ["rarity", "name", "category"]:
		sort.add_item(tr("SORT_" + s.to_upper()))
	sort.item_selected.connect(func(i: int) -> void:
		_sort = ["rarity", "name", "category"][i]
		_rebuild())
	bar.add_child(sort)
	var own := CheckBox.new()
	own.text = tr("INV_OWNED_ONLY")
	own.toggled.connect(func(on: bool) -> void:
		_owned_only = on
		_rebuild())
	bar.add_child(own)
	bar.add_child(UITheme.spacer())
	bar.add_child(Icons.rect("ui_search", 18, UITheme.TEXT_DIM))
	_search = LineEdit.new()
	_search.placeholder_text = tr("INV_SEARCH")
	_search.custom_minimum_size.x = 200
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	bar.add_child(_search)
	_frag = UITheme.label("", UITheme.T_BODY, UITheme.TEXT)
	bar.add_child(Icons.rect("r_fragments", 18, UITheme.TEXT))
	bar.add_child(_frag)
	var row := UITheme.hbox(14)
	c.add_child(row)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, maxf(320.0, vs.y - 250.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = maxi(2, int((mini(int(vs.x) - 64, 1400) - 370) / 178))
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(_grid)
	var dp := UITheme.panel(16)
	dp.custom_minimum_size = Vector2(320, 0)
	dp.size_flags_horizontal = Control.SIZE_SHRINK_END
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
	_frag.text = UITheme.num(float(p.fragments()))
	for ch in _grid.get_children():
		ch.queue_free()
	var list := Inventory.list(p, {"category": _cat, "rarity": _rarity, "owned_only": _owned_only, "search": _search.text}, _sort)
	for it: Dictionary in list:
		var card := ItemView.card(it, p)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var id := String(it["id"])
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_select(id)
				if e.double_click and p.owns(id):
					Profile.equip(id)
					_refresh_all())
		_grid.add_child(card)
	if list.is_empty():
		_grid.add_child(UITheme.label(tr("INV_EMPTY"), UITheme.T_BODY, UITheme.TEXT_DIM))
	_select(_selected if _selected != "" else (String(list[0]["id"]) if not list.is_empty() else ""))


func _refresh_all() -> void:
	# Equipment can change the UI theme (accent colour everywhere): rebuild the screen.
	App.refresh_screen()


func _select(id: String) -> void:
	_selected = id
	for ch in _detail.get_children():
		ch.queue_free()
	if id == "":
		return
	var p: ProfileData = Profile.data
	var it := MetaData.item(id)
	var pv := ItemView.preview(it, 140)
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail.add_child(pv)
	_detail.add_child(UITheme.label(MetaData.text(it["name"]), UITheme.T_TITLE, UITheme.TEXT, true))
	var rc := UITheme.rarity_color(String(it["rarity"]))
	var h := UITheme.hbox(8)
	h.add_child(UITheme.badge(ItemView.rarity_name(String(it["rarity"])), rc))
	h.add_child(UITheme.label(ItemView.category_name(String(it["category"])), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	_detail.add_child(h)
	var eff := UITheme.label(tr("CAT_" + String(it["category"]).to_upper() + "_EFFECT"), UITheme.T_BODY, UITheme.TEXT_DIM)
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.custom_minimum_size.x = 280
	_detail.add_child(eff)
	_detail.add_child(UITheme.label(tr("INV_COSMETIC_ONLY"), UITheme.T_CAPTION, UITheme.TEXT_FAINT))
	var cat := String(it["category"])
	if p.owns(id):
		if p.equipped(cat) == id:
			_detail.add_child(UITheme.icon_label("ui_check", tr("INV_EQUIPPED"), UITheme.ACCENT))
			if not cat in ["avatar", "emblem", "frame", "title"]:
				_detail.add_child(UITheme.button(tr("INV_UNEQUIP"), func() -> void:
					Profile.unequip(cat)
					_refresh_all(), 0, "ui_close"))
		else:
			_detail.add_child(UITheme.accent_button(tr("INV_EQUIP"), func() -> void:
				Profile.equip(id)
				_refresh_all(), 0, "ui_check"))
	else:
		var cost := Inventory.craft_cost(id)
		var b := UITheme.button(tr("INV_CRAFT") % cost, func() -> void:
			if Profile.craft(id):
				_rebuild(), 0, "r_fragments")
		b.disabled = p.fragments() < cost
		_detail.add_child(b)
		var how := UITheme.label(tr("INV_HOW_TO_GET"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size.x = 280
		_detail.add_child(how)
