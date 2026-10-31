extends Node
## Autoload "Profile": the player's persistent profile (scripts/meta/*, docs/progression/PROGRESSION.md).
## Owns loading/saving, and exposes the player actions (rename, equip, buy / open cases, craft).
## Match rewards go through RewardManager via pay_match().

signal changed
## A level-up, achievement or reward worth a toast: (text, icon, colour).
signal notify(text: String, icon: String, color: Color)

var data: ProfileData
var store: ProfileStore
## Report of the last paid match (for the results screen).
var last_report: Dictionary = {}
var last_result: Dictionary = {}


func _ready() -> void:
	store = ProfileStore.new()
	data = store.load_profile()
	if store.last_load == "restored_backup":
		push_warning("Profile restored from backup")
	QuestSystem.refresh_week(data, now())
	_apply_cosmetics()
	_register_menu()


func now() -> int:
	return int(Time.get_unix_time_from_system())


func save() -> void:
	store.save_profile(data)
	changed.emit()


## Pays a match result once (see RewardManager) and saves. Returns the report.
func pay_match(result: Dictionary) -> Dictionary:
	var lvl := data.level()
	var report := RewardManager.apply_match(data, result, now())
	if report.get("duplicate", false):
		return report
	last_report = report
	last_result = result
	save()
	if data.level() > lvl:
		notify.emit(tr("TOAST_LEVEL_UP") % data.level(), "r_xp", UITheme.XP)
	for id: String in report["achievements"]:
		notify.emit(tr("TOAST_ACHIEVEMENT") % MetaData.text(MetaData.achievement(id)["name"]), "m_achievements", UITheme.GOLD)
	return report


func rename(n: String) -> void:
	data.data["name"] = n.strip_edges().substr(0, 24)
	save()


func equip(item_id: String) -> bool:
	if not Inventory.equip(data, item_id):
		return false
	save()
	_apply_cosmetics()
	return true


func unequip(category: String) -> bool:
	if not Inventory.unequip(data, category):
		return false
	save()
	_apply_cosmetics()
	return true


func buy_case(case_id: String) -> bool:
	if not CaseSystem.buy(data, case_id):
		return false
	save()
	return true


## Opens a case; the outcome is final and saved before any animation plays.
func open_case(case_id: String) -> Dictionary:
	var out := CaseSystem.open_case(data, case_id)
	if out.is_empty():
		return out
	var report := {"achievements": [], "cases": {}, "items": [], "levels": []}
	for id in AchievementSystem.check(data, {}, now()):
		(report["achievements"] as Array).append(id)
		RewardManager.grant(data, MetaData.achievement(id)["reward"], report)
		notify.emit(tr("TOAST_ACHIEVEMENT") % MetaData.text(MetaData.achievement(id)["name"]), "m_achievements", UITheme.GOLD)
	save()
	return out


func craft(item_id: String) -> bool:
	if not Inventory.craft(data, item_id):
		return false
	save()
	return true


func _apply_cosmetics() -> void:
	UITheme.apply_theme(Cosmetics.ui_theme())


func _register_menu() -> void:
	App.add_menu_entry("progress", "m_profile", "MENU_PROFILE", App.State.PROFILE)
	App.add_menu_entry("progress", "m_quests", "MENU_PROGRESS", App.State.PROGRESS)
	App.add_menu_entry("progress", "m_cases", "MENU_CASES", App.State.CASES)
	App.add_menu_entry("progress", "m_inventory", "MENU_INVENTORY", App.State.INVENTORY)
	App.add_menu_entry("progress", "m_achievements", "MENU_ACHIEVEMENTS", App.State.ACHIEVEMENTS)
	App.menu_cards.append(_profile_card)


func _profile_card() -> Control:
	var c := UITheme.card(14)
	var h := UITheme.hbox(12)
	c.add_child(h)
	h.add_child(Cosmetics.avatar_widget(64))
	var v := UITheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UITheme.label(data.display_name(), UITheme.T_TITLE, UITheme.TEXT, true))
	var t := Cosmetics.title()
	if t != "":
		v.add_child(UITheme.label(t, UITheme.T_CAPTION, UITheme.ACCENT))
	var lv := Progression.level_for(data.xp())
	v.add_child(UITheme.label(tr("PROFILE_LEVEL") % data.level(), UITheme.T_BODY, UITheme.TEXT_DIM))
	v.add_child(UITheme.progress(float(lv["into"]) / float(lv["need"]), UITheme.XP, 6))
	var row := UITheme.hbox(14)
	row.add_child(UITheme.icon_label("r_credits", UITheme.num(float(data.credits())), UITheme.CREDITS, UITheme.T_BODY))
	var cases := 0
	for k: String in data.data["cases"]:
		cases += int(data.data["cases"][k])
	if cases > 0:
		row.add_child(UITheme.icon_label("m_cases", str(cases), UITheme.TEXT, UITheme.T_BODY))
	v.add_child(row)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			App.goto(App.State.PROFILE))
	return c
