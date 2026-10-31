class_name NavalSystem
extends RefCounted
## Transports (naval landings). The order names any land tile of another state (or unclaimed land);
## LandingPlanner picks the beach (the goal itself when it is a reachable coast, otherwise the best
## coast connected to it overland), the departure coast and the water route. The transport really
## sails the route; on arrival the landing takes the beach and starts a land attack that pushes
## towards the goal. If the beach changed hands or the goal changed owner meanwhile, the boat
## re-plans from where it is; if nothing works it brings the troops home (no troops are lost). An
## order can be cancelled: the boat turns round and the troops return on arrival.
## (RoWorld SimNaval.luau launch_boat / _land.) Only transports exist; warships come later.


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
	## Tile the order was given for (may be inland), its owner at launch, departure coast tile.
	var goal_tile: int = -1
	var goal_owner: int = 0
	var source_tile: int = -1
	## Overland way from the beach to the goal (for drawing).
	var land_path: PackedVector2Array = PackedVector2Array()
	## Cancelled: sailing back to `source_tile`, troops return on arrival.
	var returning: bool = false
	var reroutes: int = 0

	func position() -> Vector2:
		var d := progress
		for i in seg_len.size():
			if d <= seg_len[i] or i == seg_len.size() - 1:
				return path[i].lerp(path[i + 1], clampf(d / maxf(seg_len[i], 0.001), 0.0, 1.0))
			d -= seg_len[i]
		return path[path.size() - 1] if path.size() > 0 else Vector2.ZERO

	func to_dict() -> Dictionary:
		return {"id": id, "owner": owner, "troops": troops, "target_tile": target_tile, "path": path,
			"seg_len": seg_len, "length": length, "progress": progress, "alive": alive, "goal_tile": goal_tile,
			"goal_owner": goal_owner, "source_tile": source_tile, "land_path": land_path, "returning": returning,
			"reroutes": reroutes}

	## Replaces the route (re-planning or turning round) and restarts progress along it.
	func set_path(p: PackedVector2Array) -> void:
		path = p
		seg_len = PackedFloat32Array()
		seg_len.resize(maxi(0, p.size() - 1))
		length = 0.0
		for i in p.size() - 1:
			seg_len[i] = p[i].distance_to(p[i + 1])
			length += seg_len[i]
		progress = 0.0

	## Current heading (unit vector along the route).
	func heading() -> Vector2:
		var d := progress
		for i in seg_len.size():
			if d <= seg_len[i] or i == seg_len.size() - 1:
				var v := path[i + 1] - path[i]
				return v.normalized() if v.length() > 0.0001 else Vector2.RIGHT
			d -= seg_len[i]
		return Vector2.RIGHT

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


var mods: Modifiers
var structures: StructureSystem


func max_boats(who: int = 0) -> int:
	return int(rules.n["max_boats"]) + (int(mods.add("boat_limit_add", who)) if mods != null and who > 0 else 0)


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


func water_next_to(t: int, body: int) -> int:
	var W := st.W
	var x := t % W
	for nb: int in [t - 1 if x > 0 else -1, t + 1 if x < W - 1 else -1, t - W, t + W]:
		if nb >= 0 and nb < st.N and st.map.water_body[nb] == body:
			return nb
	return -1


## Validates and launches a transport with `troops` (taken from the army) for an order on `target`
## (any land tile of another state or unclaimed land). Returns "" on success or a rejection reason.
func launch(who: int, target: int, troops: float) -> String:
	if target < 0 or target >= st.N or st.map.land[target] == 0:
		return "not_land"
	if st.owner[target] == who:
		return "own_land"
	if st.o_boats[who] >= max_boats(who):
		return "too_many_boats"
	var sup: float = rules.n["boat_supplies"]
	if st.o_supplies[who] < sup:
		return "no_supplies"
	troops = floorf(minf(troops, st.o_troops[who]))
	if troops < 1.0:
		return "no_troops"
	var p := LandingPlanner.plan(self, who, target)
	if not p["ok"]:
		return String(p["reason"])
	var b := Boat.new()
	b.id = next_id
	next_id += 1
	b.owner = who
	b.troops = troops
	b.target_tile = p["beach"]
	b.goal_tile = target
	b.goal_owner = p["goal_owner"]
	b.source_tile = p["source"]
	b.land_path = p["land_path"]
	b.set_path(p["path"])
	boats.append(b)
	st.add_troops(who, -troops)
	st.add_supplies(who, -sup)
	st.add_boats(who, 1)
	events.emit(SimEvents.BOAT_LAUNCHED, {"id": b.id, "owner": who, "target": b.target_tile, "goal": target,
		"target_owner": st.owner[target], "troops": troops})
	return ""


## Turns `who`'s boat `boat_id` round; its troops come back when it reaches the departure coast.
func cancel(who: int, boat_id: int) -> String:
	for b in boats:
		if b.alive and b.id == boat_id and b.owner == who:
			if b.returning:
				return "no_boat"
			var back := PackedVector2Array([b.position()])
			var d := b.progress
			var idx := 0
			for i in b.seg_len.size():
				if d <= b.seg_len[i]:
					idx = i
					break
				d -= b.seg_len[i]
				idx = i + 1
			for i in range(mini(idx, b.path.size() - 1), -1, -1):
				if b.path[i].distance_squared_to(back[back.size() - 1]) > 0.0001:
					back.append(b.path[i])
			if back.size() < 2:
				back.append(b.path[0])
			b.returning = true
			b.set_path(back)
			events.emit(SimEvents.BOAT_RECALLED, {"id": b.id, "owner": who})
			return ""
	return "no_boat"


func tick() -> void:
	var speed: float = float(rules.n["boat_speed_tiles_per_tick"]) / rules.k_lin
	for b in boats:
		if not b.alive:
			continue
		if not st.is_alive(b.owner):
			_finish(b)
			continue
		b.progress += speed * (mods.mult("boat_speed_mult", b.owner) if mods != null else 1.0)
		if b.progress >= b.length:
			if b.returning:
				_bring_home(b, "recalled")
			else:
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


## Troops come back to the army in full (cancelled order, or no usable landing left).
func _bring_home(b: Boat, reason: String) -> void:
	_finish(b)
	st.add_troops(b.owner, b.troops)
	events.emit(SimEvents.BOAT_FAILED if reason != "recalled" else SimEvents.BOAT_RETURNED,
		{"id": b.id, "owner": b.owner, "reason": reason, "troops": b.troops})


## The landing is still valid when the beach belongs to the goal's current owner (or, for an old
## order without a goal, to anyone but us).
func _landing_valid(b: Boat) -> bool:
	var t := b.target_tile
	if b.goal_tile < 0:
		return st.owner[t] != b.owner
	var go := st.owner[b.goal_tile]
	return go != b.owner and st.owner[t] == go and (go == 0 or st.is_alive(go))


## Re-plans from the boat's position after the beach or the goal changed hands. False = no way.
func _reroute(b: Boat) -> bool:
	if b.goal_tile < 0 or b.reroutes >= 2 or st.owner[b.goal_tile] == b.owner:
		return false
	var pos := b.position()
	var wt := st.map.tile_at(clampi(int(pos.x), 0, st.W - 1), clampi(int(pos.y), 0, st.map.height - 1))
	if st.map.water_body[wt] == 0:
		return false
	var p := LandingPlanner.plan(self, b.owner, b.goal_tile, wt)
	if not p["ok"]:
		return false
	b.reroutes += 1
	b.target_tile = p["beach"]
	b.goal_owner = p["goal_owner"]
	b.land_path = p["land_path"]
	b.set_path(p["path"])
	events.emit(SimEvents.BOAT_REROUTED, {"id": b.id, "owner": b.owner, "target": b.target_tile})
	return true


func _land(b: Boat) -> void:
	var who := b.owner
	if not _landing_valid(b):
		if _reroute(b):
			return
		_bring_home(b, "goal_taken" if b.goal_tile >= 0 and st.owner[b.goal_tile] == who else "no_landing")
		return
	_finish(b)
	var t := b.target_tile
	var prev := st.owner[t]
	# Radar coverage of the defender: the landing is spotted early and loses part of its troops.
	var spotted := prev > 0 and structures != null and structures.in_zone(prev, Rules.B_RADAR, t)
	var troops := b.troops
	if spotted:
		var lost := troops * float(rules.building_effect(Rules.B_RADAR).get("landing_loss", 0.0))
		troops -= lost
		st.stat_troops_lost(who, lost)
	st.set_owner(t, who)
	events.emit(SimEvents.BOAT_LANDED, {"id": b.id, "owner": who, "target_owner": prev, "tile": t, "troops": troops,
		"spotted": spotted, "goal": b.goal_tile})
	var a := attacks.start(who, prev, troops, t)
	if a != null and b.goal_tile >= 0 and b.goal_tile != t:
		a.goal = b.goal_tile


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
