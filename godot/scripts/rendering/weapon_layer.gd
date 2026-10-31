class_name WeaponLayer
extends Node2D
## Weapons on the map, all read from WeaponSystem (nothing invented):
##   aiming   — the blast zone at the cursor (inner ring for nukes, spread for cluster / MIRV), the
##              flight path from the chosen launcher, the SAM rings covering the target, a cross
##              when the launch is impossible, an amber edge when our own land is inside;
##   flight   — munitions turned along their course with a fading trail; the player's and incoming
##              ones show their remaining path; interceptors climb from their SAM to the munition;
##   impacts  — a blast ring and flash, an EMP pulse, a nuclear flash, fireball and shock wave, small
##              bursts for interceptions and misses.

const BLAST_SECS := 0.9
const NUKE_SECS := 3.2
const BURST_SECS := 0.5

var sim: Sim
var cam: MapCamera
## Aiming preview from the controller: {"weapon", "tile", "check", "est", "locked"} or {}.
var aim: Dictionary = {}
var _fx: Array = []
var _shown: Dictionary = {}


func _process(_delta: float) -> void:
	for f: Dictionary in _fx:
		f["t"] = float(f["t"]) + _delta
	_fx = _fx.filter(func(f: Dictionary) -> bool: return float(f["t"]) < float(f["life"]))
	queue_redraw()


func _c(t: int) -> Vector2:
	return Vector2(t % sim.map.width + 0.5, t / sim.map.width + 0.5)


## Visual reaction to weapon events.
func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		SimEvents.WEAPON_IMPACT:
			var kind := "emp" if String(e["weapon"]) == "emp" else "blast"
			_fx.append({"kind": kind, "pos": _c(int(e["tile"])), "r": float(e["radius"]), "t": 0.0, "life": BLAST_SECS * (1.6 if kind == "emp" else 1.0)})
		SimEvents.NUKE_DETONATED:
			_fx.append({"kind": "nuke", "pos": _c(int(e["tile"])), "r": float(e["radius"]), "inner": float(e["inner"]), "t": 0.0,
				"life": NUKE_SECS * (0.6 if e.get("warhead", false) else 1.0)})
		SimEvents.INTERCEPTED:
			_fx.append({"kind": "kill", "pos": Vector2(float(e["x"]), float(e["y"])), "r": 0.0, "t": 0.0, "life": BURST_SECS * 1.4})
		SimEvents.INTERCEPT_MISSED:
			_fx.append({"kind": "miss", "pos": Vector2(float(e["x"]), float(e["y"])), "r": 0.0, "t": 0.0, "life": BURST_SECS})
		SimEvents.MIRV_SPLIT:
			_fx.append({"kind": "split", "pos": _c(int(e["tile"])), "r": 0.0, "t": 0.0, "life": BURST_SECS * 2.0})
	if _fx.size() > 60:
		_fx = _fx.slice(_fx.size() - 60)


func _draw() -> void:
	if sim == null or cam == null:
		return
	var z := cam.zoom.x
	var now := sim.st.tick
	var t_ms := Time.get_ticks_msec() / 1000.0
	if not aim.is_empty():
		_draw_aim(z, t_ms)
	_draw_munitions(z, now, t_ms)
	_draw_interceptors(z, now)
	_draw_fx(z)


# ---- aiming -----------------------------------------------------------------------------------

func _draw_aim(z: float, t_ms: float) -> void:
	var w: int = aim["weapon"]
	var tile: int = aim["tile"]
	var wd := sim.rules.weapon(w)
	var ef: Dictionary = wd["effect"]
	var c: Dictionary = aim.get("check", {})
	var est: Dictionary = aim.get("est", {})
	var ok: bool = c.get("ok", false)
	var p := _c(tile)
	var lw := maxf(0.12, 1.6 / z)
	var col := UITheme.ACCENT if ok else UITheme.BAD
	var friendly := int(est.get("own_tiles", 0)) > 0 or int(est.get("own_structures", 0)) > 0
	var pulse := 0.85 + 0.15 * sin(t_ms * 5.0)
	# Flight path from the chosen launcher.
	if ok and c.has("path"):
		var pts: PackedVector2Array = c["path"]
		for i in range(1, pts.size()):
			draw_dashed_line(pts[i - 1], pts[i], Color("#f2efe8", 0.55), lw, maxf(0.5, 6.0 / z))
		draw_circle(pts[0], maxf(0.4, 4.0 / z), Color("#f2efe8", 0.85))
	# SAMs of the target's owner that cover it.
	var to := sim.st.owner[tile]
	if to > 0 and to != sim.player_id:
		for s in sim.structures.of_owner(to, Rules.B_SAM):
			if s.counted() <= 0:
				continue
			var rr := sim.weapons.sam_range(s)
			if float(sim.map.dist2(s.tile, tile)) <= rr * rr:
				draw_arc(_c(s.tile), rr, 0.0, TAU, 72, Color(UITheme.BAD, 0.45), lw)
				draw_circle(_c(s.tile), maxf(0.4, 3.0 / z), Color(UITheme.BAD, 0.8))
	# Blast zone.
	var kind := String(ef["kind"])
	var r := float(wd["radius"])
	match kind:
		"cluster":
			draw_arc(p, float(ef["spread"]) + r, 0.0, TAU, 64, Color(col, 0.55), lw)
			for b in sim.weapons.bomblet_tiles(tile, int(ef["bomblets"]), float(ef["spread"]), sim.weapons.next_id):
				draw_circle(_c(b), r, Color(col, 0.16 * pulse))
				draw_arc(_c(b), r, 0.0, TAU, 32, Color(col, 0.7), lw * 0.8)
		"mirv":
			draw_circle(p, r, Color(col, 0.06 * pulse))
			draw_arc(p, r, 0.0, TAU, 96, Color(col, 0.7), lw)
		_:
			draw_circle(p, r, Color(col, 0.14 * pulse))
			draw_arc(p, r, 0.0, TAU, 72, Color(col, 0.85), lw * 1.2)
			if kind == "nuke":
				draw_circle(p, float(wd["radius_inner"]), Color(col, 0.2 * pulse))
				draw_arc(p, float(wd["radius_inner"]), 0.0, TAU, 64, Color(col, 0.9), lw)
	if friendly:
		draw_arc(p, r * (1.0 if kind != "cluster" else 1.0) + 2.0 / z, 0.0, TAU, 72, Color(UITheme.WARN, 0.9), lw * 2.0)
	# Reticle.
	var k := maxf(0.8, 9.0 / z)
	if ok:
		draw_line(p - Vector2(k * 1.6, 0), p - Vector2(k * 0.5, 0), col, lw * 1.4)
		draw_line(p + Vector2(k * 0.5, 0), p + Vector2(k * 1.6, 0), col, lw * 1.4)
		draw_line(p - Vector2(0, k * 1.6), p - Vector2(0, k * 0.5), col, lw * 1.4)
		draw_line(p + Vector2(0, k * 0.5), p + Vector2(0, k * 1.6), col, lw * 1.4)
		if aim.get("locked", false):
			draw_arc(p, k * 1.9, 0.0, TAU, 32, Color(col, pulse), lw * 1.6)
	else:
		draw_line(p - Vector2(k, k), p + Vector2(k, k), col, lw * 2.0)
		draw_line(p - Vector2(k, -k), p + Vector2(k, -k), col, lw * 2.0)


# ---- flight -----------------------------------------------------------------------------------

## Symbol and its own heading (radians) for a flying munition.
func _glyph(m: WeaponSystem.Munition) -> Array:
	var id := String(sim.rules.weapon(m.weapon)["id"])
	if m.warhead:
		return ["", 0.0]
	match id:
		"artillery":
			return ["", 0.0]
		"air_strike":
			return ["w_air_strike", 3.0 * PI / 4.0]
		"heavy_missile", "tactical_nuke", "strategic_nuke", "mirv":
			return ["w_heavy_missile", -PI / 4.0]
	return ["w_missile", -PI / 4.0]


func _draw_munitions(z: float, now: int, t_ms: float) -> void:
	var pid := sim.player_id
	var view := cam.visible_rect().grow(20)
	var seen := {}
	for m in sim.weapons.munitions:
		if not m.alive:
			continue
		seen[m.id] = true
		var real := m.position(now)
		var pos: Vector2 = _shown.get(m.id, real)
		pos = pos.lerp(real, 0.35)
		_shown[m.id] = pos
		var oc: Color = sim.st.o_color[m.owner].lightened(0.35)
		var mine := m.owner == pid
		var incoming := not mine and pid > 0 and sim.st.owner[m.to_tile] == pid
		var nuclear := sim.weapons.is_nuclear(m.weapon) or m.warhead
		# Remaining path for the player's and incoming munitions; target mark.
		if (mine or incoming) and not m.warhead:
			var pc := Color("#f2efe8", 0.4) if mine else Color(UITheme.BAD, 0.55)
			var f := m.fraction(now)
			var prev := real
			for i in range(1, 13):
				var q := m.position(m.launch_tick + m.delay + roundi(m.flight * (f + (1.0 - f) * float(i) / 12.0)))
				if i % 2 == 1:
					draw_line(prev, q, pc, maxf(0.1, 1.2 / z))
				prev = q
			var tp := _c(m.to_tile)
			draw_arc(tp, maxf(0.6, 7.0 / z), 0.0, TAU, 24, pc, maxf(0.12, 1.4 / z))
		if not view.has_point(pos):
			continue
		if m.fraction(now) <= 0.0:
			# Still on the launcher: a pulsing launch light.
			draw_circle(pos, maxf(0.4, (3.0 + 2.0 * sin(t_ms * 8.0)) / z), Color(UITheme.WARN, 0.85))
			continue
		# Trail: past positions on the same path, fading.
		var trail_col := Color(1.0, 0.85, 0.6) if not nuclear else SimState.RADIATION_COLOR
		var prev_p := pos
		var flying_since := m.launch_tick + m.delay
		for i in range(1, 9):
			if now - i < flying_since:
				break
			var q := m.position(now - i)
			draw_line(prev_p, q, Color(trail_col, 0.5 * (1.0 - float(i) / 9.0)), maxf(0.12, (2.6 - i * 0.2) / z))
			prev_p = q
		var dir := m.position(now + 1) - real
		var ang := dir.angle() if dir.length() > 0.0001 else 0.0
		var g := _glyph(m)
		var size := (22.0 if nuclear and not m.warhead else 16.0) / z
		if String(g[0]) == "":
			draw_circle(pos, maxf(0.35, (4.0 if m.warhead else 3.0) / z), Color(0.08, 0.07, 0.06, 0.85))
			draw_circle(pos, maxf(0.25, (3.0 if m.warhead else 2.2) / z), trail_col if m.warhead else Color("#f2efe8"))
			continue
		var tex := Symbols.tex_px(String(g[0]), maxi(12, int(size * z)), "map_full")
		if tex == null:
			continue
		draw_set_transform(pos, ang - float(g[1]), Vector2.ONE)
		var half := size * 0.5
		draw_texture_rect(tex, Rect2(Vector2(-half, -half), Vector2(size, size)), false, oc if not nuclear else Color(1.0, 0.85, 0.75))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if nuclear:
			draw_arc(pos, size * 0.7, 0.0, TAU, 20, Color(SimState.RADIATION_COLOR, 0.5 + 0.4 * sin(t_ms * 10.0)), maxf(0.12, 1.4 / z))
	for id: int in _shown.keys():
		if not seen.has(id):
			_shown.erase(id)


func _draw_interceptors(z: float, now: int) -> void:
	for x in sim.weapons.interceptors:
		var m := sim.weapons._munition(x.munition)
		if m == null or not m.alive:
			continue
		var f := clampf(float(now - x.launch_tick) / float(maxi(1, x.hit_tick - x.launch_tick)), 0.0, 1.0)
		var target: Vector2 = _shown.get(m.id, m.position(now))
		var p := x.from.lerp(target, f)
		draw_line(x.from, p, Color(1, 1, 1, 0.35), maxf(0.1, 1.2 / z))
		draw_circle(p, maxf(0.3, 2.6 / z), Color(1, 1, 1, 0.95))


# ---- impacts ----------------------------------------------------------------------------------

func _draw_fx(z: float) -> void:
	for f: Dictionary in _fx:
		var k := float(f["t"]) / float(f["life"])
		var p: Vector2 = f["pos"]
		var r: float = f["r"]
		var lw := maxf(0.15, 2.0 / z)
		match String(f["kind"]):
			"blast":
				draw_circle(p, r * (0.3 + 0.7 * k), Color(1.0, 0.62, 0.3, 0.45 * (1.0 - k)))
				draw_arc(p, r * (0.4 + 0.8 * k), 0.0, TAU, 48, Color(1.0, 0.85, 0.6, 1.0 - k), lw * 1.5)
				if k < 0.25:
					draw_circle(p, r * 0.35, Color(1, 1, 0.9, 0.9 * (1.0 - k * 4.0)))
			"emp":
				for i in 3:
					var kk := fmod(k * 1.5 + i * 0.33, 1.0)
					draw_arc(p, r * kk, 0.0, TAU, 64, Color(0.65, 0.85, 1.0, 0.8 * (1.0 - kk) * (1.0 - k)), lw * 1.6)
			"nuke":
				# Radiation green: white-green flash, acid fireball with a dark scorched rim, green shock wave.
				var inner: float = f.get("inner", r * 0.4)
				var rad := SimState.RADIATION_COLOR
				if k < 0.12:
					draw_circle(p, r * 1.15, Color(rad.lightened(0.7), 0.85 * (1.0 - k / 0.12)))
				var fire := inner * (0.6 + 0.4 * minf(k * 3.0, 1.0))
				draw_circle(p, fire * 1.08, Color(0.04, 0.05, 0.03, 0.55 * (1.0 - k)))
				draw_circle(p, fire, Color(rad, 0.8 * (1.0 - k)))
				draw_circle(p, inner * 0.45, Color(rad.lightened(0.55), 0.85 * maxf(0.0, 1.0 - k * 2.0)))
				draw_arc(p, r * (0.3 + 1.1 * k), 0.0, TAU, 96, Color(rad.lightened(0.3), 0.9 * (1.0 - k)), lw * 2.2)
				draw_arc(p, r * (0.2 + 0.8 * k), 0.0, TAU, 96, Color(0.04, 0.05, 0.03, 0.6 * (1.0 - k)), lw * 1.6)
			"kill":
				var rr := maxf(0.6, 10.0 / z) * (0.4 + k)
				draw_circle(p, rr * 0.6, Color(1, 1, 0.9, 0.8 * (1.0 - k)))
				draw_arc(p, rr, 0.0, TAU, 20, Color(1, 1, 1, 1.0 - k), lw)
			"miss":
				draw_circle(p, maxf(0.4, 5.0 / z) * (0.5 + k), Color(0.7, 0.7, 0.7, 0.5 * (1.0 - k)))
			"split":
				draw_arc(p, maxf(0.6, 18.0 / z) * (0.3 + k), 0.0, TAU, 28, Color(1, 0.7, 0.5, 1.0 - k), lw * 1.4)
