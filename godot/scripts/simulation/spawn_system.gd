class_name SpawnSystem
extends RefCounted
## Start positions: nations at their map coordinates (with jitter), tribes at random spread-out
## tiles, the player where they click. A start claims the free land in a disk of radius
## spawn_radius around a tile corner (RoWorld Sim.luau:681-760).

var st: SimState
var rules: Rules
var rng: SimRng
var starts: Array[int] = []


func _init(state: SimState, rules_: Rules, rng_: SimRng) -> void:
	st = state
	rules = rules_
	rng = rng_


func disk_tiles(center: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := rules.spawn_radius
	var ri := ceili(r)
	var W := st.W
	var cx := center % W
	var cy := center / W
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if (dx + 0.5) * (dx + 0.5) + (dy + 0.5) * (dy + 0.5) > r * r:
				continue
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= W or y >= st.H:
				continue
			out.append(y * W + x)
	return out


## A tile is a valid start when it is free land and most of its disk is free land.
func is_valid_start(t: int) -> bool:
	if t < 0 or t >= st.N or st.map.land[t] == 0 or st.owner[t] != 0:
		return false
	var disk := disk_tiles(t)
	var free := 0
	for d in disk:
		if st.map.land[d] == 1 and st.owner[d] == 0:
			free += 1
	return free * 2 >= disk.size()


func claim(id: int, center: int) -> void:
	for d in disk_tiles(center):
		if st.map.land[d] == 1 and st.owner[d] == 0:
			st.set_owner(d, id)
	st.set_spawn_tile(id, center)
	starts.append(center)


func _far_from_starts(t: int, min_d: float) -> bool:
	var m2 := min_d * min_d
	for s in starts:
		if st.map.dist2(s, t) < m2:
			return false
	return true


## Start near (x, y): 50 random tries within the jitter, then the nearest valid tile, then random.
func place_near(id: int, x: int, y: int) -> bool:
	var j := int(rules.nation_jitter)
	for _i in 50:
		var t := st.map.tile_at(x + rng.range_i(-j, j), y + rng.range_i(-j, j))
		if t >= 0 and is_valid_start(t) and (st.map.code(t) != Rules.T_MOUNTAIN or rng.chance(0.5)):
			claim(id, t)
			return true
	var c := st.map.tile_at(clampi(x, 0, st.W - 1), clampi(y, 0, st.H - 1))
	for radius in range(1, 120):
		for k in 24:
			var ang := TAU * float(k) / 24.0
			var t := st.map.tile_at(x + roundi(cos(ang) * radius), y + roundi(sin(ang) * radius))
			if t >= 0 and is_valid_start(t):
				claim(id, t)
				return true
	if c >= 0 and is_valid_start(c):
		claim(id, c)
		return true
	return place_random(id, rules.tribe_min_dist)


func place_random(id: int, min_dist: float) -> bool:
	var lt := st.map.land_tiles
	if lt.is_empty():
		return false
	for attempt in 1000:
		var t := lt[rng.below(lt.size())]
		if not is_valid_start(t):
			continue
		if attempt < 750 and not _far_from_starts(t, min_dist):
			continue
		claim(id, t)
		return true
	return false
