class_name SimEvents
extends RefCounted
## Events the simulation reports to the UI, the event log and statistics. Each is a Dictionary
## {"type": String, "tick": int, ...}. The simulation never reads them back.

const ATTACK_STARTED := "attack_started"
const ATTACK_ENDED := "attack_ended"
const ATTACK_RETREAT := "attack_retreat"
const ANNEXED := "annexed"
const ELIMINATED := "eliminated"
const BOAT_LAUNCHED := "boat_launched"
const BOAT_LANDED := "boat_landed"
const BOAT_FAILED := "boat_failed"
## A cancelled transport reached home / was turned round / re-planned its landing at sea.
const BOAT_RETURNED := "boat_returned"
## Diplomacy (Phase 2F).
const DIPLO_REQUEST := "diplo_request"
const DIPLO_FORMED := "diplo_formed"
const DIPLO_DECLINED := "diplo_declined"
const DIPLO_ENDED := "diplo_ended"
const DIPLO_RENEWED := "diplo_renewed"
const DIPLO_EXTEND_ASKED := "diplo_extend_asked"
const DIPLO_EXPIRING := "diplo_expiring"
const TRAITOR := "traitor"
const CONVOY_SENT := "convoy_sent"
const CONVOY_ARRIVED := "convoy_arrived"
const HELP_REQUEST := "help_request"
const HELP_ANSWER := "help_answer"
## Weapons and air defence (Phase 2E).
const WEAPON_LAUNCHED := "weapon_launched"
const WEAPON_IMPACT := "weapon_impact"
const NUKE_DETONATED := "nuke_detonated"
const INTERCEPT_LAUNCHED := "intercept_launched"
const INTERCEPTED := "intercepted"
const INTERCEPT_MISSED := "intercept_missed"
const MIRV_SPLIT := "mirv_split"
const STRUCT_DAMAGED := "struct_damaged"
const STRUCT_DISABLED := "struct_disabled"
const STRUCT_ENABLED := "struct_enabled"
const BOAT_RECALLED := "boat_recalled"
const BOAT_REROUTED := "boat_rerouted"
const BUILD_STARTED := "build_started"
const BUILD_DONE := "build_done"
const STRUCT_CAPTURED := "struct_captured"
const STRUCT_DESTROYED := "struct_destroyed"
const SPAWNED := "spawned"
const PHASE := "phase"
const GAME_OVER := "game_over"
const CAPITULATED := "capitulated"
const COMMAND_REJECTED := "command_rejected"
const RESEARCH_DONE := "research_done"

var tick: int = 0
var _queue: Array[Dictionary] = []
## Keep the buffer bounded when nobody drains it (headless AI runs).
var max_buffer: int = 4000


func emit(type: String, data: Dictionary = {}) -> void:
	data["type"] = type
	data["tick"] = tick
	_queue.append(data)
	if _queue.size() > max_buffer:
		_queue = _queue.slice(_queue.size() - max_buffer / 2)


func drain() -> Array[Dictionary]:
	var out := _queue
	_queue = []
	return out
