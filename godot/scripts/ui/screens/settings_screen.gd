extends ScreenBase
## User settings (stored in user://settings.cfg), in tabs: General, Display (UI scale, animations,
## colour-vision mode with a preview, effects quality), Sound (volume per category with a sample),
## Controls (edge scrolling, rebindable hotkeys). Every change is applied and saved at once.

const TABS := ["general", "display", "audio", "controls"]
const SAMPLE_COLORS := ["#d94f4f", "#4fa34f", "#4f7fd9", "#d9a84f", "#9a4fd9", "#4fc4c4", "#d97f4f", "#8fbf3f"]

## Action being rebound ("" = none) and the last rebinding notice.
var _capturing: String = ""
var _notice: String = ""
var _tab: String = "general"
var _tab_buttons: Dictionary = {}
var _body: VBoxContainer


func _ready() -> void:
	var c := build_frame(tr("SETTINGS_TITLE"), 680)
	var bar := UITheme.hbox(4)
	bar.name = "Tabs"
	for id: String in TABS:
		var tid := id
		var b := UITheme.ghost_button(tr("SETTINGS_TAB_" + id.to_upper()), func() -> void: show_tab(tid))
		b.toggle_mode = true
		b.name = "Tab_" + id
		_tab_buttons[id] = b
		bar.add_child(b)
	c.add_child(bar)
	var p := UITheme.panel(16)
	c.add_child(p)
	_body = UITheme.vbox(12)
	p.add_child(_body)
	c.add_child(back_button())
	show_tab(_tab)


func show_tab(id: String) -> void:
	_tab = id
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == id
	for ch in _body.get_children():
		ch.queue_free()
	match id:
		"general":
			_general()
		"display":
			_display()
		"audio":
			_audio()
		"controls":
			_controls()


func _general() -> void:
	var lang := OptionButton.new()
	lang.add_item("Русский")
	lang.add_item("English")
	lang.select(0 if Settings.locale == "ru" else 1)
	lang.item_selected.connect(func(i: int) -> void:
		Settings.locale = "ru" if i == 0 else "en"
		Settings.apply()
		Settings.save_settings()
		if not overlay:
			App.goto(App.State.MAIN_MENU)
			App.goto(App.State.SETTINGS))
	_body.add_child(_row(tr("SETTINGS_LANGUAGE"), lang))
	_body.add_child(_check(tr("SETTINGS_AI_DEBUG"), Settings.show_ai_debug, func(on: bool) -> void: Settings.show_ai_debug = on))
	var tips := _check(tr("SETTINGS_TIPS"), Settings.show_tips, func(on: bool) -> void: Settings.show_tips = on)
	var tr_ := UITheme.hbox(12)
	tr_.add_child(tips)
	tr_.add_child(UITheme.ghost_button(tr("SETTINGS_TIPS_RESET"), func() -> void:
		Tips.reset()
		(tips as CheckBox).button_pressed = true, "ui_restart"))
	_body.add_child(tr_)


func _audio() -> void:
	var note := UITheme.label(tr("SETTINGS_AUDIO_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	_body.add_child(note)
	# [setting, label, test sound]
	for v: Array in [["volume_master", "SETTINGS_VOL_MASTER", "build_done"], ["volume_ui", "SETTINGS_VOL_UI", "ui_open"],
			["volume_sfx", "SETTINGS_VOL_SFX", "impact"], ["volume_alerts", "SETTINGS_VOL_ALERTS", "alert_attack"],
			["volume_ambience", "SETTINGS_VOL_AMBIENCE", ""]]:
		var key: String = v[0]
		var h := UITheme.hbox(10)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(Settings.get(key))
		s.custom_minimum_size.x = 240
		s.name = key
		var pct := UITheme.label("%d%%" % roundi(s.value * 100.0), 14, UITheme.TEXT_DIM)
		pct.custom_minimum_size.x = 48
		s.value_changed.connect(func(x: float) -> void:
			Settings.set(key, x)
			pct.text = "%d%%" % roundi(x * 100.0)
			Audio.apply_volumes())
		s.drag_ended.connect(func(_c: bool) -> void: Settings.save_settings())
		h.add_child(s)
		h.add_child(pct)
		var snd: String = v[2]
		if snd != "":
			var t := UITheme.icon_button("ui_volume", tr("SETTINGS_VOL_TEST"), func() -> void: Audio.play(snd), 30)
			t.set_meta("silent", true)
			t.set_meta("label", tr("SETTINGS_VOL_TEST"))
			h.add_child(t)
		_body.add_child(_row(tr(v[1]), h))
	_body.add_child(_check(tr("SETTINGS_MUTE_UNFOCUSED"), Settings.mute_unfocused, func(on: bool) -> void:
		Settings.mute_unfocused = on
		Audio.apply_volumes()))


func _display() -> void:
	var scale := HSlider.new()
	scale.min_value = 0.75
	scale.max_value = 1.5
	scale.step = 0.05
	scale.value = Settings.ui_scale
	scale.custom_minimum_size.x = 260
	scale.drag_ended.connect(func(_changed: bool) -> void:
		Settings.ui_scale = scale.value
		Settings.apply()
		Settings.save_settings())
	_body.add_child(_row(tr("SETTINGS_UI_SCALE"), scale))
	_body.add_child(_check(tr("SETTINGS_ANIMATIONS"), Settings.ui_animations, func(on: bool) -> void: Settings.ui_animations = on))
	var fx := OptionButton.new()
	fx.name = "EffectsQuality"
	for q in 3:
		fx.add_item(tr("SETTINGS_FX_%d" % q), q)
	fx.select(Settings.effects_quality)
	fx.item_selected.connect(func(i: int) -> void:
		Settings.effects_quality = i
		Settings.apply()
		Settings.save_settings())
	_body.add_child(_row(tr("SETTINGS_EFFECTS"), fx))
	var fxn := UITheme.label(tr("SETTINGS_EFFECTS_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	fxn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fxn.custom_minimum_size.x = 560
	_body.add_child(fxn)
	var cm := OptionButton.new()
	cm.name = "ColorMode"
	for m: String in ColorAccess.MODES:
		cm.add_item(tr("SETTINGS_COLOR_" + m.to_upper()))
	cm.select(maxi(0, ColorAccess.MODES.find(Settings.color_mode)))
	var preview := UITheme.hbox(4)
	cm.item_selected.connect(func(i: int) -> void:
		Settings.color_mode = ColorAccess.MODES[i]
		Settings.apply()
		Settings.save_settings()
		_fill_preview(preview))
	_body.add_child(_row(tr("SETTINGS_COLOR_MODE"), cm))
	_fill_preview(preview)
	_body.add_child(_row(tr("SETTINGS_COLOR_PREVIEW"), preview))
	var cn := UITheme.label(tr("SETTINGS_COLOR_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	cn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cn.custom_minimum_size.x = 560
	_body.add_child(cn)


## Sample state colours as the map shows them in the current mode.
func _fill_preview(box: HBoxContainer) -> void:
	for ch in box.get_children():
		ch.queue_free()
	for h: String in SAMPLE_COLORS:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(28, 20)
		r.color = ColorAccess.color(Color(h))
		box.add_child(r)


func _controls() -> void:
	_body.add_child(_check(tr("SETTINGS_EDGE_SCROLL"), Settings.edge_scroll, func(on: bool) -> void:
		Settings.edge_scroll = on
		Settings.apply()))
	var note := UITheme.label(tr("SETTINGS_KEYS_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	_body.add_child(note)
	if _notice != "":
		_body.add_child(UITheme.label(_notice, UITheme.T_CAPTION, UITheme.WARN))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UITheme.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id: String in Keys.ids():
		var aid := id
		var b := UITheme.button(tr("KEYS_PRESS") if _capturing == id else Keys.label(id), func() -> void:
			_capturing = aid
			_notice = ""
			show_tab("controls"), 150)
		b.name = "Key_" + id
		b.set_meta("action", id)
		var h := UITheme.hbox(10)
		var l := UITheme.label(tr(Keys.label_key(id)), 14, UITheme.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(b)
		list.add_child(h)
	_body.add_child(scroll)
	_body.add_child(UITheme.ghost_button(tr("SETTINGS_KEYS_RESET"), func() -> void:
		Settings.key_overrides.clear()
		Settings.apply()
		Settings.save_settings()
		_notice = ""
		show_tab("controls"), "ui_restart"))


## While an action waits for its key, the next key press binds it (Esc cancels).
func _input(event: InputEvent) -> void:
	if _capturing == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	var code := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
	var id := _capturing
	_capturing = ""
	if code == KEY_ESCAPE:
		show_tab("controls")
		return
	bind(id, code)


## Binds `code` to action `id` and reports which action lost it.
func bind(id: String, code: int) -> void:
	var lost := Keys.rebind(id, code, Settings.key_overrides)
	if lost == "reserved":
		_notice = tr("SETTINGS_KEYS_RESERVED")
	elif lost != "":
		_notice = tr("SETTINGS_KEYS_MOVED") % [Keys.key_name(code), tr(Keys.label_key(lost))]
	else:
		_notice = ""
	Settings.apply()
	Settings.save_settings()
	show_tab("controls")


func _check(text: String, on: bool, cb: Callable) -> CheckBox:
	var b := CheckBox.new()
	b.text = text
	b.button_pressed = on
	b.toggled.connect(func(x: bool) -> void:
		cb.call(x)
		Settings.save_settings())
	return b


func _row(t: String, ctl: Control) -> Control:
	var h := UITheme.hbox(10)
	var l := UITheme.label(t, 15, UITheme.TEXT_DIM)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	h.add_child(ctl)
	return h
