class_name NavalSystem
extends RefCounted
## Transports (naval landings): troops sail from the owner's nearest coast on the same water body
## to an enemy or unclaimed coastal tile; the landing takes the beach and starts a land attack
## from it (RoWorld SimNaval.luau launch_boat / _land). Warships and trade ships come later.


class Boat:
	extends RefCounted
	var id: int = 0
	var owner: int = 0
	var troops: float = 0.0
	var target_tile: int = 0
	var path: PackedVector2Array = PackedVector2Array()
	var seg_len: PackedFloat32Array = PackedFloat32Array()
	var length: float = 0.0
	var progress: float = 0.0
	var alive: bool = true

	func position() -> Vector2:
		var d := progress
		for i in seg_len.size():
			if d <= seg_len[i] or i == seg_len.size() - 1:
				return path[i].lerp(path[i + 1], clampf(d / maxf(seg_len[i], 0.001), 0.0, 1.0))
			d -= seg_len[i]
		return path[path.size() - 1] if path.size() > 0 else Vector2.ZERO

	func to_dict() -> Dictionary:
		return {"id": id, "owner": owner, "troops": troops, "target_tile": target_tile, "path": path,
			"seg_len": seg_len, "length": length, "progress": progress, "alive": alive}

	static func from_dict(d: Dictionary) -> Boat:
		var b := Boat.new()
		for k: String in d:
			b.set(k, d[k])
		return b


var st: SimState
var rules: Rules
var events: SimEvents
var attacks: AttackSystem
var nav: WaterNav
var boats: Array[Boat] = []
var next_id: int = 1


func _init(state: SimState, rules_: Rules, ev: SimEvents, atk: AttackSystem) -> void:
	st = state
	rules = rules_
	events = ev
	attacks = atk
	nav = WaterNav.for_map(st.map, int(rules.n["nav_cell"]))


func max_boats() -> int:
	return int(rules.n["max_boats"])


## The owner's coastal tile on target's water body nearest the target, or -1.
func source_for(who: int, target: int) -> int:
	var body := st.map.coast_body[target]
	if body == 0 or not st.map.coast_by_body.has(body):
		return -1
	var list: PackedInt32Array = st.map.coast_by_body[body]
	var owner := st.owner
	var best := -1
	var bd := 1 << 62
	for t in list:
		if owner[t] == who:
			var d := st.map.dist2(t, target)
			if d < bd:
				bd = d
				best = t
	return best


func _water_next_to(t: int, body: int) -> int:
	var W := st.W
	var x := t % W
	for nb: int in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W]:
		if nb >= 0 and nb < st.N and st.map.water_body[nb] == body:
			return nb
	return -1


## Validates and launches a transport with `troops` (taken from the army). Returns "" on success
## or a rejection reason.
func launch(who: int, target: int, troops: float) -> String:
	if target < 0 or target >= st.N or st.map.land[target] == 0 or st.map.coastal[target] == 0:
		return "not_coast"
	if st.owner[target] == who:
		return "own_land"
	if st.o_boats[who] >= max_boats():
		return "too_many_boats"
	var sup: float = rules.n["boat_supplies"]
	if st.o_supplies[who] < sup:
		return "no_supplies"
	troops = floorf(minf(troops, st.o_troops[who]))
	if troops < 1.0:
		return "no_troops"
	var src := source_for(who, target)
	if src < 0:
		return "no_coast"
	var body := st.map.coast_body[target]
	var w0 := _water_next_to(src, body)
	var w1 := _water_next_to(target, body)
	if w0 < 0 or w1 < 0:
		return "no_route"
	var path := nav.find_path(w0, w1)
	if path.size() < 2:
		return "no_route"
	var b := Boat.new()
	b.id = next_id
	next_id += 1
	b.owner = who
	b.troops = troops
	b.target_tile = target
	b.path = path
	b.seg_len.resize(path.size() - 1)
	for i in path.size() - 1:
		b.seg_len[i] = path[i].distance_to(path[i + 1])
		b.length += b.seg_len[i]
	boats.append(b)
	st.add_troops(who, -troops)
	st.add_supplies(who, -sup)
	st.add_boats(who, 1)
	events.emit(SimEvents.BOAT_LAUNCHED, {"id": b.id, "owner": who, "target": target,
		"target_owner": st.owner[target], "troops": troops})
	return ""


func tick() -> void:
	var speed: float = float(rules.n["boat_speed_tiles_per_tick"]) / rules.k_lin
	for b in boats:
		if not b.alive:
			continue
		if not st.is_alive(b.owner):
			_finish(b)
			continue
		b.progress += speed
		if b.progress >= b.length:
			_land(b)
	var j := 0
	for i in boats.size():
		if boats[i].alive:
			boats[j] = boats[i]
			j += 1
	boats.resize(j)


func _finish(b: Boat) -> void:
	b.alive = false
	st.add_boats(b.owner, -1)


func _land(b: Boat) -> void:
	_finish(b)
	var t := b.target_tile
	var who := b.owner
	var prev := st.owner[t]
	if prev == who:
		st.add_troops(who, b.troops * float(rules.n["own_landing_keep"]))
		events.emit(SimEvents.BOAT_FAILED, {"id": b.id, "owner": who, "reason": "own_coast"})
		return
	st.set_owner(t, who)
	events.emit(SimEvents.BOAT_LANDED, {"id": b.id, "owner": who, "target_owner": prev, "tile": t, "troops": b.troops})
	attacks.start(who, prev, b.troops)


func remove_owner(who: int) -> void:
	for b in boats:
		if b.alive and b.owner == who:
			_finish(b)


func to_dict() -> Dictionary:
	var arr := []
	for b in boats:
		if b.alive:
			arr.append(b.to_dict())
	return {"next_id": next_id, "boats": arr}


func from_dict(d: Dictionary) -> void:
	next_id = d["next_id"]
	boats.clear()
	for bd: Dictionary in d["boats"]:
		boats.append(Boat.from_dict(bd))
