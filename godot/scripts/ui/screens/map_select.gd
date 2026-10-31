extends ScreenBase
## Map selection: one card per registered map (from MapRegistry — nothing hard-coded), plus
## "Random world" and the world generator.

var _selected: MapDefinition
var _cards: Dictionary = {}
var _next: Button
var _status: Label


func _ready() -> void:
	var c := build_frame(tr("MAP_SELECT_TITLE"), 1320)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1320, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for def in MapRegistry.all():
		var card := _card(def)
		grid.add_child(card)
		_cards[def.id] = card
	var row := UITheme.hbox(12)
	row.add_child(back_button())
	row.add_child(UITheme.button(tr("MENU_GENERATOR"), func() -> void: App.goto(App.State.MAP_GENERATOR), 220))
	row.add_child(UITheme.button(tr("RANDOM_WORLD"), _random_world, 220))
	_status = UITheme.label("", 15, UITheme.TEXT_DIM)
	row.add_child(_status)
	row.add_child(UITheme.spacer())
	_next = UITheme.accent_button(tr("NEXT"), _go_next, 200)
	_next.disabled = true
	row.add_child(_next)
	c.add_child(row)
	if App.map_def != null and _cards.has(App.map_def.id):
		_select(App.map_def)


func _card(def: MapDefinition) -> Control:
	var p := UITheme.panel(10)
	p.custom_minimum_size = Vector2(318, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UITheme.vbox(6)
	p.add_child(v)
	var tex := TextureRect.new()
	if ResourceLoader.exists(def.preview_path()):
		tex.texture = load(def.preview_path())
	tex.custom_minimum_size = Vector2(296, 150)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	v.add_child(tex)
	var head := UITheme.hbox(6)
	head.add_child(UITheme.label(def.display_name(), 20, UITheme.TEXT, true))
	head.add_child(UITheme.spacer())
	head.add_child(UITheme.label(tr("CATEGORY_" + def.category.to_upper()), 13, UITheme.ACCENT))
	v.add_child(head)
	var desc := UITheme.label(def.description(), 13, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(296, 54)
	v.add_child(desc)
	var st: Dictionary = def.stats
	v.add_child(UITheme.label(tr("MAP_STATS") % [def.width, def.height, int(st.get("continents", 0)),
		int(st.get("islands", 0)), def.nations.size()], 13))
	v.add_child(UITheme.label(tr("MAP_LAND") % UITheme.num(float(st.get("land_tiles", 0))), 13))
	var feats := PackedStringArray()
	for f in def.features:
		feats.append(tr("FEATURE_" + f.to_upper()))
	var fl := UITheme.label(" · ".join(feats), 12, UITheme.ACCENT_2)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size.x = 296
	v.add_child(fl)
	v.add_child(UITheme.label(tr("MAP_RECOMMENDED") % [def.recommended_bots.x, def.recommended_bots.y], 13, UITheme.TEXT_DIM))
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(def)
			if e.double_click:
				_go_next())
	return p


func _select(def: MapDefinition) -> void:
	_selected = def
	for id: String in _cards:
		var card: PanelContainer = _cards[id]
		card.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL_LIGHT if id == def.id else UITheme.PANEL,
			10, UITheme.ACCENT if id == def.id else UITheme.BORDER, 10))
	_next.disabled = false


func _go_next() -> void:
	if _selected == null:
		return
	App.select_map(_selected)
	App.goto(App.State.MATCH_SETUP)


func _random_world() -> void:
	_status.text = tr("GENERATING")
	await get_tree().process_frame
	await get_tree().process_frame
	var seed_value := randi() % 1000000
	var presets := GenParams.preset_ids()
	var p := GenParams.from_preset(presets[seed_value % (presets.size() - 1)], seed_value, "M")
	var res := MapGenerator.new().generate(p)
	App.select_map(MapGenerator.definition_for(res, tr("RANDOM_WORLD"), "Random world"), res.map)
	App.goto(App.State.MATCH_SETUP)
