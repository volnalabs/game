class_name ResearchSystem
extends RefCounted
## In-match research (data/research/tech_tree.json). Every state earns research points each tick
## (base + research centres, times research_mult) into its current research; finishing a tech
## applies its modifiers and unlocks buildings. Saved with the match.

static var _tree: Dictionary = {}
static var _by_id: Dictionary = {}

var st: SimState
var rules: Rules
var events: SimEvents
var mods: Modifiers
## owner -> {"done": Array[String], "current": String, "progress": {tech: rp}}
var state: Dictionary = {}


func _init(state_: SimState, rules_: Rules, ev: SimEvents, mods_: Modifiers) -> void:
	st = state_
	rules = rules_
	events = ev
	mods = mods_


static func tree() -> Dictionary:
	if _tree.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/research/tech_tree.json"))
		_tree = d if d is Dictionary else {"techs": [], "branches": [], "rp_base_per_sec": 0.0}
		for t: Dictionary in _tree["techs"]:
			_by_id[String(t["id"])] = t
	return _tree


static func tech(id: String) -> Dictionary:
	tree()
	return _by_id.get(id, {})


static func techs() -> Array:
	return tree()["techs"]


func _s(id: int) -> Dictionary:
	if not state.has(id):
		state[id] = {"done": [], "current": "", "progress": {}}
	return state[id]


func done(id: int) -> Array:
	return state[id]["done"] if state.has(id) else []


func has_tech(id: int, tech_id: String) -> bool:
	return tech_id == "" or (state.has(id) and (state[id]["done"] as Array).has(tech_id))


func current(id: int) -> String:
	return String(state[id]["current"]) if state.has(id) else ""


func progress(id: int, tech_id: String) -> float:
	return float((state[id]["progress"] as Dictionary).get(tech_id, 0.0)) if state.has(id) else 0.0


## Whether a tech can be started now: not done and every prerequisite done.
func available(id: int, tech_id: String) -> bool:
	var t := tech(tech_id)
	if t.is_empty() or has_tech(id, tech_id):
		return false
	for r: String in t["requires"]:
		if not has_tech(id, r):
			return false
	return true


## Research points per tick of a state.
func rate(id: int) -> float:
	var per_sec := float(tree()["rp_base_per_sec"])
	per_sec += float(rules.building_effect(Rules.B_RESEARCH).get("research_per_level", 0.0)) * st.blevel(id, Rules.B_RESEARCH)
	return per_sec * mods.mult("research_mult", id) / float(rules.tick_rate)


## Command: start (or switch to) a research. Returns "" or a rejection reason.
func start(id: int, tech_id: String) -> String:
	if tech(tech_id).is_empty():
		return "bad_tech"
	if has_tech(id, tech_id):
		return "tech_done"
	if not available(id, tech_id):
		return "tech_locked"
	_s(id)["current"] = tech_id
	return ""


func tick() -> void:
	for id in range(1, st.owner_count + 1):
		if not state.has(id) or st.o_alive[id] == 0:
			continue
		var s: Dictionary = state[id]
		var cur := String(s["current"])
		if cur == "":
			continue
		var p := float((s["progress"] as Dictionary).get(cur, 0.0)) + rate(id)
		var cost := float(tech(cur)["cost"])
		if p >= cost:
			(s["progress"] as Dictionary).erase(cur)
			(s["done"] as Array).append(cur)
			s["current"] = ""
			mods.mark(id)
			events.emit(SimEvents.RESEARCH_DONE, {"owner": id, "tech": cur})
		else:
			s["progress"][cur] = p


func to_dict() -> Dictionary:
	var out := {}
	for id: int in state:
		out[str(id)] = (state[id] as Dictionary).duplicate(true)
	return out


func from_dict(d: Dictionary) -> void:
	state.clear()
	for k: String in d:
		state[int(k)] = (d[k] as Dictionary).duplicate(true)
