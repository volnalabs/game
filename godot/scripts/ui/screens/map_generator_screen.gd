extends ScreenBase
## World generator: every GenParams field with a live preview. The same seed and settings always
## rebuild the same world.

var p: GenParams
var _preview: TextureRect
var _stats: Label
var _play: Button
var _seed_edit: LineEdit
var _result: MapGenerator.GenResult
var _controls: Dictionary = {}
var _preset_opt: OptionButton
var _size_opt: OptionButton
var _sym_opt: OptionButton


func _ready() -> void:
	p = GenParams.from_preset("continents", randi() % 1000000, "M")
	var c := build_frame(tr("GEN_TITLE"), 1300)
	var row := UITheme.hbox(18)
	c.add_child(row)
	var left := UITheme.panel(14)
	left.custom_minimum_size = Vector2(430, 620)
	row.add_child(left)
	var form := UITheme.vbox(6)
	left.add_child(form)
	_preset_opt = OptionButton.new()
	for id: String in GenParams.preset_ids():
		_preset_opt.add_item(tr("PRESET_" + id.to_upper()))
	_preset_opt.item_selected.connect(func(i: int) -> void:
		var sd := p.seed
		var sz := p.size_name
		p.apply_preset(GenParams.preset_ids()[i])
		p.seed = sd
		p.set_size(sz)
		_sync_controls())
	form.add_child(_field(tr("GEN_PRESET"), _preset_opt))
	var seed_row := UITheme.hbox(6)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(p.seed)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_changed.connect(func(t: String) -> void: p.seed = int(t) if t.is_valid_int() else hash(t) % 1000000)
	seed_row.add_child(_seed_edit)
	seed_row.add_child(UITheme.button("🎲", func() -> void:
		p.seed = randi() % 1000000
		_seed_edit.text = str(p.seed)))
	form.add_child(_field(tr("GEN_SEED"), seed_row))
	_size_opt = OptionButton.new()
	for s in ["S", "M", "L", "XL"]:
		var wh: Array = GenParams.presets()["sizes"][s]
		_size_opt.add_item("%s — %d×%d" % [tr("SIZE_" + s), wh[0], wh[1]])
	_size_opt.select(1)
	_size_opt.item_selected.connect(func(i: int) -> void: p.set_size(["S", "M", "L", "XL"][i]))
	form.add_child(_field(tr("GEN_SIZE"), _size_opt))
	_slider(form, "continents", tr("GEN_CONTINENTS"), 1, 8, 1)
	_slider(form, "islands", tr("GEN_ISLANDS"), 0, 80, 1)
	_slider(form, "land_percent", tr("GEN_LAND"), 0.15, 0.7, 0.01)
	_slider(form, "inland_seas", tr("GEN_INLAND_SEAS"), 0, 4, 1)
	_slider(form, "river_density", tr("GEN_RIVERS"), 0.0, 2.0, 0.1)
	_slider(form, "roughness", tr("GEN_ROUGHNESS"), 0.2, 1.0, 0.05)
	_slider(form, "mountains", tr("GEN_MOUNTAINS"), 0.0, 1.0, 0.05)
	_slider(form, "start_positions", tr("GEN_STARTS"), 4, 60, 1)
	_sym_opt = OptionButton.new()
	for s in ["none", "mirror", "rotate2", "rotate4"]:
		_sym_opt.add_item(tr("SYM_" + s.to_upper()))
	_sym_opt.item_selected.connect(func(i: int) -> void: p.symmetry = ["none", "mirror", "rotate2", "rotate4"][i])
	form.add_child(_field(tr("GEN_SYMMETRY"), _sym_opt))
	var right := UITheme.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var pp := UITheme.panel(8)
	right.add_child(pp)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(820, 440)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pp.add_child(_preview)
	_stats = UITheme.label(tr("GEN_HINT"), 15, UITheme.TEXT_DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_stats)
	var actions := UITheme.hbox(12)
	actions.add_child(back_button())
	actions.add_child(UITheme.spacer())
	actions.add_child(UITheme.button(tr("GEN_GENERATE"), _generate, 220))
	_play = UITheme.accent_button(tr("GEN_PLAY"), _play_map, 220)
	_play.disabled = true
	actions.add_child(_play)
	right.add_child(actions)
	_sync_controls()


func _field(label_text: String, ctl: Control) -> Control:
	var h := UITheme.hbox(8)
	var l := UITheme.label(label_text, 14, UITheme.TEXT_DIM)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h


func _slider(form: VBoxContainer, prop: String, label_text: String, lo: float, hi: float, step: float) -> void:
	var h := UITheme.hbox(8)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 170
	var val := UITheme.label("", 14)
	val.custom_minimum_size.x = 44
	s.value_changed.connect(func(v: float) -> void:
		if step >= 1.0:
			p.set(prop, int(v))
			val.text = str(int(v))
		else:
			p.set(prop, v)
			val.text = ("%d%%" % int(v * 100.0)) if prop == "land_percent" else "%.2f" % v)
	h.add_child(s)
	h.add_child(val)
	form.add_child(_field(label_text, h))
	_controls[prop] = s


func _sync_controls() -> void:
	_preset_opt.select(GenParams.preset_ids().find(p.preset))
	for prop: String in _controls:
		(_controls[prop] as HSlider).value = float(p.get(prop))
	_sym_opt.select(["none", "mirror", "rotate2", "rotate4"].find(p.symmetry))


func _generate() -> void:
	_stats.text = tr("GENERATING")
	_play.disabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	_result = MapGenerator.new().generate(GenParams.from_dict(p.to_dict()))
	_preview.texture = ImageTexture.create_from_image(TerrainColors.preview(_result.map, 820))
	var s := _result.stats
	_stats.text = tr("GEN_RESULT") % [_result.map.width, _result.map.height, UITheme.num(float(s["land_tiles"])),
		int(s["continents"]), int(s["islands"]), _result.starts.size(), float(s["fairness"]) * 100.0, int(s["ms"])]
	_play.disabled = false


func _play_map() -> void:
	if _result == null:
		return
	App.select_map(MapGenerator.definition_for(_result, tr("GEN_WORLD_NAME") % p.seed, "World %d" % p.seed), _result.map)
	App.goto(App.State.MATCH_SETUP)
