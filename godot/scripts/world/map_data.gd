class_name MapData
extends RefCounted
## Static geography of one map: a W x H grid of tiles (tile i = y * W + x, no wrap, 4-neighbours in
## the order west, east, north, south — the same convention as RoWorld's WorldMap.luau).
## Built from a terrain image (docs/maps/MAP_SYSTEM.md) or from generator arrays; read-only after
## derive().

const RIVER_BIT := 16
const CODE_MASK := 15

var id: String = ""
var width: int = 0
var height: int = 0
var size: int = 0
var k_lin: float = 1.0

## Terrain code (bits 0-3) | river (bit 4).
var terrain: PackedByteArray
## Elevation 0-255 (rendering only).
var elevation: PackedByteArray
## 1 on contestable land (plains .. tundra).
var land: PackedByteArray
## 1 on contestable land 4-adjacent to water.
var coastal: PackedByteArray
## Water body id per water tile (0 on land); 1 = the largest body (the ocean).
var water_body: PackedInt32Array
var water_body_sizes: PackedInt32Array = PackedInt32Array([0])
## Landmass id per land tile (0 on water); sorted by size, 1 = the largest.
var landmass: PackedInt32Array
var landmass_sizes: PackedInt32Array = PackedInt32Array([0])
## The water body each coastal tile touches first (W, E, N, S), 0 elsewhere.
var coast_body: PackedInt32Array
var land_count: int = 0
var land_tiles: PackedInt32Array
var coast_tiles: PackedInt32Array
## water body id -> PackedInt32Array of coastal land tiles touching it.
var coast_by_body: Dictionary = {}
var terrain_hash: int = 0


static func from_image(img: Image, map_id: String = "", k: float = 1.0) -> MapData:
	var m := MapData.new()
	m.id = map_id
	m.k_lin = k
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	m.width = img.get_width()
	m.height = img.get_height()
	m.size = m.width * m.height
	var data := img.get_data()
	m.terrain = PackedByteArray()
	m.terrain.resize(m.size)
	m.elevation = PackedByteArray()
	m.elevation.resize(m.size)
	for i in m.size:
		m.terrain[i] = data[i * 3]
		m.elevation[i] = data[i * 3 + 1]
	m.derive()
	return m


static func from_arrays(map_id: String, w: int, h: int, terrain_bytes: PackedByteArray, elev: PackedByteArray, k: float = 1.0) -> MapData:
	var m := MapData.new()
	m.id = map_id
	m.k_lin = k
	m.width = w
	m.height = h
	m.size = w * h
	m.terrain = terrain_bytes
	m.elevation = elev
	m.derive()
	return m


## The terrain as an RGB8 image (the map file format).
func to_image() -> Image:
	var data := PackedByteArray()
	data.resize(size * 3)
	for i in size:
		data[i * 3] = terrain[i]
		data[i * 3 + 1] = elevation[i]
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data)


func code(t: int) -> int:
	return terrain[t] & CODE_MASK


func is_river(t: int) -> bool:
	return (terrain[t] & RIVER_BIT) != 0


func is_water_code(c: int) -> bool:
	return c <= Rules.T_LAKE


func x_of(t: int) -> int:
	return t % width


func y_of(t: int) -> int:
	return t / width


func tile_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return y * width + x


func dist2(a: int, b: int) -> int:
	var dx := (a % width) - (b % width)
	var dy := (a / width) - (b / width)
	return dx * dx + dy * dy


## Fills land, coastal, water bodies, landmasses, lists and the terrain hash.
func derive() -> void:
	var w := width
	var n := size
	land = PackedByteArray()
	land.resize(n)
	var water := PackedByteArray()
	water.resize(n)
	land_count = 0
	for i in n:
		var c := terrain[i] & CODE_MASK
		if c >= Rules.T_PLAINS and c <= Rules.T_TUNDRA:
			land[i] = 1
			land_count += 1
		elif c <= Rules.T_LAKE:
			water[i] = 1
	water_body = PackedInt32Array()
	water_body.resize(n)
	water_body_sizes = _label(water, water_body)
	landmass = PackedInt32Array()
	landmass.resize(n)
	landmass_sizes = _label(land, landmass)
	coastal = PackedByteArray()
	coastal.resize(n)
	coast_body = PackedInt32Array()
	coast_body.resize(n)
	land_tiles = PackedInt32Array()
	land_tiles.resize(land_count)
	var coast_list: Array[int] = []
	var by_body: Dictionary = {}
	var li := 0
	for i in n:
		if land[i] == 0:
			continue
		land_tiles[li] = i
		li += 1
		var x := i % w
		var b := 0
		if x > 0 and water[i - 1] == 1:
			b = water_body[i - 1]
		elif x < w - 1 and water[i + 1] == 1:
			b = water_body[i + 1]
		elif i >= w and water[i - w] == 1:
			b = water_body[i - w]
		elif i + w < n and water[i + w] == 1:
			b = water_body[i + w]
		if b > 0:
			coastal[i] = 1
			coast_body[i] = b
			coast_list.append(i)
			if not by_body.has(b):
				by_body[b] = []
			(by_body[b] as Array).append(i)
	coast_tiles = PackedInt32Array(coast_list)
	coast_by_body = {}
	for b: int in by_body:
		coast_by_body[b] = PackedInt32Array(by_body[b])
	terrain_hash = hash(terrain)


## 4-connected component labelling of mask==1 tiles; ids sorted by size (1 = largest).
## Returns sizes indexed by id (index 0 unused).
func _label(mask: PackedByteArray, out: PackedInt32Array) -> PackedInt32Array:
	var w := width
	var n := size
	var queue := PackedInt32Array()
	queue.resize(n)
	var raw_sizes: Array[int] = [0]
	var next_id := 1
	for start in n:
		if mask[start] == 0 or out[start] != 0:
			continue
		var head := 0
		var tail := 0
		queue[tail] = start
		tail += 1
		out[start] = next_id
		while head < tail:
			var t := queue[head]
			head += 1
			var x := t % w
			if x > 0:
				var q := t - 1
				if mask[q] == 1 and out[q] == 0:
					out[q] = next_id
					queue[tail] = q
					tail += 1
			if x < w - 1:
				var q := t + 1
				if mask[q] == 1 and out[q] == 0:
					out[q] = next_id
					queue[tail] = q
					tail += 1
			if t >= w:
				var q := t - w
				if mask[q] == 1 and out[q] == 0:
					out[q] = next_id
					queue[tail] = q
					tail += 1
			if t + w < n:
				var q := t + w
				if mask[q] == 1 and out[q] == 0:
					out[q] = next_id
					queue[tail] = q
					tail += 1
		raw_sizes.append(tail)
		next_id += 1
	# Relabel by size, largest first.
	var order: Array[int] = []
	for i in range(1, raw_sizes.size()):
		order.append(i)
	order.sort_custom(func(p: int, q: int) -> bool:
		return raw_sizes[p] > raw_sizes[q] or (raw_sizes[p] == raw_sizes[q] and p < q))
	var remap := PackedInt32Array()
	remap.resize(raw_sizes.size())
	var sizes := PackedInt32Array()
	sizes.resize(raw_sizes.size())
	for rank in order.size():
		remap[order[rank]] = rank + 1
		sizes[rank + 1] = raw_sizes[order[rank]]
	for i in n:
		var v := out[i]
		if v != 0:
			out[i] = remap[v]
	return sizes


## Number of landmasses holding at least `share` of all land.
func continent_count(share: float = 0.02) -> int:
	var c := 0
	for i in range(1, landmass_sizes.size()):
		if landmass_sizes[i] >= share * land_count:
			c += 1
	return c


func island_count(share: float = 0.02) -> int:
	return landmass_sizes.size() - 1 - continent_count(share)
