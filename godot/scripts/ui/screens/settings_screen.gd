extends ScreenBase
## User settings (stored in user://settings.cfg), in tabs: General, Sound (volume per category with
## a test sound each). Every change is applied and saved at once.

const TABS := ["general", "audio"]

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
		"audio":
			_audio()


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
	_body.add_child(_check(tr("SETTINGS_EDGE_SCROLL"), Settings.edge_scroll, func(on: bool) -> void: Settings.edge_scroll = on))
	_body.add_child(_check(tr("SETTINGS_AI_DEBUG"), Settings.show_ai_debug, func(on: bool) -> void: Settings.show_ai_debug = on))
	_body.add_child(_check(tr("SETTINGS_ANIMATIONS"), Settings.ui_animations, func(on: bool) -> void: Settings.ui_animations = on))
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
