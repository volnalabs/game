extends ScreenBase
## New game settings: your state, opponents, difficulty, AI personalities, tribes, victory
## conditions and the match seed. Fills App.config.

var cfg: MatchConfig
var def: MapDefinition
var _diff_buttons: Dictionary = {}
var _bots_val: Label
var _tribes_val: Label
var _dom_val: Label


func _ready() -> void:
	def = App.map_def
	if def == null:
		App.goto(App.State.MAP_SELECT)
		return
	cfg = App.config
	cfg.map_id = def.id
	cfg.generator = def.generator
	cfg.has_player = true
	cfg.seed = randi() % 1000000
	var max_bots := maxi(1, mini(120, maxi(def.max_bots, 8)))
	cfg.bots = clampi(Settings.last_bots, 1, max_bots) if Settings.last_bots > 0 else clampi((def.recommended_bots.x + def.recommended_bots.y) / 2, 1, max_bots)
	cfg.difficulty = Settings.last_difficulty
	cfg.tribes = int(def.balance.get("tribes_default", 40))
	var c := build_frame(tr("SETUP_TITLE"), 1180)
	var row := UITheme.hbox(18)
	c.add_child(row)
	# Left: the map.
	var mp := UITheme.panel(12)
	mp.custom_minimum_size.x = 420
	row.add_child(mp)
	var mv := UITheme.vbox(8)
	mp.add_child(mv)
	var tex := TextureRect.new()
	if App.map_data != null:
		tex.texture = ImageTexture.create_from_image(TerrainColors.preview(App.map_data, 400))
	elif ResourceLoader.exists(def.preview_path()):
		tex.texture = load(def.preview_path())
	tex.custom_minimum_size = Vector2(396, 200)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mv.add_child(tex)
	mv.add_child(UITheme.label(def.display_name(), 24, UITheme.TEXT, true))
	var d := UITheme.label(def.description(), 14, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 396
	mv.add_child(d)
	mv.add_child(UITheme.label(tr("MAP_RECOMMENDED") % [def.recommended_bots.x, def.recommended_bots.y], 14, UITheme.ACCENT))
	# Right: settings.
	var sp := UITheme.panel(16)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var form := UITheme.vbox(12)
	sp.add_child(form)
	var nation := OptionButton.new()
	nation.add_item(tr("SETUP_FREE_STATE"))
	var names: Array = []
	for i in def.nations.size():
		names.append([MapDefinition.nation_name(def.nations[i]), i])
	names.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	for e: Array in names:
		nation.add_item(e[0], int(e[1]) + 1)
	cfg.player_nation = -1
	nation.item_selected.connect(func(i: int) -> void: cfg.player_nation = nation.get_item_id(i) - 1 if i > 0 else -1)
	form.add_child(_field(tr("SETUP_YOUR_STATE"), nation))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = tr("SETUP_NAME_HINT")
	name_edit.custom_minimum_size.x = 320
	name_edit.text_changed.connect(func(t: String) -> void: cfg.player_name = t.strip_edges())
	form.add_child(_field(tr("SETUP_NAME"), name_edit))
	var bots_row := UITheme.hbox(8)
	var bots := HSlider.new()
	bots.min_value = 1
	bots.max_value = max_bots
	bots.value = cfg.bots
	bots.custom_minimum_size.x = 380
	_bots_val = UITheme.label(str(cfg.bots), 16)
	bots.value_changed.connect(func(v: float) -> void:
		cfg.bots = int(v)
		_bots_val.text = str(int(v)))
	bots_row.add_child(bots)
	bots_row.add_child(_bots_val)
	form.add_child(_field(tr("SETUP_BOTS"), bots_row))
	var diff_row := UITheme.hbox(8)
	for id: String in AIProfile.difficulty_ids():
		var b := UITheme.button(tr("DIFF_" + id.to_upper()), func() -> void: _set_diff(id), 150)
		b.toggle_mode = true
		_diff_buttons[id] = b
		diff_row.add_child(b)
	form.add_child(_field(tr("SETUP_DIFFICULTY"), diff_row))
	var diff_hint := UITheme.label(tr("SETUP_DIFF_HINT"), 13, UITheme.TEXT_DIM)
	diff_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(diff_hint)
	_set_diff(cfg.difficulty)
	var pers := OptionButton.new()
	pers.add_item(tr("PERS_MIXED"))
	for pid: String in AIProfile.personality_ids():
		pers.add_item(tr("PERS_" + pid.to_upper()))
	pers.item_selected.connect(func(i: int) -> void: cfg.personality_mix = "mixed" if i == 0 else AIProfile.personality_ids()[i - 1])
	cfg.personality_mix = "mixed"
	form.add_child(_field(tr("SETUP_PERSONALITIES"), pers))
	var tr_row := UITheme.hbox(8)
	var tribes := HSlider.new()
	tribes.min_value = 0
	tribes.max_value = 150
	tribes.value = cfg.tribes
	tribes.custom_minimum_size.x = 380
	_tribes_val = UITheme.label(str(cfg.tribes), 16)
	tribes.value_changed.connect(func(v: float) -> void:
		cfg.tribes = int(v)
		_tribes_val.text = str(int(v)))
	tr_row.add_child(tribes)
	tr_row.add_child(_tribes_val)
	form.add_child(_field(tr("SETUP_TRIBES"), tr_row))
	var dom_row := UITheme.hbox(8)
	var dom := HSlider.new()
	dom.min_value = 0.5
	dom.max_value = 1.0
	dom.step = 0.05
	dom.value = cfg.victory.domination_share
	dom.custom_minimum_size.x = 380
	_dom_val = UITheme.label("%d%%" % int(cfg.victory.domination_share * 100.0), 16)
	dom.value_changed.connect(func(v: float) -> void:
		cfg.victory.domination_share = v
		_dom_val.text = "%d%%" % int(round(v * 100.0)))
	dom_row.add_child(dom)
	dom_row.add_child(_dom_val)
	form.add_child(_field(tr("SETUP_DOMINATION"), dom_row))
	var tl := OptionButton.new()
	for m in [0, 30, 60, 90]:
		tl.add_item(tr("TIME_NONE") if m == 0 else tr("TIME_MIN") % m, m)
	tl.item_selected.connect(func(i: int) -> void: cfg.victory.time_limit_minutes = tl.get_item_id(i))
	form.add_child(_field(tr("SETUP_TIME_LIMIT"), tl))
	var elim := CheckBox.new()
	for st_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		elim.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	elim.text = tr("SETUP_ELIMINATE_ALL")
	elim.button_pressed = cfg.victory.eliminate_all
	elim.toggled.connect(func(on: bool) -> void: cfg.victory.eliminate_all = on)
	form.add_child(elim)
	# Profile perks of the loadout, or Fair mode (no perks for anyone, +10% rewards).
	var fair := CheckBox.new()
	for st_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		fair.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	fair.text = tr("SETUP_FAIR")
	fair.tooltip_text = tr("SETUP_FAIR_TIP")
	fair.button_pressed = cfg.fair_mode
	var perks_l := UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	var show_perks := func() -> void:
		var lo: Array = Profile.data.data["perks"]["loadout"]
		if cfg.fair_mode:
			perks_l.text = tr("SETUP_PERKS_OFF")
		elif lo.is_empty():
			perks_l.text = tr("SETUP_PERKS_NONE")
		else:
			var perk_names := PackedStringArray()
			for id: String in lo:
				perk_names.append(MetaData.text(MetaPerks.perk(id).get("name", {})))
			perks_l.text = tr("SETUP_PERKS") % ", ".join(perk_names)
	fair.toggled.connect(func(on: bool) -> void:
		cfg.fair_mode = on
		show_perks.call())
	show_perks.call()
	var fr := UITheme.hbox(12)
	fr.add_child(fair)
	fr.add_child(perks_l)
	form.add_child(fr)
	var seed_edit := LineEdit.new()
	seed_edit.text = str(cfg.seed)
	seed_edit.text_changed.connect(func(t: String) -> void: cfg.seed = int(t) if t.is_valid_int() else hash(t) % 1000000)
	form.add_child(_field(tr("SETUP_SEED"), seed_edit))
	var actions := UITheme.hbox(12)
	actions.add_child(back_button(App.State.MAP_SELECT))
	actions.add_child(UITheme.spacer())
	actions.add_child(UITheme.accent_button(tr("SETUP_START"), _start, 260))
	c.add_child(actions)


func _field(label_text: String, ctl: Control) -> Control:
	var h := UITheme.hbox(10)
	var l := UITheme.label(label_text, 15, UITheme.TEXT_DIM)
	l.custom_minimum_size.x = 210
	h.add_child(l)
	h.add_child(ctl)
	return h


func _set_diff(id: String) -> void:
	cfg.difficulty = id
	for k: String in _diff_buttons:
		(_diff_buttons[k] as Button).button_pressed = k == id


func _start() -> void:
	Settings.last_bots = cfg.bots
	Settings.last_difficulty = cfg.difficulty
	Settings.save_settings()
	App.start_new_match()
