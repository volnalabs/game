class_name StartPositions
extends RefCounted
## Fair start positions: candidates on land masses big enough to grow, scored by the value of the
## land around them; greedy pick with a minimum spacing that relaxes until enough starts exist.
## fairness = weakest / strongest chosen score.

const RADIUS := 24


static func score(map: MapData, t: int, rng: SimRng) -> float:
	var W := map.width
	var cx := t % W
	var cy := t / W
	var s := 0.0
	for _k in 40:
		var ang := rng.range_f(0.0, TAU)
		var r := sqrt(rng.randf()) * RADIUS
		var u := map.tile_at(cx + roundi(cos(ang) * r), cy + roundi(sin(ang) * r))
		if u >= 0 and map.land[u] == 1:
			var c := map.code(u)
			s += [0.0, 0.0, 0.0, 1.0, 0.9, 0.8, 0.5, 0.35, 0.4, 0.0][c] + (0.3 if map.is_river(u) else 0.0)
	return s


static func pick(map: MapData, n: int, rng: SimRng) -> Dictionary:
	var starts := PackedInt32Array()
	if map.land_count == 0 or n <= 0:
		return {"starts": starts, "fairness": 0.0}
	var min_mass := maxi(300, map.land_count / maxi(n * 6, 1))
	var cands: Array = []
	for _i in n * 40:
		var t := map.land_tiles[rng.below(map.land_count)]
		var lm := map.landmass[t]
		if map.landmass_sizes[lm] < min_mass:
			continue
		cands.append([score(map, t, rng), t])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var min_d := sqrt(float(map.land_count) / float(n)) * 0.75
	var chosen_scores: Array[float] = []
	while starts.size() < n and min_d > 4.0:
		for c: Array in cands:
			if starts.size() >= n:
				break
			var t: int = c[1]
			var ok := true
			for s in starts:
				if map.dist2(s, t) < min_d * min_d:
					ok = false
					break
			if ok:
				starts.append(t)
				chosen_scores.append(float(c[0]))
		min_d *= 0.8
	var lo := INF
	var hi := 0.0
	for s in chosen_scores:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	return {"starts": starts, "fairness": lo / hi if hi > 0.0 else 0.0}
