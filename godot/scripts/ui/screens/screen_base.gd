class_name ScreenBase
extends Control
## Common layout of menu screens: a dimmed world-map backdrop and a centred content column.

var content: VBoxContainer
## Shown over a running match (pause menu): "back" closes the overlay instead of changing screens.
var overlay: bool = false


func build_backdrop(live: bool = false, dim: float = 0.78) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if live and not overlay:
		add_child(MenuBackground.new())
	else:
		var tex := TextureRect.new()
		tex.texture = load("res://data/maps/earth/preview.png")
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.modulate = Color(1, 1, 1, 0.22)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
	# Darkening gradient: strong on the left (navigation), lighter on the right.
	var g := Gradient.new()
	g.set_color(0, Color(UITheme.BG, dim + 0.12))
	g.set_color(1, Color(UITheme.BG, dim - 0.3))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func build_frame(heading: String, width: int = 1100) -> VBoxContainer:
	build_backdrop(false, 0.8)
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
		content.add_child(UITheme.title(heading, UITheme.T_H1))
	return content


func footer() -> Label:
	var l := UITheme.label(tr("FOOTER_COPYRIGHT"), 13, UITheme.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 14)
	add_child(l)
	return l


func back_button(target: int = App.State.MAIN_MENU) -> Button:
	return UITheme.button(tr("BACK"), func() -> void: go_back(target), 160, "ui_left")


func go_back(target: int = App.State.MAIN_MENU) -> void:
	if overlay:
		queue_free()
	else:
		App.goto(target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and App.state != App.State.MAIN_MENU:
		get_viewport().set_input_as_handled()
		go_back()
