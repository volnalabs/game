class_name EffectsLayer
extends Node2D
## Everything that moves on the map, all read from the simulation (nothing invented):
## - attack arrows (AttackArrow): gently curved, tapered arrows from the attacker's side to the live
##   front (smoothed position of the tiles the attack is capturing), width by troops committed, a
##   light pulse travelling along the player's arrows; landings start at their beach, retreats are
##   reversed and hollow, other states' attacks are thinner and quieter; finished attacks fade out;
##   hovering an arrow is answered by pick_arrow() (who, from where, where, troops, kind, state);
## - capture sparks where an attack takes tiles, loss floaters (attacker and defender losses per
##   second for attacks involving the player or the selected state);
## - transports at sea with their route, landing markers;
## - markers for destroyed / captured buildings and retreats, rings for spawns, eliminations,
##   completed buildings.
## Counts are capped so effects never cost more than the map itself.

const MAX_ARROWS := 80
const MAX_FLOATERS := 40
const MAX_SPARKS := 200
const FLOAT_SECS := 1.6
const MARK_SECS := 2.4

var sim: Sim
var cam: MapCamera
var rings: Array = []
## SpawnAdvisor analyses of the tile under the cursor and of the chosen start.
var spawn_hover: Dictionary = {}
var spawn_pending: Dictionary = {}
## Owner whose attacks are emphasised besides the player's (selected state).
var focus_owner: int = 0
## Effects quality 0..2 (Settings); 0 keeps arrows and markers only.
var quality: int = 2
## attack id -> {"p": Vector2 front, "lost": float, "killed": float, "acc": float, "last": int, "spark": float}
var _fronts: Dictionary = {}
var _floaters: Array = []
var _marks: Array = []
var _sparks: Array = []
var _font: Font
## Equipped capture effect of the player ({} = default): {"color", "rainbow", "style"}.
var player_capture: Dictionary = {}
var _boat_prev: Dictionary = {}
## Arrows drawn this frame: attack id -> {"pts": PackedVector2Array (tiles), "w": half-width (tiles)}.
var arrows: Dictionary = {}
## Attack whose arrow is under the cursor (drawn slightly brighter and wider), -1 = none.
var hovered_arrow: int = -1
## Arrows of finished attacks fading out: {"pts", "c", "w", "t", "hollow"}.
var _fading: Array = []
const FADE_SECS := 0.6
var _boat_dir: Dictionary = {}


func _ready() -> void:
	_font = UITheme.theme().default_font if UITheme.theme().default_font != null else ThemeDB.fallback_font


func _c(t: int) -> Vector2:
	var W := sim.map.width
	return Vector2(t % W + 0.5, t / W + 0.5)


func ring(tile: int, color: Color, radius: float = 12.0) -> void:
	rings.append({"pos": _c(tile), "c": color, "r": radius, "t": 0.0})


## Icon marker that rises and fades at a tile (destroyed building, retreat, landing...).
func mark(tile: int, icon: String, color: Color) -> void:
	if _marks.size() > 40:
		_marks.pop_front()
	_marks.append({"pos": _c(tile), "icon": icon, "c": color, "t": 0.0})


func floater(pos: Vector2, text: String, color: Color) -> void:
	if _floaters.size() >= MAX_FLOATERS:
		_floaters.pop_front()
	_floaters.append({"pos": pos, "text": text, "c": color, "t": 0.0})


## Visual reaction to a simulation event (called by the match controller for every event).
func on_event(e: Dictionary) -> void:
	var st := sim.st
	match String(e["type"]):
		SimEvents.STRUCT_DESTROYED:
			mark(int(e["tile"]), "g_explosion", UITheme.BAD)
			ring(int(e["tile"]), Color("#ff9a4a"), 9.0)
		SimEvents.STRUCT_CAPTURED:
			mark(int(e["tile"]), "b_" + sim.rules.b_ids[int(e["kind"])], st.o_color[int(e["to"])].lightened(0.3))
		SimEvents.ATTACK_RETREAT:
			var f: Dictionary = _fronts.get(int(e["id"]), {})
			if not f.is_empty():
				var p: Vector2 = f["p"]
				mark(sim.map.tile_at(int(p.x), int(p.y)), "ui_back", st.o_color[int(e["attacker"])].lightened(0.3))
		SimEvents.BOAT_LANDED, SimEvents.BOAT_FAILED:
			_boat_prev.erase(int(e["id"]))
			_boat_dir.erase(int(e["id"]))
			if not e.has("tile"):
				return
			mark(int(e["tile"]), "g_landing", st.o_color[int(e["owner"])].lightened(0.3))
		SimEvents.ATTACK_ENDED:
			var aid := int(e["id"])
			if arrows.has(aid) and _fading.size() < 24:
				var ar: Dictionary = arrows[aid]
				_fading.append({"pts": ar["pts"], "c": ar["c"], "w": ar["w"], "t": 0.0, "hollow": ar["hollow"]})
			_fronts.erase(aid)
			arrows.erase(aid)


func _process(delta: float) -> void:
	for r: Dictionary in rings:
		r["t"] = float(r["t"]) + delta
	rings = rings.filter(func(r: Dictionary) -> bool: return float(r["t"]) < 1.2)
	for f: Dictionary in _floaters:
		f["t"] = float(f["t"]) + delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return float(f["t"]) < FLOAT_SECS)
	for m: Dictionary in _marks:
		m["t"] = float(m["t"]) + delta
	_marks = _marks.filter(func(m: Dictionary) -> bool: return float(m["t"]) < MARK_SECS)
	for s: Dictionary in _sparks:
		s["t"] = float(s["t"]) + delta
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return float(s["t"]) < 0.5)
	for f: Dictionary in _fading:
		f["t"] = float(f["t"]) + delta
	_fading = _fading.filter(func(f: Dictionary) -> bool: return float(f["t"]) < FADE_SECS)
	if sim != null:
		_track_fronts(delta)
	queue_redraw()


func _involved(a: AttackSystem.Attack) -> bool:
	var pid := sim.player_id
	return a.attacker == pid or a.target == pid or (focus_owner > 0 and (a.attacker == focus_owner or a.target == focus_owner))


## Follows each attack's front and turns its losses into floaters once a second.
func _track_fronts(delta: float) -> void:
	var pid := sim.player_id
	for a in sim.attacks.attacks:
		if not a.alive:
			continue
		var f: Dictionary = _fronts.get(a.id, {})
		if f.is_empty():
			if a.last_tile < 0:
				continue
			f = {"p": _c(a.last_tile), "lost": a.lost, "killed": a.killed, "acc": 0.0, "last": a.last_tile, "spark": 0.0,
				"origin": _c(a.last_tile), "tail": Vector2.INF}
			_fronts[a.id] = f
		if a.last_tile >= 0:
			var k := 1.0 - exp(-delta * 3.0)
			f["p"] = (f["p"] as Vector2).lerp(_c(a.last_tile), k)
			f["spark"] = float(f["spark"]) - delta
			if a.last_tile != int(f["last"]) and float(f["spark"]) <= 0.0 and quality > 0 and _sparks.size() < MAX_SPARKS:
				var sc: Color = sim.st.o_color[a.attacker].lightened(0.5)
				var ring_style := false
				if a.attacker == sim.player_id and not player_capture.is_empty():
					sc = Color.from_hsv(fmod(Time.get_ticks_msec() / 1500.0, 1.0), 0.6, 1.0) if player_capture["rainbow"] else player_capture["color"]
					ring_style = player_capture["style"] == "rings"
				_sparks.append({"pos": _c(a.last_tile), "c": sc, "t": 0.0, "ring": ring_style})
				f["spark"] = 0.12
			f["last"] = a.last_tile
		f["acc"] = float(f["acc"]) + delta
		if float(f["acc"]) >= 1.0:
			f["acc"] = 0.0
			var dl := a.lost - float(f["lost"])
			var dk := a.killed - float(f["killed"])
			f["lost"] = a.lost
			f["killed"] = a.killed
			if quality > 0 and _involved(a):
				var p: Vector2 = f["p"]
				if dl >= 1.0:
					floater(p + Vector2(-26, 10) / cam.zoom.x, "-" + UITheme.num(dl), UITheme.BAD if a.attacker == pid else sim.st.o_color[a.attacker].lightened(0.4))
				if dk >= 1.0 and a.target > 0:
					floater(p + Vector2(26, -14) / cam.zoom.x, "-" + UITheme.num(dk), UITheme.BAD if a.target == pid else sim.st.o_color[a.target].lightened(0.4))


func _draw() -> void:
	if sim == null:
		return
	var z := cam.zoom.x
	var view := cam.visible_rect().grow(8)
	_draw_arrows(z, view)
	for s: Dictionary in _sparks:
		var k := float(s["t"]) / 0.5
		var sz := maxf(0.6, 3.0 / z) * (1.0 + k)
		if s.get("ring", false):
			draw_arc(s["pos"], sz * 1.4, 0.0, TAU, 16, Color(s["c"], 1.0 - k), maxf(0.15, 1.2 / z))
		else:
			draw_rect(Rect2(s["pos"] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(s["c"], 1.0 - k))
	for b in sim.naval.boats:
		if not b.alive:
			continue
		var p := b.position()
		if not p.is_finite() or not view.has_point(p):
			continue
		var c: Color = sim.st.o_color[b.owner]
		var s := clampf(6.0 / z, 0.8, 8.0)
		var prev: Vector2 = _boat_prev.get(b.id, p)
		var dir: Vector2 = _boat_dir.get(b.id, Vector2.RIGHT)
		if p.distance_squared_to(prev) > 0.0001:
			dir = (p - prev).normalized()
			_boat_dir[b.id] = dir
		_boat_prev[b.id] = p
		var n := dir.orthogonal()
		var pts := PackedVector2Array([p + dir * s * 1.4, p - dir * s + n * s * 0.8, p - dir * s - n * s * 0.8])
		draw_colored_polygon(pts, c)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.8), maxf(0.15, 1.0 / z))
		if (b.owner == sim.player_id or sim.st.owner[b.target_tile] == sim.player_id) and b.path.size() > 1:
			draw_line(p, b.path[b.path.size() - 1], Color(c, 0.35), maxf(0.2, 1.2 / z))
	if sim.phase == Sim.Phase.SPAWN:
		if not spawn_pending.is_empty():
			_draw_spawn(spawn_pending, z, true)
		if not spawn_hover.is_empty() and int(spawn_hover["tile"]) != int(spawn_pending.get("tile", -1)):
			_draw_spawn(spawn_hover, z, false)
	for r: Dictionary in rings:
		var k := float(r["t"]) / 1.2
		var c2: Color = r["c"]
		draw_arc(r["pos"], float(r["r"]) * (0.3 + k), 0.0, TAU, 32, Color(c2, 1.0 - k), maxf(0.3, 2.0 / z))
	for m: Dictionary in _marks:
		var k := float(m["t"]) / MARK_SECS
		var ir := clampf(10.0 / z, 0.8, 14.0)
		var pos: Vector2 = m["pos"] - Vector2(0, k * 12.0 / z)
		var tex := Icons.tex(String(m["icon"]), maxi(16, int(ir * z * 2.0)))
		if tex != null:
			draw_texture_rect(tex, Rect2(pos - Vector2(ir, ir) * 0.8, Vector2(ir, ir) * 1.6), false, Color(m["c"], 1.0 - k * k))
	for f: Dictionary in _floaters:
		var k := float(f["t"]) / FLOAT_SECS
		var pos: Vector2 = f["pos"] - Vector2(0, k * 18.0 / z)
		draw_set_transform(pos, 0.0, Vector2(1.0 / z, 1.0 / z))
		var col: Color = f["c"]
		draw_string_outline(_font, Vector2.ZERO, String(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, 4, Color(0, 0, 0, 0.8 * (1.0 - k)))
		draw_string(_font, Vector2.ZERO, String(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(col, 1.0 - k * k))
		draw_set_transform(Vector2.ZERO)


## Start preview: claimed land (exactly the tiles the spawn takes), reachable free land, the
## nearest states with lines coloured by how close they are.
func _draw_spawn(info: Dictionary, z: float, chosen: bool) -> void:
	var t: int = info["tile"]
	var hp := _c(t)
	var ok := String(info["reason"]) == ""
	var c := UITheme.GOOD if ok else UITheme.BAD
	var lw := maxf(0.2, 2.0 / z)
	if ok:
		var pc: Color = sim.st.o_color[sim.player_id]
		var a := 0.3 if chosen else 0.18
		for r in info["reach"]:
			draw_rect(Rect2(Vector2(r % sim.map.width, r / sim.map.width), Vector2.ONE), Color(UITheme.ACCENT, a))
		for r in info["claim"]:
			draw_rect(Rect2(Vector2(r % sim.map.width, r / sim.map.width), Vector2.ONE), Color(pc, 0.75 if chosen else 0.5))
		for n: Dictionary in info["neighbours"]:
			var np := sim.st.centroid(int(n["id"]))
			var k := clampf(1.0 - float(n["dist"]) / SpawnAdvisor.NEAR_RADIUS, 0.0, 1.0)
			var lc := UITheme.GOOD.lerp(UITheme.BAD, k)
			if hp.distance_to(np) > 1.0:
				draw_dashed_line(hp, np, Color(lc, 0.55), lw * 0.7, maxf(1.0, 6.0 / z))
	var rad := sim.rules.spawn_radius + 0.5
	draw_arc(hp, rad, 0.0, TAU, 32, c, lw)
	if chosen:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		draw_arc(hp, rad * (1.4 + 0.3 * pulse), 0.0, TAU, 40, Color(c, 0.4 + 0.4 * pulse), lw)
		var tex := Icons.tex("g_capital", maxi(16, int(rad * z)))
		if tex != null:
			draw_texture_rect(tex, Rect2(hp - Vector2(rad, rad) * 0.5, Vector2(rad, rad)), false, Color.WHITE)


## Tail of an arrow: a landing starts at its beach; a land attack starts inside the attacker's
## land, `length` tiles back from the front towards the attacker's centre.
func _tail_for(a: AttackSystem.Attack, f: Dictionary, head: Vector2, length: float) -> Vector2:
	if a.landing:
		var o: Vector2 = f["origin"]
		if o.distance_to(head) > length * 0.35:
			return o
		var away := (head - o).normalized() if head.distance_to(o) > 0.01 else Vector2.RIGHT
		return head - away * length * 0.35
	var from := sim.st.centroid(a.attacker)
	var dir := head - from
	if not dir.is_finite() or dir.length() < 0.5:
		return Vector2.INF
	return head - dir.normalized() * minf(length, dir.length())


## Visual kind of an attack's arrow.
func arrow_kind(a: AttackSystem.Attack) -> String:
	if a.retreat_at > 0:
		return AttackArrow.RETREAT
	if a.landing:
		return AttackArrow.LANDING
	return AttackArrow.LAND if _involved(a) else AttackArrow.OTHER


func _draw_arrows(z: float, view: Rect2) -> void:
	arrows.clear()
	var pid := sim.player_id
	var n := 0
	var now := Time.get_ticks_msec() / 1000.0
	var k_smooth := 1.0 - exp(-get_process_delta_time() * 4.0)
	for a in sim.attacks.attacks:
		# Expansion into unclaimed land grows in every direction: no arrow (except landings).
		if not a.alive or (a.target <= 0 and not a.landing):
			continue
		var f: Dictionary = _fronts.get(a.id, {})
		if f.is_empty():
			continue
		var head: Vector2 = f["p"]
		if not view.has_point(head):
			continue
		var kind := arrow_kind(a)
		if kind == AttackArrow.OTHER and z < 1.2:
			continue
		var length := clampf(110.0 / z, 7.0, 46.0)
		var want := _tail_for(a, f, head, length)
		if not want.is_finite():
			continue
		# The tail follows smoothly, so turning fronts bend the arrow instead of snapping it.
		var tail: Vector2 = f["tail"]
		tail = want if not tail.is_finite() else tail.lerp(want, k_smooth)
		f["tail"] = tail
		if tail.distance_to(head) < 2.0 / z:
			continue
		var bend := 0.16 if a.id % 2 == 0 else -0.16
		var w := AttackArrow.width_px(a.troops) / z
		var col: Color = sim.st.o_color[a.attacker].lightened(0.3)
		var alpha := 0.95
		var hollow := false
		var pts: PackedVector2Array
		match kind:
			AttackArrow.RETREAT:
				# Falling back: the arrow points home, muted and hollow.
				pts = AttackArrow.curve(head, tail, bend)
				col = col.lerp(Color("#b5aea3"), 0.5)
				alpha = 0.75
				hollow = true
				w *= 0.8
			AttackArrow.OTHER:
				pts = AttackArrow.curve(tail, head, bend)
				alpha = 0.55
				w *= 0.7
			_:
				pts = AttackArrow.curve(tail, head, bend)
		if a.id == hovered_arrow:
			w *= 1.2
			alpha = 1.0
			col = col.lightened(0.15)
		_draw_one(pts, w, Color(col, alpha), z, hollow, kind == AttackArrow.LAND and a.attacker == pid, now + a.id * 0.37)
		if kind == AttackArrow.LANDING:
			_landing_mark(pts[0], col, z)
		if a.target == pid and kind != AttackArrow.RETREAT:
			var pulse := 0.5 + 0.5 * sin(now * 7.0)
			draw_arc(head, w * 3.6, 0.0, TAU, 28, Color(UITheme.BAD, 0.35 + 0.45 * pulse), maxf(0.12, 1.4 / z))
		arrows[a.id] = {"pts": pts, "w": w, "c": Color(col, alpha), "hollow": hollow}
		n += 1
		if n >= MAX_ARROWS:
			break
	for fd: Dictionary in _fading:
		var k := 1.0 - float(fd["t"]) / FADE_SECS
		var c: Color = fd["c"]
		_draw_one(fd["pts"], fd["w"], Color(c, c.a * k * k), z, fd["hollow"], false, 0.0)


## One arrow: a soft dark under-stroke for contrast, the filled (or hollow) tapered shape and, for
## the player's own advances, a light pulse travelling from tail to head.
func _draw_one(pts: PackedVector2Array, w: float, col: Color, z: float, hollow: bool, flow: bool, phase: float) -> void:
	var poly := AttackArrow.outline(pts, w * 0.35, w, w * 3.4, w * 2.3)
	if poly.size() < 3:
		return
	var edge := Color(0.08, 0.07, 0.06, 0.55 * col.a)
	var closed := poly.duplicate()
	closed.append(poly[0])
	if hollow:
		draw_colored_polygon(poly, Color(col, col.a * 0.22))
		draw_polyline(closed, col, maxf(0.12, 1.6 / z), true)
		return
	draw_polyline(closed, edge, maxf(0.15, 2.4 / z), true)
	draw_colored_polygon(poly, col)
	if flow:
		var t := fmod(phase * 0.6, 1.0)
		var p := AttackArrow.point_at(pts, t * 0.82)
		draw_circle(p, w * 0.55, Color(1, 1, 1, 0.45 * sin(t * PI)))


## Small anchor-like marker where a landing came ashore.
func _landing_mark(p: Vector2, col: Color, z: float) -> void:
	var r := maxf(0.5, 5.0 / z)
	draw_circle(p, r * 1.25, Color(0.08, 0.07, 0.06, 0.7))
	draw_circle(p, r, col)
	draw_arc(p, r * 0.45, 0.0, TAU, 12, Color(0.08, 0.07, 0.06, 0.8), maxf(0.1, 1.2 / z))


## Attack whose arrow lies under a screen position (within its width plus a margin), or -1.
func pick_arrow(screen_pos: Vector2) -> int:
	if cam == null:
		return -1
	var p := cam.get_canvas_transform().affine_inverse() * screen_pos
	var best := -1
	var bd := INF
	for aid: int in arrows:
		var ar: Dictionary = arrows[aid]
		var d := AttackArrow.distance_to(ar["pts"], p)
		var lim := float(ar["w"]) * 1.6 + 4.0 / cam.zoom.x
		if d <= lim and d < bd:
			bd = d
			best = aid
	return best


## Hover card of an attack: who, from where, to where, troops, kind and state.
func arrow_info(aid: int) -> Dictionary:
	var a := sim.attacks.get_by_id(aid)
	if a == null:
		return {}
	var st := sim.st
	var kind := arrow_kind(a)
	var kind_txt := tr("ARROW_KIND_LANDING") if a.landing else tr("ARROW_KIND_LAND")
	var state := tr("ARROW_STATE_RETREAT") if kind == AttackArrow.RETREAT else tr("ARROW_STATE_ADVANCE")
	return {"title": tr("ARROW_TITLE") % [st.o_name[a.attacker], st.o_name[a.target] if a.target > 0 else tr("ARROW_NEUTRAL")],
		"text": kind_txt,
		"rows": [[tr("ARROW_FROM"), st.o_name[a.attacker]], [tr("ARROW_TO"), st.o_name[a.target] if a.target > 0 else tr("ARROW_NEUTRAL")],
			[tr("ARROW_TROOPS"), UITheme.num(a.troops)], [tr("ARROW_STATE"), state]]}
