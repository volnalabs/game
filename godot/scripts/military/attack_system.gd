class_name AttackSystem
extends RefCounted
## Land attacks: one attack per (attacker, target) pair advancing along the whole shared border.
## Ported from RoWorld's SimAttacks.luau (OpenFront attack logic), AGPL-3.0:
##  * troops are committed up front; a counter-attack cancels the enemy's attack troops 1:1;
##  * the front is a priority queue of target tiles touching the attacker (pockets first);
##  * each tick an attack spends a budget of 1.0 on tiles, each costing a terrain/size/density
##    dependent fraction, and loses troops per tile (rules/combat_math.gd);
##  * a defender under annex_below_tiles is annexed; retreats return 75 % after a delay.


class Attack:
	extends RefCounted
	var id: int = 0
	var attacker: int = 0
	var target: int = 0
	var troops: float = 0.0
	var initial: float = 0.0
	var q: FrontQueue = FrontQueue.new()
	var front: int = 0
	var head: int = -1
	var chew: float = 0.0
	var retreat_at: int = 0
	var frozen_from: int = 0
	var start_tick: int = 0
	var taken: int = 0
	var lost: float = 0.0
	var killed: float = 0.0
	var alive: bool = true
	var last_tile: int = -1
	## A naval landing: its own front grows from the beachhead (not merged with land attacks).
	var landing: bool = false
	## Tile the attack pushes towards (an inland goal of a naval landing), -1 = none.
	var goal: int = -1

	func to_dict() -> Dictionary:
		return {"id": id, "attacker": attacker, "target": target, "troops": troops, "initial": initial,
			"q": q.to_dict(), "front": front, "head": head, "chew": chew, "retreat_at": retreat_at,
			"frozen_from": frozen_from, "start_tick": start_tick, "taken": taken, "lost": lost,
			"killed": killed, "last_tile": last_tile, "landing": landing, "goal": goal}

	static func from_dict(d: Dictionary) -> Attack:
		var a := Attack.new()
		for k: String in d:
			if k == "q":
				a.q = FrontQueue.from_dict(d["q"])
			else:
				a.set(k, d[k])
		return a


var st: SimState
var rules: Rules
var rng: SimRng
var events: SimEvents
var structures: StructureSystem
var attacks: Array[Attack] = []
var mods: Modifiers
## Attacks that ended since the AI last looked (outcomes the bots learn from).
var recently_ended: Array[Dictionary] = []
var _pair: Dictionary = {}
var next_id: int = 1
## LCG state for front-priority jitter (cheaper than the RNG in the hottest loop; saved).
var _lcg: int = 12345


var _prio_base: int = 10
var _goal_bias: float = 0.35
var _prio_rand: int = 7
## Per terrain byte (code | river bit): attack magnitude and tile cost, without / with a post.
var _mag: PackedFloat32Array
var _cost: PackedFloat32Array


func _init(state: SimState, rules_: Rules, rng_: SimRng, ev: SimEvents) -> void:
	st = state
	rules = rules_
	rng = rng_
	events = ev
	_prio_base = int(rules.a["priority_base"])
	_prio_rand = maxi(1, int(rules.a["priority_rand"]))
	_goal_bias = float(rules.n.get("landing_goal_bias", 0.35))
	_mag = PackedFloat32Array()
	_mag.resize(64)
	_cost = PackedFloat32Array()
	_cost.resize(64)
	for b in 32:
		var code := b & MapData.CODE_MASK
		if code >= rules.t_mag.size():
			code = Rules.T_PLAINS
		for d in 2:
			var mc := CombatMath.tile_mag_cost(rules, code, (b & MapData.RIVER_BIT) != 0, d == 1)
			_mag[b * 2 + d] = mc.x
			_cost[b * 2 + d] = mc.y


static func pair_key(attacker: int, target: int) -> int:
	return attacker * 4096 + target


func find(attacker: int, target: int) -> Attack:
	return _pair.get(pair_key(attacker, target))


func get_by_id(aid: int) -> Attack:
	for a in attacks:
		if a.id == aid and a.alive:
			return a
	return null


## Attacks launched by `id` (alive).
func outgoing(id: int) -> Array[Attack]:
	var out: Array[Attack] = []
	for a in attacks:
		if a.alive and a.attacker == id:
			out.append(a)
	return out


## Attacks against `id` (alive).
func incoming(id: int) -> Array[Attack]:
	var out: Array[Attack] = []
	for a in attacks:
		if a.alive and a.target == id:
			out.append(a)
	return out


func troops_in_attacks(id: int) -> float:
	var s := 0.0
	for a in attacks:
		if a.alive and a.attacker == id:
			s += a.troops
	return s


## Starts (or reinforces) an attack of `troops` already taken from the attacker's army.
## Returns the attack, or null when the troops were refunded (no front, nothing left).
## `beach` >= 0: a naval landing whose front starts at that tile.
func start(attacker: int, target: int, troops: float, beach: int = -1) -> Attack:
	if troops < 1.0:
		return null
	# A counter-attack cancels the enemy's attack troops 1:1.
	if target != 0:
		var opp := find(target, attacker)
		if opp != null and opp.alive:
			var c := minf(troops, opp.troops)
			opp.troops -= c
			troops -= c
			opp.lost += c
			st.stat_troops_lost(target, c)
			st.stat_troops_lost(attacker, c)
			if opp.troops < 1.0:
				end_attack(opp, false)
			if troops < 1.0:
				return null
	if beach >= 0:
		return _start_landing(attacker, target, troops, beach)
	var existing := find(attacker, target)
	if existing != null and existing.alive:
		existing.troops += troops
		existing.initial += troops
		existing.retreat_at = 0
		_seed_from_border(existing)
		return existing
	var a := Attack.new()
	a.id = next_id
	next_id += 1
	a.attacker = attacker
	a.target = target
	a.troops = troops
	a.initial = troops
	a.start_tick = st.tick
	_seed_from_border(a)
	if a.q.is_empty():
		st.add_troops(attacker, troops)
		return null
	attacks.append(a)
	_pair[pair_key(attacker, target)] = a
	st.stat_attack(attacker)
	if target != 0:
		st.mark_attacked(target)
	events.emit(SimEvents.ATTACK_STARTED, {"id": a.id, "attacker": attacker, "target": target, "troops": troops})
	return a


func _start_landing(attacker: int, target: int, troops: float, beach: int) -> Attack:
	var a := Attack.new()
	a.id = next_id
	next_id += 1
	a.attacker = attacker
	a.target = target
	a.troops = troops
	a.initial = troops
	a.start_tick = st.tick
	a.landing = true
	_add_neighbors(a, beach)
	if a.q.is_empty():
		st.add_troops(attacker, troops)
		return null
	attacks.append(a)
	st.stat_attack(attacker)
	if target != 0:
		st.mark_attacked(target)
	events.emit(SimEvents.ATTACK_STARTED, {"id": a.id, "attacker": attacker, "target": target, "troops": troops, "landing": true})
	return a


func retreat(attacker: int, aid: int) -> bool:
	var a := get_by_id(aid)
	if a == null or a.attacker != attacker or a.retreat_at > 0:
		return false
	a.frozen_from = st.tick + 2
	a.retreat_at = st.tick + rules.retreat_delay_ticks + 1
	events.emit(SimEvents.ATTACK_RETREAT, {"id": a.id, "attacker": a.attacker, "target": a.target})
	return true


func end_attack(a: Attack, refund: bool, keep: float = 1.0) -> void:
	if not a.alive:
		return
	a.alive = false
	if refund and a.troops > 0.0 and st.is_alive(a.attacker):
		st.add_troops(a.attacker, a.troops * keep)
		if keep < 1.0:
			st.stat_troops_lost(a.attacker, a.troops * (1.0 - keep))
	var key := pair_key(a.attacker, a.target)
	if _pair.get(key) == a:
		_pair.erase(key)
	recently_ended.append({"id": a.id, "attacker": a.attacker, "target": a.target, "taken": a.taken,
		"initial": a.initial, "lost": a.lost, "killed": a.killed})
	if recently_ended.size() > 512:
		recently_ended = recently_ended.slice(256)
	events.emit(SimEvents.ATTACK_ENDED, {"id": a.id, "attacker": a.attacker, "target": a.target,
		"taken": a.taken, "lost": a.lost, "killed": a.killed, "left": a.troops if refund else 0.0})


## Ends every attack by or against `id` (elimination).
func end_all_of(id: int) -> void:
	for a in attacks:
		if a.alive and (a.attacker == id or a.target == id):
			end_attack(a, a.attacker != id)


func tick() -> void:
	var n := attacks.size()
	for i in n:
		var a := attacks[i]
		if a.alive:
			_process(a)
	var j := 0
	for i in attacks.size():
		if attacks[i].alive:
			attacks[j] = attacks[i]
			j += 1
	attacks.resize(j)


func _seed_from_border(a: Attack) -> void:
	var owner := st.owner
	var land := st.map.land
	var W := st.W
	var N := st.N
	var tg := a.target
	var t := st.o_border_head[a.attacker]
	while t >= 0:
		var x := t % W
		if x > 0 and owner[t - 1] == tg and land[t - 1] == 1:
			_push(a, t - 1)
		if x < W - 1 and owner[t + 1] == tg and land[t + 1] == 1:
			_push(a, t + 1)
		if t >= W and owner[t - W] == tg and land[t - W] == 1:
			_push(a, t - W)
		if t + W < N and owner[t + W] == tg and land[t + W] == 1:
			_push(a, t + W)
		t = st.bnext[t]


func _push(a: Attack, u: int) -> void:
	var owner := st.owner
	var W := st.W
	var x := u % W
	var nb := 0
	if x > 0 and owner[u - 1] == a.attacker:
		nb += 1
	if x < W - 1 and owner[u + 1] == a.attacker:
		nb += 1
	if u >= W and owner[u - W] == a.attacker:
		nb += 1
	if u + W < st.N and owner[u + W] == a.attacker:
		nb += 1
	var pm: float = rules.t_prio[st.map.terrain[u] & MapData.CODE_MASK]
	_lcg = (_lcg * 1103515245 + 12345) & 0x7fffffff
	var r: int = _prio_base + (_lcg >> 8) % _prio_rand
	var key := float(st.tick) + float(r) * (1.0 - 0.5 * nb + pm * 0.5)
	if a.goal >= 0:
		# A landing heads for its goal: tiles closer to it are taken first.
		key += sqrt(float(st.map.dist2(u, a.goal))) * _goal_bias
	a.q.push(key, u)
	if st.front_mark[u] != a.id:
		st.set_front_mark(u, a.id)
		a.front += 1


func _pop(a: Attack) -> int:
	var t := a.q.pop()
	if t >= 0 and st.front_mark[t] == a.id:
		st.set_front_mark(t, 0)
		a.front = maxi(0, a.front - 1)
	return t


func _add_neighbors(a: Attack, t: int) -> void:
	var owner := st.owner
	var land := st.map.land
	var W := st.W
	var x := t % W
	var tg := a.target
	if x > 0 and owner[t - 1] == tg and land[t - 1] == 1:
		_push(a, t - 1)
	if x < W - 1 and owner[t + 1] == tg and land[t + 1] == 1:
		_push(a, t + 1)
	if t >= W and owner[t - W] == tg and land[t - W] == 1:
		_push(a, t - W)
	if t + W < st.N and owner[t + W] == tg and land[t + W] == 1:
		_push(a, t + W)


func _process(a: Attack) -> void:
	var at := a.attacker
	var tg := a.target
	if not st.is_alive(at) or (tg != 0 and not st.is_alive(tg)):
		end_attack(a, true)
		return
	var tick := st.tick
	var neutral := tg == 0
	var fallout := st.fallout
	var fallout_mult := float(rules.w_fallout.get("capture_loss_mult", 1.0))
	if a.retreat_at > 0:
		if tick >= a.retreat_at:
			end_attack(a, true, 1.0 if neutral else minf(1.0, rules.retreat_keep + (mods.add("retreat_keep_add", at) if mods != null else 0.0)))
			return
		if tick >= a.frozen_from:
			return
	var k_area := rules.k_area
	var border := float(a.front) * rules.k_lin + float(rng.below(int(rules.a["border_jitter"])))
	var border1 := maxf(border, 1.0)
	var bonus := Vector2.ONE
	var mag_k := 1.0
	var akind := st.o_kind[at]
	if not neutral:
		bonus = CombatMath.player_bonuses(rules, st.o_tiles[at], st.o_tiles[tg], border)
		if st.o_kind[tg] == Rules.KIND_TRIBE and akind != Rules.KIND_TRIBE:
			mag_k = rules.a["tribe_defender_loss_mult"]
		st.mark_attacked(tg)
	# Defended ground: defence posts and bunkers of the defender, each with its own radius.
	var zone_tiles: Array[PackedInt32Array] = []
	var zone_r2: PackedFloat32Array = PackedFloat32Array()
	if not neutral:
		for dk in rules.defended_kinds():
			var tl := structures.active_tiles_of(tg, dk)
			if not tl.is_empty():
				zone_tiles.append(tl)
				zone_r2.append(rules.building_radius(dk) * rules.building_radius(dk))
	# Air support: the attacker's airbases lower its losses on tiles in their radius.
	var air := PackedInt32Array() if akind == Rules.KIND_TRIBE else structures.active_tiles_of(at, Rules.B_AIRBASE)
	var air_r2 := rules.building_radius(Rules.B_AIRBASE) * rules.building_radius(Rules.B_AIRBASE)
	var air_mult := float(rules.building_effect(Rules.B_AIRBASE).get("attack_loss_mult", 1.0))
	var loss_k := 1.0
	var speed_k := 1.0
	if mods != null:
		loss_k = mods.mult("attack_loss_mult", at) * (mods.mult("defense_loss_mult", tg) if not neutral else 1.0)
		speed_k = (mods.mult("defense_speed_mult", tg) if not neutral else 1.0) / mods.mult("attack_speed_mult", at)
	var nl_per: float = rules.a["tribe_neutral_loss_per_mag"] if akind == Rules.KIND_TRIBE else rules.a["neutral_loss_per_mag"]
	var nc_scale: float = rules.a["neutral_cost_scale"]
	var nc_min: float = rules.a["neutral_min_cost"]
	var nc_max: float = rules.a["neutral_max_cost"]
	var loss_dens: float = rules.a["attacker_loss_per_density"]
	var owner := st.owner
	var terrain := st.map.terrain
	var land := st.map.land
	var W := st.W
	var cap := rules.max_tiles_per_tick
	var budget := 1.0
	var taken := 0
	while budget > 0.0:
		if a.troops < 1.0:
			a.troops = 0.0
			end_attack(a, false)
			return
		var t := a.head
		if t >= 0 and (owner[t] != tg or not st.touches(t, at)):
			a.head = -1
			a.chew = 0.0
			t = -1
		if t < 0:
			if taken >= cap:
				break
			t = _pop(a)
			if t < 0:
				end_attack(a, true)
				return
			if owner[t] != tg or land[t] == 0 or not st.touches(t, at):
				continue
			_add_neighbors(a, t)
			a.head = t
			a.chew = 0.0
		var defended := 0
		var tx := t % W
		var ty := t / W
		for zi in zone_tiles.size():
			for p in zone_tiles[zi]:
				var dx := (p % W) - tx
				var dy := (p / W) - ty
				if dx * dx + dy * dy <= zone_r2[zi]:
					defended = 1
					break
			if defended == 1:
				break
		var ti := (terrain[t] & 31) * 2 + defended
		var mag := _mag[ti] * loss_k
		var tc := _cost[ti] * speed_k
		for p in air:
			var dx := (p % W) - tx
			var dy := (p / W) - ty
			if dx * dx + dy * dy <= air_r2:
				mag *= air_mult
				break
		var loss: float
		var tf: float
		var dloss := 0.0
		if fallout[t] == 1:
			# Contaminated ground: taking it costs many more troops.
			mag *= fallout_mult
		if neutral:
			loss = mag * nl_per
			tf = maxf(clampf(nc_scale * tc / maxf(a.troops, 1.0), nc_min, nc_max) / (border1 * 2.0), 1e-6)
		else:
			var dtroops := st.o_troops[tg]
			dloss = dtroops / maxf(float(st.o_tiles[tg]) * k_area, 1.0)
			var ratio := dtroops / a.troops
			loss = mag * mag_k * clampf(ratio, 0.6, 2.0) * (bonus.x + loss_dens * dloss)
			tf = maxf(clampf(ratio, 0.82, 7.5) * clampf(ratio / 20.0, 1.0, 50.0) * tc * bonus.y, 1e-6)
		var dfloor := floorf(dloss)
		var need := k_area - a.chew
		var can := ceilf(budget / tf)
		if loss > 0.0:
			can = minf(can, ceilf(a.troops / loss))
		if can >= need:
			budget -= need * tf
			a.troops -= need * loss
			a.lost += need * loss
			st.stat_troops_lost(at, need * loss)
			if not neutral:
				var dl := minf(need * dfloor, maxf(st.o_troops[tg], 0.0))
				st.add_troops(tg, -dl)
				st.stat_troops_lost(tg, dl)
				a.killed += dl
			a.chew = 0.0
			a.head = -1
			st.set_owner(t, at)
			a.last_tile = t
			a.taken += 1
			taken += 1
			if not neutral and float(st.o_tiles[tg]) * k_area < rules.annex_below_tiles:
				annex(tg, at)
				end_attack(a, true)
				return
		else:
			budget -= can * tf
			a.troops -= can * loss
			a.lost += can * loss
			st.stat_troops_lost(at, can * loss)
			if not neutral:
				var dl2 := minf(can * dfloor, maxf(st.o_troops[tg], 0.0))
				st.add_troops(tg, -dl2)
				st.stat_troops_lost(tg, dl2)
				a.killed += dl2
			a.chew += can


## The victim's remaining land goes to `by` where it touches `by`, otherwise to any bordering
## owner; up to 100 passes (RoWorld SimAttacks._annex).
func annex(victim: int, by: int) -> void:
	var tiles := st.owned_tiles(victim)
	var owner := st.owner
	var W := st.W
	var N := st.N
	for _pass in 100:
		var progressed := false
		var rest := PackedInt32Array()
		for t in tiles:
			if owner[t] != victim:
				continue
			if st.touches(t, by):
				st.set_owner(t, by)
				progressed = true
				continue
			var taker := 0
			var x := t % W
			if x > 0 and owner[t - 1] > 0 and owner[t - 1] != victim:
				taker = owner[t - 1]
			elif x < W - 1 and owner[t + 1] > 0 and owner[t + 1] != victim:
				taker = owner[t + 1]
			elif t >= W and owner[t - W] > 0 and owner[t - W] != victim:
				taker = owner[t - W]
			elif t + W < N and owner[t + W] > 0 and owner[t + W] != victim:
				taker = owner[t + W]
			if taker > 0:
				st.set_owner(t, taker)
				progressed = true
			else:
				rest.append(t)
		tiles = rest
		if not progressed or tiles.is_empty():
			break
	# Isolated pockets nobody touches become the annexer's.
	for t in tiles:
		if owner[t] == victim:
			st.set_owner(t, by)
	events.emit(SimEvents.ANNEXED, {"victim": victim, "by": by})


func to_dict() -> Dictionary:
	var arr := []
	for a in attacks:
		if a.alive:
			arr.append(a.to_dict())
	return {"next_id": next_id, "attacks": arr, "lcg": _lcg}


func from_dict(d: Dictionary) -> void:
	next_id = d["next_id"]
	_lcg = d.get("lcg", 12345)
	attacks.clear()
	_pair.clear()
	for ad: Dictionary in d["attacks"]:
		var a := Attack.from_dict(ad)
		attacks.append(a)
		if not a.landing:
			_pair[pair_key(a.attacker, a.target)] = a
