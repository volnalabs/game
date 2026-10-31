class_name DiplomacySystem
extends RefCounted
## Relations between states (Phase 2F). Pure and deterministic; saved with the match.
##
## Relations: alliance (timed, renewable; teams are permanent alliances), non-aggression pact (NAP,
## timed), war (an attack between the two in the last hostile_ticks) or neutral. Allies and pact
## partners cannot attack, land on or strike each other; a SAM also defends its allies' land.
## Requests (alliance / NAP) wait for an answer for request_ticks; asking the same state again has a
## cooldown. An alliance expires unless both ask to renew it in its last extend_window_ticks.
## Breaking an alliance or a pact early (or nuking an ally's land) marks the breaker a traitor for
## traitor_ticks: anyone attacking a traitor loses traitor_loss_mult as many troops.
## Allies can send each other troops or gold by convoy (travel time from capital to capital) and ask
## for help against an enemy; an accepted request is answered with an attack.
## (RoWorld Sim.luau ally_request / ally_reply / ally_extend / ally_break / donate, Rules.luau.)

const ALLIANCE := "alliance"
const NAP := "nap"


class Convoy:
	extends RefCounted
	var id: int = 0
	var from: int = 0
	var to: int = 0
	## "troops" or "gold".
	var kind: String = "troops"
	var amount: float = 0.0
	var start: int = 0
	var arrive: int = 0
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO

	func position(now: int) -> Vector2:
		var f := clampf(float(now - start) / float(maxi(1, arrive - start)), 0.0, 1.0)
		return from_pos.lerp(to_pos, f)

	func to_dict() -> Dictionary:
		return {"id": id, "from": from, "to": to, "kind": kind, "amount": amount, "start": start, "arrive": arrive,
			"from_pos": from_pos, "to_pos": to_pos}

	static func from_dict(d: Dictionary) -> Convoy:
		var c := Convoy.new()
		for k: String in d:
			c.set(k, d[k])
		return c


var st: SimState
var rules: Rules
var events: SimEvents
var attacks: AttackSystem
var d: Dictionary
## Pair key -> {"kind", "since", "until" (-1 = permanent), "ext_a", "ext_b", "team"}.
var pacts: Dictionary = {}
## Directed key (from, to) -> {"kind", "tick"}: pending requests.
var requests: Dictionary = {}
## Directed key -> tick of the last request (cooldown).
var last_request: Dictionary = {}
## Pair key -> tick until which the two are at war (recent attacks).
var hostile_until: Dictionary = {}
## Owner -> tick until which it counts as a traitor.
var traitor_until: Dictionary = {}
## Owner -> team number (0 = no team).
var team: Dictionary = {}
var convoys: Array[Convoy] = []
## Pending help requests: {"id", "from", "to" (asked ally), "enemy", "tick"}.
var help: Array[Dictionary] = []
var next_id: int = 1


func _init(state: SimState, rules_: Rules, ev: SimEvents, atk: AttackSystem) -> void:
	st = state
	rules = rules_
	events = ev
	attacks = atk
	d = rules.dip


static func pair(a: int, b: int) -> int:
	return mini(a, b) * 1024 + maxi(a, b)


static func directed(a: int, b: int) -> int:
	return a * 1024 + b


# ---------------------------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------------------------

func pact(a: int, b: int) -> Dictionary:
	return pacts.get(pair(a, b), {})


func allied(a: int, b: int) -> bool:
	if a == b or a <= 0 or b <= 0:
		return false
	return String(pact(a, b).get("kind", "")) == ALLIANCE


func has_nap(a: int, b: int) -> bool:
	return a != b and a > 0 and b > 0 and String(pact(a, b).get("kind", "")) == NAP


func same_team(a: int, b: int) -> bool:
	return a != b and int(team.get(a, 0)) > 0 and int(team.get(a, 0)) == int(team.get(b, 0))


## Whether `a` may attack, land on or strike `b` (unclaimed land and tribes always).
func can_attack(a: int, b: int) -> bool:
	if b <= 0 or a == b:
		return b != a
	return not allied(a, b) and not has_nap(a, b)


## Why `a` cannot attack `b` ("" = it can): "ally", "team" or "pact".
func block_reason(a: int, b: int) -> String:
	if b <= 0 or a == b:
		return ""
	if same_team(a, b):
		return "team"
	if allied(a, b):
		return "ally"
	if has_nap(a, b):
		return "pact"
	return ""


func at_war(a: int, b: int) -> bool:
	return int(hostile_until.get(pair(a, b), -1)) > st.tick


func is_traitor(o: int) -> bool:
	return int(traitor_until.get(o, -1)) > st.tick


## "team", "ally", "nap", "war" or "neutral" — what the interface shows.
func relation(a: int, b: int) -> String:
	if same_team(a, b):
		return "team"
	if allied(a, b):
		return ALLIANCE
	if has_nap(a, b):
		return NAP
	if at_war(a, b):
		return "war"
	return "neutral"


func allies_of(a: int) -> Array[int]:
	var out: Array[int] = []
	for k: int in pacts:
		var p: Dictionary = pacts[k]
		if String(p["kind"]) != ALLIANCE:
			continue
		var x := k / 1024
		var y := k % 1024
		if x == a:
			out.append(y)
		elif y == a:
			out.append(x)
	out.sort()
	return out


func pending(from: int, to: int) -> Dictionary:
	return requests.get(directed(from, to), {})


## Requests waiting for `to`'s answer: [{"from", "kind", "tick"}].
func requests_to(to: int) -> Array:
	var out: Array = []
	for k: int in requests:
		if k % 1024 == to:
			var r: Dictionary = requests[k]
			out.append({"from": k / 1024, "kind": r["kind"], "tick": r["tick"]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["tick"]) < int(y["tick"]))
	return out


func cooldown_left(from: int, to: int) -> int:
	var last := int(last_request.get(directed(from, to), -1000000))
	return maxi(0, last + int(d.get("request_cooldown_ticks", 300)) - st.tick)


## Ticks left of a pact (-1 = permanent, 0 = none).
func time_left(a: int, b: int) -> int:
	var p := pact(a, b)
	if p.is_empty():
		return 0
	var u := int(p["until"])
	return -1 if u < 0 else maxi(0, u - st.tick)


func in_extend_window(a: int, b: int) -> bool:
	var left := time_left(a, b)
	return String(pact(a, b).get("kind", "")) == ALLIANCE and left > 0 and left <= int(d.get("extend_window_ticks", 300))


# ---------------------------------------------------------------------------------------------
# Actions (each returns "" or a refusal reason)
# ---------------------------------------------------------------------------------------------

## Asks `to` for an alliance or a NAP; an answer to a pending request from `to` of the same kind
## accepts it at once.
func request(from: int, to: int, kind: String) -> String:
	if to <= 0 or to == from or not st.is_alive(to) or st.o_kind[to] == Rules.KIND_TRIBE:
		return "bad_target"
	if kind != ALLIANCE and kind != NAP:
		return "bad_kind"
	var cur := String(pact(from, to).get("kind", ""))
	if cur == ALLIANCE or (cur == NAP and kind == NAP):
		return "already"
	if kind == ALLIANCE and (allies_of(from).size() >= int(d.get("max_allies", 3)) or allies_of(to).size() >= int(d.get("max_allies", 3))):
		return "too_many_allies"
	var back := pending(to, from)
	if not back.is_empty() and String(back["kind"]) == kind:
		requests.erase(directed(to, from))
		_form(to, from, kind)
		return ""
	if not pending(from, to).is_empty():
		return "already_asked"
	if cooldown_left(from, to) > 0:
		return "cooldown"
	requests[directed(from, to)] = {"kind": kind, "tick": st.tick}
	last_request[directed(from, to)] = st.tick
	events.emit(SimEvents.DIPLO_REQUEST, {"from": from, "to": to, "kind": kind})
	return ""


## `who` answers `requester`'s pending request.
func reply(who: int, requester: int, accept: bool) -> String:
	var r := pending(requester, who)
	if r.is_empty():
		return "no_request"
	requests.erase(directed(requester, who))
	var kind := String(r["kind"])
	if accept and st.is_alive(requester):
		if kind == ALLIANCE and (allies_of(who).size() >= int(d.get("max_allies", 3)) or allies_of(requester).size() >= int(d.get("max_allies", 3))):
			events.emit(SimEvents.DIPLO_DECLINED, {"from": requester, "to": who, "kind": kind, "reason": "too_many_allies"})
			return "too_many_allies"
		_form(requester, who, kind)
	else:
		events.emit(SimEvents.DIPLO_DECLINED, {"from": requester, "to": who, "kind": kind, "reason": "declined"})
	return ""


func _form(a: int, b: int, kind: String) -> void:
	var length := int(d.get("alliance_ticks", 3000)) if kind == ALLIANCE else int(d.get("nap_ticks", 2400))
	pacts[pair(a, b)] = {"kind": kind, "since": st.tick, "until": st.tick + length, "ext_a": false, "ext_b": false, "team": false}
	requests.erase(directed(b, a))
	hostile_until.erase(pair(a, b))
	_stop_fighting(a, b)
	events.emit(SimEvents.DIPLO_FORMED, {"a": a, "b": b, "kind": kind, "until": st.tick + length})


## New partners stop attacking each other: their attacks end and the troops come home.
func _stop_fighting(a: int, b: int) -> void:
	for at in attacks.attacks:
		if at.alive and ((at.attacker == a and at.target == b) or (at.attacker == b and at.target == a)):
			attacks.end_attack(at, true)


## Ends the pact between `by` and `other` early: `by` becomes a traitor (not when it simply lapses).
func break_pact(by: int, other: int) -> String:
	var p := pact(by, other)
	if p.is_empty():
		return "no_pact"
	if bool(p.get("team", false)):
		return "team"
	_end(by, other, "broken", by)
	return ""


func _end(a: int, b: int, reason: String, breaker: int = 0) -> void:
	var p := pact(a, b)
	if p.is_empty():
		return
	pacts.erase(pair(a, b))
	if breaker > 0:
		traitor_until[breaker] = st.tick + int(d.get("traitor_ticks", 300))
		events.emit(SimEvents.TRAITOR, {"id": breaker, "victim": b if breaker == a else a, "until": traitor_until[breaker]})
	events.emit(SimEvents.DIPLO_ENDED, {"a": a, "b": b, "kind": p["kind"], "reason": reason, "breaker": breaker})


## `by` asks to renew its alliance with `other` (in the last extend window); renewed once both asked.
## Returns "asked", "renewed" or a refusal.
func extend(by: int, other: int) -> String:
	var p := pact(by, other)
	if String(p.get("kind", "")) != ALLIANCE or bool(p.get("team", false)):
		return "no_pact"
	if not in_extend_window(by, other):
		return "too_early"
	var mine := "ext_a" if by == mini(by, other) else "ext_b"
	p[mine] = true
	if bool(p["ext_a"]) and bool(p["ext_b"]):
		p["until"] = int(p["until"]) + int(d.get("alliance_ticks", 3000))
		p["ext_a"] = false
		p["ext_b"] = false
		events.emit(SimEvents.DIPLO_RENEWED, {"a": by, "b": other, "until": p["until"]})
		return "renewed"
	events.emit(SimEvents.DIPLO_EXTEND_ASKED, {"from": by, "to": other})
	return "asked"


## Sends troops or gold to an ally by convoy (troops leave the army now and arrive later).
func send(from: int, to: int, kind: String, amount: float) -> String:
	if not allied(from, to) or not st.is_alive(to):
		return "not_ally"
	amount = floorf(amount)
	if kind == "troops":
		amount = minf(amount, st.o_troops[from])
		if amount < 1.0:
			return "no_troops"
		st.add_troops(from, -amount)
	elif kind == "gold":
		amount = minf(amount, st.o_gold[from])
		if amount < 1.0:
			return "no_gold"
		st.add_gold(from, -amount)
	else:
		return "bad_kind"
	var c := Convoy.new()
	c.id = next_id
	next_id += 1
	c.from = from
	c.to = to
	c.kind = kind
	c.amount = amount
	c.start = st.tick
	c.from_pos = _capital(from)
	c.to_pos = _capital(to)
	var dist := c.from_pos.distance_to(c.to_pos)
	c.arrive = st.tick + maxi(int(d.get("convoy_min_ticks", 20)), ceili(dist / maxf(float(d.get("convoy_speed", 4.0)), 0.01)))
	convoys.append(c)
	events.emit(SimEvents.CONVOY_SENT, {"id": c.id, "from": from, "to": to, "kind": kind, "amount": amount, "arrive": c.arrive})
	return ""


func _capital(o: int) -> Vector2:
	var sp := st.o_spawn_tile[o]
	if sp >= 0 and st.owner[sp] == o:
		return Vector2(sp % st.W + 0.5, sp / st.W + 0.5)
	return st.centroid(o)


## `from` asks its ally `to` for help against `enemy`.
func ask_help(from: int, to: int, enemy: int) -> String:
	if not allied(from, to):
		return "not_ally"
	if enemy <= 0 or not st.is_alive(enemy) or enemy == to or allied(to, enemy) or has_nap(to, enemy):
		return "bad_target"
	for h: Dictionary in help:
		if int(h["from"]) == from and int(h["to"]) == to:
			return "already_asked"
	help.append({"id": next_id, "from": from, "to": to, "enemy": enemy, "tick": st.tick})
	next_id += 1
	events.emit(SimEvents.HELP_REQUEST, {"from": from, "to": to, "enemy": enemy})
	return ""


func help_for(to: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in help:
		if int(h["to"]) == to:
			out.append(h)
	return out


## `who` answers `asker`'s help request: accepting attacks the enemy with `troops` (when they share a
## border; otherwise the troops go to the ally by convoy).
func answer_help(who: int, asker: int, accept: bool, troops: float) -> String:
	var idx := -1
	for i in help.size():
		if int(help[i]["to"]) == who and int(help[i]["from"]) == asker:
			idx = i
			break
	if idx < 0:
		return "no_request"
	var h: Dictionary = help[idx]
	help.remove_at(idx)
	var enemy := int(h["enemy"])
	var how := "declined"
	if accept:
		troops = floorf(minf(troops, st.o_troops[who]))
		if troops >= 1.0 and can_attack(who, enemy) and st.is_alive(enemy):
			st.add_troops(who, -troops)
			var a := attacks.start(who, enemy, troops)
			if a != null:
				how = "attack"
			else:
				st.add_troops(who, troops)
				if allied(who, asker) and send(who, asker, "troops", troops) == "":
					how = "convoy"
	events.emit(SimEvents.HELP_ANSWER, {"from": asker, "to": who, "enemy": enemy, "accepted": how != "declined", "how": how})
	return ""


# ---------------------------------------------------------------------------------------------
# Teams, hooks, tick
# ---------------------------------------------------------------------------------------------

## Puts owners on teams: everyone on a team is permanently allied with their teammates.
func set_teams(assignment: Dictionary) -> void:
	team = assignment.duplicate()
	var ids: Array = team.keys()
	ids.sort()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: int = ids[i]
			var b: int = ids[j]
			if int(team[a]) > 0 and int(team[a]) == int(team[b]):
				pacts[pair(a, b)] = {"kind": ALLIANCE, "since": st.tick, "until": -1, "ext_a": false, "ext_b": false, "team": true}


## A nuclear burst by `owner` took `lost` tiles from `victim`: an ally doing that breaks the alliance.
func on_nuked(owner: int, victim: int, lost: int) -> void:
	if owner != victim and allied(owner, victim) and not bool(pact(owner, victim).get("team", false)) \
			and lost >= int(d.get("nuke_break_tiles", 100)) / maxi(1, int(rules.k_area)):
		_end(owner, victim, "nuked", owner)


## Drops everything involving an eliminated state.
func remove_owner(o: int) -> void:
	for k: int in pacts.keys():
		if k / 1024 == o or k % 1024 == o:
			var other: int = k % 1024 if k / 1024 == o else k / 1024
			_end(o, other, "eliminated")
	for k: int in requests.keys():
		if k / 1024 == o or k % 1024 == o:
			requests.erase(k)
	help = help.filter(func(h: Dictionary) -> bool: return int(h["from"]) != o and int(h["to"]) != o and int(h["enemy"]) != o)


func tick() -> void:
	var now := st.tick
	# Wars: states fighting each other right now.
	var hostile := int(d.get("hostile_ticks", 600))
	for a in attacks.attacks:
		if a.alive and a.target > 0:
			hostile_until[pair(a.attacker, a.target)] = now + hostile
	# Requests expire.
	var rt := int(d.get("request_ticks", 200))
	for k: int in requests.keys():
		var r: Dictionary = requests[k]
		if now - int(r["tick"]) >= rt:
			requests.erase(k)
			events.emit(SimEvents.DIPLO_DECLINED, {"from": k / 1024, "to": k % 1024, "kind": r["kind"], "reason": "expired"})
	# Pacts expire; the renewal window opens.
	var win := int(d.get("extend_window_ticks", 300))
	for k: int in pacts.keys():
		var p: Dictionary = pacts[k]
		var u := int(p["until"])
		if u < 0:
			continue
		if now >= u:
			_end(k / 1024, k % 1024, "expired")
		elif u - now == win and String(p["kind"]) == ALLIANCE:
			events.emit(SimEvents.DIPLO_EXPIRING, {"a": k / 1024, "b": k % 1024, "until": u})
	# Help requests expire.
	var ht := int(d.get("help_ticks", 300))
	help = help.filter(func(h: Dictionary) -> bool: return now - int(h["tick"]) < ht)
	# Convoys arrive (or go home when the alliance is gone).
	if not convoys.is_empty():
		var keep: Array[Convoy] = []
		for c in convoys:
			if now < c.arrive:
				keep.append(c)
				continue
			var to := c.to if allied(c.from, c.to) and st.is_alive(c.to) else c.from
			if not st.is_alive(to):
				continue
			if c.kind == "troops":
				st.add_troops(to, c.amount)
			else:
				st.add_gold(to, c.amount)
			events.emit(SimEvents.CONVOY_ARRIVED, {"id": c.id, "from": c.from, "to": to, "kind": c.kind, "amount": c.amount,
				"returned": to != c.to})
		convoys = keep
	if now % 600 == 0:
		for k: int in hostile_until.keys():
			if int(hostile_until[k]) <= now:
				hostile_until.erase(k)
		for o: int in traitor_until.keys():
			if int(traitor_until[o]) <= now:
				traitor_until.erase(o)


# ---------------------------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var cs := []
	for c in convoys:
		cs.append(c.to_dict())
	return {"pacts": pacts.duplicate(true), "requests": requests.duplicate(true), "last_request": last_request.duplicate(),
		"hostile_until": hostile_until.duplicate(), "traitor_until": traitor_until.duplicate(), "team": team.duplicate(),
		"convoys": cs, "help": help.duplicate(true), "next_id": next_id}


func from_dict(dd: Dictionary) -> void:
	pacts = (dd.get("pacts", {}) as Dictionary).duplicate(true)
	requests = (dd.get("requests", {}) as Dictionary).duplicate(true)
	last_request = (dd.get("last_request", {}) as Dictionary).duplicate()
	hostile_until = (dd.get("hostile_until", {}) as Dictionary).duplicate()
	traitor_until = (dd.get("traitor_until", {}) as Dictionary).duplicate()
	team = (dd.get("team", {}) as Dictionary).duplicate()
	convoys.clear()
	for cd: Dictionary in dd.get("convoys", []):
		convoys.append(Convoy.from_dict(cd))
	help.clear()
	for h: Dictionary in dd.get("help", []):
		help.append(h)
	next_id = int(dd.get("next_id", 1))
