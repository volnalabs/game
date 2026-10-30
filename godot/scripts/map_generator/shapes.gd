class_name GenShapes
extends RefCounted
## Large-scale shape of a world: land masses ("blobs"), mountain ridges, inland seas and channels,
## in normalised coordinates (y in 0..1, x in 0..aspect, radii in units of the map height).
## Presets build a spec procedurally; fictional maps provide an authored spec
## (data/map_specs/*.json). rasterize() turns a spec into a low-resolution mass field.


## Procedural spec for a preset layout.
static func preset_spec(p: GenParams, rng: SimRng) -> Dictionary:
	var aspect := float(p.width) / float(p.height)
	var layout := p.layout()
	if layout == "random":
		layout = ["continents", "archipelago", "pangaea", "chains", "ring"][rng.below(5)]
	var spec := {"blobs": [], "ridges": [], "seas": [], "channels": []}
	match layout:
		"continents":
			_continents(spec, p, rng, aspect)
		"archipelago":
			_archipelago(spec, p, rng, aspect)
		"pangaea":
			_pangaea(spec, p, rng, aspect)
		"chains":
			_chains(spec, p, rng, aspect)
		"ring":
			_ring(spec, p, rng, aspect)
	_islands(spec, p.islands, rng, aspect, 0.015, 0.045)
	return spec


static func _blob(x: float, y: float, rx: float, ry: float, rot: float, w: float = 1.0) -> Dictionary:
	return {"x": x, "y": y, "rx": rx, "ry": ry, "rot": rot, "w": w}


static func _spread(n: int, rng: SimRng, aspect: float, margin: float, min_d: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for _try in n * 60:
		if pts.size() >= n:
			break
		var c := Vector2(rng.range_f(margin * aspect, (1.0 - margin) * aspect), rng.range_f(margin, 1.0 - margin))
		var ok := true
		for q in pts:
			if q.distance_to(c) < min_d:
				ok = false
				break
		if ok:
			pts.append(c)
	return pts


static func _continent_at(spec: Dictionary, c: Vector2, r: float, rng: SimRng) -> void:
	var blobs: Array = spec["blobs"]
	var rot := rng.range_f(0.0, PI)
	blobs.append(_blob(c.x, c.y, r * rng.range_f(0.8, 1.3), r * rng.range_f(0.6, 1.0), rot))
	var lobes := rng.range_i(2, 4)
	for _k in lobes:
		var ang := rng.range_f(0.0, TAU)
		var off := Vector2(cos(ang), sin(ang)) * r * rng.range_f(0.5, 0.9)
		blobs.append(_blob(c.x + off.x, c.y + off.y, r * rng.range_f(0.4, 0.7), r * rng.range_f(0.3, 0.55), rng.range_f(0.0, PI), 0.95))
	# A mountain range crossing the continent.
	var a := rng.range_f(0.0, PI)
	var d := Vector2(cos(a), sin(a)) * r * rng.range_f(0.5, 0.9)
	var mid := c + Vector2(-d.y, d.x) * rng.range_f(-0.3, 0.3)
	(spec["ridges"] as Array).append({"pts": [[c.x - d.x, c.y - d.y], [mid.x, mid.y], [c.x + d.x, c.y + d.y]], "w": 1.0, "width": 0.03})


static func _continents(spec: Dictionary, p: GenParams, rng: SimRng, aspect: float) -> void:
	var n := clampi(p.continents, 1, 8)
	var r := 0.2 * sqrt(3.0 / float(n)) * clampf(aspect / 2.0, 0.7, 1.3)
	var centres := _spread(n, rng, aspect, 0.16, r * 1.9)
	for c in centres:
		_continent_at(spec, c, r, rng)


static func _pangaea(spec: Dictionary, p: GenParams, rng: SimRng, aspect: float) -> void:
	var c := Vector2(aspect * 0.5 + rng.range_f(-0.1, 0.1), 0.5 + rng.range_f(-0.05, 0.05))
	var blobs: Array = spec["blobs"]
	blobs.append(_blob(c.x, c.y, 0.42 * clampf(aspect / 2.0, 0.8, 1.2), 0.3, rng.range_f(-0.3, 0.3)))
	for _k in rng.range_i(6, 9):
		var ang := rng.range_f(0.0, TAU)
		var off := Vector2(cos(ang) * 0.42 * aspect / 2.0, sin(ang) * 0.28)
		blobs.append(_blob(c.x + off.x, c.y + off.y, rng.range_f(0.12, 0.22), rng.range_f(0.08, 0.16), rng.range_f(0.0, PI), 0.95))
	for _k in 3:
		var a := rng.range_f(0.0, PI)
		var d := Vector2(cos(a), sin(a)) * rng.range_f(0.15, 0.3)
		var s := c + Vector2(rng.range_f(-0.2, 0.2), rng.range_f(-0.1, 0.1))
		(spec["ridges"] as Array).append({"pts": [[s.x - d.x, s.y - d.y], [s.x + d.x, s.y + d.y]], "w": 1.0, "width": 0.03})


static func _archipelago(spec: Dictionary, p: GenParams, rng: SimRng, aspect: float) -> void:
	var blobs: Array = spec["blobs"]
	for c in _spread(clampi(p.continents, 0, 4), rng, aspect, 0.2, 0.35):
		blobs.append(_blob(c.x, c.y, rng.range_f(0.08, 0.12), rng.range_f(0.06, 0.09), rng.range_f(0.0, PI)))
	for c in _spread(clampi(p.islands / 2, 4, 40), rng, aspect, 0.06, 0.12):
		blobs.append(_blob(c.x, c.y, rng.range_f(0.035, 0.07), rng.range_f(0.025, 0.05), rng.range_f(0.0, PI), 0.95))


static func _chains(spec: Dictionary, p: GenParams, rng: SimRng, aspect: float) -> void:
	var blobs: Array = spec["blobs"]
	for _c in clampi(p.continents, 2, 6):
		var a := Vector2(rng.range_f(0.1, 0.9) * aspect, rng.range_f(0.1, 0.9))
		var b := Vector2(rng.range_f(0.1, 0.9) * aspect, rng.range_f(0.1, 0.9))
		var ctrl := (a + b) * 0.5 + Vector2(rng.range_f(-0.3, 0.3), rng.range_f(-0.3, 0.3))
		var n := rng.range_i(7, 12)
		for i in n:
			var t := float(i) / float(n - 1)
			var q := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
			var r := rng.range_f(0.03, 0.065) * (1.2 - 0.5 * absf(t - 0.5))
			blobs.append(_blob(q.x, q.y, r * 1.3, r, rng.range_f(0.0, PI)))
		(spec["ridges"] as Array).append({"pts": [[a.x, a.y], [ctrl.x, ctrl.y], [b.x, b.y]], "w": 0.8, "width": 0.02})


static func _ring(spec: Dictionary, p: GenParams, rng: SimRng, aspect: float) -> void:
	var blobs: Array = spec["blobs"]
	var c := Vector2(aspect * 0.5, 0.5)
	var rx := 0.36 * aspect * 0.5 * 1.6
	var ry := 0.33
	var n := 22
	var gaps := clampi(p.continents, 0, 8)
	var gap_at := {}
	for _g in gaps:
		gap_at[rng.below(n)] = true
	for i in n:
		if gap_at.has(i):
			continue
		var ang := TAU * float(i) / float(n)
		var q := c + Vector2(cos(ang) * rx, sin(ang) * ry)
		blobs.append(_blob(q.x, q.y, rng.range_f(0.08, 0.11), rng.range_f(0.06, 0.09), ang + PI / 2.0))
	blobs.append(_blob(c.x, c.y, 0.07, 0.06, 0.0))
	var pts: Array = []
	for i in 13:
		var ang2 := TAU * float(i) / 12.0
		pts.append([c.x + cos(ang2) * rx, c.y + sin(ang2) * ry])
	(spec["ridges"] as Array).append({"pts": pts, "w": 0.8, "width": 0.025})


static func _islands(spec: Dictionary, n: int, rng: SimRng, aspect: float, rmin: float, rmax: float) -> void:
	var blobs: Array = spec["blobs"]
	for _i in clampi(n, 0, 200):
		var c := Vector2(rng.range_f(0.04, 0.96) * aspect, rng.range_f(0.06, 0.94))
		var r := rng.range_f(rmin, rmax)
		blobs.append(_blob(c.x, c.y, r * rng.range_f(0.8, 1.5), r, rng.range_f(0.0, PI), 0.9))


# ---------------------------------------------------------------------------------------------
# Rasterisation (low resolution)
# ---------------------------------------------------------------------------------------------

static func _falloff(d: float) -> float:
	return clampf((1.2 - d) / 0.7, 0.0, 1.0)


## Returns {"mass": PackedFloat32Array, "ridge": PackedFloat32Array} of lw x lh.
static func rasterize(spec: Dictionary, lw: int, lh: int, warp: FastNoiseLite, warp_amp: float) -> Dictionary:
	var mass := PackedFloat32Array()
	mass.resize(lw * lh)
	var ridge := PackedFloat32Array()
	ridge.resize(lw * lh)
	var scale := float(lh)
	# Domain warp offsets per low-res pixel (shared by every shape).
	var wx := PackedFloat32Array()
	wx.resize(lw * lh)
	var wy := PackedFloat32Array()
	wy.resize(lw * lh)
	for y in lh:
		for x in lw:
			var i := y * lw + x
			wx[i] = warp.get_noise_2d(x, y) * warp_amp
			wy[i] = warp.get_noise_2d(x + 913.0, y - 377.0) * warp_amp
	for b: Dictionary in spec.get("blobs", []):
		_stamp_ellipse(mass, wx, wy, lw, lh, scale, b, true)
	for s: Dictionary in spec.get("seas", []):
		_stamp_ellipse(mass, wx, wy, lw, lh, scale, s, false)
	for r: Dictionary in spec.get("ridges", []):
		_stamp_line(ridge, lw, lh, scale, r["pts"], float(r.get("width", 0.03)), float(r.get("w", 1.0)), true)
	for c: Dictionary in spec.get("channels", []):
		_stamp_line(mass, lw, lh, scale, c["pts"], float(c.get("width", 0.01)), 0.0, false)
	return {"mass": mass, "ridge": ridge}


static func _stamp_ellipse(field: PackedFloat32Array, wx: PackedFloat32Array, wy: PackedFloat32Array,
		lw: int, lh: int, scale: float, b: Dictionary, add: bool) -> void:
	var cx := float(b["x"]) * scale
	var cy := float(b["y"]) * scale
	var rx := maxf(float(b["rx"]) * scale, 1.0)
	var ry := maxf(float(b["ry"]) * scale, 1.0)
	var rot := float(b.get("rot", 0.0))
	var w := float(b.get("w", 1.0))
	var cs := cos(rot)
	var sn := sin(rot)
	var ext := maxf(rx, ry) * 1.3 + 8.0
	var x0 := maxi(0, int(cx - ext))
	var x1 := mini(lw - 1, int(cx + ext))
	var y0 := maxi(0, int(cy - ext))
	var y1 := mini(lh - 1, int(cy + ext))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * lw + x
			var px := float(x) + wx[i] - cx
			var py := float(y) + wy[i] - cy
			var u := (px * cs + py * sn) / rx
			var v := (-px * sn + py * cs) / ry
			var f := _falloff(sqrt(u * u + v * v)) * w
			if add:
				if f > field[i]:
					field[i] = f
			elif f > 0.0:
				field[i] -= f * 1.2


static func _stamp_line(field: PackedFloat32Array, lw: int, lh: int, scale: float, pts: Array, width: float,
		w: float, add: bool) -> void:
	var rad := maxf(width * scale, 1.0)
	for k in range(pts.size() - 1):
		var a := Vector2(float(pts[k][0]), float(pts[k][1])) * scale
		var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][1])) * scale
		var x0 := maxi(0, int(minf(a.x, b.x) - rad * 2.0))
		var x1 := mini(lw - 1, int(maxf(a.x, b.x) + rad * 2.0))
		var y0 := maxi(0, int(minf(a.y, b.y) - rad * 2.0))
		var y1 := mini(lh - 1, int(maxf(a.y, b.y) + rad * 2.0))
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.0001)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var pnt := Vector2(x, y)
				var t := clampf((pnt - a).dot(ab) / len2, 0.0, 1.0)
				var d := pnt.distance_to(a + ab * t) / rad
				var i := y * lw + x
				if add:
					var f := clampf(1.0 - d * 0.5, 0.0, 1.0) * w
					if f > field[i]:
						field[i] = f
				elif d < 1.0:
					field[i] = minf(field[i], -0.4)
