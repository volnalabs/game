class_name HudZoneLegend
extends PanelContainer
## Legend of the zone overlay: one row per building kind with an effect radius (colour, icon,
## name, radius in tiles), shown while zones are visible.

var hud: GameHUD
var _rows: VBoxContainer


func _init(h: GameHUD) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.SURFACE, 0.92), UITheme.R_M, UITheme.STROKE, 10))
	var v := UITheme.vbox(6)
	add_child(v)
	v.add_child(UITheme.section(tr("ZONES_TITLE"), "ui_zones"))
	_rows = UITheme.vbox(4)
	v.add_child(_rows)
	var rules := hud.sim.rules
	for k in ZoneLayer.zone_kinds(rules):
		var row := UITheme.hbox(8)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(12, 12)
		sw.color = ZoneLayer.kind_color(rules, k)
		row.add_child(sw)
		row.add_child(Icons.rect("b_" + rules.b_ids[k], 18, UITheme.TEXT))
		row.add_child(UITheme.label(tr("B_" + rules.b_ids[k].to_upper()), UITheme.T_BODY))
		row.add_child(UITheme.spacer())
		row.add_child(UITheme.label(tr("BUILD_TIP_RADIUS") % roundi(rules.building_radius(k)), UITheme.T_CAPTION, UITheme.TEXT_DIM))
		_rows.add_child(row)
	var note := UITheme.label(tr("ZONES_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 230
	v.add_child(note)
	for c in find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
