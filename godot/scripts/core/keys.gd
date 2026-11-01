class_name Keys
extends RefCounted
## Hotkeys of the match (Phase 2G): one registry of InputMap actions ("tf_<id>") with default keys.
## The player can rebind the main key of each action (Settings.key_overrides: id -> keycode); extra
## default keys (arrows next to WASD, keypad +/-) stay. Esc always cancels and opens the menu (not
## rebindable), so the player can never lock themselves out. Hints read the current key from here.

## [id, label key, default keycodes...] — the first keycode is the rebindable main key.
const ACTIONS := [
	["pause", "KEYS_PAUSE", KEY_SPACE],
	["speed_up", "KEYS_SPEED_UP", KEY_EQUAL, KEY_KP_ADD],
	["speed_down", "KEYS_SPEED_DOWN", KEY_MINUS, KEY_KP_SUBTRACT],
	["ratio_down", "KEYS_RATIO_DOWN", KEY_Q],
	["ratio_up", "KEYS_RATIO_UP", KEY_E],
	["confirm", "KEYS_CONFIRM", KEY_ENTER, KEY_KP_ENTER],
	["build", "KEYS_BUILD", KEY_B],
	["zones", "KEYS_ZONES", KEY_Z],
	["home", "KEYS_HOME", KEY_HOME],
	["toggle_ui", "KEYS_TOGGLE_UI", KEY_TAB],
	["save", "KEYS_SAVE", KEY_F5],
	["encyclopedia", "KEYS_ENCYCLOPEDIA", KEY_F1],
	["ai_debug", "KEYS_AI_DEBUG", KEY_F3],
	["cam_left", "KEYS_CAM_LEFT", KEY_A, KEY_LEFT],
	["cam_right", "KEYS_CAM_RIGHT", KEY_D, KEY_RIGHT],
	["cam_up", "KEYS_CAM_UP", KEY_W, KEY_UP],
	["cam_down", "KEYS_CAM_DOWN", KEY_S, KEY_DOWN],
	["quick_1", "KEYS_QUICK_1", KEY_1],
	["quick_2", "KEYS_QUICK_2", KEY_2],
	["quick_3", "KEYS_QUICK_3", KEY_3],
	["quick_4", "KEYS_QUICK_4", KEY_4],
	["quick_5", "KEYS_QUICK_5", KEY_5],
	["quick_6", "KEYS_QUICK_6", KEY_6],
]

## Keys that cannot be bound to an action (Esc is reserved for cancel / menu).
const RESERVED := [KEY_ESCAPE]


static func action(id: String) -> StringName:
	return StringName("tf_" + id)


static func ids() -> Array[String]:
	var out: Array[String] = []
	for a: Array in ACTIONS:
		out.append(String(a[0]))
	return out


static func _def(id: String) -> Array:
	for a: Array in ACTIONS:
		if String(a[0]) == id:
			return a
	return []


static func default_key(id: String) -> int:
	var a := _def(id)
	return int(a[2]) if a.size() > 2 else KEY_NONE


static func label_key(id: String) -> String:
	var a := _def(id)
	return String(a[1]) if a.size() > 1 else id


## The main key of `id` with the player's overrides applied (KEY_NONE = unbound).
static func key(id: String, overrides: Dictionary) -> int:
	return int(overrides.get(id, default_key(id)))


## (Re)creates every action in the InputMap from the defaults and `overrides`.
static func install(overrides: Dictionary) -> void:
	for a: Array in ACTIONS:
		var id := String(a[0])
		var act := action(id)
		if InputMap.has_action(act):
			InputMap.action_erase_events(act)
		else:
			InputMap.add_action(act)
		var main := key(id, overrides)
		var codes: Array[int] = []
		if main != KEY_NONE:
			codes.append(main)
		for i in range(3, a.size()):
			var extra := int(a[i])
			# An extra default key stays unless the player gave it to another action.
			if extra != main and not _taken_elsewhere(extra, id, overrides):
				codes.append(extra)
		for code in codes:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(act, ev)


static func _taken_elsewhere(code: int, id: String, overrides: Dictionary) -> bool:
	for other: String in ids():
		if other != id and key(other, overrides) == code:
			return true
	return false


## Binds `code` as the main key of `id`. Returns the id of the action that lost this key ("" if
## none); that action is left unbound so two actions never share a key.
static func rebind(id: String, code: int, overrides: Dictionary) -> String:
	if code in RESERVED:
		return "reserved"
	var lost := ""
	for other: String in ids():
		if other != id and key(other, overrides) == code:
			overrides[other] = KEY_NONE
			lost = other
	if code == default_key(id):
		overrides.erase(id)
	else:
		overrides[id] = code
	install(overrides)
	return lost


## Human-readable main key of `id` ("—" when unbound), for hints and the settings screen.
static func label(id: String) -> String:
	var s: Node = Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() is SceneTree else null
	var ov: Dictionary = s.key_overrides if s != null else {}
	return key_name(key(id, ov))


static func key_name(code: int) -> String:
	if code == KEY_NONE:
		return "—"
	match code:
		KEY_SPACE:
			return TranslationServer.translate("KEY_SPACE")
		KEY_ENTER:
			return "Enter"
		KEY_ESCAPE:
			return "Esc"
		KEY_EQUAL:
			return "="
		KEY_MINUS:
			return "−"
		KEY_KP_ADD:
			return "Num +"
		KEY_KP_SUBTRACT:
			return "Num −"
	return OS.get_keycode_string(code)
