extends ScreenBase
## Map selection: one card per registered map (from MapRegistry — nothing hard-coded), plus
## "Random world" and the world generator.

const CARD_W := 300
const GAP := 14

var _selected: MapDefinition
var _cards: Dictionary = {}
var _next: Button
var _status: Label
var _grid: GridContainer
var _scroll: ScrollContainer


func _ready() -> void:
	var vs := get_viewport_rect().size
	var cols := clampi(int((vs.x - 64.0 + GAP) / (CARD_W + GAP)), 2, 5)
	var c := build_frame(tr("MAP_SELECT_TITLE"), cols * (CARD_W + GAP) - GAP + 12)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, maxf(300.0, vs.y - 230.0))
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c.add_child(_scroll)
	var grid := GridContainer.new()
	_grid = grid
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(grid)
	for def in MapRegistry.all():
		var card := _card(def)
		grid.add_child(card)
		_cards[def.id] = card
	var row := UITheme.hbox(12)
	row.add_child(back_button())
	row.add_child(UITheme.button(tr("MENU_GENERATOR"), func() -> void: App.goto(App.State.MAP_GENERATOR), 220, "ui_world"))
	row.add_child(UITheme.button(tr("RANDOM_WORLD"), _random_world, 220, "ui_sparkles"))
	_status = UITheme.label("", 15, UITheme.TEXT_DIM)
	row.add_child(_status)
	row.add_child(UITheme.spacer())
	_next = UITheme.accent_button(tr("NEXT"), _go_next, 200, "ui_right")
	_next.disabled = true
	row.add_child(_next)
	c.add_child(row)
	if App.map_def != null and _cards.has(App.map_def.id):
		_select(App.map_def)


func _card(def: MapDefinition) -> Control:
	var p := UITheme.card(10)
	p.custom_minimum_size = Vector2(CARD_W, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func() -> void: if _selected != def: Anim.pulse(p, Color(1.12, 1.12, 1.12), 0.3))
	var v := UITheme.vbox(6)
	p.add_child(v)
	var tex := TextureRect.new()
	if ResourceLoader.exists(def.preview_path()):
		tex.texture = load(def.preview_path())
	tex.custom_minimum_size = Vector2(CARD_W - 20, 140)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	v.add_child(tex)
	var head := UITheme.hbox(6)
	var name_l := UITheme.label(def.display_name(), UITheme.T_TITLE, UITheme.TEXT, true)
	name_l.clip_text = true
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	head.add_child(UITheme.badge(tr("CATEGORY_" + def.category.to_upper()), UITheme.ACCENT))
	v.add_child(head)
	var desc := UITheme.label(def.description(), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_W - 20, 54)
	desc.max_lines_visible = 3
	v.add_child(desc)
	var st: Dictionary = def.stats
	var facts := UITheme.hbox(10)
	facts.add_child(UITheme.icon_label("ui_map", "%d×%d" % [def.width, def.height], UITheme.TEXT_DIM, UITheme.T_CAPTION))
	facts.add_child(UITheme.icon_label("ui_flag", str(def.nations.size()), UITheme.TEXT_DIM, UITheme.T_CAPTION))
	facts.add_child(UITheme.icon_label("r_land", UITheme.num(float(st.get("land_tiles", 0))), UITheme.TEXT_DIM, UITheme.T_CAPTION))
	facts.add_child(UITheme.icon_label("ui_users", "%d–%d" % [def.recommended_bots.x, def.recommended_bots.y], UITheme.TEXT_DIM, UITheme.T_CAPTION))
	facts.tooltip_text = (tr("MAP_STATS") % [def.width, def.height, int(st.get("continents", 0)),
		int(st.get("islands", 0)), def.nations.size()]) + "\n" + (tr("MAP_RECOMMENDED") % [def.recommended_bots.x, def.recommended_bots.y])
	facts.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(facts)
	var feats := PackedStringArray()
	for f in def.features:
		feats.append(tr("FEATURE_" + f.to_upper()))
	var fl := UITheme.label(" · ".join(feats), 12, UITheme.ACCENT_2)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size.x = CARD_W - 20
	fl.max_lines_visible = 2
	v.add_child(fl)
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
		var on := id == def.id
		var sb := UITheme.box(UITheme.SURFACE_3 if on else UITheme.SURFACE_2, UITheme.R_M, UITheme.ACCENT if on else UITheme.STROKE, 10)
		sb.set_border_width_all(2 if on else 1)
		card.add_theme_stylebox_override("panel", sb)
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
