extends Node
## Autoload "App": the application state machine (docs/game-design/GAME_DESIGN.md §1) and the data
## handed from one screen to the next. scenes/main/main.gd swaps screens on state_changed.

signal state_changed(state: int)

enum State { MAIN_MENU, MAP_SELECT, MAP_GENERATOR, MATCH_SETUP, LOADING, SPAWN_SELECT, PLAYING, PAUSED,
	VICTORY, DEFEAT, LOAD_GAME, SETTINGS, CREDITS }

const STATE_NAMES := ["main_menu", "map_select", "map_generator", "match_setup", "loading", "spawn_select",
	"playing", "paused", "victory", "defeat", "load_game", "settings", "credits"]

var state: int = State.MAIN_MENU
## Selected map for the next match (registry map or a generated world).
var map_def: MapDefinition
## Pre-built terrain of a generated world (registry maps are loaded by MapLoader).
var map_data: MapData
var config: MatchConfig = MatchConfig.new()
## Path of a save to load when entering LOADING (empty = new match).
var load_path: String = ""
## Extra main-menu entries registered by optional systems: {section: play|progress|info, icon,
## label (translation key), action: Callable}. Keeps the menu free of hard-coded screens.
var menu_extras: Array[Dictionary] = []
## Callables returning a Control for the right column of the main menu (profile card...).
var menu_cards: Array[Callable] = []


func add_menu_entry(section: String, icon: String, label: String, state: int) -> void:
	menu_extras.append({"section": section, "icon": icon, "label": label, "action": func() -> void: goto(state)})


func goto(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)


func is_match_state(s: int = -1) -> bool:
	if s < 0:
		s = state
	return s in [State.LOADING, State.SPAWN_SELECT, State.PLAYING, State.PAUSED, State.VICTORY, State.DEFEAT]


func select_map(def: MapDefinition, data: MapData = null) -> void:
	map_def = def
	map_data = data
	config.map_id = def.id
	config.generator = def.generator


func start_new_match() -> void:
	load_path = ""
	goto(State.LOADING)


func load_match(path: String) -> void:
	load_path = path
	goto(State.LOADING)
