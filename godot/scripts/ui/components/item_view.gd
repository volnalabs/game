class_name ItemView
extends RefCounted
## Previews and cards for cosmetic items (inventory, cases, rewards). Each category shows what it
## actually changes in game.


## A square preview of an item's effect.
static func preview(it: Dictionary, px: int) -> Control:
	var rc := UITheme.rarity_color(String(it.get("rarity", "common")))
	match String(it.get("category", "")):
		"avatar", "emblem", "victory_effect":
			var col := Color(String(it["color"])) if it.has("color") else UITheme.TEXT
			return _boxed(Icons.rect(String(it["icon"]), int(px * 0.62), col), px, rc)
		"frame":
			var p := PanelContainer.new()
			var sb := UITheme.box(UITheme.SURFACE_3, px / 2, Color(String(it["color"])), 4)
			sb.set_border_width_all(int(it["width"]) + 1)
			p.add_theme_stylebox_override("panel", sb)
			p.custom_minimum_size = Vector2(px, px)
			var r := Icons.rect("a_recruit", int(px * 0.5), UITheme.TEXT_DIM)
			r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			p.add_child(r)
			return p
		"title":
			var l := UITheme.label("«%s»" % MetaData.text(it["name"]), UITheme.T_CAPTION, rc, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(px, px)
			return _boxed(l, px, rc)
		"ui_theme":
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/themes.json"))
			var accent := Color(String(d["themes"].get(String(it["theme"]), {}).get("accent", "#3ec7d6")))
			return _swatch([UITheme.SURFACE, accent, UITheme.SURFACE_3], px, rc)
		"player_color":
			return _swatch([Color(String(it["color"]))], px, rc)
		"map_style":
			var cols: Array = []
			for i in [0, 1, 3, 4, 5, 6, 7, 9]:
				cols.append(TerrainColors.styled(TerrainColors.BASE[i], String(it["style"])))
			return _swatch(cols, px, rc)
		"building_skin":
			var s := PlateShape.new()
			s.shape = String(it["shape"])
			s.custom_minimum_size = Vector2(px, px) * 0.7
			s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return _boxed(s, px, rc)
		"capture_effect":
			var c := String(it["color"])
			return _boxed(Icons.rect("ui_sparkles", int(px * 0.6), Color("#ff8af0") if c == "rainbow" else Color(c)), px, rc)
	return _boxed(Control.new(), px, rc)


static func _boxed(inner: Control, px: int, rc: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(rc, 0.10), UITheme.R_M, Color(rc, 0.55), 4))
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(inner)
	return p


static func _swatch(cols: Array, px: int, rc: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.custom_minimum_size = Vector2(px * 0.7, px * 0.7)
	for c: Color in cols:
		var r := ColorRect.new()
		r.color = c
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return _boxed(h, px, rc)


static func category_name(cat: String) -> String:
	return TranslationServer.translate("CAT_" + cat.to_upper())


static func rarity_name(r: String) -> String:
	return TranslationServer.translate("RARITY_" + r.to_upper())


## Card: preview, name, rarity, category, and a state line (equipped / owned / locked).
static func card(it: Dictionary, p: ProfileData, w: int = 168) -> PanelContainer:
	var rc := UITheme.rarity_color(String(it["rarity"]))
	var owned := p.owns(String(it["id"]))
	var eq: bool = p.equipped(String(it["category"])) == String(it["id"])
	var c := PanelContainer.new()
	var sb := UITheme.box(UITheme.SURFACE_2, UITheme.R_M, UITheme.ACCENT if eq else (Color(rc, 0.6) if owned else UITheme.STROKE), 10)
	sb.set_border_width_all(2 if eq else 1)
	c.add_theme_stylebox_override("panel", sb)
	c.custom_minimum_size = Vector2(w, 0)
	var v := UITheme.vbox(4)
	c.add_child(v)
	var pv := preview(it, w - 24)
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if not owned:
		pv.modulate = Color(1, 1, 1, 0.45)
	v.add_child(pv)
	var n := UITheme.label(MetaData.text(it["name"]), UITheme.T_BODY, UITheme.TEXT if owned else UITheme.TEXT_DIM, true)
	n.clip_text = true
	n.custom_minimum_size.x = w - 20
	n.tooltip_text = MetaData.text(it["name"])
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(n)
	v.add_child(UITheme.label(rarity_name(String(it["rarity"])), UITheme.T_CAPTION, rc))
	var cl := UITheme.label(category_name(String(it["category"])), UITheme.T_CAPTION, UITheme.TEXT_FAINT)
	cl.clip_text = true
	v.add_child(cl)
	var state := TranslationServer.translate("INV_EQUIPPED") if eq else (TranslationServer.translate("INV_OWNED") if owned else TranslationServer.translate("INV_LOCKED"))
	if owned and int(p.data["owned"][it["id"]]) > 1:
		state += " ×%d" % int(p.data["owned"][it["id"]])
	v.add_child(UITheme.icon_label("ui_check" if eq else ("ui_star" if owned else "ui_lock"), state, UITheme.ACCENT if eq else UITheme.TEXT_DIM, UITheme.T_CAPTION))
	return c


## Compact reward summary (credits, XP, cases, item).
static func reward_line(r: Dictionary) -> HBoxContainer:
	var h := UITheme.hbox(8)
	if r.has("credits"):
		h.add_child(UITheme.icon_label("r_credits", UITheme.num(float(r["credits"])), UITheme.CREDITS, UITheme.T_CAPTION))
	if r.has("xp"):
		h.add_child(UITheme.icon_label("r_xp", UITheme.num(float(r["xp"])), UITheme.XP, UITheme.T_CAPTION))
	for cid: String in r.get("cases", {}):
		h.add_child(UITheme.icon_label("m_cases", "×%d" % int(r["cases"][cid]), UITheme.TEXT, UITheme.T_CAPTION))
	if r.has("item"):
		var it := MetaData.item(String(r["item"]))
		h.add_child(UITheme.icon_label("ui_gift", MetaData.text(it.get("name", {})), UITheme.rarity_color(String(it.get("rarity", "common"))), UITheme.T_CAPTION))
	return h
