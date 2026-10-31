class_name LandingPlanner
extends RefCounted
## Naval invasion planning (pure, deterministic): given any land tile of another state (or unclaimed
## land), finds how troops can get there by sea and then overland:
##   1. the goal itself, when it is a reachable coast, is the landing (the classic landing);
##   2. otherwise a breadth-first walk from the goal through land of the goal's owner finds the
##      coasts connected to it by land (with the overland distance and the way back to the goal);
##   3. a few well-spread candidate beaches are tried: each needs our own coast on the same water
##      body (the departure point) and a real water route (WaterNav);
##   4. the best one minimises sea length + overland distance × weight + a penalty for beaches inside
##      the defender's defence-post or radar zones.
## The same function serves the order preview (UI), the simulation (launch and re-routing at sea)
## and the AI, so what the player sees is what the simulation does.
## Failure reasons: not_land, own_land, dead_target, no_land_path (the goal is not connected to any
## coast through the owner's land), no_coast (we have no coast on any water body that touches those
## beaches), no_route (no water route), no_landing (no usable beach).


## The most valuable tile of state `id` to aim a landing at: its first city, port or factory,
## otherwise its centre (when that is its own land), its start tile, or any border tile.
static func key_tile(nv: NavalSystem, id: int) -> int:
	var st := nv.st
	if nv.structures != null:
		for k: int in [Rules.B_CITY, Rules.B_PORT, Rules.B_FACTORY]:
			var list := nv.structures.of_owner(id, k)
			if not list.is_empty():
				return list[0].tile
	var c := st.centroid(id)
	var t := st.map.tile_at(clampi(int(c.x), 0, st.W - 1), clampi(int(c.y), 0, st.map.height - 1))
	if t >= 0 and st.owner[t] == id:
		return t
	var sp := st.o_spawn_tile[id]
	if sp >= 0 and st.owner[sp] == id:
		return sp
	return st.o_border_head[id]


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Plan for `who` to reach `goal`. `from_water` >= 0 plans from a boat already at sea (re-routing):
## the departure is that water tile instead of our own coast.
static func plan(nv: NavalSystem, who: int, goal: int, from_water: int = -1) -> Dictionary:
	var st := nv.st
	var map := st.map
	var n: Dictionary = nv.rules.n
	if goal < 0 or goal >= st.N or map.land[goal] == 0:
		return _fail("not_land")
	var go := st.owner[goal]
	if go == who:
		return _fail("own_land")
	if go > 0 and not st.is_alive(go):
		return _fail("dead_target")
	# 1. The goal is a coast: land right there when it can be reached.
	if map.coastal[goal] == 1:
		var direct := _candidate(nv, who, goal, 0, from_water)
		if direct["ok"]:
			direct["land_path"] = PackedVector2Array([_pos(st, goal)])
			return _finish(nv, who, goal, go, direct)
	# 2. Coasts connected to the goal through the owner's land.
	var budget := int(n.get("landing_search_tiles", 60000))
	var spread := int(n.get("landing_beach_spread", 40))
	var parent := {goal: -1}
	var dist := {goal: 0}
	var q := PackedInt32Array([goal])
	var head := 0
	var beaches := PackedInt32Array()
	var first_d := -1
	var W := st.W
	var owner := st.owner
	while head < q.size():
		var u := q[head]
		head += 1
		var d: int = dist[u]
		if first_d >= 0 and d > first_d + spread:
			break
		if map.coastal[u] == 1 and u != goal:
			beaches.append(u)
			if first_d < 0:
				first_d = d
		var x := u % W
		for nb: int in [u - 1 if x > 0 else -1, u + 1 if x < W - 1 else -1, u - W, u + W]:
			if nb < 0 or nb >= st.N or map.land[nb] == 0 or owner[nb] != go or parent.has(nb):
				continue
			parent[nb] = u
			dist[nb] = d + 1
			q.append(nb)
		if q.size() > budget:
			break
	if beaches.is_empty():
		return _fail("no_land_path")
	# 3. A few beaches, spread along the coast (nearest overland first).
	var picks := PackedInt32Array()
	var max_c := int(n.get("landing_candidates", 8))
	for b in beaches:
		var far := true
		for p in picks:
			if map.dist2(b, p) < 64:
				far = false
				break
		if far:
			picks.append(b)
			if picks.size() >= max_c:
				break
	var best: Dictionary = {}
	var saw_coast := false
	for b in picks:
		var c := _candidate(nv, who, b, int(dist[b]), from_water)
		if String(c.get("reason", "")) != "no_coast":
			saw_coast = true
		if c["ok"] and (best.is_empty() or float(c["score"]) < float(best["score"])):
			best = c
	if best.is_empty():
		return _fail("no_route" if saw_coast else "no_coast")
	# The overland way from the beach back to the goal (sparse points for drawing).
	var lp := PackedVector2Array()
	var t: int = best["beach"]
	var step := 0
	while t >= 0:
		if step % 4 == 0 or parent[t] == -1:
			lp.append(_pos(st, t))
		t = parent[t]
		step += 1
	best["land_path"] = lp
	return _finish(nv, who, goal, go, best)


## One beach: departure, water route and score.
static func _candidate(nv: NavalSystem, who: int, beach: int, land_len: int, from_water: int) -> Dictionary:
	var st := nv.st
	var map := st.map
	var body := map.coast_body[beach]
	if body == 0:
		return _fail("no_coast")
	var src := -1
	var w0 := -1
	if from_water >= 0:
		if map.water_body[from_water] != body:
			return _fail("no_coast")
		w0 = from_water
	else:
		src = nv.source_for(who, beach)
		if src < 0:
			return _fail("no_coast")
		w0 = nv.water_next_to(src, body)
	var w1 := nv.water_next_to(beach, body)
	if w0 < 0 or w1 < 0:
		return _fail("no_route")
	var path := nv.nav.find_path(w0, w1)
	if path.size() < 2:
		return _fail("no_route")
	var sea := 0.0
	for i in path.size() - 1:
		sea += path[i].distance_to(path[i + 1])
	var n: Dictionary = nv.rules.n
	var unsafe := false
	var bo := st.owner[beach]
	if bo > 0 and nv.structures != null:
		unsafe = nv.structures.in_zone(bo, Rules.B_DEFENSE, beach) or nv.structures.in_zone(bo, Rules.B_RADAR, beach)
	var score := sea + float(land_len) * float(n.get("landing_land_weight", 3.0)) + (float(n.get("landing_unsafe_penalty", 60.0)) if unsafe else 0.0)
	return {"ok": true, "reason": "", "beach": beach, "source": src, "path": path, "sea_len": sea, "land_len": land_len,
		"unsafe": unsafe, "score": score}


static func _finish(nv: NavalSystem, _who: int, goal: int, go: int, c: Dictionary) -> Dictionary:
	var speed := maxf(0.01, float(nv.rules.n["boat_speed_tiles_per_tick"]) / nv.rules.k_lin)
	c["goal"] = goal
	c["goal_owner"] = go
	c["eta_ticks"] = ceili(float(c["sea_len"]) / speed)
	return c


static func _pos(st: SimState, t: int) -> Vector2:
	return Vector2(t % st.W + 0.5, t / st.W + 0.5)
