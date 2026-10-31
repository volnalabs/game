class_name Commands
extends RefCounted
## Command constructors. A command is a plain Dictionary (serializable, network-ready):
## {"type": ..., "owner": id, ...}. The player's input and the AI build the same commands.

const SPAWN := "spawn"
const ATTACK := "attack"
const BOAT := "boat"
const BUILD := "build"
const RETREAT := "retreat"
const RESEARCH := "research"
const CANCEL_BOAT := "cancel_boat"
const LAUNCH := "launch"
const DIPLO := "diplo"
const SEND := "send"
const HELP := "help"
const HELP_ANSWER := "help_answer"


## Start (or switch to) researching `tech`.
static func research(owner: int, tech: String) -> Dictionary:
	return {"type": RESEARCH, "owner": owner, "tech": tech}


static func spawn(owner: int, tile: int) -> Dictionary:
	return {"type": SPAWN, "owner": owner, "tile": tile}


## Attack the owner of `tile` with `ratio` of the army.
static func attack_tile(owner: int, tile: int, ratio: float) -> Dictionary:
	return {"type": ATTACK, "owner": owner, "tile": tile, "ratio": ratio}


## Attack `target` (0 = unclaimed land) with exactly `troops`.
static func attack_target(owner: int, target: int, troops: float) -> Dictionary:
	return {"type": ATTACK, "owner": owner, "target": target, "troops": troops}


static func boat(owner: int, tile: int, troops: float) -> Dictionary:
	return {"type": BOAT, "owner": owner, "tile": tile, "troops": troops}


static func boat_ratio(owner: int, tile: int, ratio: float) -> Dictionary:
	return {"type": BOAT, "owner": owner, "tile": tile, "ratio": ratio}


## Diplomacy: action "request" (kind "alliance" / "nap"), "reply" (accept), "break", "extend".
static func diplo(owner: int, action: String, other: int, kind: String = "", accept: bool = false) -> Dictionary:
	return {"type": DIPLO, "owner": owner, "action": action, "other": other, "kind": kind, "accept": accept}


## Send troops or gold to an ally by convoy.
static func send(owner: int, to: int, kind: String, amount: float) -> Dictionary:
	return {"type": SEND, "owner": owner, "to": to, "kind": kind, "amount": amount}


## Ask an ally for help against an enemy / answer such a request.
static func help(owner: int, ally: int, enemy: int) -> Dictionary:
	return {"type": HELP, "owner": owner, "ally": ally, "enemy": enemy}


static func help_answer(owner: int, asker: int, accept: bool, troops: float) -> Dictionary:
	return {"type": HELP_ANSWER, "owner": owner, "asker": asker, "accept": accept, "troops": troops}


## Launch weapon `weapon` (id from weapons.json) at tile `tile`.
static func launch(owner: int, weapon: String, tile: int) -> Dictionary:
	return {"type": LAUNCH, "owner": owner, "weapon": weapon, "tile": tile}


## Turn a transport round: its troops come back when it reaches the departure coast.
static func cancel_boat(owner: int, boat_id: int) -> Dictionary:
	return {"type": CANCEL_BOAT, "owner": owner, "boat": boat_id}


static func build(owner: int, kind: int, tile: int) -> Dictionary:
	return {"type": BUILD, "owner": owner, "kind": kind, "tile": tile}


static func retreat(owner: int, attack_id: int) -> Dictionary:
	return {"type": RETREAT, "owner": owner, "attack": attack_id}
