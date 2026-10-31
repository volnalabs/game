class_name UITheme
extends RefCounted
## VolnaLabs design system (docs/ui/UI_DESIGN.md): tokens (colour, spacing, radius, type scale),
## the Godot Theme built from them, switchable accent themes (cosmetic UI themes) and builders for
## the shared components. Every screen and panel is built from these helpers so the whole game
## shares one visual language.

# ---- colour tokens ----
const BG := Color("#0a0e14")
const SURFACE := Color(0.063, 0.086, 0.118, 0.9)
const SURFACE_2 := Color(0.094, 0.125, 0.165, 0.95)
const SURFACE_3 := Color(0.13, 0.17, 0.22, 0.98)
const STROKE := Color(1, 1, 1, 0.07)
const STROKE_STRONG := Color(1, 1, 1, 0.16)
const TEXT := Color("#e6edf3")
const TEXT_DIM := Color("#8b98a8")
const TEXT_FAINT := Color("#5c6a7a")
const GOLD := Color("#f2c14e")
const SUPPLY := Color("#7cc4ff")
const ARMY := Color("#dfe7ef")
const RESEARCH := Color("#b48cff")
const CREDITS := Color("#ffd166")
const XP := Color("#7ee0b8")
const GOOD := Color("#4fd18b")
const BAD := Color("#ff5d5d")
const WARN := Color("#ffb547")
const ACCENT_2 := GOLD
# Legacy names used by Phase 1 screens.
const PANEL := SURFACE
const PANEL_LIGHT := SURFACE_2
const BORDER := STROKE_STRONG

const RARITY := {"common": Color("#a7b1bd"), "uncommon": Color("#5fd38d"), "rare": Color("#4ea8ff"),
	"epic": Color("#b67cff"), "legendary": Color("#ffb13d")}

# ---- spacing / radius / type scale ----
const SP_XS := 4
const SP_S := 8
const SP_M := 12
const SP_L := 16
const SP_XL := 24
const SP_XXL := 32
const R_S := 6
const R_M := 10
const R_L := 14
const T_CAPTION := 12
const T_BODY := 14
const T_BODY_L := 16
const T_TITLE := 20
const T_H2 := 26
const T_H1 := 40
const T_DISPLAY := 60

## Current accent (switchable UI theme cosmetic).
static var ACCENT: Color = Color("#3ec7d6")
static var theme_id: String = "volna"

static var _theme: Theme
static var font_regular: Font
static var font_medium: Font
static var font_bold: Font
static var font_heading: FontVariation


static func _fonts() -> void:
	if font_regular != null:
		return
	font_regular = load("res://assets/fonts/Rubik-Regular.ttf")
	font_medium = load("res://assets/fonts/Rubik-Medium.ttf")
	font_bold = load("res://assets/fonts/Rubik-Bold.ttf")
	font_heading = FontVariation.new()
	font_heading.base_font = font_bold
	font_heading.spacing_glyph = 1


## Applies a UI theme (data/ui/themes.json) — accent colour of buttons, bars and highlights.
static func apply_theme(id: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/themes.json"))
	var themes: Dictionary = d["themes"]
	if not themes.has(id):
		id = "volna"
	theme_id = id
	ACCENT = Color(String(themes[id]["accent"]))
	_theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	_fonts()
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = T_BODY
	for cls in ["Label", "Button", "LineEdit", "OptionButton", "CheckBox", "CheckButton", "TooltipLabel", "ItemList"]:
		t.set_color("font_color", cls, TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_font("font", "Button", font_medium)
	t.set_font_size("font_size", "Button", T_BODY)
	t.set_stylebox("normal", "Button", box(SURFACE_2, R_M, STROKE, 10))
	t.set_stylebox("hover", "Button", box(SURFACE_3, R_M, STROKE_STRONG, 10))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.55), R_M, ACCENT, 10))
	t.set_stylebox("disabled", "Button", box(Color(0.07, 0.09, 0.12, 0.7), R_M, Color(1, 1, 1, 0.04), 10))
	t.set_stylebox("focus", "Button", box(Color.TRANSPARENT, R_M, ACCENT.darkened(0.2), 10))
	t.set_stylebox("panel", "PanelContainer", box(SURFACE, R_L, STROKE, 12))
	t.set_stylebox("panel", "Panel", box(SURFACE, R_L, STROKE, 12))
	t.set_stylebox("normal", "LineEdit", box(Color(0.05, 0.07, 0.1), R_S, STROKE_STRONG, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0.05, 0.07, 0.1), R_S, ACCENT, 8))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_stylebox("normal", "OptionButton", box(SURFACE_2, R_S, STROKE_STRONG, 8))
	t.set_stylebox("hover", "OptionButton", box(SURFACE_3, R_S, ACCENT.darkened(0.3), 8))
	t.set_stylebox("pressed", "OptionButton", box(SURFACE_3, R_S, ACCENT, 8))
	t.set_stylebox("focus", "OptionButton", box(Color.TRANSPARENT, R_S, ACCENT.darkened(0.3), 8))
	t.set_stylebox("panel", "PopupMenu", box(SURFACE_3, R_S, STROKE_STRONG, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", box(ACCENT.darkened(0.5), R_S, Color.TRANSPARENT, 4))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.08, 0.11, 0.98), R_S, STROKE_STRONG, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", T_BODY)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.08), 3, Color.TRANSPARENT, 2))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.15), 3, Color.TRANSPARENT, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 3, Color.TRANSPARENT, 2))
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.07), 4, Color.TRANSPARENT, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4, Color.TRANSPARENT, 0))
	t.set_stylebox("panel", "ItemList", box(Color(0.05, 0.07, 0.1), R_S, STROKE, 6))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", box(SURFACE, R_M, STROKE, 10))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_constant("separation", "VBoxContainer", SP_S)
	t.set_constant("separation", "HBoxContainer", SP_S)
	var sep := StyleBoxLine.new()
	sep.color = STROKE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = STROKE
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	_theme = t
	return t


# ---------------------------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------------------------

static func box(bg: Color, radius: int = R_M, border: Color = Color.TRANSPARENT, pad: int = 8) -> StyleBoxFlat:
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
	s.anti_aliasing = true
	return s


static func label(text: String, size: int = T_BODY, color: Color = TEXT, bold: bool = false) -> Label:
	_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	return l


static func caption(text: String, color: Color = TEXT_DIM) -> Label:
	_fonts()
	var l := label(text.to_upper(), 11, color)
	l.add_theme_font_override("font", font_heading)
	return l


static func title(text: String, size: int = T_H2) -> Label:
	_fonts()
	var l := label(text, size, TEXT)
	l.add_theme_font_override("font", font_heading)
	return l


static func button(text: String, cb: Callable = Callable(), min_w: int = 0, icon: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	if icon != "":
		b.icon = Icons.tex(icon, 18)
		b.add_theme_constant_override("h_separation", 8)
		b.add_theme_constant_override("icon_max_width", 18)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func accent_button(text: String, cb: Callable = Callable(), min_w: int = 0, icon: String = "") -> Button:
	var b := button(text, cb, min_w, icon)
	b.add_theme_stylebox_override("normal", box(ACCENT.darkened(0.35), R_M, ACCENT, 10))
	b.add_theme_stylebox_override("hover", box(ACCENT.darkened(0.2), R_M, ACCENT.lightened(0.3), 10))
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.5), R_M, ACCENT, 10))
	return b


static func ghost_button(text: String, cb: Callable = Callable(), icon: String = "") -> Button:
	var b := button(text, cb, 0, icon)
	b.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, R_M, Color.TRANSPARENT, 8))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.06), R_M, Color.TRANSPARENT, 8))
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.6), R_M, Color.TRANSPARENT, 8))
	return b


## Square icon-only button with a tooltip.
static func icon_button(icon: String, tooltip: String, cb: Callable = Callable(), px: int = 38, toggle: bool = false) -> Button:
	var b := Button.new()
	b.icon = Icons.tex(icon, int(px * 0.55))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	b.toggle_mode = toggle
	b.add_theme_stylebox_override("normal", box(Color.TRANSPARENT, R_M, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.07), R_M, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.55), R_M, ACCENT.darkened(0.1), 4))
	b.add_theme_color_override("icon_normal_color", TEXT_DIM)
	b.add_theme_color_override("icon_hover_color", TEXT)
	b.add_theme_color_override("icon_pressed_color", Color.WHITE)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func panel(pad: int = SP_M) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(SURFACE, R_L, STROKE, pad))
	return p


## A raised card (inside panels).
static func card(pad: int = SP_M, highlight: Color = Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(SURFACE_2, R_M, highlight if highlight.a > 0.0 else STROKE, pad))
	return p


static func vbox(sep: int = SP_S) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = SP_S) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(expand_h: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


## Icon + label in a row.
static func icon_label(icon: String, text: String, color: Color = TEXT, size: int = T_BODY, icon_color: Color = Color(0, 0, 0, 0)) -> HBoxContainer:
	var h := hbox(6)
	h.add_child(Icons.rect(icon, size + 4, icon_color if icon_color.a > 0.0 else color))
	h.add_child(label(text, size, color))
	return h


## Section header: small caps caption with an optional icon.
static func section(text: String, icon: String = "") -> HBoxContainer:
	var h := hbox(6)
	if icon != "":
		h.add_child(Icons.rect(icon, 14, TEXT_DIM))
	h.add_child(caption(text))
	return h


## Label / value row for panels.
static func stat_row(k: String, v: String, color: Color = TEXT, icon: String = "") -> HBoxContainer:
	var h := hbox(8)
	if icon != "":
		h.add_child(Icons.rect(icon, 16, TEXT_DIM))
	var kl := label(k, T_BODY - 1, TEXT_DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	var vl := label(v, T_BODY - 1, color)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(vl)
	return h


static func progress(value: float, color: Color = Color(0, 0, 0, 0), height: int = 6) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = 1.0
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size.y = height
	if color.a > 0.0:
		p.add_theme_stylebox_override("fill", box(color, 3, Color.TRANSPARENT, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Small rounded tag (rarity, status).
static func badge(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color(color, 0.16), 20, Color(color, 0.55), 2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, 11, color.lightened(0.15), true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func rarity_color(r: String) -> Color:
	return RARITY.get(r, TEXT_DIM)


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


static func flag_rect(tex: Texture2D, w: int = 36, h: int = 24) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(w, h)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
