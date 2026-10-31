class_name BuildTip
extends PanelContainer
## Small label next to the cursor while placing a building: one line saying whether the order can
## be placed here (or why not). Name, cost, time and radius are already in the bottom build bar, so
## the cost row appears only when gold or supplies are short (in red). Data from
## StructureSystem.preview.

var _icon: TextureRect
var _name: Label
var _gold: Label
var _sup: Label
var _time: Label
var _radius: Label
var _status: Label
var _sup_row: Control
var _radius_row: Control
var _costs: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, UITheme.R_S, Color.TRANSPARENT, 7))
	var v := UITheme.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var h := UITheme.hbox(8)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(16, 16)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_icon)
	_name = UITheme.label("", UITheme.T_CAPTION, UITheme.TEXT_DIM)
	h.add_child(_name)
	h.visible = false
	v.add_child(h)
	var costs := UITheme.hbox(12)
	var g := UITheme.hbox(4)
	g.add_child(Icons.rect("r_gold", 16, UITheme.GOLD))
	_gold = UITheme.label("", UITheme.T_BODY)
	g.add_child(_gold)
	costs.add_child(g)
	_sup_row = UITheme.hbox(4)
	_sup_row.add_child(Icons.rect("r_supplies", 16, UITheme.SUPPLY))
	_sup = UITheme.label("", UITheme.T_BODY)
	_sup_row.add_child(_sup)
	costs.add_child(_sup_row)
	var tm := UITheme.hbox(4)
	tm.add_child(Icons.rect("ui_clock", 16, UITheme.TEXT_DIM))
	_time = UITheme.label("", UITheme.T_BODY, UITheme.TEXT_DIM)
	tm.add_child(_time)
	costs.add_child(tm)
	_radius_row = UITheme.hbox(4)
	_radius_row.add_child(Icons.rect("ui_zones", 16, UITheme.TEXT_DIM))
	_radius = UITheme.label("", UITheme.T_BODY, UITheme.TEXT_DIM)
	_radius_row.add_child(_radius)
	costs.add_child(_radius_row)
	_costs = costs
	v.add_child(costs)
	_status = UITheme.label("", UITheme.T_CAPTION, UITheme.GOOD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.move_child(_status, 0)
	for c in find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Fills the card from a StructureSystem.preview result and places it next to `at` (screen).
func show_preview(pv: Dictionary, sim: Sim, at: Vector2) -> void:
	var pid := sim.player_id
	var kind: int = pv["kind"]
	var id := sim.rules.b_ids[kind]
	_icon.texture = Icons.tex("b_" + id, 16)
	_name.text = tr("B_" + id.to_upper())
	if int(pv["upgrade"]) >= 0:
		_name.text += "  " + tr("BUILD_TIP_LEVEL") % int(pv["level"])
	var gold: float = pv["gold"]
	var sup: float = pv["supplies"]
	_gold.text = UITheme.num(gold)
	_gold.add_theme_color_override("font_color", UITheme.TEXT if sim.st.o_gold[pid] >= gold else UITheme.BAD)
	_sup_row.visible = sup > 0.0
	_sup.text = UITheme.num(sup)
	_sup.add_theme_color_override("font_color", UITheme.TEXT if sim.st.o_supplies[pid] >= sup else UITheme.BAD)
	_time.text = "%d %s" % [ceili(float(pv["ticks"]) / 10.0), tr("SEC_SHORT")]
	var radius: float = pv["radius"]
	var short_gold: bool = sim.st.o_gold[pid] < gold
	var short_sup: bool = sup > 0.0 and sim.st.o_supplies[pid] < sup
	_costs.visible = short_gold or short_sup
	_sup_row.visible = short_sup
	(_gold.get_parent() as Control).visible = short_gold
	(_time.get_parent() as Control).visible = false
	_radius_row.visible = false
	_radius.text = tr("BUILD_TIP_RADIUS") % roundi(radius)
	if pv["ok"]:
		_status.text = tr("BUILD_TIP_UPGRADE") if int(pv["upgrade"]) >= 0 else tr("BUILD_TIP_OK")
		_status.add_theme_color_override("font_color", UITheme.GOOD)
	else:
		_status.text = reason_text(pv, sim.rules)
		_status.add_theme_color_override("font_color", UITheme.BAD)
	# Short status stays on one line; long refusals wrap at a readable width.
	var long := _status.text.length() > 34
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if long else TextServer.AUTOWRAP_OFF
	_status.custom_minimum_size.x = 220.0 if long else 0.0
	visible = true
	reset_size()
	var vs := get_viewport_rect().size
	var p := at + Vector2(22, 18)
	if p.x + size.x > vs.x - 8.0:
		p.x = at.x - size.x - 22.0
	if p.y + size.y > vs.y - 8.0:
		p.y = at.y - size.y - 18.0
	position = p


## Human-readable refusal for a preview (most specific reason first).
static func reason_text(pv: Dictionary, rules: Rules) -> String:
	var detail := String(pv.get("detail", ""))
	if detail == "not_own_land":
		return TranslationServer.translate("REJECT_BUILD_OWN_LAND")
	var reason := String(pv["reason"])
	if reason == "locked":
		return TranslationServer.translate("BUILD_REQUIRES") % MetaData.text(ResearchSystem.tech(detail).get("name", {}))
	if reason == "no_site":
		if detail == "no_coast":
			return TranslationServer.translate("BUILD_DETAIL_NO_COAST")
		return TranslationServer.translate("BUILD_DETAIL_TOO_CLOSE") % roundi(rules.b_min_dist)
	return TranslationServer.translate("REJECT_" + reason.to_upper())
