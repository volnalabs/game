class_name HudDock
extends HBoxContainer
## Left dock: an icon rail and one collapsible side panel. Tabs are registered with a builder
## callable, so later systems (research, weapons, diplomacy, alliances) plug in the same way.

var hud: GameHUD
var rail: VBoxContainer
var panel: SidePanel
var current: String = ""
var _tabs: Dictionary = {}
var _buttons: Dictionary = {}
var _order: Array[String] = []
var _dirty: bool = true


func _init(h: GameHUD) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE, 10, Color.TRANSPARENT, 4))
	rp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(rp)
	rail = UITheme.vbox(2)
	rp.add_child(rail)
	panel = SidePanel.new(380)
	panel.custom_minimum_size.y = 470
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.visible = false
	panel.closed.connect(func() -> void: open(""))
	add_child(panel)
	register("state", "ui_flag", "DOCK_STATE", HudPanels.state)
	register("army", "r_army", "DOCK_ARMY", HudPanels.army)
	register("economy", "r_gold", "DOCK_ECONOMY", HudPanels.economy)
	register("research", "r_research", "DOCK_RESEARCH", HudPanels.research)
	register("arsenal", "w_missile", "DOCK_ARSENAL", HudPanels.arsenal)
	register("diplomacy", "ui_users", "DOCK_DIPLOMACY", DiplomacyPanel.panel)
	register("log", "ui_book", "DOCK_LOG", HudPanels.events)


func register(id: String, icon: String, title_key: String, builder: Callable) -> void:
	_tabs[id] = {"icon": icon, "title": title_key, "builder": builder}
	_order.append(id)
	var b := UITheme.rail_button(icon, tr(title_key + "_SHORT"), func() -> void:
		if current != id and hud.ctl != null and hud.ctl.get("build_open") == true:
			hud.ctl.close_build_mode()  # a side panel replaces the build bar, never both
		open(id if current != id else ""), 72, true)
	Hints.attach(b, {"title": tr(title_key), "text": tr(title_key + "_HINT")})
	_buttons[id] = b
	b.set_meta("silent", true)  # the panel's own open/close sound plays instead of a click
	rail.add_child(b)


func open(id: String) -> void:
	if id != current:
		Audio.play("ui_open" if id != "" else "ui_close")
	current = id
	for k: String in _buttons:
		(_buttons[k] as Button).button_pressed = k == id
	panel.visible = id != ""
	if id != "":
		var t: Dictionary = _tabs[id]
		panel.set_header(t["icon"], tr(t["title"]))
		_dirty = true
		refresh()
		Anim.slide_in(panel, Vector2(-16, 0), 0.16)


func mark_dirty() -> void:
	_dirty = true


func log_changed() -> void:
	if current == "log":
		_dirty = true


## Rebuilds the open panel (called at the HUD refresh rate; hidden panels cost nothing).
func refresh() -> void:
	if current == "" or not panel.visible:
		return
	if current == "log" and not _dirty:
		return
	# Don't rebuild under the cursor (a click must hit the button it was aimed at).
	if not _dirty and panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	_dirty = false
	panel.clear()
	(_tabs[current]["builder"] as Callable).call(hud, panel.body)
