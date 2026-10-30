class_name AIDirector
extends RefCounted
## Owns every AI controller of a match and runs them in owner-id order (deterministic).
## Nations get the VolnaLabs strategic AI (or the legacy baseline for comparisons), tribes a simple
## filler AI. Personalities are spread deterministically from the match seed.

var sim: Sim
var brains: Array[AIBrain] = []
var _by_id: Dictionary = {}


func _init(sim_: Sim) -> void:
	sim = sim_


func setup() -> void:
	var st := sim.st
	var cfg := sim.config
	var pers := AIProfile.personality_ids().duplicate()
	var pers_rng := sim.rng.fork(41)
	var bag: Array = []
	var nation_index := 0
	for id in range(1, st.owner_count + 1):
		if st.o_alive[id] == 0 or id == sim.player_id:
			continue
		var brng := sim.rng.fork(1000 + id)
		var brain: AIBrain
		if st.o_kind[id] == Rules.KIND_TRIBE:
			brain = TribeAI.new(id, sim, brng)
		else:
			var ov: Dictionary = cfg.bot_overrides[nation_index] if nation_index < cfg.bot_overrides.size() else {}
			nation_index += 1
			var personality: String = cfg.personality_mix
			if personality == "mixed" or not AIProfile.personality_ids().has(personality):
				if bag.is_empty():
					bag = pers.duplicate()
					pers_rng.shuffle(bag)
				personality = bag.pop_back()
			personality = ov.get("personality", personality)
			var diff: String = ov.get("difficulty", cfg.difficulty)
			var ai_kind: String = ov.get("ai", cfg.ai_kind)
			if ai_kind == "legacy":
				brain = LegacyAI.new(id, sim, brng, diff)
			else:
				brain = StrategicAI.new(id, sim, brng, diff, personality)
		brain.next_think = 1 + brng.below(20)
		brains.append(brain)
		_by_id[id] = brain


func tick() -> void:
	var now := sim.st.tick
	for b in brains:
		if now >= b.next_think and sim.st.o_alive[b.id] == 1:
			b.think()


func brain_of(id: int) -> AIBrain:
	return _by_id.get(id)


func to_dict() -> Dictionary:
	var d := {}
	for b in brains:
		d[b.id] = b.to_dict()
	return d


func from_dict(d: Dictionary) -> void:
	for b in brains:
		if d.has(b.id):
			b.from_dict(d[b.id])
