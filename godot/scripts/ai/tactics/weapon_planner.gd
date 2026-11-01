class_name WeaponPlanner
extends RefCounted
## Weapons for the AI (Phase 2E). Every so often, at war or under attack, the bot looks for the
## best strike against its enemies: their buildings within reach and their land near our border
## (where their armies stand). Each candidate is valued with WeaponSystem.estimate — the very
## function the impact uses — in gold: troops killed (× troop_value), building levels knocked
## off (the price of rebuilding them), land a nuke destroys (× tile worth), times the chance the strike gets
## through the target's SAMs, minus the price of the weapon. Never when our own land or buildings
## would be hit, never on impossible launches (WeaponSystem.check). Nuclear weapons only in
## retaliation (the target used them) or for a warlike state against the leader late in a match.
## No randomness: the same match makes the same decisions.

## Gold per enemy troop killed; a strike must return at least MIN_GAIN of its price (it is only
## considered with twice its price in the treasury, i.e. from surplus gold).
const TROOP_VALUE := 3.0
const MIN_GAIN := 0.5
const FRONT_MULT := 2.0


## Called from the bot's think loop.
static func act(bot: StrategicAI) -> bool:
	var sim := bot.sim
	var st := sim.st
	var id := bot.id
	if st.tick < bot.next_weapon:
		return false
	bot.next_weapon = st.tick + 60
	var enemies := _enemies(bot)
	if enemies.is_empty():
		return false
	var best: Dictionary = {}
	for w in sim.rules.w_list.size():
		if not sim.weapons.unlocked(id, w):
			continue
		var wd := sim.rules.weapon(w)
		# Gold has to stay for the economy: a strike may use at most half of what we have.
		if st.o_gold[id] < float(wd["cost"]) * 2.0 or st.o_supplies[id] < float(wd["supplies"]) * 1.5:
			continue
		# Surplus gold lowers the bar (like buildings, strikes come from surplus): at ten times the
		# price in the treasury the full MIN_GAIN, down to a fifth of it with fifty times.
		var bar := MIN_GAIN * clampf(10.0 * float(wd["cost"]) / maxf(st.o_gold[id], 1.0), 0.2, 1.0)
		if sim.weapons.is_nuclear(w) and not _nuclear_ok(bot, enemies):
			continue
		var rd := WeaponInfo.readiness(sim, w, id)
		if int(rd["ready"]) <= 0:
			continue
		for o: int in enemies:
			for t in _targets(bot, o, w):
				var c := sim.weapons.check(id, w, t)
				if not c["ok"]:
					continue
				var est := sim.weapons.estimate(id, w, t)
				if int(est["own_tiles"]) > 0 or int(est["own_structures"]) > 0:
					continue
				var u := _value(bot, w, est, _at_front(bot, o, t)) * (1.0 - float(est["intercept"]["chance"]))
				var gain := u / maxf(float(wd["cost"]), 1.0)
				if gain >= bar and (best.is_empty() or gain > float(best["gain"])):
					best = {"w": w, "tile": t, "gain": gain, "owner": o}
	if best.is_empty():
		return false
	var wid := String(sim.rules.weapon(int(best["w"]))["id"])
	bot.submit(Commands.launch(id, wid, int(best["tile"])))
	bot.log.add(st.tick, "strike", int(best["owner"]), {"weapon": wid, "u": best["gain"]})
	return true


## Our war target and whoever is attacking us.
static func _enemies(bot: StrategicAI) -> Array[int]:
	var out: Array[int] = []
	var st := bot.sim.st
	var dip := bot.sim.diplomacy
	if bot.target > 0 and st.is_alive(bot.target) and (bot.state == StrategicAI.S_WAR or bot.state == StrategicAI.S_DEFEND) \
			and bot.may_attack(bot.target):
		out.append(bot.target)
	for a in bot.sim.attacks.incoming(bot.id):
		if a.attacker > 0 and st.o_kind[a.attacker] != Rules.KIND_TRIBE and not out.has(a.attacker) \
				and dip.can_attack(bot.id, a.attacker):
			out.append(a.attacker)
	return out


## Nuclear weapons: in retaliation, or a warlike state against the leader after 20 minutes.
static func _nuclear_ok(bot: StrategicAI, enemies: Array[int]) -> bool:
	var sim := bot.sim
	for o in enemies:
		if int(sim.weapons.nukes_launched.get(o, 0)) > 0:
			return true
	return float(bot.pers.get("war_appetite", 1.0)) >= 1.3 and sim.elapsed_seconds() > 1200.0 \
		and enemies.has(bot.perception.leader)


## Candidate aim points against `o`: their buildings (most valuable first) and tiles of their land
## along our common front (where their armies stand). For range-limited weapons (artillery from
## defence posts, air strikes from airbases) only front tiles within reach of one of our launchers
## count — sampling their whole border found almost nothing in range in real matches.
static func _targets(bot: StrategicAI, o: int, w: int) -> PackedInt32Array:
	var sim := bot.sim
	var st := sim.st
	var out := PackedInt32Array()
	var rng_max := float(sim.rules.weapon(w).get("range", 0.0))
	var launch_tiles: Array[int] = []
	if rng_max > 0.0:
		for l: Dictionary in sim.weapons.launchers_for(bot.id, w, -1):
			if int(l["charges"]) > 0:
				launch_tiles.append((l["s"] as StructureSystem.Structure).tile)
		if launch_tiles.is_empty():
			return out
	var reach := func(t: int) -> bool:
		if rng_max <= 0.0:
			return true
		for lt in launch_tiles:
			if float(st.map.dist2(lt, t)) <= rng_max * rng_max:
				return true
		return false
	var order := [Rules.B_SAM, Rules.B_SILO, Rules.B_CITY, Rules.B_FACTORY, Rules.B_AIRBASE, Rules.B_PORT, Rules.B_RADAR]
	for k: int in order:
		for s in sim.structures.of_owner(o, k):
			if reach.call(s.tile):
				out.append(s.tile)
			if out.size() >= 6:
				break
		if out.size() >= 6:
			break
	# Their land along our border (walking our own border list), spread over the reachable front.
	var front := PackedInt32Array()
	var W := st.W
	var t := st.o_border_head[bot.id]
	var i := 0
	while t >= 0 and i < 6000:
		i += 1
		var x := t % W
		for u: int in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W]:
			if u >= 0 and u < st.N and st.owner[u] == o:
				if reach.call(u):
					front.append(u)
				break
		t = st.bnext[t]
	if not front.is_empty():
		var n := mini(8, front.size())
		for k in n:
			out.append(front[int(float(k) * float(front.size()) / float(n))])
	return out


## Whether tile `t` of `o` lies at an active front between us (our attack on `o` or theirs on us):
## troops killed there would cost us dearly to beat, or are about to hit us.
static func _at_front(bot: StrategicAI, o: int, t: int) -> bool:
	var st := bot.sim.st
	if bot.sim.attacks.find(bot.id, o) == null and bot.sim.attacks.find(o, bot.id) == null:
		return false
	return st.touches(t, bot.id)


## Worth of an estimated strike in gold (troops killed at an active front count FRONT_MULT times).
static func _value(bot: StrategicAI, w: int, est: Dictionary, front: bool = false) -> float:
	var sim := bot.sim
	var id := bot.id
	var v := 0.0
	var killed: Dictionary = est.get("killed", {})
	for o: int in killed:
		if o != id:
			v += float(killed[o]) * TROOP_VALUE * (FRONT_MULT if front else 1.0)
	var levels := int(sim.rules.weapon(w)["effect"].get("struct_levels", 0))
	var kind := String(est.get("kind", ""))
	for sid: int in est.get("structures", []):
		var s: StructureSystem.Structure = sim.structures.structs[sid]
		if s.owner == id:
			continue
		var lv := s.level if kind == "nuke" else mini(levels, s.level)
		if kind == "emp":
			lv = 1
		# A level knocked off costs its owner a rebuild (an EMP only a pause).
		v += sim.rules.building_cost(s.kind, 0) * float(lv) * (0.25 if kind == "emp" else 1.0)
	if kind == "nuke":
		var tiles: Dictionary = est.get("tiles", {})
		var worth := AttackPlanner.tile_worth(sim.st.o_tiles[id])
		for o: int in tiles:
			if o != id:
				v += float(tiles[o]) * worth * TROOP_VALUE
	if kind == "mirv":
		v += float(est.get("warheads", 0)) * 200000.0
	return v
