class_name AttackArrow
extends RefCounted
## Geometry of VolnaLabs' attack arrows (pure, no nodes): a gently bent quadratic curve from the
## attacker's side to the live front, drawn as a tapered body that is thin and rounded at the tail
## and widest just before a compact head with slightly swept-back barbs. The same points are kept
## for hit-testing, so hovering an arrow finds exactly what is drawn.

const SAMPLES := 18

## Visual kinds.
const LAND := "land"          ## the player's or a watched state's land attack
const LANDING := "landing"    ## land advance that started from a landing (sea → shore → inland)
const RETREAT := "retreat"    ## troops falling back (reversed, hollow, muted)
const OTHER := "other"        ## AI attacks not involving the player: thinner and quieter


## Points of a quadratic curve tail → head, bent sideways by `bend` × length (sign = side).
static func curve(tail: Vector2, head: Vector2, bend: float, samples: int = SAMPLES) -> PackedVector2Array:
	var d := head - tail
	var ctrl := (tail + head) * 0.5 + d.orthogonal() * bend
	var pts := PackedVector2Array()
	pts.resize(samples + 1)
	for i in samples + 1:
		var t := float(i) / float(samples)
		var a := tail.lerp(ctrl, t)
		var b := ctrl.lerp(head, t)
		pts[i] = a.lerp(b, t)
	return pts


## Closed outline: tapered body (w_tail → w_body) along `pts` up to the head base, then a head of
## length `head_len` and half-width `head_w` ending exactly at the last point.
static func outline(pts: PackedVector2Array, w_tail: float, w_body: float, head_len: float, head_w: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 2:
		return PackedVector2Array()
	var total := length(pts)
	if total <= 0.0001:
		return PackedVector2Array()
	head_len = minf(head_len, total * 0.6)
	var body_end := total - head_len
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var acc := 0.0
	var base := pts[n - 1]
	var base_dir := (pts[n - 1] - pts[n - 2]).normalized()
	for i in n:
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		if acc > body_end:
			# Interpolate the exact head base on this segment.
			var seg := pts[i].distance_to(pts[i - 1])
			var k := 1.0 - (acc - body_end) / maxf(seg, 0.0001)
			base = pts[i - 1].lerp(pts[i], k)
			base_dir = (pts[i] - pts[i - 1]).normalized()
			var nb := base_dir.orthogonal()
			left.append(base + nb * w_body)
			right.append(base - nb * w_body)
			break
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := dir.orthogonal()
		# Smooth taper: thin tail growing to the body width by ~60 % of the way.
		var t := clampf(acc / maxf(body_end * 0.6, 0.0001), 0.0, 1.0)
		var w := lerpf(w_tail, w_body, t * t * (3.0 - 2.0 * t))
		left.append(pts[i] + nrm * w)
		right.append(pts[i] - nrm * w)
	var nh := base_dir.orthogonal()
	var tip := pts[n - 1]
	var barb_back := base - base_dir * head_len * 0.18
	var poly := PackedVector2Array()
	poly.append_array(left)
	poly.append(barb_back + nh * head_w)
	poly.append(tip)
	poly.append(barb_back - nh * head_w)
	right.reverse()
	poly.append_array(right)
	return poly


static func length(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(1, pts.size()):
		s += pts[i].distance_to(pts[i - 1])
	return s


## Point at fraction `f` (0..1) of the curve's length.
static func point_at(pts: PackedVector2Array, f: float) -> Vector2:
	var total := length(pts) * clampf(f, 0.0, 1.0)
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if total <= seg:
			return pts[i - 1].lerp(pts[i], total / maxf(seg, 0.0001))
		total -= seg
	return pts[pts.size() - 1] if pts.size() > 0 else Vector2.ZERO


## Shortest distance from `p` to the polyline.
static func distance_to(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in range(1, pts.size()):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])))
	return best


## Body half-width in screen pixels for a troop count (log scale, bounded).
static func width_px(troops: float) -> float:
	return clampf(2.2 + log(1.0 + maxf(troops, 0.0)) * 0.42, 2.5, 7.5)
