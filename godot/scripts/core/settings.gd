extends Node
## Autoload "Settings": user preferences in user://settings.cfg (ConfigFile).

const PATH := "user://settings.cfg"

var locale: String = "ru"
var ui_scale: float = 1.0
var edge_scroll: bool = true
var default_speed: float = 1.0
var show_ai_debug: bool = false
var ui_animations: bool = true
var show_zones: bool = false
## Contextual first-time tips, and the ones already seen.
var show_tips: bool = true
var seen_tips: Array = []
var last_difficulty: String = "normal"
var last_bots: int = 20


## The game was called "VolnaLabs: World Strategy" before it became TerraFront; Godot keeps user data
## per project name, so the old folder (settings, profile, saves) is copied over once.
const OLD_DATA_DIR := "VolnaLabs- World Strategy"


func _ready() -> void:
	migrate_old_user_data()
	load_settings()
	apply()


## Copies the previous name's user data into this one when this one is still empty.
static func migrate_old_user_data() -> void:
	var here := OS.get_user_data_dir()
	migrate_dir(here.get_base_dir().path_join(OLD_DATA_DIR), here)


## Copies `old` into `here` unless `here` already has settings or a profile. True if it copied.
static func migrate_dir(old: String, here: String) -> bool:
	if old == here or not DirAccess.dir_exists_absolute(old):
		return false
	if FileAccess.file_exists(here.path_join("settings.cfg")) or FileAccess.file_exists(here.path_join("profile.json")):
		return false
	_copy_dir(old, here)
	return true


static func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			var src := from.path_join(n)
			var dst := to.path_join(n)
			if d.current_is_dir():
				_copy_dir(src, dst)
			elif not FileAccess.file_exists(dst):
				DirAccess.copy_absolute(src, dst)
		n = d.get_next()
	d.list_dir_end()


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
	ui_animations = cfg.get_value("ui", "animations", ui_animations)
	show_zones = cfg.get_value("game", "zones", show_zones)
	show_tips = cfg.get_value("ui", "tips", show_tips)
	seen_tips = cfg.get_value("ui", "seen_tips", seen_tips)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "locale", locale)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.set_value("controls", "edge_scroll", edge_scroll)
	cfg.set_value("game", "speed", default_speed)
	cfg.set_value("game", "ai_debug", show_ai_debug)
	cfg.set_value("game", "difficulty", last_difficulty)
	cfg.set_value("game", "bots", last_bots)
	cfg.set_value("ui", "animations", ui_animations)
	cfg.set_value("game", "zones", show_zones)
	cfg.set_value("ui", "tips", show_tips)
	cfg.set_value("ui", "seen_tips", seen_tips)
	cfg.save(PATH)


func apply() -> void:
	TranslationServer.set_locale(locale)
	if get_tree() != null and get_tree().root != null:
		get_tree().root.content_scale_factor = ui_scale
