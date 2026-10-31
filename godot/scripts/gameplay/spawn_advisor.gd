class_name SpawnAdvisor
extends RefCounted
## Read-only analysis of a candidate start tile for the spawn screen: validity with a precise
## reason, the land the start claims (SpawnSystem.disk_tiles — exactly what the sim will take),
## the free land around it that an early expansion can reach (an estimate, bounded by water and
## other states), the nearest states, and a danger rating from their troops and distance.

const NEAR_RADIUS := 90.0
const REACH_STEPS := 3.0

var sim: Sim


func _init(sim_: Sim) -> void:
	sim = sim_


## Why a tile cannot be a start ("" when it can): not_land, taken, crowded.
func refusal(t: int) -> String:
	var st := sim.st
	if t < 0 or t >= st.N or sim.map.land[t] == 0:
		return "not_land"
	if st.owner[t] != 0:
		return "taken"
	if not sim.spawn.is_valid_start(t):
		return "crowded"
	return ""


func analyze(t: int) -> Dictionary:
	var st := sim.st
	var out := {"tile": t, "reason": refusal(t), "claim": PackedInt32Array(), "reach": PackedInt32Array(),
		"free": 0, "coastal": false, "neighbours": [], "danger": 0.0, "danger_level": 0}
	if out["reason"] == "not_land":
		return out
	var claim := PackedInt32Array()
	for d in sim.spawn.disk_tiles(t):
		if sim.map.land[d] == 1 and st.owner[d] == 0:
			claim.append(d)
			if sim.map.coastal[d] == 1:
				out["coastal"] = true
	out["claim"] = claim
	out["reach"] = _reach(t, sim.rules.spawn_radius * REACH_STEPS)
	out["free"] = (out["reach"] as PackedInt32Array).size()
	var cx := float(t % st.W) + 0.5
	var cy := float(t / st.W) + 0.5
	var near: Array = []
	var danger := 0.0
	for o in range(1, st.owner_count + 1):
		if st.o_alive[o] != 1 or st.o_tiles[o] <= 0 or o == sim.player_id:
			continue
		var c := st.centroid(o)
		var edge := maxf(0.0, Vector2(cx, cy).distance_to(c) - sqrt(float(st.o_tiles[o]) / PI))
		if edge > NEAR_RADIUS:
			continue
		near.append({"id": o, "dist": edge, "troops": st.o_troops[o], "tribe": st.o_kind[o] == Rules.KIND_TRIBE})
		var w := 0.35 if st.o_kind[o] == Rules.KIND_TRIBE else 1.0
		danger += w * st.o_troops[o] / maxf(edge, 8.0)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	out["neighbours"] = near.slice(0, 5)
	# Relative to what the player starts with: 1.0 = one start army pressing from 10 tiles away.
	var own := sim.rules.start_troops
	out["danger"] = danger / maxf(own / 10.0, 1.0)
	out["danger_level"] = 0 if out["danger"] < 0.6 else (1 if out["danger"] < 1.6 else 2)
	return out


## Free land reachable from t by land within `radius` steps (stops at water and owned tiles).
func _reach(t: int, radius: float) -> PackedInt32Array:
	var st := sim.st
	var W := st.W
	var out := PackedInt32Array()
	var seen := {t: true}
	var frontier: Array[int] = [t]
	var steps := 0
	while not frontier.is_empty() and steps < int(radius) and out.size() < 20000:
		var nxt: Array[int] = []
		for c in frontier:
			out.append(c)
			var x := c % W
			for nb: int in [c - 1 if x > 0 else -1, c + 1 if x < W - 1 else -1, c - W, c + W]:
				if nb < 0 or nb >= st.N or seen.has(nb):
					continue
				seen[nb] = true
				if sim.map.land[nb] == 1 and st.owner[nb] == 0:
					nxt.append(nb)
		frontier = nxt
		steps += 1
	return out
