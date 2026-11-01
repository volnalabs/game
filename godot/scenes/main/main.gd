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
	App.State.PROFILE: "res://scripts/ui/screens/profile_screen.gd",
	App.State.PROGRESS: "res://scripts/ui/screens/progress_screen.gd",
	App.State.CASES: "res://scripts/ui/screens/cases_screen.gd",
	App.State.INVENTORY: "res://scripts/ui/screens/inventory_screen.gd",
	App.State.ACHIEVEMENTS: "res://scripts/ui/screens/achievements_screen.gd",
	App.State.RESULTS: "res://scripts/ui/screens/results_screen.gd",
	App.State.SKILLS: "res://scripts/ui/screens/skill_tree_screen.gd",
	App.State.ENCYCLOPEDIA: "res://scripts/ui/screens/encyclopedia_screen.gd",
}
const MATCH_SCENE := "res://scenes/gameplay/match.tscn"

var _current: Node
var _current_path: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The root only hosts screens: it must never swallow mouse events, or clicks on the map
	# (handled in MatchController._unhandled_input) never arrive.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.theme()
	App.state_changed.connect(_on_state)
	App.refresh_requested.connect(_refresh)
	_on_state(App.state)


func _refresh() -> void:
	theme = UITheme.theme()
	if not App.is_match_state(App.state):
		_current_path = ""
		_on_state(App.state)


func _on_state(s: int) -> void:
	var path: String = MATCH_SCENE if App.is_match_state(s) else SCREENS.get(s, SCREENS[App.State.MAIN_MENU])
	if path == _current_path and _current != null and s != App.State.LOADING:
		return
	if _current != null:
		_current.queue_free()
	# Newer screens are plain scripts (no scene file needed).
	var res: Resource = load(path)
	_current = (res as GDScript).new() if res is GDScript else (res as PackedScene).instantiate()
	_current_path = path
	add_child(_current)
