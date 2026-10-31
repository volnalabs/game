extends ScreenBase
## User settings (stored in user://settings.cfg).


func _ready() -> void:
	var c := build_frame(tr("SETTINGS_TITLE"), 640)
	var p := UITheme.panel(16)
	c.add_child(p)
	var form := UITheme.vbox(12)
	p.add_child(form)
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
	form.add_child(_row(tr("SETTINGS_LANGUAGE"), lang))
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
	form.add_child(_row(tr("SETTINGS_UI_SCALE"), scale))
	var edge := CheckBox.new()
	edge.text = tr("SETTINGS_EDGE_SCROLL")
	edge.button_pressed = Settings.edge_scroll
	edge.toggled.connect(func(on: bool) -> void:
		Settings.edge_scroll = on
		Settings.save_settings())
	form.add_child(edge)
	var dbg := CheckBox.new()
	dbg.text = tr("SETTINGS_AI_DEBUG")
	dbg.button_pressed = Settings.show_ai_debug
	dbg.toggled.connect(func(on: bool) -> void:
		Settings.show_ai_debug = on
		Settings.save_settings())
	form.add_child(dbg)
	c.add_child(back_button())


func _row(t: String, ctl: Control) -> Control:
	var h := UITheme.hbox(10)
	var l := UITheme.label(t, 15, UITheme.TEXT_DIM)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	h.add_child(ctl)
	return h
