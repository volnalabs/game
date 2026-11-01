extends Node
## Autoload `Audio`: buses per category (Interface, Effects, Alerts, Ambience under Master), volumes
## from Settings, a small pool of players, and the sounds of the game — all synthesized on first use
## by SoundSynth from data/audio/sounds.json and cached. Every button in the tree clicks (unless it
## has the "silent" meta). Simulation events that concern the player map to sounds in on_event();
## repeats of one sound are limited by its min_interval so a busy war never turns into noise.

const BUS_NAMES := {"ui": "Interface", "sfx": "Effects", "alerts": "Alerts", "ambience": "Ambience"}
const POOL := 10

var defs: Dictionary = {}
var _cache: Dictionary = {}
var _last: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambience: AudioStreamPlayer
## Sounds played (id -> count) — read by tests and the debug overlay.
var played: Dictionary = {}
var _focused := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/sounds.json"))
	if d is Dictionary:
		defs = (d as Dictionary).get("sounds", {})
	_ensure_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = BUS_NAMES["ambience"]
	add_child(_ambience)
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)


func _ensure_buses() -> void:
	for k: String in BUS_NAMES:
		var name: String = BUS_NAMES[k]
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


## Applies the volumes in Settings (0..1 per category) to the buses.
func apply_volumes() -> void:
	var s := get_node_or_null("/root/Settings")
	if s == null:
		return
	_set_bus("Master", float(s.volume_master) * (1.0 if _focused or not bool(s.mute_unfocused) else 0.0))
	_set_bus(BUS_NAMES["ui"], float(s.volume_ui))
	_set_bus(BUS_NAMES["sfx"], float(s.volume_sfx))
	_set_bus(BUS_NAMES["alerts"], float(s.volume_alerts))
	_set_bus(BUS_NAMES["ambience"], float(s.volume_ambience))


func _set_bus(name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
		apply_volumes()


## The synthesized stream of sound `id` (built once).
func stream(id: String) -> AudioStreamWAV:
	if not _cache.has(id):
		if not defs.has(id):
			return null
		_cache[id] = SoundSynth.build(defs[id])
	return _cache[id]


## Plays sound `id` unless it played less than its min_interval ago. Returns whether it played.
func play(id: String, pitch: float = 1.0) -> bool:
	if not defs.has(id):
		return false
	var def: Dictionary = defs[id]
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < int(float(def.get("min_interval", 0.05)) * 1000.0):
		return false
	_last[id] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream(id)
	p.bus = BUS_NAMES.get(String(def.get("bus", "sfx")), "Master")
	p.pitch_scale = pitch
	p.play()
	played[id] = int(played.get(id, 0)) + 1
	return true


func start_ambience() -> void:
	if not defs.has("ambience") or _ambience.playing:
		return
	_ambience.stream = stream("ambience")
	_ambience.play()


func stop_ambience() -> void:
	_ambience.stop()


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		(n as BaseButton).pressed.connect(func() -> void: play("ui_click"))


## Sounds for simulation events that concern player `pid`.
func on_event(e: Dictionary, pid: int) -> void:
	if pid <= 0:
		return
	match String(e["type"]):
		SimEvents.ATTACK_STARTED:
			if int(e["attacker"]) == pid and int(e.get("target", 0)) > 0:
				play("attack_start")
			elif int(e.get("target", 0)) == pid and int(e["attacker"]) > 0:
				play("alert_attack")
		SimEvents.BUILD_DONE:
			if int(e["owner"]) == pid:
				play("build_done")
		SimEvents.RESEARCH_DONE:
			if int(e["owner"]) == pid:
				play("research_done")
		SimEvents.BOAT_LAUNCHED:
			if int(e["owner"]) == pid:
				play("boat_launch")
			elif int(e.get("target_owner", 0)) == pid:
				play("alert_attack")
		SimEvents.BOAT_LANDED:
			if int(e["owner"]) == pid or int(e.get("target_owner", 0)) == pid:
				play("landing")
		SimEvents.WEAPON_LAUNCHED:
			if int(e["owner"]) == pid:
				play("missile_launch")
			elif int(e.get("target_owner", 0)) == pid:
				play("alert_missile")
		SimEvents.WEAPON_IMPACT:
			if int(e["owner"]) == pid or (e.get("killed", {}) as Dictionary).has(pid):
				play("impact")
		SimEvents.NUKE_DETONATED:
			play("nuke")
		SimEvents.INTERCEPTED:
			if int(e.get("by", 0)) == pid or int(e["owner"]) == pid:
				play("intercept")
		SimEvents.DIPLO_REQUEST:
			if int(e["to"]) == pid:
				play("diplo_offer")
		SimEvents.HELP_REQUEST:
			if int(e["to"]) == pid:
				play("diplo_offer")
		SimEvents.DIPLO_ENDED:
			var breaker := int(e.get("breaker", 0))
			if breaker > 0 and breaker != pid and (int(e["a"]) == pid or int(e["b"]) == pid):
				play("betrayal")
		SimEvents.CONVOY_ARRIVED:
			if int(e["to"]) == pid and int(e["from"]) != pid:
				play("convoy")
		SimEvents.COMMAND_REJECTED:
			if int(e.get("owner", 0)) == pid:
				play("ui_error")
