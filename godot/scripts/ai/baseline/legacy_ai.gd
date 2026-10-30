class_name LegacyAI
extends AIBrain
## Baseline for AI comparisons: a simplified port of RoWorld's nation AI (SimAI.luau,
## SimAIEconomy.luau). Omniscient troop ratios, "send everything above a fixed reserve", a fixed
## build recipe. VolnaLabs' StrategicAI must beat it (tests/ai, docs/ai/AI_DESIGN.md §11).

const RATES := {"easy": Vector2i(65, 100), "normal": Vector2i(55, 70), "hard": Vector2i(45, 60)}

var aggression: float = 1.0
var naval: float = 1.0
var trigger_r: float = 0.5
var reserve_r: float = 0.3
var expand_r: float = 0.1
var attack_rate: int = 60
var next_attack: int = 0
var last_boat: int = -10000
var started_once: bool = false


func _init(owner_id: int, sim_: Sim, rng_: SimRng, diff: String) -> void:
	super(owner_id, sim_, rng_)
	kind_name = "legacy"
	difficulty_id = diff
	personality_id = "legacy"
	aggression = rng.range_f(0.8, 1.25)
	naval = rng.range_f(0.5, 1.5)
	trigger_r = rng.range_f(0.5, 0.59)
	reserve_r = rng.range_f(0.3, 0.39)
	expand_r = rng.range_f(0.1, 0.19)
	var r: Vector2i = RATES.get(diff, RATES["normal"])
	attack_rate = rng.range_i(r.x, r.y)


func _above(keep: float) -> float:
	var st := sim.st
	return st.o_troops[id] - keep * maxf(st.o_cap[id], 1.0)


func think() -> void:
	var st := sim.st
	var now := st.tick
	next_think = now + 15 + rng.range_i(-3, 3)
	var nb := st.neighbours(id, 800)
	if not started_once:
		started_once = true
		submit(Commands.attack_target(id, 0, st.o_troops[id] * 0.5))
		log.add(now, "expand", 0, {"troops": st.o_troops[id] * 0.5})
		next_attack = now + attack_rate
		return
	var defended := _defend()
	var due := now >= next_attack
	var started_war := false
	if due:
		next_attack = now + attack_rate
		if nb.has(0):
			var send := _above(expand_r)
			if send > 100.0:
				submit(Commands.attack_target(id, 0, send))
				log.add(now, "expand", 0, {"troops": send})
		elif not defended:
			started_war = _consider_war(nb)
	_consider_build()
	if not nb.has(0) and not started_war:
		_consider_boat()


func _defend() -> bool:
	var st := sim.st
	if st.tick - st.o_attacked_tick[id] > 40:
		return false
	var worst: AttackSystem.Attack = null
	for a in sim.attacks.incoming(id):
		if a.attacker != 0 and (worst == null or a.troops > worst.troops):
			worst = a
	if worst == null:
		return false
	var mine := st.o_troops[id]
	if mine < 1.1 * worst.troops or worst.troops < 0.02 * mine:
		return false
	var own := sim.attacks.find(id, worst.attacker)
	if own != null and own.troops >= 0.8 * worst.troops:
		return false
	var ratio := clampf(1.25 * worst.troops / mine, 0.05, 0.4)
	submit(Commands.attack_target(id, worst.attacker, mine * ratio))
	log.add(st.tick, "counter", worst.attacker, {"troops": mine * ratio})
	return true


func _consider_war(nb: Dictionary) -> bool:
	var st := sim.st
	var cap := maxf(st.o_cap[id], 1.0)
	var fill := st.o_troops[id] / cap
	if fill < reserve_r or (fill < trigger_r and not rng.chance(0.1)):
		return false
	var wars := sim.attacks.outgoing(id).size()
	if wars >= 2:
		return false
	var best := 0
	var best_s := 0.0
	var mine := st.o_troops[id]
	for o: int in nb:
		if o == 0 or not st.is_alive(o) or int(nb[o]) < 2:
			continue
		var s := mine / (st.o_troops[o] + 1.0)
		if st.o_kind[o] == Rules.KIND_TRIBE:
			s *= 1.5
		s *= aggression * (0.8 + 0.2 * minf(float(nb[o]) / 20.0, 1.0))
		if s > best_s:
			best_s = s
			best = o
	if best == 0 or best_s < 1.0:
		return false
	var send := _above(reserve_r)
	if send < 100.0:
		return false
	submit(Commands.attack_target(id, best, send))
	log.add(st.tick, "attack", best, {"troops": send, "u": best_s})
	return true


func _consider_build() -> void:
	var st := sim.st
	var gold := st.o_gold[id]
	if gold < 100000.0:
		return
	var kind := Rules.B_CITY
	var cities := st.bowned(id, Rules.B_CITY)
	var coastal := _has_coast()
	if coastal and st.bowned(id, Rules.B_PORT) == 0:
		kind = Rules.B_PORT
	elif coastal and st.bowned(id, Rules.B_PORT) < int(0.75 * cities):
		kind = Rules.B_PORT
	elif st.bowned(id, Rules.B_FACTORY) < int(0.75 * cities * (0.33 if coastal else 1.0)):
		kind = Rules.B_FACTORY
	if not sim.structures.can_afford(id, kind):
		return
	var t := _site_tile(kind)
	if t >= 0:
		submit(Commands.build(id, kind, t))
		log.add(st.tick, "build", -1, {"building": sim.rules.b_ids[kind]})


func _has_coast() -> bool:
	return _site_tile(Rules.B_PORT) >= 0


func _site_tile(kind: int) -> int:
	var st := sim.st
	if kind == Rules.B_PORT:
		var t := st.o_border_head[id]
		var n := 0
		while t >= 0 and n < 3000:
			if st.map.coastal[t] == 1:
				return t
			t = st.bnext[t]
			n += 1
		# Interior coast (not a border tile): try the spawn area.
		var sp := st.o_spawn_tile[id]
		return sp if sp >= 0 and st.owner[sp] == id and st.map.coastal[sp] == 1 else -1
	var c := st.centroid(id)
	var ct := st.map.tile_at(int(c.x), int(c.y))
	if ct >= 0 and st.owner[ct] == id:
		return ct
	var sp2 := st.o_spawn_tile[id]
	if sp2 >= 0 and st.owner[sp2] == id:
		return sp2
	return st.o_border_head[id]


func _consider_boat() -> void:
	var st := sim.st
	var now := st.tick
	if now < 600 or st.o_boats[id] >= 1 or now - last_boat < int(300.0 / naval):
		return
	last_boat = now
	var coast := st.map.coast_tiles
	if coast.is_empty():
		return
	var best := -1
	var best_s := 0.35
	var mine := st.o_troops[id]
	var c := st.centroid(id)
	for _i in 48:
		var t := coast[rng.below(coast.size())]
		var o := st.owner[t]
		if o == id:
			continue
		var s := 3.0
		if o != 0:
			var dens := st.o_troops[o] / maxf(1.0, float(st.o_tiles[o]))
			var ratio := 0.3 * mine / (dens * 60.0 + 1.0)
			if ratio < 1.0:
				continue
			s = 1.0 + 0.3 * minf(ratio, 3.0)
		var d := Vector2(t % st.W, t / st.W).distance_to(c)
		s /= 1.0 + d / 110.0
		if s > best_s:
			best_s = s
			best = t
	if best >= 0:
		submit(Commands.boat(id, best, mine * 0.2))
		log.add(now, "boat", st.owner[best], {"troops": mine * 0.2})


func to_dict() -> Dictionary:
	var d := super()
	d.merge({"next_attack": next_attack, "last_boat": last_boat, "started_once": started_once})
	return d


func from_dict(d: Dictionary) -> void:
	super(d)
	next_attack = d.get("next_attack", 0)
	last_boat = d.get("last_boat", -10000)
	started_once = d.get("started_once", false)
