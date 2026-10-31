class_name WeaponSystem
extends RefCounted
## Weapons and air defence (Phase 2E; data/weapons/weapons.json). Pure and deterministic.
##
## Launch: a weapon leaves from one of the owner's working launchers (silo, airbase or defence
## post) that has a charge and reaches the target (range 0 = anywhere). Launchers hold
## charges_per_level × level charges and reload one every reload_ticks. Gold and supplies are paid
## at launch; the munition waits launch_delay ticks, then flies at constant speed along an arc (a
## cubic Bézier raised towards the top of the map, as in RoWorld) or a straight line.
## Air defence: each working SAM of the state that owns the target tile engages munitions inside its
## range (×radar_range_mult when the SAM is inside its owner's radar zone), one interceptor per
## charge, paying shot_supplies; at most max_per_munition interceptors chase one munition. An
## interceptor reaches its munition after distance / interceptor_speed ticks and hits with the
## weapon's intercept chance (+radar_hit_bonus); a munition that lands first wins the race.
## Impact (the same functions build the targeting preview):
##   blast   — every army with land under the disc loses min(troops × kill_frac, tiles × kill_per_tile);
##             buildings in the disc lose struct_levels levels;
##   cluster — the bus breaks into bomblets spread around the aim point, each a small blast;
##   nuke    — land inside the inner radius is wiped out, the outer ring partly (deterministic hash);
##             owners' troops shrink by ((T − lost) / T)^5; buildings inside are destroyed; fallout
##             covers the disc for a while (land worth less, it decays); nuclear history counts it;
##   mirv    — the bus cannot be intercepted; over the target it releases warheads onto the target
##             owner's land, each a small interceptable nuke;
##   emp     — buildings in the disc switch off for disable_ticks (no effects, SAMs and launchers silent).

const ARC_SAMPLES := 32


class Munition:
	extends RefCounted
	var id: int = 0
	var owner: int = 0
	var weapon: int = 0
	var from_tile: int = 0
	var to_tile: int = 0
	var target_owner: int = 0
	var launch_tick: int = 0
	## Ticks waiting on the launcher, then ticks in the air.
	var delay: int = 0
	var flight: int = 1
	## Path points (map tiles) and cumulative lengths for constant-speed motion.
	var pts: PackedVector2Array = PackedVector2Array()
	var lens: PackedFloat32Array = PackedFloat32Array()
	var alive: bool = true
	## A MIRV warhead (radii in warhead fields of the parent weapon).
	var warhead: bool = false
	## Interceptors already chasing it.
	var chased: int = 0

	func impact_tick() -> int:
		return launch_tick + delay + flight

	## Fraction of the flight done at tick `now` (0 while still on the launcher).
	func fraction(now: int) -> float:
		return clampf(float(now - launch_tick - delay) / float(maxi(flight, 1)), 0.0, 1.0)

	func position(now: int) -> Vector2:
		var total := lens[lens.size() - 1] if lens.size() > 0 else 0.0
		var want := fraction(now) * total
		for i in range(1, pts.size()):
			if lens[i] >= want or i == pts.size() - 1:
				var seg := lens[i] - lens[i - 1]
				var f := (want - lens[i - 1]) / seg if seg > 0.0 else 0.0
				return pts[i - 1].lerp(pts[i], clampf(f, 0.0, 1.0))
		return pts[0] if pts.size() > 0 else Vector2.ZERO

	func to_dict() -> Dictionary:
		return {"id": id, "owner": owner, "weapon": weapon, "from_tile": from_tile, "to_tile": to_tile,
			"target_owner": target_owner, "launch_tick": launch_tick, "delay": delay, "flight": flight, "pts": pts,
			"lens": lens, "alive": alive, "warhead": warhead, "chased": chased}

	static func from_dict(d: Dictionary) -> Munition:
		var m := Munition.new()
		for k: String in d:
			m.set(k, d[k])
		return m


class Interceptor:
	extends RefCounted
	var id: int = 0
	var owner: int = 0
	var sam: int = 0
	var munition: int = 0
	var from: Vector2 = Vector2.ZERO
	var launch_tick: int = 0
	var hit_tick: int = 0
	var chance: float = 0.0

	func to_dict() -> Dictionary:
		return {"id": id, "owner": owner, "sam": sam, "munition": munition, "from": from, "launch_tick": launch_tick,
			"hit_tick": hit_tick, "chance": chance}

	static func from_dict(d: Dictionary) -> Interceptor:
		var x := Interceptor.new()
		for k: String in d:
			x.set(k, d[k])
		return x


var st: SimState
var rules: Rules
var rng: SimRng
var events: SimEvents
var structures: StructureSystem
var research: ResearchSystem
var attacks: AttackSystem
var munitions: Array[Munition] = []
var interceptors: Array[Interceptor] = []
## Structure id -> [charges, next refill tick] for launchers and SAMs (missing = full).
var ammo: Dictionary = {}
## Tile -> tick its fallout ends.
var fallout: Dictionary = {}
## Tiles whose fallout appeared or cleared since the renderer last looked.
var fallout_changed: PackedInt32Array = PackedInt32Array()
## Nuclear history: owner -> nukes launched (any nuclear weapon) / last nuclear launch tick.
var nukes_launched: Dictionary = {}
var last_nuke_tick: Dictionary = {}
var next_id: int = 1
var _base_value: Dictionary = {}


func _init(state: SimState, rules_: Rules, rng_: SimRng, ev: SimEvents, structs: StructureSystem, rs: ResearchSystem, atk: AttackSystem) -> void:
	st = state
	rules = rules_
	rng = rng_
	events = ev
	structures = structs
	research = rs
	attacks = atk


# ---------------------------------------------------------------------------------------------
# Launchers, charges, unlocks
# ---------------------------------------------------------------------------------------------

func unlocked(who: int, w: int) -> bool:
	return research == null or research.has_tech(who, String(rules.weapon(w).get("requires", "")))


func is_nuclear(w: int) -> bool:
	return String(rules.weapon(w)["effect"]["kind"]) in ["nuke", "mirv"]


## Charges a launcher / SAM structure holds when full.
func capacity(s: StructureSystem.Structure, per_level: int) -> int:
	return maxi(0, s.counted()) * per_level


## Ready charges of structure `s` right now (refilling lazily).
func charges(s: StructureSystem.Structure, per_level: int, reload: int) -> int:
	var cap := capacity(s, per_level)
	if not ammo.has(s.id):
		return cap
	var a: Array = ammo[s.id]
	var n: int = a[0]
	var nxt: int = a[1]
	while n < cap and st.tick >= nxt:
		n += 1
		nxt += reload
	if n >= cap:
		ammo.erase(s.id)
		return cap
	a[0] = n
	a[1] = nxt
	return n


## Ticks until the next charge of `s` (0 when it has one).
func reload_left(s: StructureSystem.Structure, per_level: int, reload: int) -> int:
	if charges(s, per_level, reload) > 0:
		return 0
	if not ammo.has(s.id):
		return 0
	return maxi(0, int(ammo[s.id][1]) - st.tick)


func _use_charge(s: StructureSystem.Structure, per_level: int, reload: int) -> void:
	var n := charges(s, per_level, reload)
	if ammo.has(s.id):
		ammo[s.id][0] = n - 1
	else:
		ammo[s.id] = [n - 1, st.tick + reload]


## Launchers of weapon `w` owned by `who`: [{"s", "charges", "reload_left", "in_range"}], nearest first.
func launchers_for(who: int, w: int, target: int) -> Array:
	var kind := rules.weapon_launcher_kind(w)
	var per := rules.launcher_charges_per_level(w)
	var reload := rules.launcher_reload(w)
	var rng_max: float = float(rules.weapon(w).get("range", 0.0))
	var out: Array = []
	if kind < 0:
		return out
	for s in structures.of_owner(who, kind):
		if s.counted() <= 0:
			continue
		var d2 := st.map.dist2(s.tile, target) if target >= 0 else 0
		var ok := rng_max <= 0.0 or float(d2) <= rng_max * rng_max
		out.append({"s": s, "charges": charges(s, per, reload), "reload_left": reload_left(s, per, reload), "in_range": ok, "d2": d2})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["d2"]) != int(b["d2"]):
			return int(a["d2"]) < int(b["d2"])
		return (a["s"] as StructureSystem.Structure).id < (b["s"] as StructureSystem.Structure).id)
	return out


## Validates a launch of weapon `w` by `who` at tile `target` (the same check the targeting preview
## shows). {"ok", "reason", "launcher" (structure), "flight", "delay"}.
func check(who: int, w: int, target: int) -> Dictionary:
	if w < 0 or w >= rules.w_list.size():
		return {"ok": false, "reason": "bad_weapon"}
	var wd := rules.weapon(w)
	if not unlocked(who, w):
		return {"ok": false, "reason": "locked"}
	if target < 0 or target >= st.N or st.map.land[target] == 0:
		return {"ok": false, "reason": "not_land"}
	if st.owner[target] == who:
		return {"ok": false, "reason": "own_land"}
	var ls := launchers_for(who, w, target)
	if ls.is_empty():
		return {"ok": false, "reason": "no_launcher"}
	var best: Dictionary = {}
	var any_range := false
	for l: Dictionary in ls:
		if not l["in_range"]:
			continue
		any_range = true
		if int(l["charges"]) > 0:
			best = l
			break
	if not any_range:
		return {"ok": false, "reason": "out_of_range"}
	if best.is_empty():
		return {"ok": false, "reason": "reloading"}
	if st.o_gold[who] < float(wd["cost"]):
		return {"ok": false, "reason": "no_gold"}
	if st.o_supplies[who] < float(wd["supplies"]):
		return {"ok": false, "reason": "no_supplies"}
	var s: StructureSystem.Structure = best["s"]
	var path := path_for(w, s.tile, target)
	return {"ok": true, "reason": "", "launcher": s, "path": path[0],
		"flight": flight_ticks(w, path[1]), "delay": int(wd.get("launch_delay", 0))}


# ---------------------------------------------------------------------------------------------
# Flight paths
# ---------------------------------------------------------------------------------------------

func _c(t: int) -> Vector2:
	return Vector2(t % st.W + 0.5, t / st.W + 0.5)


## [points, cumulative lengths] of a weapon's path from tile a to tile b.
func path_for(w: int, a: int, b: int, flat_override: bool = false) -> Array:
	var p0 := _c(a)
	var p3 := _c(b)
	var pts := PackedVector2Array()
	var flat := flat_override or String(rules.weapon(w).get("flight", "arc")) == "flat"
	if flat:
		pts.append(p0)
		pts.append(p3)
	else:
		var d := p3 - p0
		var h := maxf(d.length() / 3.0, 50.0 / rules.k_lin)
		var p1 := Vector2(p0.x + d.x / 4.0, clampf(p0.y + d.y / 4.0 - h, 0.0, float(st.H - 1)))
		var p2 := Vector2(p0.x + d.x * 0.75, clampf(p0.y + d.y * 0.75 - h, 0.0, float(st.H - 1)))
		for i in ARC_SAMPLES + 1:
			var t := float(i) / ARC_SAMPLES
			var u := 1.0 - t
			pts.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
	var lens := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + pts[i].distance_to(pts[i - 1]))
	return [pts, lens]


func flight_ticks(w: int, lens: PackedFloat32Array, speed: float = -1.0) -> int:
	var v := speed if speed > 0.0 else float(rules.weapon(w)["speed"])
	return maxi(1, ceili(lens[lens.size() - 1] / maxf(v, 0.01)))


# ---------------------------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------------------------

## Launches weapon `w` from `who` at `target`. Returns "" or a rejection reason.
func launch(who: int, w: int, target: int) -> String:
	var c := check(who, w, target)
	if not c["ok"]:
		return String(c["reason"])
	var wd := rules.weapon(w)
	var s: StructureSystem.Structure = c["launcher"]
	_use_charge(s, rules.launcher_charges_per_level(w), rules.launcher_reload(w))
	st.add_gold(who, -float(wd["cost"]))
	st.add_supplies(who, -float(wd["supplies"]))
	st.stat_gold(who, 0.0, float(wd["cost"]), 0.0)
	var path := path_for(w, s.tile, target)
	var m := _spawn(who, w, s.tile, target, path, int(wd.get("launch_delay", 0)), flight_ticks(w, path[1]), false)
	if is_nuclear(w):
		nukes_launched[who] = int(nukes_launched.get(who, 0)) + 1
		last_nuke_tick[who] = st.tick
	if m.target_owner > 0:
		st.mark_attacked(m.target_owner)
	events.emit(SimEvents.WEAPON_LAUNCHED, {"id": m.id, "owner": who, "weapon": String(wd["id"]), "from": s.tile, "to": target,
		"target_owner": m.target_owner, "impact": m.impact_tick(), "nuclear": is_nuclear(w)})
	return ""


func _spawn(who: int, w: int, from_t: int, to_t: int, path: Array, delay: int, flight: int, warhead: bool) -> Munition:
	var m := Munition.new()
	m.id = next_id
	next_id += 1
	m.owner = who
	m.weapon = w
	m.from_tile = from_t
	m.to_tile = to_t
	m.target_owner = st.owner[to_t]
	m.launch_tick = st.tick
	m.delay = delay
	m.flight = flight
	m.pts = path[0]
	m.lens = path[1]
	m.warhead = warhead
	munitions.append(m)
	return m


# ---------------------------------------------------------------------------------------------
# Tick: air defence, impacts, fallout
# ---------------------------------------------------------------------------------------------

func tick() -> void:
	if not munitions.is_empty():
		_air_defence()
		_resolve_interceptors()
		var now := st.tick
		for m in munitions:
			if m.alive and now >= m.impact_tick():
				m.alive = false
				_impact(m)
		var j := 0
		for i in munitions.size():
			if munitions[i].alive:
				munitions[j] = munitions[i]
				j += 1
		munitions.resize(j)
	elif not interceptors.is_empty():
		interceptors.clear()
	if not fallout.is_empty() and st.tick % maxi(1, int(rules.w_fallout.get("check_every", 20))) == 0:
		_decay_fallout()


## Intercept chance of weapon `w` (warhead or not) by a SAM, with or without radar support.
func hit_chance(w: int, warhead: bool, radar: bool) -> float:
	var ef: Dictionary = rules.weapon(w)["effect"]
	var p := float(ef.get("warhead_intercept", 0.0)) if warhead else float(rules.weapon(w).get("intercept", 0.0))
	if p <= 0.0:
		return 0.0
	if radar:
		p += float(rules.w_sam.get("radar_hit_bonus", 0.0))
	return minf(p, float(rules.w_sam.get("hit_cap", 0.97)))


## Range of a SAM (tiles), boosted inside its owner's radar zone.
func sam_range(s: StructureSystem.Structure) -> float:
	var r := rules.building_radius(Rules.B_SAM)
	if structures.in_zone(s.owner, Rules.B_RADAR, s.tile):
		r *= float(rules.w_sam.get("radar_range_mult", 1.0))
	return r


func _air_defence() -> void:
	var now := st.tick
	var per := int(rules.w_sam.get("charges_per_level", 1))
	var reload := int(rules.w_sam.get("reload_ticks", 90))
	var shot_sup := float(rules.w_sam.get("shot_supplies", 0.0))
	var max_chase := int(rules.w_sam.get("max_per_munition", 2))
	var speed := maxf(float(rules.w_sam.get("interceptor_speed", 12.0)), 0.01)
	# Candidates: flying, interceptable munitions; most dangerous and soonest first.
	var cands: Array[Munition] = []
	for m in munitions:
		if m.alive and now >= m.launch_tick + m.delay and m.chased < max_chase and hit_chance(m.weapon, m.warhead, false) > 0.0:
			cands.append(m)
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Munition, b: Munition) -> bool:
		var ta := float(rules.weapon(a.weapon).get("threat", 1.0))
		var tb := float(rules.weapon(b.weapon).get("threat", 1.0))
		if ta != tb:
			return ta > tb
		if a.impact_tick() != b.impact_tick():
			return a.impact_tick() < b.impact_tick()
		return a.id < b.id)
	for s in structures.structs:
		if not s.alive or s.kind != Rules.B_SAM or s.counted() <= 0:
			continue
		if charges(s, per, reload) <= 0 or st.o_supplies[s.owner] < shot_sup:
			continue
		var sp := _c(s.tile)
		var r := sam_range(s)
		var radar := structures.in_zone(s.owner, Rules.B_RADAR, s.tile)
		for m in cands:
			# A SAM defends its owner's land: munitions aimed at it.
			if m.chased >= max_chase or m.owner == s.owner or st.owner[m.to_tile] != s.owner:
				continue
			var mp := m.position(now)
			var d := sp.distance_to(mp)
			if d > r:
				continue
			var hit := now + maxi(1, ceili(d / speed))
			if hit >= m.impact_tick():
				continue
			_use_charge(s, per, reload)
			st.add_supplies(s.owner, -shot_sup)
			var x := Interceptor.new()
			x.id = next_id
			next_id += 1
			x.owner = s.owner
			x.sam = s.id
			x.munition = m.id
			x.from = sp
			x.launch_tick = now
			x.hit_tick = hit
			x.chance = hit_chance(m.weapon, m.warhead, radar)
			interceptors.append(x)
			m.chased += 1
			events.emit(SimEvents.INTERCEPT_LAUNCHED, {"id": x.id, "owner": s.owner, "sam": s.id, "munition": m.id, "hit_tick": hit})
			if charges(s, per, reload) <= 0 or st.o_supplies[s.owner] < shot_sup:
				break


func _munition(id: int) -> Munition:
	for m in munitions:
		if m.id == id:
			return m
	return null


func _resolve_interceptors() -> void:
	var now := st.tick
	var keep: Array[Interceptor] = []
	for x in interceptors:
		if now < x.hit_tick:
			keep.append(x)
			continue
		var m := _munition(x.munition)
		if m == null or not m.alive:
			continue
		var pos := m.position(now)
		if rng.randf() < x.chance:
			m.alive = false
			events.emit(SimEvents.INTERCEPTED, {"munition": m.id, "by": x.owner, "owner": m.owner, "weapon": String(rules.weapon(m.weapon)["id"]),
				"x": pos.x, "y": pos.y, "warhead": m.warhead})
		else:
			m.chased = maxi(0, m.chased - 1)
			events.emit(SimEvents.INTERCEPT_MISSED, {"munition": m.id, "by": x.owner, "owner": m.owner, "x": pos.x, "y": pos.y})
	interceptors = keep


# ---------------------------------------------------------------------------------------------
# Impacts (also used by the targeting preview)
# ---------------------------------------------------------------------------------------------

## Land tiles within `radius` of tile `c` (euclidean).
func disc(c: int, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var W := st.W
	var cx := c % W
	var cy := c / W
	var r := ceili(radius)
	var r2 := radius * radius
	for y in range(maxi(0, cy - r), mini(st.H, cy + r + 1)):
		var dy := y - cy
		for x in range(maxi(0, cx - r), mini(W, cx + r + 1)):
			var dx := x - cx
			if float(dx * dx + dy * dy) <= r2:
				var t := y * W + x
				if st.map.land[t] == 1:
					out.append(t)
	return out


## Deterministic 0..1 value of a tile for munition `mid` (outer-ring losses, scatter).
static func _h01(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0x1000000)


## What a blast of `w` at `c` would do: {"tiles": {owner: n}, "killed": {owner: troops},
## "structures": [ids], "levels": n}.
func blast_effect(w: int, c: int, radius: float, kill_frac: float, kill_per_tile: float, struct_levels: int) -> Dictionary:
	var by_owner := {}
	for t in disc(c, radius):
		var o := st.owner[t]
		if o > 0:
			by_owner[o] = int(by_owner.get(o, 0)) + 1
	var killed := {}
	for o: int in by_owner:
		killed[o] = floorf(minf(st.o_troops[o] * kill_frac, float(by_owner[o]) * kill_per_tile))
	var hit: Array[int] = []
	if struct_levels > 0:
		for s in structures.near(c, radius + 1.0):
			if st.map.dist2(s.tile, c) <= radius * radius:
				hit.append(s.id)
	return {"tiles": by_owner, "killed": killed, "structures": hit, "levels": struct_levels}


## What a nuclear burst at `c` would do: {"lost": {owner: tiles}, "killed": {owner: troops},
## "structures": [ids], "fallout": tile count}. `salt` makes the outer ring deterministic.
func nuke_effect(c: int, inner: float, outer: float, salt: int) -> Dictionary:
	var lost := {}
	var tiles := disc(c, outer)
	var inner2 := inner * inner
	var lost_tiles := PackedInt32Array()
	var span := maxf(outer - inner, 0.001)
	for t in tiles:
		var d2 := float(st.map.dist2(t, c))
		var gone := d2 <= inner2
		if not gone:
			var k := (sqrt(d2) - inner) / span
			gone = _h01(t, salt) < 0.85 * (1.0 - k)
		if gone:
			lost_tiles.append(t)
			var o := st.owner[t]
			if o > 0:
				lost[o] = int(lost.get(o, 0)) + 1
	var killed := {}
	var ex := float(rules.weapons_raw.get("nuke_troop_exponent", 5.0))
	for o: int in lost:
		var before := float(st.o_tiles[o])
		var f := pow(maxf(0.0, before - float(lost[o])) / maxf(before, 1.0), ex)
		killed[o] = floorf(st.o_troops[o] * (1.0 - f))
	var hit: Array[int] = []
	for s in structures.near(c, outer + 1.0):
		if st.map.dist2(s.tile, c) <= outer * outer:
			hit.append(s.id)
	return {"lost": lost, "killed": killed, "structures": hit, "fallout": tiles.size(), "lost_tiles": lost_tiles, "disc": tiles}


## Preview of a launch: who loses what, our own land in the blast, interception odds.
func estimate(who: int, w: int, target: int) -> Dictionary:
	var wd := rules.weapon(w)
	var ef: Dictionary = wd["effect"]
	var kind := String(ef["kind"])
	var out := {"kind": kind, "radius": float(wd["radius"]), "inner": float(wd.get("radius_inner", 0.0))}
	match kind:
		"blast":
			var b := blast_effect(w, target, float(wd["radius"]), float(ef["kill_frac"]), float(ef["kill_per_tile"]), int(ef.get("struct_levels", 0)))
			out.merge(b)
		"cluster":
			var spread := float(ef["spread"])
			var total := {"tiles": {}, "killed": {}, "structures": [], "levels": int(ef.get("struct_levels", 0))}
			for p in bomblet_tiles(target, int(ef["bomblets"]), spread, next_id):
				var b := blast_effect(w, p, float(wd["radius"]), float(ef["kill_frac"]), float(ef["kill_per_tile"]), int(ef.get("struct_levels", 0)))
				for o: int in b["tiles"]:
					total["tiles"][o] = int(total["tiles"].get(o, 0)) + int(b["tiles"][o])
					total["killed"][o] = float(total["killed"].get(o, 0.0)) + float(b["killed"][o])
				for sid: int in b["structures"]:
					if not (total["structures"] as Array).has(sid):
						(total["structures"] as Array).append(sid)
			out.merge(total)
			out["radius"] = spread + float(wd["radius"])
		"nuke":
			var n := nuke_effect(target, float(wd["radius_inner"]), float(wd["radius"]), next_id)
			out["tiles"] = n["lost"]
			out["killed"] = n["killed"]
			out["structures"] = n["structures"]
			out["fallout"] = n["fallout"]
		"mirv":
			var tg := st.owner[target]
			out["tiles"] = {tg: mini(int(ef["warheads"]), st.o_tiles[tg])} if tg > 0 else {}
			out["killed"] = {}
			out["structures"] = []
			out["warheads"] = int(ef["warheads"])
		"emp":
			var hit: Array[int] = []
			for s in structures.near(target, float(wd["radius"]) + 1.0):
				if st.map.dist2(s.tile, target) <= float(wd["radius"]) * float(wd["radius"]):
					hit.append(s.id)
			out["structures"] = hit
			out["tiles"] = {}
			out["killed"] = {}
	var tiles: Dictionary = out.get("tiles", {})
	out["own_tiles"] = int(tiles.get(who, 0))
	var own_structs := 0
	for sid: int in out.get("structures", []):
		if structures.structs[sid].owner == who:
			own_structs += 1
	out["own_structures"] = own_structs
	out["intercept"] = intercept_risk(who, w, target)
	return out


## Chance that SAMs defending `target` stop the munition (all their ready interceptors, capped by
## max_per_munition), and how many SAMs cover it.
func intercept_risk(who: int, w: int, target: int) -> Dictionary:
	var to := st.owner[target]
	if to <= 0 or to == who:
		return {"chance": 0.0, "sams": 0}
	var ef: Dictionary = rules.weapon(w)["effect"]
	var warhead := String(ef["kind"]) == "mirv"
	var per := int(rules.w_sam.get("charges_per_level", 1))
	var reload := int(rules.w_sam.get("reload_ticks", 90))
	var shots: Array[float] = []
	var n := 0
	for s in structures.of_owner(to, Rules.B_SAM):
		if s.counted() <= 0:
			continue
		var r := sam_range(s)
		if float(st.map.dist2(s.tile, target)) > r * r:
			continue
		n += 1
		var radar := structures.in_zone(to, Rules.B_RADAR, s.tile)
		var p := hit_chance(w, warhead, radar)
		for i in charges(s, per, reload):
			shots.append(p)
	shots.sort()
	shots.reverse()
	var miss := 1.0
	var max_chase := int(rules.w_sam.get("max_per_munition", 2))
	for i in mini(shots.size(), max_chase):
		miss *= 1.0 - shots[i]
	return {"chance": 1.0 - miss if not shots.is_empty() else 0.0, "sams": n}


## Bomblet impact tiles of a cluster munition (deterministic, on land when possible).
func bomblet_tiles(c: int, n: int, spread: float, salt: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cx := c % st.W
	var cy := c / st.W
	for i in n:
		var ang := TAU * (float(i) + _h01(i, salt) * 0.6) / float(n)
		var rr := spread * (0.45 + 0.55 * _h01(salt, i + 17))
		var x := clampi(int(round(cx + cos(ang) * rr)), 0, st.W - 1)
		var y := clampi(int(round(cy + sin(ang) * rr)), 0, st.H - 1)
		out.append(y * st.W + x)
	return out


func _impact(m: Munition) -> void:
	var wd := rules.weapon(m.weapon)
	var ef: Dictionary = wd["effect"]
	var kind := String(ef["kind"])
	if m.warhead:
		_nuclear_burst(m, float(ef["warhead_inner"]), float(ef["warhead_outer"]))
		return
	match kind:
		"blast":
			_blast(m, m.to_tile, float(wd["radius"]), ef)
		"cluster":
			for p in bomblet_tiles(m.to_tile, int(ef["bomblets"]), float(ef["spread"]), m.id):
				_blast(m, p, float(wd["radius"]), ef)
		"nuke":
			_nuclear_burst(m, float(wd["radius_inner"]), float(wd["radius"]))
		"mirv":
			_split_mirv(m, ef)
		"emp":
			_emp(m, float(wd["radius"]), int(ef["disable_ticks"]))


func _blast(m: Munition, c: int, radius: float, ef: Dictionary) -> void:
	var b := blast_effect(m.weapon, c, radius, float(ef["kill_frac"]), float(ef["kill_per_tile"]), int(ef.get("struct_levels", 0)))
	var killed: Dictionary = b["killed"]
	for o: int in killed:
		var k := minf(float(killed[o]), st.o_troops[o])
		st.add_troops(o, -k)
		st.stat_troops_lost(o, k)
		if o != m.owner:
			st.mark_attacked(o)
	var destroyed := 0
	for sid: int in b["structures"]:
		if structures.damage(structures.structs[sid], int(ef.get("struct_levels", 0))):
			destroyed += 1
	events.emit(SimEvents.WEAPON_IMPACT, {"id": m.id, "owner": m.owner, "weapon": String(rules.weapon(m.weapon)["id"]), "tile": c,
		"radius": radius, "killed": killed, "structures": (b["structures"] as Array).size(), "destroyed": destroyed,
		"target_owner": st.owner[c]})


func _nuclear_burst(m: Munition, inner: float, outer: float) -> void:
	var c := m.to_tile
	var n := nuke_effect(c, inner, outer, m.id)
	var killed: Dictionary = n["killed"]
	# Troops first (fractions use the land before the blast), then land, buildings, fallout.
	var ex := float(rules.weapons_raw.get("nuke_troop_exponent", 5.0))
	var lost: Dictionary = n["lost"]
	for o: int in lost:
		var before := float(st.o_tiles[o])
		var f := pow(maxf(0.0, before - float(lost[o])) / maxf(before, 1.0), ex)
		var k := st.o_troops[o] * (1.0 - f)
		st.add_troops(o, -k)
		st.stat_troops_lost(o, k)
		for a in attacks.attacks:
			if a.alive and a.attacker == o:
				a.troops *= f
		if o != m.owner:
			st.mark_attacked(o)
	for sid: int in n["structures"]:
		structures.destroy(structures.structs[sid])
	for t in (n["lost_tiles"] as PackedInt32Array):
		if st.owner[t] != 0:
			var o := st.owner[t]
			st.set_owner(t, 0)
			if st.o_tiles[o] <= 0:
				st.o_killer[o] = m.owner
	var until := st.tick + int(rules.w_fallout.get("ticks", 1800))
	for t in (n["disc"] as PackedInt32Array):
		_add_fallout(t, until)
	events.emit(SimEvents.NUKE_DETONATED, {"id": m.id, "owner": m.owner, "weapon": String(rules.weapon(m.weapon)["id"]), "tile": c,
		"radius": outer, "inner": inner, "killed": killed, "lost": lost, "structures": (n["structures"] as Array).size(),
		"target_owner": m.target_owner, "warhead": m.warhead})


func _split_mirv(m: Munition, ef: Dictionary) -> void:
	var tg := st.owner[m.to_tile]
	if tg <= 0:
		tg = m.target_owner
	var n := int(ef["warheads"])
	var spread := float(rules.weapon(m.weapon)["radius"])
	# Warheads aim at the target owner's land: sampled deterministically around the aim point.
	var picks := PackedInt32Array()
	var tries := 0
	var cx := m.to_tile % st.W
	var cy := m.to_tile / st.W
	while picks.size() < n and tries < n * 30:
		var ang := TAU * _h01(tries, m.id)
		var rr := spread * sqrt(_h01(m.id, tries + 101))
		var x := clampi(int(round(cx + cos(ang) * rr)), 0, st.W - 1)
		var y := clampi(int(round(cy + sin(ang) * rr)), 0, st.H - 1)
		var t := y * st.W + x
		tries += 1
		if st.map.land[t] == 1 and (tg <= 0 or st.owner[t] == tg) and not picks.has(t):
			picks.append(t)
	var speed := float(ef.get("warhead_speed", 20.0))
	for t in picks:
		var path := path_for(m.weapon, m.to_tile, t, true)
		var w := _spawn(m.owner, m.weapon, m.to_tile, t, path, 0, flight_ticks(m.weapon, path[1], speed), true)
		w.target_owner = st.owner[t]
	events.emit(SimEvents.MIRV_SPLIT, {"id": m.id, "owner": m.owner, "tile": m.to_tile, "warheads": picks.size()})


func _emp(m: Munition, radius: float, ticks: int) -> void:
	var until := st.tick + ticks
	var n := 0
	for s in structures.near(m.to_tile, radius + 1.0):
		if s.alive and st.map.dist2(s.tile, m.to_tile) <= radius * radius:
			structures.disable(s, until)
			ammo.erase(s.id)
			ammo[s.id] = [0, until]
			n += 1
			events.emit(SimEvents.STRUCT_DISABLED, {"id": s.id, "owner": s.owner, "kind": s.kind, "tile": s.tile, "until": until})
	events.emit(SimEvents.WEAPON_IMPACT, {"id": m.id, "owner": m.owner, "weapon": String(rules.weapon(m.weapon)["id"]), "tile": m.to_tile,
		"radius": radius, "killed": {}, "structures": n, "destroyed": 0, "target_owner": st.owner[m.to_tile]})


# ---------------------------------------------------------------------------------------------
# Fallout
# ---------------------------------------------------------------------------------------------

func is_fallout(t: int) -> bool:
	return fallout.has(t)


func _add_fallout(t: int, until: int) -> void:
	if not fallout.has(t):
		_base_value[t] = st.tile_value[t]
		_set_value(t, st.tile_value[t] * float(rules.w_fallout.get("value_mult", 0.2)))
		fallout_changed.append(t)
	fallout[t] = maxi(int(fallout.get(t, 0)), until)


func _set_value(t: int, v: float) -> void:
	var o := st.owner[t]
	if o > 0:
		st.o_value[o] += v - st.tile_value[t]
	st.tile_value[t] = v


func _decay_fallout() -> void:
	var now := st.tick
	var gone := PackedInt32Array()
	for t: int in fallout:
		if now >= int(fallout[t]):
			gone.append(t)
	for t in gone:
		fallout.erase(t)
		_set_value(t, float(_base_value.get(t, st.tile_value[t])))
		_base_value.erase(t)
		fallout_changed.append(t)


func drain_fallout_changes() -> PackedInt32Array:
	var out := fallout_changed
	fallout_changed = PackedInt32Array()
	return out


# ---------------------------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ms := []
	for m in munitions:
		if m.alive:
			ms.append(m.to_dict())
	var xs := []
	for x in interceptors:
		xs.append(x.to_dict())
	var ft := PackedInt32Array()
	var fe := PackedInt32Array()
	var fb := PackedFloat32Array()
	for t: int in fallout:
		ft.append(t)
		fe.append(int(fallout[t]))
		fb.append(float(_base_value.get(t, st.tile_value[t])))
	return {"next_id": next_id, "munitions": ms, "interceptors": xs, "ammo": ammo.duplicate(true), "fallout_t": ft,
		"fallout_end": fe, "fallout_base": fb, "nukes_launched": nukes_launched.duplicate(), "last_nuke_tick": last_nuke_tick.duplicate()}


## Restores the weapons state (after SimState: owner values are already saved, so only the
## per-tile values of fallout tiles are re-applied).
func from_dict(d: Dictionary) -> void:
	next_id = int(d.get("next_id", 1))
	munitions.clear()
	for md: Dictionary in d.get("munitions", []):
		munitions.append(Munition.from_dict(md))
	interceptors.clear()
	for xd: Dictionary in d.get("interceptors", []):
		interceptors.append(Interceptor.from_dict(xd))
	ammo = (d.get("ammo", {}) as Dictionary).duplicate(true)
	fallout.clear()
	_base_value.clear()
	var ft: PackedInt32Array = d.get("fallout_t", PackedInt32Array())
	var fe: PackedInt32Array = d.get("fallout_end", PackedInt32Array())
	var fb: PackedFloat32Array = d.get("fallout_base", PackedFloat32Array())
	for i in ft.size():
		var t := ft[i]
		fallout[t] = fe[i]
		_base_value[t] = fb[i]
		st.tile_value[t] = fb[i] * float(rules.w_fallout.get("value_mult", 0.2))
		fallout_changed.append(t)
	nukes_launched = (d.get("nukes_launched", {}) as Dictionary).duplicate()
	last_nuke_tick = (d.get("last_nuke_tick", {}) as Dictionary).duplicate()
