extends ScreenBase
## Main menu.


func _ready() -> void:
	var c := build_frame("", 420)
	var t := UITheme.title("VolnaLabs", 56)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(t)
	var sub := UITheme.label(tr("GAME_SUBTITLE"), 22, UITheme.ACCENT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(sub)
	c.add_child(UITheme.spacer(false))
	var buttons := [
		[tr("MENU_NEW_GAME"), func() -> void: App.goto(App.State.MAP_SELECT), true],
		[tr("MENU_LOAD"), func() -> void: App.goto(App.State.LOAD_GAME), false],
		[tr("MENU_GENERATOR"), func() -> void: App.goto(App.State.MAP_GENERATOR), false],
		[tr("MENU_SETTINGS"), func() -> void: App.goto(App.State.SETTINGS), false],
		[tr("MENU_CREDITS"), func() -> void: App.goto(App.State.CREDITS), false],
		[tr("MENU_QUIT"), func() -> void: get_tree().quit(), false],
	]
	for b: Array in buttons:
		var btn := UITheme.accent_button(b[0], b[1]) if b[2] else UITheme.button(b[0], b[1])
		btn.custom_minimum_size = Vector2(420, 48)
		btn.add_theme_font_size_override("font_size", 20)
		c.add_child(btn)
	footer()
