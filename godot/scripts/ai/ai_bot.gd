class_name StrategicAI
extends AIBrain
## VolnaLabs' strategic AI for one state (docs/ai/AI_DESIGN.md). Layers:
##   Perception (fog of war, noisy remembered estimates) -> StrategicPlanner (state machine with
##   utilities) -> tactics (AttackPlanner with BattleForecaster, DefensePlanner, NavalPlanner)
##   -> EconomicPlanner (buildings). Personality weights and difficulty (decision quality only)
##   come from data/ai/*.json. Every decision and refusal is logged with its reason.

const S_EXPAND := 0
const S_DEVELOP := 1
const S_PREPARE := 2
const S_WAR := 3
const S_DEFEND := 4
const S_CONSOLIDATE := 5
const STATE_NAMES := ["expand", "develop", "prepare_war", "war", "defend", "consolidate"]

var pers: Dictionary
var diff: Dictionary
var perception: AIPerception
var state: int = S_EXPAND
var target: int = 0
var state_since: int = 0
var war_plan: Dictionary = {}
var options: Array = []
var threats: Dictionary = {}
var relations: Dictionary = {}
var plan_note: String = ""
var has_coast: bool = true
var bodies_cache: Array[int] = []
## Offensive commitments (expansions, attacks, reinforcements, landings) are spaced by at least
## OFFENSE_GAP ticks whatever the difficulty: series showed that a bot thinking every 5 ticks
## otherwise keeps feeding attacks and scatters its army. Reactions (counter-attacks) stay fast.
const OFFENSE_GAP := 20
var next_offense: int = 0
## Tick of the last offensive commitment (stalemate pressure).
var last_offense: int = 0
var bodies_tick: int = -100000
var next_strategic: int = 0
var next_econ: int = 0
var next_naval: int = 0
var last_war_end: int = -100000
var state_ticks: Dictionary = {}
var _noticed: Dictionary = {}
## Attack id -> tick of our last counter (or hold decision) against it.
var countered: Dictionary = {}
var _started: bool = false


func _init(owner_id: int, sim_: Sim, rng_: SimRng, diff_id: String, pers_id: String) -> void:
	super(owner_id, sim_, rng_)
	kind_name = "strategic"
	difficulty_id = diff_id
	personality_id = pers_id
	pers = AIProfile.personality(pers_id)
	diff = AIProfile.difficulty(diff_id)
	perception = AIPerception.new(owner_id, sim_, rng_.fork(7), diff)


# ---- helpers used by the planners ----

func troops() -> float:
	return sim.st.o_troops[id]


func cap() -> float:
	return maxf(sim.st.o_cap[id], 1.0)


func fill() -> float:
	return troops() / cap()


func relation(o: int) -> Dictionary:
	if not relations.has(o):
		relations[o] = {"grudge": 0.0, "attacks": 0, "last_attack": -100000, "tiles_prev": sim.st.o_tiles[o],
			"tick_prev": sim.st.tick, "growth": 0.0, "eff": 1.0, "expect": {}}
	return relations[o]


## Minimum army kept at home (share of the cap): a dense home army is what makes invaders pay.
func home_floor() -> float:
	return cap() * (0.24 + 0.3 * float(pers["reserve"]))


## Remember what an attack was expected to take, to compare with what it really took.
func expect(target: int, troops: float, captured: float) -> void:
	if target <= 0:
		return
	var rel := relation(target)
	rel["pending"] = [troops, captured, sim.st.tick]


## Learning from outcomes: the ratio of real to forecast tiles per troop against this target
## corrects every later forecast against it (fortifications, hidden reserves, bad estimates).
func on_attack_ended(info: Dictionary) -> void:
	var tg := int(info["target"])
	if tg <= 0 or not relations.has(tg):
		return
	var rel: Dictionary = relations[tg]
	var pend: Array = rel.get("pending", [])
	if pend.is_empty():
		return
	var sent := maxf(float(info["initial"]), 1.0)
	var forecast_per_troop := float(pend[1]) / maxf(float(pend[0]), 1.0)
	var real_per_troop := float(info["taken"]) / sent
	if forecast_per_troop <= 0.0:
		return
	var ratio := clampf(real_per_troop / forecast_per_troop, 0.05, 2.0)
	rel["eff"] = lerpf(float(rel.get("eff", 1.0)), ratio, 0.6)
	rel.erase("pending")
	log.add(sim.st.tick, "learn", tg, {"u": ratio, "reason": "outcome %d tiles vs %.0f forecast" % [int(info["taken"]), float(pend[1]) * sent / maxf(float(pend[0]), 1.0)]})


func note_attacked_by(o: int, their: float) -> void:
	var rel := relation(o)
	rel["last_attack"] = sim.st.tick


func set_state(s: int, tgt: int) -> void:
	if s != state or tgt != target:
		log.add(sim.st.tick, "state", tgt if s in [S_WAR, S_PREPARE] else -1, {"state": STATE_NAMES[s]})
		state = s
		target = tgt
		state_since = sim.st.tick


func max_wars() -> int:
	return int(pers.get("max_wars", 2))


# ---- the think loop ----

func think() -> void:
	var st := sim.st
	var now := st.tick
	var tact := int(diff["tactical_interval"])
	next_think = now + tact
	state_ticks[state] = int(state_ticks.get(state, 0)) + tact
	perception.refresh()
	_update_memory()
	if not _started:
		_started = true
		_opening()
		return
	if now >= next_strategic:
		next_strategic = now + int(diff["strategic_interval"])
		_strategic_upkeep()
		StrategicPlanner.decide(self)
	DefensePlanner.counter(self)
	DefensePlanner.review_attacks(self)
	_act_on_state()
	if now >= next_econ:
		next_econ = now + int(diff["econ_interval"])
		EconomicPlanner.act(self)


## First move: grab free land around the start (like every player does).
func _opening() -> void:
	perception.estimate_free_land()
	var send := troops() * 0.6
	if perception.free_contact > 0:
		submit(Commands.attack_target(id, 0, send))
		log.add(sim.st.tick, "expand", 0, {"troops": send, "reason": "opening"})
	next_strategic = sim.st.tick + 5


func _update_memory() -> void:
	for e: Dictionary in perception.incoming:
		var aid: int = e["id"]
		if _noticed.has(aid):
			continue
		_noticed[aid] = true
		var o: int = e["attacker"]
		var rel := relation(o)
		rel["grudge"] = minf(1.5, float(rel["grudge"]) + 0.25 + 0.5 * minf(1.0, float(e["troops"]) / maxf(troops(), 1.0)))
		rel["attacks"] = int(rel["attacks"]) + 1
		rel["last_attack"] = sim.st.tick


func _strategic_upkeep() -> void:
	var st := sim.st
	var decay := 0.02 / maxf(float(pers["grudge"]), 0.2)
	for o: int in relations:
		var rel: Dictionary = relations[o]
		rel["grudge"] = maxf(0.0, float(rel["grudge"]) * (1.0 - decay) - 0.002)
		var dt := st.tick - int(rel["tick_prev"])
		if dt >= 300:
			var prev := maxf(1.0, float(rel["tiles_prev"]))
			rel["growth"] = (float(st.o_tiles[o]) - prev) / prev * (600.0 / dt)
			rel["tiles_prev"] = st.o_tiles[o]
			rel["tick_prev"] = st.tick
	if _noticed.size() > 200:
		_noticed.clear()
	if countered.size() > 200:
		countered.clear()


func _wars() -> int:
	var n := 0
	for a in sim.attacks.outgoing(id):
		if a.target != 0:
			n += 1
	return n


func _available() -> float:
	return maxf(0.0, troops() - maxf(DefensePlanner.reserve_needed(self), home_floor()))


## Troops free for expansion: troop growth peaks around 40 % of the cap, so a sensible state keeps
## a growth reserve instead of draining its army into empty land.
func _available_expand() -> float:
	var keep := maxf((0.22 + 0.35 * float(pers["reserve"])) * cap(), home_floor())
	return maxf(0.0, troops() - maxf(DefensePlanner.reserve_needed(self), keep))


func _act_on_state() -> void:
	var st := sim.st
	var now := st.tick
	match state:
		S_EXPAND:
			_expand()
			_opportunistic(0.25)
		S_PREPARE:
			if fill() >= 0.3 + float(pers["reserve"]) * 0.5 or not perception.incoming.is_empty():
				set_state(S_WAR, target)
				_wage_war()
		S_WAR:
			_wage_war()
		S_DEFEND:
			_opportunistic(0.25)
		S_DEVELOP, S_CONSOLIDATE:
			_opportunistic(0.4)
	# Naval: whenever there is no free land to take on our own landmass, compare the best landing
	# (free islands, overseas rivals) with the best land war and take it when it is worth more.
	# Landings are limited by the boats at sea, not by the land offensive cooldown.
	if now >= next_naval and perception.free_contact == 0 and state != S_DEFEND:
		var landing := NavalPlanner.best_landing(self)
		var land_u := 0.0
		if not options.is_empty() and float(options[0]["u"]) > 0.0:
			land_u = float(options[0]["u"])
		if not landing.is_empty() and float(landing["u"]) > land_u * 0.7:
			NavalPlanner.launch(self, landing)
			last_offense = now
			next_naval = now + 30
		else:
			next_naval = now + int(150.0 / maxf(float(pers["naval"]), 0.3))


func _offense_ready() -> bool:
	return sim.st.tick >= next_offense


func _committed() -> void:
	next_offense = sim.st.tick + OFFENSE_GAP
	last_offense = sim.st.tick


func _expand() -> void:
	if perception.free_contact == 0 or not _offense_ready():
		return
	var a := sim.attacks.find(id, 0)
	var available := _available_expand()
	if a != null and a.troops > available * 0.25:
		return
	var e := AttackPlanner.best_size(self, 0, available)
	if e.is_empty() or float(e["u"]) <= 0.0:
		return
	var send: float = e["troops"]
	# Don't overspend on a small patch: enough to take it with a margin.
	var need := float(perception.free_estimate) * CombatMath.neutral_loss(sim.rules, perception.free_mag, sim.st.o_kind[id]) * 1.3
	send = minf(send, maxf(need, 300.0))
	if send >= 100.0:
		submit(Commands.attack_target(id, 0, send))
		_committed()
		log.add(sim.st.tick, "expand", 0, {"troops": send, "u": e["u"]})


func _wage_war() -> void:
	var st := sim.st
	if target <= 0 or not st.is_alive(target) or not perception.neighbors.has(target):
		last_war_end = st.tick
		set_state(S_DEVELOP, 0)
		return
	if not _offense_ready():
		return
	var a := sim.attacks.find(id, target)
	var available := _available()
	if a != null:
		if a.troops > 0.3 * a.initial or available < 500.0:
			return
		var e := AttackPlanner.best_size(self, target, available)
		if not e.is_empty() and float(e["u"]) > 0.0:
			submit(Commands.attack_target(id, target, float(e["troops"])))
			_committed()
			log.add(st.tick, "reinforce", target, {"troops": e["troops"], "u": e["u"], "reason": e["reason"]})
		return
	if _wars() >= max_wars():
		return
	var e2 := AttackPlanner.best_size(self, target, available)
	if e2.is_empty() or float(e2["u"]) <= 0.0:
		log.add(st.tick, "refuse", target, {"u": e2.get("u", 0.0), "reason": e2.get("reason", "insufficient_troops"),
			"troops": e2.get("troops", available)})
		last_war_end = st.tick
		set_state(S_DEVELOP, 0)
		return
	submit(Commands.attack_target(id, target, float(e2["troops"])))
	_committed()
	expect(target, float(e2["troops"]), float(e2["captured"]))
	log.add(st.tick, "attack", target, {"troops": e2["troops"], "u": e2["u"], "captured": e2["captured"],
		"loss": e2["loss"], "reason": e2["reason"]})


## Outside of a war: take an exceptional opportunity (utility above `bar` x troops sent).
func _opportunistic(bar: float) -> void:
	if options.is_empty() or _wars() >= max_wars() or not _offense_ready():
		return
	var best: Dictionary = options[0]
	var tgt: int = best["target"]
	if not sim.st.is_alive(tgt) or sim.attacks.find(id, tgt) != null or not perception.neighbors.has(tgt):
		return
	var e := AttackPlanner.best_size(self, tgt, _available())
	if e.is_empty() or float(e["u"]) < bar * float(e["troops"]):
		return
	submit(Commands.attack_target(id, tgt, float(e["troops"])))
	_committed()
	expect(tgt, float(e["troops"]), float(e["captured"]))
	log.add(sim.st.tick, "attack", tgt, {"troops": e["troops"], "u": e["u"], "captured": e["captured"],
		"reason": "opportunity:" + String(e["reason"])})
	options.clear()


# ---- debugging / statistics ----

func debug_info() -> Dictionary:
	var d := super()
	d["state"] = STATE_NAMES[state]
	d["target"] = target
	d["note"] = plan_note
	var top: Array = []
	for o: int in threats:
		top.append([o, threats[o]])
	top.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	d["threats"] = top.slice(0, 3)
	d["fill"] = fill()
	d["reserve"] = DefensePlanner.reserve_needed(self)
	d["options"] = options.slice(0, 3).map(func(o: Dictionary) -> Dictionary:
		return {"target": o["target"], "u": o["u"], "troops": o["troops"], "reason": o["reason"]})
	return d


func stats() -> Dictionary:
	var d := super()
	var named := {}
	for k: int in state_ticks:
		named[STATE_NAMES[k]] = state_ticks[k]
	d["state_ticks"] = named
	return d


func to_dict() -> Dictionary:
	var d := super()
	d.merge({"state": state, "target": target, "state_since": state_since, "relations": relations,
		"next_strategic": next_strategic, "next_econ": next_econ, "next_naval": next_naval,
		"last_war_end": last_war_end, "state_ticks": state_ticks, "started": _started,
		"has_coast": has_coast, "memory": perception.memory, "prng": perception.rng.get_state(),
		"options": options, "threats": threats, "war_plan": war_plan, "countered": countered, "noticed": _noticed,
		"free_estimate": perception.free_estimate, "plan_note": plan_note, "next_offense": next_offense, "last_offense": last_offense})
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	state = d.get("state", S_EXPAND)
	target = d.get("target", 0)
	state_since = d.get("state_since", 0)
	relations = d.get("relations", {})
	next_strategic = d.get("next_strategic", 0)
	next_econ = d.get("next_econ", 0)
	next_naval = d.get("next_naval", 0)
	last_war_end = d.get("last_war_end", -100000)
	state_ticks = d.get("state_ticks", {})
	_started = d.get("started", false)
	has_coast = d.get("has_coast", true)
	perception.memory = d.get("memory", {})
	options = d.get("options", [])
	threats = d.get("threats", {})
	war_plan = d.get("war_plan", {})
	countered = d.get("countered", {})
	_noticed = d.get("noticed", {})
	perception.free_estimate = d.get("free_estimate", 0)
	plan_note = d.get("plan_note", "")
	next_offense = d.get("next_offense", 0)
	last_offense = d.get("last_offense", 0)
	if d.has("prng"):
		perception.rng.set_state(d["prng"])
