extends ScreenBase
## List of saved matches.

var _list: VBoxContainer


func _ready() -> void:
	var c := build_frame(tr("LOAD_TITLE"), 900)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 520)
	c.add_child(scroll)
	_list = UITheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	c.add_child(back_button())
	_refresh()


func _refresh() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var saves := SaveManager.list()
	if saves.is_empty():
		_list.add_child(UITheme.label(tr("LOAD_EMPTY"), 16, UITheme.TEXT_DIM))
		return
	for h in saves:
		var p := UITheme.panel(10)
		var row := UITheme.hbox(12)
		p.add_child(row)
		var info := UITheme.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mname: Dictionary = h["map"].get("name", {})
		info.add_child(UITheme.label("%s — %s" % [h.get("slot", "?"), MapDefinition._pick(mname, "") if not mname.is_empty() else h["map"]["id"]], 17, UITheme.TEXT, true))
		var sm: Dictionary = h.get("summary", {})
		info.add_child(UITheme.label(tr("LOAD_INFO") % [h.get("created", ""), sm.get("player", ""), int(sm.get("tiles", 0)),
			int(float(sm.get("elapsed", 0.0)) / 60.0)], 13, UITheme.TEXT_DIM))
		row.add_child(info)
		var path: String = h["path"]
		row.add_child(UITheme.accent_button(tr("LOAD_BUTTON"), func() -> void: App.load_match(path), 140))
		row.add_child(UITheme.button(tr("DELETE"), func() -> void:
			SaveManager.delete(path)
			_refresh(), 120))
		_list.add_child(p)
