class_name AIPerception
extends RefCounted
## What one bot knows (docs/ai/AI_DESIGN.md §3): exact own data; for neighbours the public tile
## count, the contact along the shared border, visible defence posts near the border and a noisy,
## remembered estimate of their troops; visible wars involving neighbours; the public leaderboard.
## Never reads other owners' gold or plans.


class NeighborView:
	extends RefCounted
	var id: int = 0
	var contact: int = 0
	var contact_tile: int = -1
	var samples: PackedInt32Array = PackedInt32Array()
	var mag_sum: float = 0.0
	var cost_sum: float = 0.0
	var value_sum: float = 0.0
	var est_troops: float = 0.0
	var tiles: int = 0
	var kind: int = 0
	var defended_share: float = 0.0
	var posts_seen: int = 0
	## Troops this neighbour has in attacks against others / others have in attacks against it.
	var war_out: float = 0.0
	var war_in: float = 0.0
	var attacking_me: float = 0.0

	func avg_mag() -> float:
		return mag_sum / maxf(1.0, float(contact))

	func avg_cost() -> float:
		return cost_sum / maxf(1.0, float(contact))

	func avg_value() -> float:
		return value_sum / maxf(1.0, float(contact))

	func density() -> float:
		return est_troops / maxf(1.0, float(tiles))


var bot: int
var sim: Sim
var rng: SimRng
var noise: float = 0.15
var scan_limit: int = 3000
var reaction_delay: int = 10

var neighbors: Dictionary = {}
var free_contact: int = 0
var free_tiles: PackedInt32Array = PackedInt32Array()
var free_mag: float = 80.0
var free_cost: float = 16.5
var free_estimate: int = 0
var incoming: Array[Dictionary] = []
var visible_wars: Array[Dictionary] = []
var leader: int = 0
var leader_share: float = 0.0
var rank: int = 0
var alive_states: int = 0
var border_box: Rect2i = Rect2i()
## Remembered troop estimates: id -> [estimate, tick].
var memory: Dictionary = {}


func _init(bot_id: int, sim_: Sim, rng_: SimRng, diff: Dictionary) -> void:
	bot = bot_id
	sim = sim_
	rng = rng_
	noise = diff["perception_noise"]
	scan_limit = int(diff["border_scan"])
	reaction_delay = int(diff["reaction_delay"])


func refresh() -> void:
	var st := sim.st
	var rules := sim.rules
	var owner := st.owner
	var land := st.map.land
	var terrain := st.map.terrain
	var W := st.W
	var N := st.N
	neighbors.clear()
	free_contact = 0
	free_tiles = PackedInt32Array()
	var fm := 0.0
	var fc := 0.0
	var minx := W
	var miny := st.H
	var maxx := 0
	var maxy := 0
	var t := st.o_border_head[bot]
	var steps := 0
	while t >= 0 and steps < scan_limit:
		steps += 1
		var x := t % W
		var y := t / W
		minx = mini(minx, x)
		maxx = maxi(maxx, x)
		miny = mini(miny, y)
		maxy = maxi(maxy, y)
		for k in 4:
			var u := -1
			if k == 0 and x > 0:
				u = t - 1
			elif k == 1 and x < W - 1:
				u = t + 1
			elif k == 2 and t >= W:
				u = t - W
			elif k == 3 and t + W < N:
				u = t + W
			if u < 0 or land[u] == 0:
				continue
			var o := owner[u]
			if o == bot:
				continue
			var code := terrain[u] & MapData.CODE_MASK
			if o == 0:
				free_contact += 1
				if free_tiles.size() < 32:
					free_tiles.append(u)
				fm += rules.t_mag[code]
				fc += rules.t_cost[code]
				continue
			var nv: NeighborView = neighbors.get(o)
			if nv == null:
				nv = NeighborView.new()
				nv.id = o
				nv.contact_tile = u
				neighbors[o] = nv
			nv.contact += 1
			if nv.samples.size() < 32:
				nv.samples.append(u)
			nv.mag_sum += rules.t_mag[code]
			nv.cost_sum += rules.t_cost[code]
			nv.value_sum += st.tile_value[u]
		t = st.bnext[t]
	if free_contact > 0:
		free_mag = fm / free_contact
		free_cost = fc / free_contact
	if steps == 0:
		border_box = Rect2i()
	else:
		border_box = Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1).grow(40)
	var now := st.tick
	for o: int in neighbors:
		var nv: NeighborView = neighbors[o]
		nv.tiles = st.o_tiles[o]
		nv.kind = st.o_kind[o]
		nv.est_troops = estimate_troops(o)
		var posts := sim.structures.defense_posts_of(o)
		var seen: Array[int] = []
		for p in posts:
			if border_box.has_point(Vector2i(p % W, p / W)):
				seen.append(p)
		nv.posts_seen = seen.size()
		if seen.size() > 0 and nv.samples.size() > 0:
			var r2 := rules.defense_radius() * rules.defense_radius()
			var covered := 0
			for s in nv.samples:
				for p in seen:
					if st.map.dist2(s, p) <= r2:
						covered += 1
						break
			nv.defended_share = float(covered) / nv.samples.size()
	# Wars that involve a neighbour or me are visible.
	incoming.clear()
	visible_wars.clear()
	for a in sim.attacks.attacks:
		if not a.alive:
			continue
		if a.target == bot and a.attacker != 0:
			if now - a.start_tick >= reaction_delay:
				incoming.append({"attacker": a.attacker, "troops": a.troops, "id": a.id, "age": now - a.start_tick})
			var nva: NeighborView = neighbors.get(a.attacker)
			if nva != null:
				nva.attacking_me += a.troops
			continue
		var na: NeighborView = neighbors.get(a.attacker)
		var nt: NeighborView = neighbors.get(a.target)
		if na == null and nt == null:
			continue
		visible_wars.append({"attacker": a.attacker, "target": a.target, "troops": a.troops})
		if na != null and a.target != 0:
			na.war_out += a.troops
		if nt != null:
			nt.war_in += a.troops
	_leaderboard()


## Noisy, remembered estimate of another owner's troops (neighbours are refreshed, others guessed
## from their public territory size).
func estimate_troops(o: int) -> float:
	var st := sim.st
	var truth := st.o_troops[o]
	var noisy := truth * (1.0 + rng.noise(noise))
	var prev: Array = memory.get(o, [])
	var est := noisy
	if prev.size() == 2 and st.tick - int(prev[1]) < 600:
		est = lerpf(float(prev[0]), noisy, 0.6)
	memory[o] = [est, st.tick]
	return est


## Rough guess for an owner we cannot see: public tiles times our own troop density.
func guess_troops(o: int) -> float:
	if neighbors.has(o):
		return (neighbors[o] as NeighborView).est_troops
	var st := sim.st
	var prev: Array = memory.get(o, [])
	if prev.size() == 2 and st.tick - int(prev[1]) < 900:
		return float(prev[0])
	var my_density := st.o_troops[bot] / maxf(1.0, float(st.o_tiles[bot]))
	return float(st.o_tiles[o]) * my_density * (1.0 + rng.noise(noise * 2.0))


func _leaderboard() -> void:
	var st := sim.st
	var best := 0
	var second := 0
	var best_t := -1
	var second_t := -1
	var mine := st.o_tiles[bot]
	rank = 1
	alive_states = 0
	for o in range(1, st.owner_count + 1):
		if st.o_alive[o] == 0 or st.o_spawned[o] == 0 or st.o_kind[o] == Rules.KIND_TRIBE:
			continue
		alive_states += 1
		var tl := st.o_tiles[o]
		if o != bot and tl > mine:
			rank += 1
		if tl > best_t:
			second = best
			second_t = best_t
			best = o
			best_t = tl
		elif tl > second_t:
			second = o
			second_t = tl
	leader = 0
	leader_share = float(best_t) / maxf(1.0, float(st.map.land_count))
	if best != 0 and leader_share > 0.2 and float(best_t) > 1.6 * maxf(1.0, float(second_t)):
		leader = best


## Unclaimed land reachable from our free contact (bounded flood fill).
func estimate_free_land(limit: int = 4000) -> int:
	var st := sim.st
	if free_tiles.is_empty():
		free_estimate = 0
		return 0
	var owner := st.owner
	var land := st.map.land
	var W := st.W
	var seen := {}
	var stack: Array[int] = []
	for t in free_tiles:
		if not seen.has(t):
			seen[t] = true
			stack.append(t)
	var count := 0
	while not stack.is_empty() and count < limit:
		var c: int = stack.pop_back()
		count += 1
		var x := c % W
		for nb: int in [c - 1 if x > 0 else -1, c + 1 if x < W - 1 else -1, c - W, c + W]:
			if nb >= 0 and nb < st.N and land[nb] == 1 and owner[nb] == 0 and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	free_estimate = count
	return count
