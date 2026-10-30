class_name Sim
extends RefCounted
## The authoritative match simulation: fixed 10 ticks per second, pure logic (no nodes, no frame
## time, no global RNG). Every player and AI action arrives as a command (scripts/simulation/
## commands.gd) and is applied at the start of a tick, which keeps the door open for lockstep
## multiplayer. Tick order follows RoWorld's Sim.step (Sim.luau:387-441).

enum Phase { SPAWN, PLAYING, OVER }

var config: MatchConfig
var def: MapDefinition
var map: MapData
var rules: Rules
var rng: SimRng
var st: SimState
var events: SimEvents
var attacks: AttackSystem
var structures: StructureSystem
var economy: EconomySystem
var naval: NavalSystem
var spawn: SpawnSystem
var victory: Victory
var ai: AIDirector

var phase: int = Phase.SPAWN
var player_id: int = 0
var countdown_end: int = 0
var play_start_tick: int = 0
var result: Dictionary = {}
var _commands: Array[Dictionary] = []
## Optional profiling: per-system milliseconds of the last step.
var profile: Dictionary = {}
var profiling: bool = false


func _init(cfg: MatchConfig, map_def: MapDefinition, map_data: MapData) -> void:
	config = cfg
	def = map_def
	map = map_data
	rules = Rules.for_k(map.k_lin)
	rng = SimRng.new(cfg.seed)
	st = SimState.new(map, rules)
	events = SimEvents.new()
	attacks = AttackSystem.new(st, rules, rng, events)
	structures = StructureSystem.new(st, rules, events)
	attacks.structures = structures
	economy = EconomySystem.new(st, rules, structures)
	naval = NavalSystem.new(st, rules, events, attacks)
	spawn = SpawnSystem.new(st, rules, rng)
	victory = Victory.new(st, cfg.victory, rules.tick_rate)
	_create_owners()
	ai = AIDirector.new(self)
	ai.setup()
	if not cfg.has_player:
		_start_playing()


# ---------------------------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------------------------

func _create_owners() -> void:
	var name_rng := rng.fork(17)
	var nations: Array = def.nations
	var n_bots := clampi(config.bots, 0, 400)
	# Player first so their id is stable (1); they choose a start later.
	if config.has_player:
		var pname := config.player_name
		var pflag := ""
		if config.player_nation >= 0 and config.player_nation < nations.size():
			var nd: Dictionary = nations[config.player_nation]
			if pname == "":
				pname = MapDefinition.nation_name(nd)
			pflag = nd.get("flag", "")
		if pname == "":
			pname = tr("PLAYER_DEFAULT_NAME")
		player_id = st.add_owner(pname, Rules.KIND_HUMAN, Palette.PLAYER, pflag, config.player_nation)
	# Bot nations: map nations in a seeded order (the player's own nation excluded), then
	# generated names when the map has fewer nations than bots.
	var order: Array = []
	for i in nations.size():
		if i != config.player_nation:
			order.append(i)
	rng.fork(29).shuffle(order)
	for k in n_bots:
		var color := Palette.nation_color(k, config.seed)
		if k < order.size():
			var ni: int = order[k]
			var nd: Dictionary = nations[ni]
			var id := st.add_owner(MapDefinition.nation_name(nd), Rules.KIND_NATION, color, nd.get("flag", ""), ni)
			if id > 0:
				st.o_troops[id] = rules.start_troops
				st.o_gold[id] = rules.start_gold
				st.o_supplies[id] = rules.start_supplies
				if not spawn.place_near(id, int(nd.get("x", 0)), int(nd.get("y", 0))):
					st.kill(id, 0)
		else:
			var id := st.add_owner(NameGen.localized(NameGen.make(name_rng)), Rules.KIND_NATION, color)
			if id > 0:
				st.o_troops[id] = rules.start_troops
				st.o_gold[id] = rules.start_gold
				st.o_supplies[id] = rules.start_supplies
				if not spawn.place_random(id, rules.tribe_min_dist * 1.5):
					st.kill(id, 0)
	for k in clampi(config.tribes, 0, 300):
		var id := st.add_owner(NameGen.localized(NameGen.make_tribe(name_rng)), Rules.KIND_TRIBE, Palette.tribe_color(k))
		if id <= 0:
			break
		st.o_troops[id] = rules.tribe_start_troops
		st.o_supplies[id] = rules.start_supplies
		if not spawn.place_random(id, rules.tribe_min_dist):
			st.kill(id, 0)
	st.drain_changed_tiles()
	st.pending_elim.clear()


func _start_playing() -> void:
	phase = Phase.PLAYING
	play_start_tick = st.tick
	victory.start_tick = st.tick
	for id in range(1, st.owner_count + 1):
		if st.o_alive[id] == 1 and st.o_spawned[id] == 1:
			st.o_cap[id] = rules.troop_cap(st.o_kind[id], st.o_tiles[id], 0)
	events.emit(SimEvents.PHASE, {"phase": "playing"})


# ---------------------------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------------------------

## Queues a command; it is applied at the start of the next tick.
func submit(cmd: Dictionary) -> void:
	_commands.append(cmd)


func _process_commands() -> void:
	var cmds := _commands
	_commands = []
	for c in cmds:
		var reason := apply_command(c)
		if reason != "":
			events.emit(SimEvents.COMMAND_REJECTED, {"owner": c.get("owner", 0), "cmd": c.get("type", ""), "reason": reason})


## Validates and applies one command. Returns "" or the rejection reason.
func apply_command(c: Dictionary) -> String:
	var who := int(c.get("owner", 0))
	var type: String = c.get("type", "")
	if type == Commands.SPAWN:
		return _cmd_spawn(who, int(c.get("tile", -1)))
	if phase != Phase.PLAYING:
		return "not_playing"
	if not st.is_alive(who) or st.o_spawned[who] == 0:
		return "dead"
	match type:
		Commands.ATTACK:
			return _cmd_attack(who, c)
		Commands.BOAT:
			var t := int(c.get("tile", -1))
			var troops := _troops_of(who, c)
			return naval.launch(who, t, troops)
		Commands.BUILD:
			var r := structures.try_build(who, int(c.get("kind", -1)), int(c.get("tile", -1)))
			return "" if r["ok"] else String(r["reason"])
		Commands.RETREAT:
			return "" if attacks.retreat(who, int(c.get("attack", -1))) else "no_attack"
	return "unknown"


func _troops_of(who: int, c: Dictionary) -> float:
	if c.has("troops"):
		return floorf(minf(float(c["troops"]), st.o_troops[who]))
	var ratio := clampf(float(c.get("ratio", rules.default_ratio)), 0.01, 1.0)
	return floorf(st.o_troops[who] * ratio)


func _cmd_attack(who: int, c: Dictionary) -> String:
	var target := -1
	if c.has("target"):
		target = int(c["target"])
	else:
		var t := int(c.get("tile", -1))
		if t < 0 or t >= st.N or map.land[t] == 0:
			return "not_land"
		target = st.owner[t]
	if target == who:
		return "own_land"
	if target != 0 and not st.is_alive(target):
		return "dead_target"
	var troops := _troops_of(who, c)
	if troops < 1.0:
		return "no_troops"
	st.add_troops(who, -troops)
	var a := attacks.start(who, target, troops)
	if a == null and attacks.find(who, target) == null and attacks.find(target, who) == null:
		return "no_border"
	return ""


func _cmd_spawn(who: int, t: int) -> String:
	if phase != Phase.SPAWN or who != player_id or player_id == 0:
		return "not_spawn_phase"
	if st.o_spawned[who] == 1:
		return "already_spawned"
	if not spawn.is_valid_start(t):
		return "bad_tile"
	spawn.claim(who, t)
	st.o_troops[who] = rules.start_troops
	st.o_gold[who] = rules.start_gold
	st.o_supplies[who] = rules.start_supplies
	countdown_end = st.tick + rules.countdown_ticks
	events.emit(SimEvents.SPAWNED, {"owner": who, "tile": t})
	return ""


# ---------------------------------------------------------------------------------------------
# Tick
# ---------------------------------------------------------------------------------------------

func step() -> void:
	st.tick += 1
	events.tick = st.tick
	if phase == Phase.OVER:
		_commands.clear()
		return
	if phase == Phase.SPAWN:
		_process_commands()
		if countdown_end > 0 and st.tick >= countdown_end:
			_start_playing()
		return
	var t0 := 0
	if profiling:
		t0 = Time.get_ticks_usec()
	economy.tick()
	_lap("economy", t0)
	_process_commands()
	structures.tick()
	_lap("commands+structures", t0)
	ai.tick()
	_lap("ai", t0)
	attacks.tick()
	_lap("attacks", t0)
	naval.tick()
	_lap("naval", t0)
	_process_eliminations()
	if st.tick % 10 == 0:
		_check_end()


func _lap(name: String, t0: int) -> void:
	if not profiling:
		return
	var now := Time.get_ticks_usec()
	var prev: int = profile.get("_last", t0)
	profile[name] = float(now - prev) / 1000.0
	profile["_last"] = now


func _process_eliminations() -> void:
	if st.pending_elim.is_empty():
		return
	var list := st.pending_elim.duplicate()
	st.pending_elim.clear()
	for id: int in list:
		if st.o_alive[id] == 0 or st.o_tiles[id] > 0:
			continue
		var killer := st.o_killer[id]
		var gold := st.o_gold[id]
		st.kill(id, killer)
		attacks.end_all_of(id)
		naval.remove_owner(id)
		if killer > 0 and st.is_alive(killer):
			st.add_gold(killer, gold * float(rules.e["conquest_gold_share"]))
		st.add_gold(id, -gold)
		events.emit(SimEvents.ELIMINATED, {"owner": id, "by": killer})


func _check_end() -> void:
	var r := victory.check()
	if r.is_empty():
		return
	result = r
	phase = Phase.OVER
	events.emit(SimEvents.GAME_OVER, r)


func is_player_alive() -> bool:
	return player_id > 0 and st.is_alive(player_id)


func elapsed_seconds() -> float:
	return float(st.tick - play_start_tick) / float(rules.tick_rate) if phase != Phase.SPAWN else 0.0


# ---------------------------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"phase": phase, "player_id": player_id, "countdown_end": countdown_end,
		"play_start_tick": play_start_tick, "result": result, "rng": rng.get_state(),
		"state": st.to_dict(), "attacks": attacks.to_dict(), "structures": structures.to_dict(),
		"naval": naval.to_dict(), "spawn_starts": spawn.starts, "victory_start": victory.start_tick,
		"commands": _commands, "ai": ai.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	phase = d["phase"]
	player_id = d["player_id"]
	countdown_end = d["countdown_end"]
	play_start_tick = d["play_start_tick"]
	result = d["result"]
	rng.set_state(d["rng"])
	st.from_dict(d["state"])
	events.tick = st.tick
	attacks.from_dict(d["attacks"])
	structures.from_dict(d["structures"])
	naval.from_dict(d["naval"])
	spawn.starts.assign(d["spawn_starts"])
	victory.start_tick = d["victory_start"]
	_commands.assign(d["commands"])
	ai.from_dict(d["ai"])


## Deterministic fingerprint of the match state (tests: replays, save/load).
func state_hash() -> int:
	var parts := [st.tick, st.owner, st.o_tiles, st.o_troops, st.o_gold, st.o_supplies, rng.get_state()]
	var atk := []
	for a in attacks.attacks:
		if a.alive:
			atk.append([a.id, a.attacker, a.target, a.troops])
	parts.append(atk)
	return hash(parts)
