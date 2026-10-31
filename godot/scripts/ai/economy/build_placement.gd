class_name BuildPlacement
extends RefCounted
## Where the bot puts a building: cities and factories deep inside the territory, ports on the
## coast of the largest water body, defence posts at the border with the main threat.


static func site(bot: StrategicAI, kind: int, threat_owner: int = 0) -> int:
	match kind:
		Rules.B_PORT:
			return _coast_site(bot)
		Rules.B_DEFENSE:
			return _border_site(bot, threat_owner)
	return _interior_site(bot)


static func _own_samples(bot: StrategicAI, want: int, tries: int) -> Array[int]:
	var st := bot.sim.st
	var out: Array[int] = []
	if bot.perception.border_box.size.x <= 0:
		return out
	var box := bot.perception.border_box.intersection(Rect2i(0, 0, st.W, st.H))
	if box.size.x <= 0 or box.size.y <= 0:
		return out
	for _i in tries:
		var x := box.position.x + bot.rng.below(box.size.x)
		var y := box.position.y + bot.rng.below(box.size.y)
		var t := y * st.W + x
		if st.owner[t] == bot.id and st.struct_at[t] < 0:
			out.append(t)
			if out.size() >= want:
				break
	return out


static func _interior_site(bot: StrategicAI) -> int:
	var st := bot.sim.st
	var cands := _own_samples(bot, 14, 120)
	if cands.is_empty():
		var sp := st.o_spawn_tile[bot.id]
		return sp if sp >= 0 and st.owner[sp] == bot.id else st.o_border_head[bot.id]
	var border: Array[int] = []
	var t := st.o_border_head[bot.id]
	var n := 0
	var stride := maxi(1, st.o_border_count[bot.id] / 24)
	while t >= 0 and border.size() < 24:
		if n % stride == 0:
			border.append(t)
		t = st.bnext[t]
		n += 1
	var best := cands[0]
	var best_d := -1
	for c in cands:
		var d := 1 << 30
		for b in border:
			d = mini(d, st.map.dist2(c, b))
		if d > best_d:
			best_d = d
			best = c
	return best


static func _coast_site(bot: StrategicAI) -> int:
	var st := bot.sim.st
	var coast := st.map.coast_tiles
	if coast.is_empty():
		return -1
	var best := -1
	var best_s := -1.0
	for _i in 300:
		var t := coast[bot.rng.below(coast.size())]
		if st.owner[t] != bot.id:
			continue
		var body := st.map.coast_body[t]
		var s := float(st.map.water_body_sizes[body]) + (0.0 if st.in_border[t] == 1 else 5000.0)
		if s > best_s:
			best_s = s
			best = t
	if best >= 0:
		return best
	# Small territory: flood from the spawn / centroid for an own coastal tile.
	var start := st.o_spawn_tile[bot.id]
	if start < 0 or st.owner[start] != bot.id:
		start = st.o_border_head[bot.id]
	if start < 0:
		return -1
	var seen := {start: true}
	var stack: Array[int] = [start]
	var steps := 0
	while not stack.is_empty() and steps < 3000:
		var c: int = stack.pop_back()
		steps += 1
		if st.map.coastal[c] == 1:
			return c
		var x := c % st.W
		for nb: int in [c - 1 if x > 0 else -1, c + 1 if x < st.W - 1 else -1, c - st.W, c + st.W]:
			if nb >= 0 and nb < st.N and st.owner[nb] == bot.id and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return -1


static func _border_site(bot: StrategicAI, threat_owner: int) -> int:
	var st := bot.sim.st
	var nv: AIPerception.NeighborView = bot.perception.neighbors.get(threat_owner)
	if nv == null or nv.contact_tile < 0:
		return -1
	var t := nv.contact_tile
	var x := t % st.W
	for nb: int in [t - 1 if x > 0 else -1, t + 1 if x < st.W - 1 else -1, t - st.W, t + st.W]:
		if nb >= 0 and nb < st.N and st.owner[nb] == bot.id:
			return nb
	return -1
