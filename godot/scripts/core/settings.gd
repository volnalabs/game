extends Node
## Autoload "Settings": user preferences in user://settings.cfg (ConfigFile).

const PATH := "user://settings.cfg"

var locale: String = "ru"
var ui_scale: float = 1.0
var edge_scroll: bool = true
var default_speed: float = 1.0
var show_ai_debug: bool = false
var ui_animations: bool = true
var last_difficulty: String = "normal"
var last_bots: int = 20


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	locale = cfg.get_value("ui", "locale", locale)
	ui_scale = cfg.get_value("ui", "scale", ui_scale)
	edge_scroll = cfg.get_value("controls", "edge_scroll", edge_scroll)
	default_speed = cfg.get_value("game", "speed", default_speed)
	show_ai_debug = cfg.get_value("game", "ai_debug", show_ai_debug)
	last_difficulty = cfg.get_value("game", "difficulty", last_difficulty)
	last_bots = cfg.get_value("game", "bots", last_bots)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "locale", locale)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.set_value("controls", "edge_scroll", edge_scroll)
	cfg.set_value("game", "speed", default_speed)
	cfg.set_value("game", "ai_debug", show_ai_debug)
	cfg.set_value("game", "difficulty", last_difficulty)
	cfg.set_value("game", "bots", last_bots)
	cfg.save(PATH)


func apply() -> void:
	TranslationServer.set_locale(locale)
	if get_tree() != null and get_tree().root != null:
		get_tree().root.content_scale_factor = ui_scale
