class_name Cosmetics
extends RefCounted
## The single reader of equipped cosmetic items. Purely visual: nothing here reaches the simulation's
## rules (the player's colour is a display colour). Works without the Profile autoload (tests, tools)
## by returning the defaults.


static func _profile() -> ProfileData:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var n := tree.root.get_node_or_null("Profile")
	return n.get("data") as ProfileData if n != null else null


static func equipped_item(category: String) -> Dictionary:
	var p := _profile()
	if p == null:
		return {}
	var id := p.equipped(category)
	return MetaData.item(id) if id != "" else {}


static func ui_theme() -> String:
	return String(equipped_item("ui_theme").get("theme", "volna"))


## Display colour of the player's state, or transparent for the default palette colour.
static func player_color() -> Color:
	var it := equipped_item("player_color")
	return Color(String(it["color"])) if not it.is_empty() else Color(0, 0, 0, 0)


static func map_style() -> String:
	return String(equipped_item("map_style").get("style", ""))


## Shape of the player's building plates: circle (default), square, diamond, hex, shield, star.
static func plate_shape() -> String:
	return String(equipped_item("building_skin").get("shape", "circle"))


## Capture effect of the player's attacks: {"color": Color, "rainbow": bool, "style": "sparks"|"rings"}.
static func capture_effect() -> Dictionary:
	var it := equipped_item("capture_effect")
	if it.is_empty():
		return {}
	var c := String(it["color"])
	return {"color": Color.WHITE if c == "rainbow" else Color(c), "rainbow": c == "rainbow", "style": String(it["style"])}


static func victory_effect() -> Dictionary:
	return equipped_item("victory_effect")


static func avatar_icon() -> String:
	return String(equipped_item("avatar").get("icon", "a_recruit"))


static func emblem_icon() -> String:
	return String(equipped_item("emblem").get("icon", "e_tower"))


static func frame() -> Dictionary:
	var it := equipped_item("frame")
	return {"color": Color(String(it.get("color", "#8a96a3"))), "width": int(it.get("width", 2)),
		"rarity": String(it.get("rarity", "common"))}


static func title() -> String:
	var it := equipped_item("title")
	return MetaData.text(it["name"]) if not it.is_empty() else ""


## Avatar inside its frame, for profile cards, the top bar and results.
static func avatar_widget(px: int) -> Control:
	var f := frame()
	var p := PanelContainer.new()
	var sb := UITheme.box(UITheme.SURFACE_3, px / 2, f["color"], 4)
	sb.set_border_width_all(int(f["width"]))
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := Icons.rect(avatar_icon(), int(px * 0.62), UITheme.TEXT)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(r)
	return p
