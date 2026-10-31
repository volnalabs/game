class_name ScreenBase
extends Control
## Common layout of menu screens: a dimmed world-map backdrop and a centred content column.

var content: VBoxContainer


func build_frame(heading: String, width: int = 1100) -> VBoxContainer:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var tex := TextureRect.new()
	tex.texture = load("res://data/maps/earth/preview.png")
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.modulate = Color(1, 1, 1, 0.18)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(tex)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	content = UITheme.vbox(14)
	content.custom_minimum_size.x = width
	center.add_child(content)
	if heading != "":
		content.add_child(UITheme.title(heading, 32))
	return content


func footer() -> Label:
	var l := UITheme.label(tr("FOOTER_COPYRIGHT"), 13, UITheme.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 14)
	add_child(l)
	return l


func back_button(target: int = App.State.MAIN_MENU) -> Button:
	return UITheme.button(tr("BACK"), func() -> void: App.goto(target), 160)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and App.state != App.State.MAIN_MENU:
		App.goto(App.State.MAIN_MENU)
