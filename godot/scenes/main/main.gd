extends Control
## Root of the game: applies the design system and shows the screen of App.state.

const SCREENS := {
	App.State.MAIN_MENU: "res://scenes/menus/main_menu.tscn",
	App.State.MAP_SELECT: "res://scenes/menus/map_select.tscn",
	App.State.MAP_GENERATOR: "res://scenes/menus/map_generator.tscn",
	App.State.MATCH_SETUP: "res://scenes/menus/match_setup.tscn",
	App.State.LOAD_GAME: "res://scenes/menus/load_game.tscn",
	App.State.SETTINGS: "res://scenes/menus/settings.tscn",
	App.State.CREDITS: "res://scenes/menus/credits.tscn",
}
const MATCH_SCENE := "res://scenes/gameplay/match.tscn"

var _current: Node
var _current_path: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	App.state_changed.connect(_on_state)
	_on_state(App.state)


func _on_state(s: int) -> void:
	var path: String = MATCH_SCENE if App.is_match_state(s) else SCREENS.get(s, SCREENS[App.State.MAIN_MENU])
	if path == _current_path and _current != null and s != App.State.LOADING:
		return
	if _current != null:
		_current.queue_free()
	_current = (load(path) as PackedScene).instantiate()
	_current_path = path
	add_child(_current)
