extends ScreenBase
## Main menu built around the living strategic map (MenuBackground): the world fills the screen and
## the menu sits on it in an asymmetric composition instead of one long column:
##   top left     — the TerraFront globe mark and wordmark (TERRA + accent FRONT);
##   top right    — quiet navigation: encyclopedia, settings, credits, quit;
##   bottom left  — the main decision: "Continue" (when a save exists, with what it is) and
##                  "New match", plus small links to loading a save and the world generator;
##   bottom right — the commander: profile card and the collection (progress, skills, cases,
##                  inventory, achievements) as small labelled tiles;
##   bottom       — the licence line (AGPL §7 notice stays visible).
## Hover gently lifts a control and warms its accent; nothing moves on its own except the map.

const PROGRESS_ORDER := ["MENU_PROGRESS", "MENU_SKILLS", "MENU_CASES", "MENU_INVENTORY", "MENU_ACHIEVEMENTS"]

var _compact: bool = false
## Named groups for tests: "primary", "links", "nav", "collection".
var groups: Dictionary = {}


func _ready() -> void:
	var vs := get_viewport_rect().size
	_compact = vs.y < 820.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mx := 40 if _compact else 64
	margin.add_theme_constant_override("margin_left", mx)
	margin.add_theme_constant_override("margin_right", mx)
	margin.add_theme_constant_override("margin_top", 28 if _compact else 44)
	margin.add_theme_constant_override("margin_bottom", 48 if _compact else 60)
	add_child(margin)
	var root_v := UITheme.vbox(0)
	root_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root_v)
	# Top: wordmark left, navigation right.
	var top := UITheme.hbox(16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_v.add_child(top)
	top.add_child(_wordmark())
	top.add_child(UITheme.spacer())
	var nav := _nav()
	nav.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(nav)
	var gap := UITheme.spacer()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_v.add_child(gap)
	# Bottom: the decision left, the commander right.
	var bottom := UITheme.hbox(24)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_v.add_child(bottom)
	var left := _play_block()
	left.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(left)
	bottom.add_child(UITheme.spacer())
	var right := _commander_block()
	right.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(right)
	var f := footer()
	f.add_theme_color_override("font_color", Color(UITheme.TEXT_DIM, 0.9))
	f.add_theme_font_size_override("font_size", 12)
	_intro([top, left, right])


## The live map with two soft scrims (left and bottom) so text stays readable; the map itself is
## not dimmed elsewhere.
func _backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	add_child(MenuBackground.new())
	add_child(_scrim(Vector2(0, 0.5), Vector2(1, 0.5), 0.78, 0.62))
	add_child(_scrim(Vector2(0.5, 1), Vector2(0.5, 0), 0.7, 0.4))
	add_child(_scrim(Vector2(0.5, 0), Vector2(0.5, 1), 0.5, 0.18))


func _scrim(from: Vector2, to: Vector2, strength: float, reach: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, reach, 1.0])
	g.colors = PackedColorArray([Color(UITheme.BG, strength), Color(UITheme.BG, 0.0), Color(UITheme.BG, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 64
	gt.height = 64
	var t := TextureRect.new()
	t.texture = gt
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _wordmark() -> Control:
	var h := UITheme.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := GlobeMark.new()
	mark.custom_minimum_size = Vector2(44, 44) if _compact else Vector2(54, 54)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var v := UITheme.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := RichTextLabel.new()
	logo.bbcode_enabled = true
	logo.fit_content = true
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.scroll_active = false
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := 34 if _compact else 44
	logo.add_theme_font_override("normal_font", UITheme.font_heading)
	logo.add_theme_font_size_override("normal_font_size", fs)
	logo.add_theme_color_override("default_color", UITheme.TEXT)
	logo.text = "TERRA[color=#%s]FRONT[/color]" % UITheme.ACCENT.to_html(false)
	logo.name = "Wordmark"
	v.add_child(logo)
	var sub := UITheme.label(tr("GAME_SUBTITLE").to_upper(), 12 if _compact else 13, UITheme.TEXT_DIM)
	sub.add_theme_font_override("font", UITheme.font_medium)
	sub.add_theme_constant_override("letter_spacing", 3)
	v.add_child(sub)
	h.add_child(v)
	return h


## Quiet top navigation: labelled text buttons.
func _nav() -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.SURFACE, 0.88), 20, Color.TRANSPARENT, 4))
	var h := UITheme.hbox(0)
	pill.add_child(h)
	groups["nav"] = h
	for e: Dictionary in App.menu_extras:
		if e.get("section", "") == "info":
			h.add_child(_nav_button(e["icon"], tr(e["label"]), e["action"]))
	h.add_child(_nav_button("ui_settings", tr("MENU_SETTINGS"), func() -> void: App.goto(App.State.SETTINGS)))
	h.add_child(_nav_button("ui_license", tr("MENU_CREDITS"), func() -> void: App.goto(App.State.CREDITS)))
	h.add_child(_nav_button("ui_quit", tr("MENU_QUIT"), func() -> void: get_tree().quit()))
	return pill


func _nav_button(icon: String, text: String, cb: Callable) -> Button:
	var b := UITheme.ghost_button(text, cb, icon)
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size.y = 34
	b.add_theme_stylebox_override("normal", UITheme.box(Color.TRANSPARENT, 17, Color.TRANSPARENT, 12))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.07), 17, Color.TRANSPARENT, 12))
	b.add_theme_stylebox_override("focus", UITheme.box(Color.TRANSPARENT, 17, Color(UITheme.ACCENT, 0.6), 12))
	b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	b.add_theme_color_override("icon_normal_color", UITheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UITheme.TEXT)
	b.add_theme_color_override("icon_hover_color", UITheme.ACCENT)
	return b


## The main decision: continue (with what) or start a new match.
func _play_block() -> Control:
	var v := UITheme.vbox(10)
	v.custom_minimum_size.x = 400 if _compact else 440
	groups["primary"] = v
	var cont := _continue_path()
	if cont != "":
		v.add_child(_continue_card(cont))
	var go_new := func() -> void: App.goto(App.State.MAP_SELECT)
	var ng: Button = UITheme.button(tr("MENU_NEW_GAME_LONG"), go_new, 0, "m_new_game") if cont != "" \
		else UITheme.accent_button(tr("MENU_NEW_GAME_LONG"), go_new, 0, "m_new_game")
	ng.custom_minimum_size.y = 48 if _compact else 56
	ng.add_theme_font_size_override("font_size", 18 if _compact else 20)
	ng.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if cont != "":
		ng.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.SURFACE, 0.92), UITheme.R_M, Color.TRANSPARENT, 12))
		ng.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_3, UITheme.R_M, Color.TRANSPARENT, 12))
	ng.set_meta("menu_primary", true)
	_lift(ng)
	v.add_child(ng)
	var links := UITheme.hbox(4)
	groups["links"] = links
	links.add_child(_link("ui_load", tr("MENU_LOAD"), func() -> void: App.goto(App.State.LOAD_GAME)))
	links.add_child(_link("ui_world", tr("MENU_GENERATOR"), func() -> void: App.goto(App.State.MAP_GENERATOR)))
	for e: Dictionary in App.menu_extras:
		if e.get("section", "") == "play":
			links.add_child(_link(e["icon"], tr(e["label"]), e["action"]))
	v.add_child(links)
	return v


func _link(icon: String, text: String, cb: Callable) -> Button:
	var b := _nav_button(icon, text, cb)
	b.add_theme_color_override("font_color", UITheme.TEXT)
	b.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.SURFACE, 0.7), 17, Color.TRANSPARENT, 12))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(UITheme.SURFACE_3, 0.95), 17, Color.TRANSPARENT, 12))
	return b


## Last save: map, state, time and land — and one clear "Continue".
func _continue_card(path: String) -> Control:
	var h := SaveManager.read_header(path)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.SURFACE, 0.92), UITheme.R_L, Color.TRANSPARENT, 16))
	var row := UITheme.hbox(16)
	p.add_child(row)
	var v := UITheme.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UITheme.label(tr("MENU_CONTINUE_CAPTION"), 12, UITheme.ACCENT))
	var mname: Dictionary = h.get("map", {}).get("name", {})
	var t := UITheme.label(MapDefinition._pick(mname, "") if not mname.is_empty() else "?", 20, UITheme.TEXT)
	t.add_theme_font_override("font", UITheme.font_medium)
	v.add_child(t)
	var sm: Dictionary = h.get("summary", {})
	var meta := UITheme.label(tr("MENU_CONTINUE_META") % [String(sm.get("player", "")), int(float(sm.get("elapsed", 0.0)) / 60.0),
		UITheme.num(float(sm.get("tiles", 0)))], 13, UITheme.TEXT_DIM)
	v.add_child(meta)
	var b := UITheme.accent_button(tr("MENU_CONTINUE"), func() -> void: App.load_match(path), 0, "ui_play")
	b.custom_minimum_size = Vector2(150, 48 if _compact else 52)
	b.add_theme_font_size_override("font_size", 17)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("menu_primary", true)
	_lift(b)
	row.add_child(b)
	return p


## Profile card and the collection tiles.
func _commander_block() -> Control:
	var v := UITheme.vbox(10)
	v.custom_minimum_size.x = 400
	for card: Callable in App.menu_cards:
		var c: Control = card.call()
		if c != null:
			c.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.SURFACE, 0.92), UITheme.R_L, Color.TRANSPARENT, 14))
			_lift(c)
			v.add_child(c)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	groups["collection"] = tiles
	var extras: Array = App.menu_extras.filter(func(e: Dictionary) -> bool:
		return e.get("section", "") == "progress" and e["label"] != "MENU_PROFILE")
	extras.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return PROGRESS_ORDER.find(a["label"]) < PROGRESS_ORDER.find(b["label"]))
	for e: Dictionary in extras:
		tiles.add_child(_tile(e["icon"], tr(String(e["label"]) + "_SHORT"), tr(e["label"]), e["action"]))
	v.add_child(tiles)
	return v


## A small collection tile: icon over a short label; the full name in the hint.
func _tile(icon: String, short: String, full: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(76, 64)
	b.add_theme_stylebox_override("normal", UITheme.box(Color(UITheme.SURFACE, 0.92), UITheme.R_M, Color.TRANSPARENT, 6))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_3, UITheme.R_M, Color.TRANSPARENT, 6))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(UITheme.ACCENT, 0.25), UITheme.R_M, Color.TRANSPARENT, 6))
	b.add_theme_stylebox_override("focus", UITheme.box(Color.TRANSPARENT, UITheme.R_M, Color(UITheme.ACCENT, 0.7), 6))
	b.pressed.connect(cb)
	var v := UITheme.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := Icons.rect(icon, 22, UITheme.TEXT)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var l := UITheme.label(short, 12, UITheme.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.set_meta("label", full)
	Hints.attach(b, {"title": full, "text": ""})
	b.mouse_entered.connect(func() -> void:
		ic.modulate = UITheme.ACCENT
		l.add_theme_color_override("font_color", UITheme.TEXT))
	b.mouse_exited.connect(func() -> void:
		ic.modulate = UITheme.TEXT
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM))
	_lift(b)
	return b


## Gentle hover reaction: a small lift and scale around the centre (no jumps, no idle motion).
func _lift(c: Control) -> void:
	c.mouse_entered.connect(func() -> void: _hover(c, true))
	c.mouse_exited.connect(func() -> void: _hover(c, false))
	c.focus_entered.connect(func() -> void: _hover(c, true))
	c.focus_exited.connect(func() -> void: _hover(c, false))


func _hover(c: Control, on: bool) -> void:
	c.pivot_offset = c.size * 0.5
	var s := Vector2.ONE * (1.025 if on else 1.0)
	if not Settings.ui_animations:
		c.scale = s
		return
	var tw := c.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", s, 0.14)


func _intro(blocks: Array) -> void:
	if not Settings.ui_animations:
		return
	var i := 0
	for b: Control in blocks:
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.35)
		i += 1


func _continue_path() -> String:
	var saves := SaveManager.list()
	return String(saves[0]["path"]) if not saves.is_empty() else ""


## The TerraFront mark: a globe (rim, parallels, a meridian) crossed by a bold front line in the
## accent colour, drawn as vector strokes.
class GlobeMark:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		var c := s * 0.5
		var r := minf(s.x, s.y) * 0.46
		var lw := maxf(1.6, r * 0.09)
		draw_circle(c, r, Color(UITheme.ACCENT, 0.14))
		var line := Color(UITheme.TEXT, 0.8)
		draw_arc(c, r, 0.0, TAU, 48, line, lw, true)
		# Parallels (flattened ellipses) and a meridian.
		for k: float in [-0.45, 0.0, 0.45]:
			var y := c.y + r * k
			var half := sqrt(maxf(0.0, 1.0 - k * k)) * r
			var pts := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				pts.append(Vector2(c.x - half + 2.0 * half * t, y + sin(t * PI) * r * 0.08))
			draw_polyline(pts, Color(line, 0.55), lw * 0.6, true)
		var mer := PackedVector2Array()
		for i in 25:
			var a := -PI / 2.0 + PI * float(i) / 24.0
			mer.append(c + Vector2(cos(a) * r * 0.42, sin(a) * r))
		draw_polyline(mer, Color(line, 0.55), lw * 0.6, true)
		# The front: a bold zigzag across the globe.
		var front := PackedVector2Array([c + Vector2(-r * 0.95, r * 0.25), c + Vector2(-r * 0.4, -r * 0.15),
			c + Vector2(-r * 0.05, r * 0.2), c + Vector2(r * 0.4, -r * 0.3), c + Vector2(r * 0.92, -r * 0.05)])
		draw_polyline(front, UITheme.ACCENT, lw * 1.4, true)
