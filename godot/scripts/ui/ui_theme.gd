class_name UITheme
extends RefCounted
## The design system: one dark, map-first palette, the Rubik font, rounded panels and a few
## helpers to build consistent widgets from code.

const BG := Color("#0f141b")
const PANEL := Color(0.075, 0.1, 0.135, 0.92)
const PANEL_LIGHT := Color(0.12, 0.16, 0.21, 0.95)
const BORDER := Color(0.25, 0.32, 0.4, 0.8)
const TEXT := Color("#e8edf2")
const TEXT_DIM := Color("#93a1b0")
const ACCENT := Color("#3fb6c8")
const ACCENT_2 := Color("#f0b54a")
const GOOD := Color("#62c370")
const BAD := Color("#e5594f")
const WARN := Color("#f0b54a")

static var _theme: Theme
static var font_regular: Font
static var font_medium: Font
static var font_bold: Font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	font_regular = load("res://assets/fonts/Rubik-Regular.ttf")
	font_medium = load("res://assets/fonts/Rubik-Medium.ttf")
	font_bold = load("res://assets/fonts/Rubik-Bold.ttf")
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.6))
	t.set_font("font", "Button", font_medium)
	t.set_stylebox("normal", "Button", box(Color(0.16, 0.21, 0.27), 8, BORDER))
	t.set_stylebox("hover", "Button", box(Color(0.2, 0.27, 0.34), 8, ACCENT))
	t.set_stylebox("pressed", "Button", box(Color(0.13, 0.42, 0.48), 8, ACCENT))
	t.set_stylebox("disabled", "Button", box(Color(0.12, 0.14, 0.17), 8, Color(0.2, 0.22, 0.25)))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 8, ACCENT))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, BORDER))
	t.set_stylebox("panel", "Panel", box(PANEL, 10, BORDER))
	t.set_stylebox("normal", "LineEdit", box(Color(0.1, 0.13, 0.17), 6, BORDER))
	t.set_stylebox("focus", "LineEdit", box(Color(0.1, 0.13, 0.17), 6, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "OptionButton", box(Color(0.16, 0.21, 0.27), 6, BORDER))
	t.set_stylebox("hover", "OptionButton", box(Color(0.2, 0.27, 0.34), 6, ACCENT))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.13, 0.42, 0.48), 6, ACCENT))
	t.set_stylebox("panel", "PopupMenu", box(PANEL_LIGHT, 6, BORDER))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_LIGHT, 6, ACCENT))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("slider", "HSlider", box(Color(0.2, 0.25, 0.3), 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.2), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 3))
	t.set_stylebox("background", "ProgressBar", box(Color(0.12, 0.15, 0.19), 4))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("panel", "ItemList", box(Color(0.08, 0.1, 0.13), 6, BORDER))
	t.set_stylebox("normal", "SpinBox", box(Color(0.1, 0.13, 0.17), 6, BORDER))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	_theme = t
	return t


static func box(bg: Color, radius: int = 8, border: Color = Color.TRANSPARENT, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	s.content_margin_left = pad + 2
	s.content_margin_right = pad + 2
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


static func label(text: String, size: int = 16, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		theme()
		l.add_theme_font_override("font", font_bold)
	return l


static func title(text: String, size: int = 34) -> Label:
	return label(text, size, TEXT, true)


static func button(text: String, cb: Callable = Callable(), min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func accent_button(text: String, cb: Callable = Callable(), min_w: int = 0) -> Button:
	var b := button(text, cb, min_w)
	b.add_theme_stylebox_override("normal", box(Color(0.12, 0.45, 0.52), 8, ACCENT))
	b.add_theme_stylebox_override("hover", box(Color(0.16, 0.55, 0.62), 8, Color.WHITE))
	return b


static func panel(pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, 10, BORDER, pad))
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(expand_h: bool = true) -> Control:
	var c := Control.new()
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Compact numbers: 1.2K, 3.4M.
static func num(v: float) -> String:
	var a := absf(v)
	var s := ""
	if a >= 1e9:
		s = "%.2fB" % (a / 1e9)
	elif a >= 1e6:
		s = "%.2fM" % (a / 1e6)
	elif a >= 1e4:
		s = "%.1fK" % (a / 1e3)
	elif a >= 1e3:
		s = "%.2fK" % (a / 1e3)
	else:
		s = "%d" % int(a)
	return ("-" if v < 0.0 else "") + s


static func flag_texture(code: String, seed_value: int, base: Color = Color.TRANSPARENT) -> Texture2D:
	if code != "":
		var path := "res://assets/flags/%s.svg" % code
		if ResourceLoader.exists(path):
			return load(path)
	return FlagGen.texture(seed_value, base)
