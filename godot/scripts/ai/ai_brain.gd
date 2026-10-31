class_name AIBrain
extends RefCounted
## Base class of every AI controller. The director calls think() when next_think is due. A brain
## acts only by submitting commands to the simulation, exactly like the player.

var id: int = 0
var sim: Sim
var rng: SimRng
var next_think: int = 0
var log: DecisionLog = DecisionLog.new()
var kind_name: String = "base"
var difficulty_id: String = "normal"
var personality_id: String = "balanced"


func _init(owner_id: int, sim_: Sim, rng_: SimRng) -> void:
	id = owner_id
	sim = sim_
	rng = rng_


func think() -> void:
	pass


## An attack this bot launched has ended (see AttackSystem.recently_ended).
func on_attack_ended(_info: Dictionary) -> void:
	pass


## Shown by the in-game AI debug panel.
func debug_info() -> Dictionary:
	return {"kind": kind_name, "difficulty": difficulty_id, "personality": personality_id}


## Per-bot statistics for the AI simulation report.
func stats() -> Dictionary:
	return {"decisions": log.counts.duplicate()}


func submit(cmd: Dictionary) -> void:
	sim.submit(cmd)


func to_dict() -> Dictionary:
	return {"next_think": next_think, "log": log.to_dict(), "rng": rng.get_state()}


func from_dict(d: Dictionary) -> void:
	next_think = d.get("next_think", 0)
	log.from_dict(d.get("log", {}))
	if d.has("rng"):
		rng.set_state(d["rng"])
