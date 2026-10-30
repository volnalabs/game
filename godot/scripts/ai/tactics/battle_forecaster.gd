class_name BattleForecaster
extends RefCounted
## Short-term prediction of a land attack with the same formulas the simulation uses
## (rules/combat_math.gd), fed with the bot's ESTIMATES instead of the truth.
##
## One forecast per target builds a curve: cumulative troops spent -> tiles captured, defenders
## killed, annexation. Any attack size is then read from the curve (with a correction for the
## defender/attacker ratio), so comparing many sizes costs one simulation. The number of steps
## (precision) depends on the difficulty.


## p: att_tiles, att_kind, troops (largest size considered), def_troops, def_tiles, def_kind,
##    border, mag, cost, defended_share, steps
static func player_curve(r: Rules, p: Dictionary) -> Dictionary:
	var att_tiles: float = p["att_tiles"]
	var troops: float = p["troops"]
	var n_max := troops
	var def_troops: float = maxf(p["def_troops"], 0.0)
	var def0 := def_troops
	var def_tiles: float = maxf(p["def_tiles"], 1.0)
	var border: float = maxf(p["border"], 1.0)
	var share: float = p.get("defended_share", 0.0)
	var mag: float = p["mag"] * (1.0 + share * (r.defense_mag_mult() - 1.0))
	var cost: float = p["cost"] * (1.0 + share * (r.defense_cost_mult() - 1.0))
	var mag_k := 1.0
	if int(p.get("def_kind", Rules.KIND_NATION)) == Rules.KIND_TRIBE and int(p.get("att_kind", Rules.KIND_NATION)) != Rules.KIND_TRIBE:
		mag_k = r.a["tribe_defender_loss_mult"]
	var steps: int = maxi(4, int(p.get("steps", 24)))
	var annex_at: float = r.annex_below_tiles / r.k_area
	var bonus := CombatMath.player_bonuses(r, int(att_tiles), int(def_tiles), border)
	# Chunk size: the first step's loss rate tells how many tiles the largest attack can take.
	var density0 := def_troops / maxf(def_tiles * r.k_area, 1.0)
	var loss0 := CombatMath.player_loss(r, mag, def_troops / maxf(troops, 1.0), density0, bonus.x, mag_k) * r.k_area
	var est_total := minf(troops / maxf(loss0, 0.001), def_tiles)
	var chunk := maxf(1.0, est_total / steps)
	var used := PackedFloat32Array([0.0])
	var cap := PackedFloat32Array([0.0])
	var kil := PackedFloat32Array([0.0])
	var spent := 0.0
	var captured := 0.0
	var killed := 0.0
	var annex_used := -1.0
	var ticks := 0.0
	for i in steps * 2:
		if troops < 1.0:
			break
		if i % 6 == 5:
			bonus = CombatMath.player_bonuses(r, int(att_tiles + captured), int(def_tiles), border)
		var density := def_troops / maxf(def_tiles * r.k_area, 1.0)
		var ratio := def_troops / maxf(troops, 1.0)
		var per_loss := CombatMath.player_loss(r, mag, ratio, density, bonus.x, mag_k) * r.k_area
		var step := minf(chunk, def_tiles - annex_at)
		if step <= 0.0:
			annex_used = spent
			break
		var affordable := troops / maxf(per_loss, 0.001)
		var last := affordable <= step
		if last:
			step = affordable
		var dk := minf(step * floorf(density) * r.k_area, def_troops)
		captured += step
		spent += step * per_loss
		troops -= step * per_loss
		def_troops -= dk
		killed += dk
		def_tiles -= step
		ticks += step * CombatMath.player_tile_fraction(cost, ratio, bonus.y) * r.k_area
		used.append(spent)
		cap.append(captured)
		kil.append(killed)
		if def_tiles <= annex_at:
			annex_used = spent
			break
		if last:
			break
	return {"used": used, "captured": cap, "killed": kil, "annex_used": annex_used,
		"remaining_tiles": maxf(def_tiles, 0.0), "n_max": n_max, "def0": def0, "ticks": ticks}


## Outcome of an attack of `n` troops read from a curve.
static func sample(curve: Dictionary, n: float) -> Dictionary:
	var used: PackedFloat32Array = curve["used"]
	var cap: PackedFloat32Array = curve["captured"]
	var kil: PackedFloat32Array = curve["killed"]
	var n_max: float = curve["n_max"]
	var def0: float = curve["def0"]
	# A smaller attack faces a worse defender/attacker ratio: spend more per tile.
	var m := clampf(def0 / maxf(n, 1.0), 0.6, 2.0) / clampf(def0 / maxf(n_max, 1.0), 0.6, 2.0)
	var budget := n / maxf(m, 0.01)
	var annex_used: float = curve["annex_used"]
	if annex_used >= 0.0 and budget >= annex_used:
		var k := used.size() - 1
		return {"captured": cap[k] + float(curve["remaining_tiles"]), "loss": annex_used * m,
			"killed": kil[k], "annex": true, "left": n - annex_used * m}
	var captured := 0.0
	var killed := 0.0
	for i in range(1, used.size()):
		if used[i] >= budget:
			var f := (budget - used[i - 1]) / maxf(used[i] - used[i - 1], 0.001)
			captured = lerpf(cap[i - 1], cap[i], f)
			killed = lerpf(kil[i - 1], kil[i], f)
			return {"captured": captured, "loss": n, "killed": killed, "annex": false, "left": 0.0}
	var k2 := used.size() - 1
	return {"captured": cap[k2], "loss": minf(n, used[k2] * m), "killed": kil[k2], "annex": false,
		"left": maxf(0.0, n - used[k2] * m)}


## Expansion into unclaimed land of `free_tiles` tiles.
static func vs_neutral(r: Rules, troops: float, mag: float, att_kind: int, free_tiles: float) -> Dictionary:
	var per := CombatMath.neutral_loss(r, mag, att_kind) * r.k_area
	var can := troops / maxf(per, 0.001)
	var captured := minf(can, free_tiles)
	return {"captured": captured, "loss": captured * per, "killed": 0.0, "annex": false,
		"left": troops - captured * per}
