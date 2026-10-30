class_name WaterNav
extends RefCounted
## Water pathfinding for transports: a coarse grid of CELL x CELL cells (each cell keeps the water
## body most of its water belongs to and a representative water tile), A* over 8-connected cells,
## then line-of-sight smoothing on the real tiles. A simplified take on RoWorld's SimNav.luau
## (hierarchical region graph); built once per map and shared.

static var _shared: Dictionary = {}

var map: MapData
var cell: int = 8
var cw: int = 0
var ch: int = 0
var c_body: PackedInt32Array
var c_rep: PackedInt32Array


static func for_map(m: MapData, cell_size: int = 8) -> WaterNav:
	var key := "%s:%d:%d" % [m.id, m.terrain_hash, cell_size]
	if not _shared.has(key):
		var nav := WaterNav.new()
		nav._build(m, cell_size)
		_shared[key] = nav
	return _shared[key]


func _build(m: MapData, cell_size: int) -> void:
	map = m
	cell = cell_size
	cw = ceili(float(m.width) / cell)
	ch = ceili(float(m.height) / cell)
	c_body = PackedInt32Array()
	c_body.resize(cw * ch)
	c_rep = PackedInt32Array()
	c_rep.resize(cw * ch)
	c_rep.fill(-1)
	var W := m.width
	for cy in ch:
		for cx in cw:
			var counts := {}
			var best_body := 0
			var best_n := 0
			var x0 := cx * cell
			var y0 := cy * cell
			for y in range(y0, mini(y0 + cell, m.height)):
				for x in range(x0, mini(x0 + cell, W)):
					var b := m.water_body[y * W + x]
					if b == 0:
						continue
					var c: int = counts.get(b, 0) + 1
					counts[b] = c
					if c > best_n:
						best_n = c
						best_body = b
			var ci := cy * cw + cx
			c_body[ci] = best_body
			if best_body == 0:
				continue
			# Representative: the tile of that body closest to the cell centre.
			var mx := x0 + cell / 2
			var my := y0 + cell / 2
			var bd := 1 << 30
			for y in range(y0, mini(y0 + cell, m.height)):
				for x in range(x0, mini(x0 + cell, W)):
					var t := y * W + x
					if m.water_body[t] == best_body:
						var d := (x - mx) * (x - mx) + (y - my) * (y - my)
						if d < bd:
							bd = d
							c_rep[ci] = t


func _cell_of(t: int) -> int:
	return ((t / map.width) / cell) * cw + (t % map.width) / cell


## Path of tile positions from water tile `from_t` to water tile `to_t` (same water body), or an
## empty array when unreachable.
func find_path(from_t: int, to_t: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var body := map.water_body[from_t]
	if body == 0 or body != map.water_body[to_t]:
		return out
	var start := _cell_of(from_t)
	var goal := _cell_of(to_t)
	var cells := PackedInt32Array()
	if start != goal:
		cells = _astar(start, goal, body)
		if cells.is_empty():
			return out
	var pts: Array[int] = [from_t]
	for i in range(1, cells.size() - 1):
		pts.append(c_rep[cells[i]])
	pts.append(to_t)
	# Line-of-sight smoothing.
	var i := 0
	out.append(_pos(pts[0]))
	while i < pts.size() - 1:
		var j := mini(pts.size() - 1, i + 24)
		while j > i + 1 and not _los(pts[i], pts[j], body):
			j -= 1
		out.append(_pos(pts[j]))
		i = j
	return out


func _pos(t: int) -> Vector2:
	return Vector2(t % map.width + 0.5, t / map.width + 0.5)


## Every tile on the segment belongs to the water body.
func _los(a: int, b: int, body: int) -> bool:
	var W := map.width
	var x0 := a % W
	var y0 := a / W
	var x1 := b % W
	var y1 := b / W
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	if steps == 0:
		return true
	for s in range(1, steps):
		var x := roundi(lerpf(x0, x1, float(s) / steps))
		var y := roundi(lerpf(y0, y1, float(s) / steps))
		if map.water_body[y * W + x] != body:
			return false
	return true


func _astar(start: int, goal: int, body: int) -> PackedInt32Array:
	var n := cw * ch
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var open := FrontQueue.new()
	var gx := goal % cw
	var gy := goal / cw
	g[start] = 0.0
	open.push(0.0, start)
	var found := false
	while not open.is_empty():
		var c := open.pop()
		if closed[c] == 1:
			continue
		closed[c] = 1
		if c == goal:
			found = true
			break
		var cx := c % cw
		var cy := c / cw
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
					continue
				var nc: int = ny * cw + nx
				if closed[nc] == 1 or c_body[nc] != body:
					continue
				var step := 1.4142 if dx != 0 and dy != 0 else 1.0
				var ng := g[c] + step
				if ng < g[nc]:
					g[nc] = ng
					came[nc] = c
					var hx := absi(nx - gx)
					var hy := absi(ny - gy)
					var h := float(maxi(hx, hy)) + 0.4142 * float(mini(hx, hy))
					open.push(ng + h * 1.2, nc)
	if not found:
		return PackedInt32Array()
	var rev: Array[int] = []
	var c := goal
	while c >= 0:
		rev.append(c)
		if c == start:
			break
		c = came[c]
	rev.reverse()
	return PackedInt32Array(rev)
