class_name StructureSystem
extends RefCounted
## Buildings: placement, construction, upgrades, capture and destruction. Placement rules follow
## RoWorld's Rules.place_site / SimStructures.luau: on own land, at least min_distance from any
## other structure, ports on the coast, a repeated build next to a finished structure of the same
## upgradable kind upgrades it. Effects are read by the economy (levels) and attacks (posts).

const CELL := 16


class Structure:
	extends RefCounted
	var id: int = 0
	var kind: int = 0
	var owner: int = 0
	var tile: int = 0
	var level: int = 1
	## Tick the current construction / upgrade finishes; 0 when idle.
	var done_tick: int = 0
	## Levels already active (an upgrading structure keeps its previous level working).
	var active_levels: int = 0
	var alive: bool = true

	func to_dict() -> Dictionary:
		return {"id": id, "kind": kind, "owner": owner, "tile": tile, "level": level,
			"done_tick": done_tick, "active_levels": active_levels, "alive": alive}

	static func from_dict(d: Dictionary) -> Structure:
		var s := Structure.new()
		for k: String in d:
			s.set(k, d[k])
		return s


var st: SimState
var rules: Rules
var events: SimEvents
var structs: Array[Structure] = []
var _grid: Dictionary = {}
var _posts_cache: Dictionary = {}


func _init(state: SimState, rules_: Rules, ev: SimEvents) -> void:
	st = state
	rules = rules_
	events = ev
	st.on_struct_tile = _on_tile_changed


func _cell_key(t: int) -> int:
	return (t / st.W / CELL) * 100000 + (t % st.W) / CELL


func _grid_add(s: Structure) -> void:
	var k := _cell_key(s.tile)
	if not _grid.has(k):
		_grid[k] = []
	(_grid[k] as Array).append(s.id)


func _grid_remove(s: Structure) -> void:
	var k := _cell_key(s.tile)
	if _grid.has(k):
		(_grid[k] as Array).erase(s.id)


## Structures (alive) within `radius` tiles of t, optionally filtered by kind / owner (-1 = any).
func near(t: int, radius: float, kind: int = -1, who: int = -1) -> Array[Structure]:
	var out: Array[Structure] = []
	var W := st.W
	var tx := t % W
	var ty := t / W
	var r := int(ceil(radius))
	var cx0 := maxi(0, (tx - r) / CELL)
	var cx1 := (tx + r) / CELL
	var cy0 := maxi(0, (ty - r) / CELL)
	var cy1 := (ty + r) / CELL
	var r2 := radius * radius
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var k := cy * 100000 + cx
			if not _grid.has(k):
				continue
			for sid: int in _grid[k]:
				var s := structs[sid]
				if not s.alive:
					continue
				if kind >= 0 and s.kind != kind:
					continue
				if who >= 0 and s.owner != who:
					continue
				var dx := (s.tile % W) - tx
				var dy := (s.tile / W) - ty
				if dx * dx + dy * dy <= r2:
					out.append(s)
	return out


func of_owner(who: int, kind: int = -1) -> Array[Structure]:
	var out: Array[Structure] = []
	for s in structs:
		if s.alive and s.owner == who and (kind < 0 or s.kind == kind):
			out.append(s)
	return out


func defense_posts_of(who: int) -> PackedInt32Array:
	if _posts_cache.has(who):
		return _posts_cache[who]
	var out := PackedInt32Array()
	for s in structs:
		if s.alive and s.owner == who and s.kind == Rules.B_DEFENSE and s.active_levels > 0:
			out.append(s.tile)
	_posts_cache[who] = out
	return out


func cost(who: int, kind: int) -> float:
	return rules.building_cost(kind, st.bowned(who, kind))


func can_afford(who: int, kind: int) -> bool:
	return st.o_gold[who] >= cost(who, kind) and st.o_supplies[who] >= rules.building_supplies(kind)


## Where a build order on tile t would go: {"tile": t, "upgrade": structure id or -1} or {} if
## nowhere.
func find_site(who: int, kind: int, t: int) -> Dictionary:
	if t < 0 or t >= st.N or st.owner[t] != who:
		return {}
	if rules.building_upgradable(kind):
		var best: Structure = null
		var bd := 1 << 30
		for s in near(t, rules.b_search_radius, kind, who):
			if s.done_tick == 0:
				var d := st.map.dist2(s.tile, t)
				if d < bd:
					bd = d
					best = s
		if best != null:
			return {"tile": best.tile, "upgrade": best.id}
	var coastal := rules.building_coastal(kind)
	var radius := rules.b_port_search if coastal else rules.b_search_radius
	var W := st.W
	var N := st.N
	var owner := st.owner
	var cand := -1
	var seen := {t: true}
	var frontier: Array[int] = [t]
	var tx := t % W
	var ty := t / W
	var min_d := rules.b_min_dist
	while not frontier.is_empty() and cand < 0:
		var nxt: Array[int] = []
		var best_d := 1 << 30
		for c in frontier:
			if st.struct_at[c] < 0 and (not coastal or st.map.coastal[c] == 1) and near(c, min_d).is_empty():
				var d := st.map.dist2(c, t)
				if d < best_d:
					best_d = d
					cand = c
			var x := c % W
			for nb: int in [c - 1 if x > 0 else -1, c + 1 if x < W - 1 else -1, c - W, c + W]:
				if nb < 0 or nb >= N or seen.has(nb) or owner[nb] != who:
					continue
				seen[nb] = true
				var dx := absi((nb % W) - tx)
				var dy := absi((nb / W) - ty)
				if float(dx + dy) <= radius:
					nxt.append(nb)
		frontier = nxt
	if cand < 0:
		return {}
	return {"tile": cand, "upgrade": -1}


## Dry run of a build order on tile t — the same checks try_build makes, without side effects.
## {"ok", "reason" (as try_build), "detail" (finer reason for the UI: not_own_land, no_coast,
## too_close), "tile" (-1 if no site), "upgrade" (structure id or -1), "level" (level after the
## order), "gold", "supplies", "ticks", "radius"}.
func preview(who: int, kind: int, t: int) -> Dictionary:
	var out := {"ok": false, "reason": "", "detail": "", "tile": -1, "upgrade": -1, "level": 1,
		"gold": 0.0, "supplies": 0.0, "ticks": 0, "radius": 0.0, "kind": kind}
	if kind < 0 or kind >= Rules.BUILDING_KINDS:
		out["reason"] = "bad_kind"
		return out
	out["gold"] = cost(who, kind)
	out["supplies"] = rules.building_supplies(kind)
	out["ticks"] = rules.building_ticks(kind)
	out["radius"] = rules.building_radius(kind)
	if not st.is_alive(who):
		out["reason"] = "dead"
		return out
	var site := find_site(who, kind, t)
	if not site.is_empty():
		out["tile"] = site["tile"]
		out["upgrade"] = site["upgrade"]
		if int(site["upgrade"]) >= 0:
			out["level"] = structs[int(site["upgrade"])].level + 1
	if st.o_gold[who] < float(out["gold"]):
		out["reason"] = "no_gold"
	elif st.o_supplies[who] < float(out["supplies"]):
		out["reason"] = "no_supplies"
	elif site.is_empty():
		out["reason"] = "no_site"
	if site.is_empty():
		if t < 0 or t >= st.N or st.owner[t] != who:
			out["detail"] = "not_own_land"
		elif rules.building_coastal(kind):
			out["detail"] = "no_coast"
		else:
			out["detail"] = "too_close"
	out["ok"] = out["reason"] == ""
	return out


## Validates, pays and starts a build. Returns {"ok": bool, "reason": String, "id": int}.
func try_build(who: int, kind: int, t: int) -> Dictionary:
	var pv := preview(who, kind, t)
	if not pv["ok"]:
		return {"ok": false, "reason": pv["reason"]}
	var gold_cost: float = pv["gold"]
	var sup_cost: float = pv["supplies"]
	var site := {"tile": pv["tile"], "upgrade": pv["upgrade"]}
	var done := st.tick + rules.building_ticks(kind)
	var s: Structure
	if int(site["upgrade"]) >= 0:
		s = structs[int(site["upgrade"])]
		s.level += 1
		s.done_tick = done
	else:
		s = Structure.new()
		s.id = structs.size()
		s.kind = kind
		s.owner = who
		s.tile = site["tile"]
		s.level = 1
		s.done_tick = done
		structs.append(s)
		st.set_struct_at(s.tile, s.id)
		_grid_add(s)
	st.add_gold(who, -gold_cost)
	st.add_supplies(who, -sup_cost)
	st.stat_gold(who, 0.0, gold_cost, 0.0)
	st.add_bowned(who, kind, 1)
	events.emit(SimEvents.BUILD_STARTED, {"id": s.id, "owner": who, "kind": kind, "tile": s.tile, "level": s.level})
	return {"ok": true, "reason": "", "id": s.id}


func tick() -> void:
	var now := st.tick
	for s in structs:
		if s.alive and s.done_tick > 0 and now >= s.done_tick:
			s.done_tick = 0
			var add := s.level - s.active_levels
			s.active_levels = s.level
			st.add_blevel(s.owner, s.kind, add)
			if s.kind == Rules.B_DEFENSE:
				_posts_cache.erase(s.owner)
			events.emit(SimEvents.BUILD_DONE, {"id": s.id, "owner": s.owner, "kind": s.kind, "tile": s.tile, "level": s.level})


func _on_tile_changed(t: int, old: int, new_owner: int) -> void:
	var sid := st.struct_at[t]
	if sid < 0:
		return
	var s := structs[sid]
	if not s.alive:
		return
	if new_owner == 0 or s.kind == Rules.B_DEFENSE:
		destroy(s)
		return
	st.add_blevel(old, s.kind, -s.active_levels)
	st.add_bowned(old, s.kind, -s.level)
	st.add_blevel(new_owner, s.kind, s.active_levels)
	st.add_bowned(new_owner, s.kind, s.level)
	s.owner = new_owner
	_posts_cache.erase(old)
	_posts_cache.erase(new_owner)
	events.emit(SimEvents.STRUCT_CAPTURED, {"id": s.id, "kind": s.kind, "from": old, "to": new_owner, "tile": t})


func destroy(s: Structure) -> void:
	if not s.alive:
		return
	s.alive = false
	st.add_blevel(s.owner, s.kind, -s.active_levels)
	st.add_bowned(s.owner, s.kind, -s.level)
	st.set_struct_at(s.tile, -1)
	_grid_remove(s)
	_posts_cache.erase(s.owner)
	events.emit(SimEvents.STRUCT_DESTROYED, {"id": s.id, "kind": s.kind, "owner": s.owner, "tile": s.tile})


func to_dict() -> Dictionary:
	var arr := []
	for s in structs:
		arr.append(s.to_dict())
	return {"structs": arr}


func from_dict(d: Dictionary) -> void:
	structs.clear()
	_grid.clear()
	_posts_cache.clear()
	for sd: Dictionary in d["structs"]:
		var s := Structure.from_dict(sd)
		structs.append(s)
		if s.alive:
			_grid_add(s)
