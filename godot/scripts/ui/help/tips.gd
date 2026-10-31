class_name Tips
extends RefCounted
## Contextual one-time tips (data/help/tips.json). A tip appears the first time the player meets a
## mechanic; it can be dismissed, opened in the encyclopedia, or all tips switched off (Settings).

static var _d: Dictionary = {}


static func data() -> Dictionary:
	if _d.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/help/tips.json"))
		for t: Dictionary in (v as Dictionary)["tips"]:
			_d[String(t["id"])] = t
	return _d


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree != null else null


## Whether tip `id` should be shown now (tips on and not seen yet).
static func should_show(id: String) -> bool:
	var s := _settings()
	if s == null or not data().has(id):
		return false
	return bool(s.get("show_tips")) and not (s.get("seen_tips") as Array).has(id)


static func mark_seen(id: String) -> void:
	var s := _settings()
	if s == null:
		return
	var seen: Array = s.get("seen_tips")
	if not seen.has(id):
		seen.append(id)
	s.call("save_settings")


static func disable_all() -> void:
	var s := _settings()
	if s != null:
		s.set("show_tips", false)
		s.call("save_settings")


static func reset() -> void:
	var s := _settings()
	if s != null:
		s.set("seen_tips", [])
		s.set("show_tips", true)
		s.call("save_settings")
