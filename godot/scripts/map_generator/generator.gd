class_name MapGenerator
extends RefCounted
## Procedural worlds (docs/maps/MAP_SYSTEM.md §3). Deterministic: the same GenParams (seed
## included) produce the same terrain bytes. Pipeline: land-mass shapes (preset or authored spec)
## at low resolution -> upscale + coastline noise -> sea level by quantile -> symmetry -> mountains,
## climate -> inland seas -> rivers -> cleanup (tiny islands / lakes) -> shallows -> start positions.

const LOW := 4


class GenResult:
	extends RefCounted
	var params: GenParams
	var map: MapData
	var starts: PackedInt32Array = PackedInt32Array()
	var nations: Array = []
	var stats: Dictionary = {}


func generate(p: GenParams) -> GenResult:
	var t0 := Time.get_ticks_msec()
	var rng := SimRng.new(p.seed)
	var W := p.width
	var H := p.height
	var N := W * H
	var spec := p.spec.duplicate(true) if not p.spec.is_empty() else GenShapes.preset_spec(p, rng.fork(1))
	if spec.has("random_islands"):
		var ri: Dictionary = spec["random_islands"]
		GenShapes._islands(spec, int(ri.get("count", 0)), rng.fork(6), float(W) / float(H),
			float(ri.get("rmin", 0.012)), float(ri.get("rmax", 0.035)))
	var lw := ceili(float(W) / LOW)
	var lh := ceili(float(H) / LOW)
	var warp := _noise(p.seed + 11, 0.012, 3)
	var fields := GenShapes.rasterize(spec, lw, lh, warp, 22.0 * clampf(p.roughness * 1.4, 0.3, 1.5))
	var mass := _upscale(fields["mass"], lw, lh, W, H)
	var ridge := _upscale(fields["ridge"], lw, lh, W, H)
	# Ridged noise adds secondary mountain chains everywhere.
	var rn := _noise(p.seed + 23, 0.006, 4)
	rn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var ridged := _noise_bytes(rn, W, H)
	var moist := _noise_bytes(_noise(p.seed + 31, 0.004, 3), W, H)
	var detail := _noise_bytes(_noise(p.seed + 47, 0.02, 5), W, H)
	var h := PackedFloat32Array()
	h.resize(N)
	var rough := p.roughness * 0.45
	for i in N:
		# Coastline noise fades out in open ocean, so no specks of land appear far from any mass.
		var near := clampf(mass[i] * 3.0 - 0.05, 0.0, 1.0)
		h[i] = mass[i] * 0.8 + ((float(detail[i]) / 255.0 - 0.5) * rough + (float(ridged[i]) / 255.0 - 0.5) * 0.06) * near
	_symmetry(h, W, H, p.symmetry)
	_symmetry(ridge, W, H, p.symmetry)
	var sea := _quantile(h, 1.0 - clampf(p.land_percent, 0.05, 0.9))
	var hmax := sea + 0.0001
	for i in N:
		hmax = maxf(hmax, h[i])
	var terrain := PackedByteArray()
	terrain.resize(N)
	var elev := PackedByteArray()
	elev.resize(N)
	var desert_bias: float = p.climate.get("desert_bias", 0.0)
	var forest_bias: float = p.climate.get("forest_bias", 0.0)
	var cold_bias: float = p.climate.get("cold_bias", 0.0)
	var mt := p.mountains
	for i in N:
		var hv := h[i]
		if hv <= sea:
			terrain[i] = Rules.T_DEEP
			continue
		var e01 := clampf((hv - sea) / (hmax - sea) * 1.4, 0.0, 1.0)
		elev[i] = 40 + int(e01 * 215.0)
		var y := i / W
		var m := ridge[i] * mt * 1.1 + float(ridged[i]) / 255.0 * mt * 0.45 + e01 * 0.35
		if m > 0.86:
			terrain[i] = Rules.T_MOUNTAIN
			continue
		if m > 0.66:
			terrain[i] = Rules.T_HILLS
			continue
		var lat := absf(float(y) / float(H) - 0.5) * 2.0
		var temp := 1.0 - lat * 1.05 - e01 * 0.25 - cold_bias
		var mo := float(moist[i]) / 255.0
		if temp < 0.1:
			terrain[i] = Rules.T_TUNDRA
		elif mo < 0.36 + desert_bias and temp > 0.42 and lat > 0.12:
			terrain[i] = Rules.T_DESERT
		elif mo > 0.56 - forest_bias:
			terrain[i] = Rules.T_FOREST
		else:
			terrain[i] = Rules.T_PLAINS
	_inland_seas(terrain, h, W, H, p.inland_seas, rng.fork(2))
	_cleanup(terrain, W, H)
	_rivers(terrain, h, W, H, p.river_density, rng.fork(3))
	_shallows(terrain, W, H)
	var map := MapData.from_arrays("gen_%d" % p.seed, W, H, terrain, elev)
	var res := GenResult.new()
	res.params = p
	res.map = map
	var sp := StartPositions.pick(map, p.start_positions, rng.fork(4))
	res.starts = sp["starts"]
	var name_rng := rng.fork(5)
	for k in res.starts.size():
		var t := res.starts[k]
		res.nations.append({"id": "g%d" % k, "name": NameGen.make(name_rng), "flag": "", "x": t % W, "y": t / W})
	res.stats = {"land_tiles": map.land_count, "continents": map.continent_count(), "islands": map.island_count(),
		"fairness": sp["fairness"], "ms": Time.get_ticks_msec() - t0}
	return res


## A MapDefinition for a generated world (shown in setup screens, stored in saves).
static func definition_for(res: GenResult, name_ru: String = "Новый мир", name_en: String = "New world") -> MapDefinition:
	var d := MapDefinition.new()
	d.id = "generated"
	d.category = "generated"
	d.names = {"ru": name_ru, "en": name_en}
	d.descriptions = {"ru": "Процедурный мир «%s», seed %d." % [res.params.preset, res.params.seed],
		"en": "Procedural world '%s', seed %d." % [res.params.preset, res.params.seed]}
	d.width = res.map.width
	d.height = res.map.height
	d.nations = res.nations
	d.max_bots = res.nations.size()
	d.recommended_bots = Vector2i(maxi(2, res.nations.size() / 3), res.nations.size())
	d.stats = res.stats
	d.generator = res.params.to_dict()
	d.source = "VolnaLabs procedural generator"
	d.license = "AGPL-3.0"
	return d


# ---------------------------------------------------------------------------------------------

static func _noise(seed_value: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n


static func _noise_bytes(n: FastNoiseLite, w: int, h: int) -> PackedByteArray:
	var img := n.get_image(w, h, false, false, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _upscale(f: PackedFloat32Array, lw: int, lh: int, w: int, h: int) -> PackedFloat32Array:
	var img := Image.create_from_data(lw, lh, false, Image.FORMAT_RF, f.to_byte_array())
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return img.get_data().to_float32_array()


static func _quantile(h: PackedFloat32Array, q: float) -> float:
	var lo := INF
	var hi := -INF
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var bins := 4096
	var hist := PackedInt32Array()
	hist.resize(bins)
	var span := maxf(hi - lo, 0.0001)
	for v in h:
		hist[mini(bins - 1, int((v - lo) / span * bins))] += 1
	var want := int(q * h.size())
	var acc := 0
	for b in bins:
		acc += hist[b]
		if acc >= want:
			return lo + span * float(b + 1) / bins
	return hi


static func _symmetry(h: PackedFloat32Array, W: int, H: int, mode: String) -> void:
	match mode:
		"mirror":
			for y in H:
				for x in range(W / 2, W):
					h[y * W + x] = h[y * W + (W - 1 - x)]
		"rotate2":
			var n := W * H
			for i in range(n / 2, n):
				h[i] = h[n - 1 - i]
		"rotate4":
			for y in H:
				for x in W:
					var sx := x if x < W / 2 else W - 1 - x
					var sy := y if y < H / 2 else H - 1 - y
					h[y * W + x] = h[sy * W + sx]


func _inland_seas(terrain: PackedByteArray, h: PackedFloat32Array, W: int, H: int, count: int, rng: SimRng) -> void:
	for _s in clampi(count, 0, 6):
		# A point deep inside land: land in every direction for 40 tiles.
		var found := -1
		for _try in 400:
			var x := rng.range_i(40, W - 41)
			var y := rng.range_i(40, H - 41)
			var t := y * W + x
			if terrain[t] == Rules.T_DEEP or terrain[t] == Rules.T_MOUNTAIN:
				continue
			var ok := true
			for d in [Vector2i(40, 0), Vector2i(-40, 0), Vector2i(0, 40), Vector2i(0, -40)]:
				if terrain[(y + d.y) * W + x + d.x] == Rules.T_DEEP:
					ok = false
					break
			if ok:
				found = t
				break
		if found < 0:
			continue
		var cx := found % W
		var cy := found / W
		var rx := rng.range_f(14.0, 30.0)
		var ry := rng.range_f(9.0, 20.0)
		var rot := rng.range_f(0.0, PI)
		var cs := cos(rot)
		var sn := sin(rot)
		for y in range(maxi(0, cy - 40), mini(H, cy + 41)):
			for x in range(maxi(0, cx - 40), mini(W, cx + 41)):
				var px := float(x - cx)
				var py := float(y - cy)
				var u := (px * cs + py * sn) / rx
				var v := (-px * sn + py * cs) / ry
				var t2 := y * W + x
				if u * u + v * v + (h[t2] - 0.5) * 0.3 < 1.0:
					terrain[t2] = Rules.T_DEEP


## Removes islands under 30 tiles and enclosed lakes under 20 tiles; small enclosed seas become lakes.
func _cleanup(terrain: PackedByteArray, W: int, H: int) -> void:
	var tmp := MapData.new()
	tmp.width = W
	tmp.height = H
	tmp.size = W * H
	var n := W * H
	var land := PackedByteArray()
	land.resize(n)
	var water := PackedByteArray()
	water.resize(n)
	for i in n:
		if terrain[i] >= Rules.T_PLAINS:
			land[i] = 1
		else:
			water[i] = 1
	var lid := PackedInt32Array()
	lid.resize(n)
	var lsz := tmp._label(land, lid)
	var wid := PackedInt32Array()
	wid.resize(n)
	var wsz := tmp._label(water, wid)
	var edge := {}
	for x in W:
		edge[wid[x]] = true
		edge[wid[(H - 1) * W + x]] = true
	for y in H:
		edge[wid[y * W]] = true
		edge[wid[y * W + W - 1]] = true
	var lake_max := maxi(400, n / 300)
	for i in n:
		if land[i] == 1:
			if lsz[lid[i]] < 40:
				terrain[i] = Rules.T_DEEP
		else:
			var b := wid[i]
			if not edge.has(b):
				if wsz[b] < 20:
					terrain[i] = Rules.T_PLAINS
				elif wsz[b] < lake_max:
					terrain[i] = Rules.T_LAKE


func _rivers(terrain: PackedByteArray, h: PackedFloat32Array, W: int, H: int, density: float, rng: SimRng) -> void:
	var land_count := 0
	for b in terrain:
		if (b & MapData.CODE_MASK) >= Rules.T_PLAINS:
			land_count += 1
	var count := clampi(int(density * float(land_count) / 12000.0), 0, 90)
	var n := W * H
	for _r in count:
		var src := -1
		for _try in 300:
			var t := rng.below(n)
			var c := terrain[t] & MapData.CODE_MASK
			if c == Rules.T_HILLS or c == Rules.T_MOUNTAIN:
				src = t
				break
		if src < 0:
			return
		var path: Array[int] = []
		var cur := src
		var reached := false
		for _step in 700:
			path.append(cur)
			var x := cur % W
			var best := -1
			var bh := h[cur]
			for nb: int in [cur - 1 if x > 0 else -1, cur + 1 if x < W - 1 else -1, cur - W, cur + W]:
				if nb < 0 or nb >= n:
					continue
				if (terrain[nb] & MapData.CODE_MASK) <= Rules.T_LAKE:
					reached = true
					break
				if h[nb] < bh:
					bh = h[nb]
					best = nb
			if reached or best < 0:
				break
			cur = best
		if reached and path.size() >= 15:
			for t in path:
				var c2 := terrain[t] & MapData.CODE_MASK
				if c2 != Rules.T_MOUNTAIN:
					terrain[t] = c2 | MapData.RIVER_BIT


## Water within 2 tiles of land becomes shallow sea (lakes stay lakes).
func _shallows(terrain: PackedByteArray, W: int, H: int) -> void:
	var n := W * H
	var near := PackedByteArray()
	near.resize(n)
	for i in n:
		if (terrain[i] & MapData.CODE_MASK) >= Rules.T_PLAINS:
			near[i] = 2
	for pass_i in 2:
		var mark := 2 - pass_i
		var nxt := near.duplicate()
		for i in n:
			if near[i] != mark:
				continue
			var x := i % W
			for nb: int in [i - 1 if x > 0 else -1, i + 1 if x < W - 1 else -1, i - W, i + W]:
				if nb >= 0 and nb < n and near[nb] == 0:
					nxt[nb] = mark - 1 if mark > 1 else 1
		near = nxt
	for i in n:
		if terrain[i] == Rules.T_DEEP and near[i] > 0 and near[i] < 2:
			terrain[i] = Rules.T_SHALLOW
