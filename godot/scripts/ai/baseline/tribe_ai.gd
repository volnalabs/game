class_name TribeAI
extends AIBrain
## Tribes: small filler states with a deliberately simple loop (RoWorld SimAI.luau:1184-1582):
## expand into free land, otherwise attack a random weaker neighbour, nations and the player
## half as often.

var attack_rate: int = 60
var trigger_r: float = 0.5
var reserve_r: float = 0.3
var expand_r: float = 0.1


func _init(owner_id: int, sim_: Sim, rng_: SimRng) -> void:
	super(owner_id, sim_, rng_)
	kind_name = "tribe"
	attack_rate = rng.range_i(40, 79)
	trigger_r = rng.range_f(0.5, 0.59)
	reserve_r = rng.range_f(0.3, 0.39)
	expand_r = rng.range_f(0.1, 0.19)


func think() -> void:
	next_think = sim.st.tick + attack_rate
	var st := sim.st
	var troops := st.o_troops[id]
	var cap := maxf(st.o_cap[id], 1.0)
	var nb := st.neighbours(id, 400)
	if nb.has(0) and sim.attacks.find(id, 0) == null:
		var send := troops - expand_r * cap
		if send >= 100.0:
			submit(Commands.attack_target(id, 0, send))
			log.add(st.tick, "expand", 0, {"troops": send})
		return
	if troops / cap < trigger_r:
		return
	var options: Array = []
	for o: int in nb:
		if o == 0 or not st.is_alive(o):
			continue
		if st.o_kind[o] != Rules.KIND_TRIBE and rng.chance(0.5):
			continue
		options.append(o)
	rng.shuffle(options)
	for o: int in options:
		if st.o_troops[o] < troops:
			var send2 := troops - reserve_r * cap
			if send2 >= 100.0:
				submit(Commands.attack_target(id, o, send2))
				log.add(st.tick, "attack", o, {"troops": send2})
			return
