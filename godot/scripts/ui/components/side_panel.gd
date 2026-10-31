class_name SidePanel
extends PanelContainer
## A titled, collapsible panel used by the HUD docks: header (icon, title, close button) and a
## scrollable body that panel builders fill.

signal closed

var body: VBoxContainer
var _title: Label
var _icon: TextureRect


func _init(width: int = 360) -> void:
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, 10, Color.TRANSPARENT, 12))
	custom_minimum_size.x = width
	var v := UITheme.vbox(10)
	add_child(v)
	var head := UITheme.hbox(8)
	_icon = Icons.rect("ui_info", 20, UITheme.TEXT_DIM)
	head.add_child(_icon)
	_title = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT)
	_title.add_theme_font_override("font", UITheme.font_medium)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := UITheme.icon_button("ui_close", "", func() -> void: closed.emit(), 30)
	Hints.attach(close, {"title": tr("CLOSE"), "text": tr("PANEL_CLOSE_HINT")})
	head.add_child(close)
	v.add_child(head)
	v.add_child(UITheme.separator())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 120
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	body = UITheme.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)


func set_header(icon: String, title: String) -> void:
	_icon.texture = Icons.tex(icon, 20)
	_title.text = title


func clear() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
