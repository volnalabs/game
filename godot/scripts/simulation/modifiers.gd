class_name Modifiers
extends RefCounted
## Per-state stat modifiers from three sources: researched techs (data/research/tech_tree.json),
## profile/personality perks (data/meta/skill_tree.json, via MatchConfig; none in Fair mode) and the
## owner-wide effects of buildings (buildings.json "effect"). Read by the economy, combat, naval,
## structures and research. Derived state: rebuilt from techs, perks and buildings, never saved.
##   *_mult stats: multiplier = 1 + sum (clamped to [MIN_MULT, MAX_MULT]); *_add stats: plain sum.

const STATS := ["gold_mult", "supply_mult", "growth_mult", "cap_mult", "upkeep_mult", "attack_loss_mult",
	"defense_loss_mult", "attack_speed_mult", "defense_speed_mult", "retreat_keep_add", "boat_speed_mult",
	"boat_limit_add", "build_cost_mult", "research_mult"]
const MIN_MULT := 0.3
const MAX_MULT := 3.0

var st: SimState
var rules: Rules
## stat -> Array of floats indexed by owner (a plain Array: packed arrays held in a Dictionary are
## copied on write, so writes through them would be lost).
var _v: Dictionary = {}
## owner -> Array[String] of perk ids.
var perks: Dictionary = {}
var _dirty: Dictionary = {}
## Set by Sim: Callable(owner) -> Array of researched tech ids.
var techs_of: Callable


func _init(state: SimState, rules_: Rules) -> void:
	st = state
	rules = rules_
	for s: String in STATS:
		var a: Array[float] = []
		a.resize(st.max_owners)
		a.fill(0.0)
		_v[s] = a


func mult(stat: String, id: int) -> float:
	return clampf(1.0 + (_v[stat] as Array)[id], MIN_MULT, MAX_MULT)


func add(stat: String, id: int) -> float:
	return (_v[stat] as Array)[id]


## Raw sum of a stat (for UI breakdowns).
func value(stat: String, id: int) -> float:
	return (_v[stat] as Array)[id]


func mark(id: int) -> void:
	if id > 0:
		_dirty[id] = true


func mark_all() -> void:
	for id in range(1, st.owner_count + 1):
		_dirty[id] = true


## Recomputes the owners marked since the last call (start of each tick).
func update() -> void:
	if _dirty.is_empty():
		return
	var ids := _dirty.keys()
	_dirty.clear()
	ids.sort()
	for id: int in ids:
		recompute(id)


func recompute(id: int) -> void:
	var sum := {}
	for s: String in STATS:
		sum[s] = 0.0
	for pid: String in perks.get(id, []):
		_add_all(sum, MetaPerks.modifiers(pid))
	if techs_of.is_valid():
		for tid: String in techs_of.call(id):
			_add_all(sum, ResearchSystem.tech(tid).get("modifiers", {}))
	_add_all(sum, building_modifiers(id))
	for s: String in STATS:
		(_v[s] as Array)[id] = float(sum[s])


## Owner-wide effects of buildings (active levels, capped by "max_levels").
func building_modifiers(id: int) -> Dictionary:
	var out := {}
	for k in rules.building_count():
		var e := rules.building_effect(k)
		if e.is_empty():
			continue
		var lv := mini(st.blevel(id, k), int(e.get("max_levels", 99)))
		if lv <= 0:
			continue
		if e.has("attack_loss_per_level"):
			out["attack_loss_mult"] = float(out.get("attack_loss_mult", 0.0)) - float(e["attack_loss_per_level"]) * lv
		if e.has("growth_per_level"):
			out["growth_mult"] = float(out.get("growth_mult", 0.0)) + float(e["growth_per_level"]) * lv
		if e.has("retreat_keep_per_level"):
			out["retreat_keep_add"] = float(out.get("retreat_keep_add", 0.0)) + float(e["retreat_keep_per_level"]) * lv
		if e.has("attack_speed_per_level"):
			out["attack_speed_mult"] = float(out.get("attack_speed_mult", 0.0)) + float(e["attack_speed_per_level"]) * lv
		if e.has("factory_output_per_level"):
			out["supply_mult"] = float(out.get("supply_mult", 0.0)) + float(e["factory_output_per_level"]) * lv
		if e.has("boat_speed_per_level"):
			out["boat_speed_mult"] = float(out.get("boat_speed_mult", 0.0)) + float(e["boat_speed_per_level"]) * lv
		if e.has("boat_limit_per_level"):
			out["boat_limit_add"] = float(out.get("boat_limit_add", 0.0)) + float(e["boat_limit_per_level"]) * lv
	return out


static func _add_all(sum: Dictionary, mods: Dictionary) -> void:
	for s: String in mods:
		if sum.has(s):
			sum[s] = float(sum[s]) + float(mods[s])
