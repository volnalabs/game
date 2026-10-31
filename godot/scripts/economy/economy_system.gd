class_name EconomySystem
extends RefCounted
## Gold, supplies, troop capacity, troop growth and army upkeep (docs/game-design/GAME_DESIGN.md §5).
## Troop cap and growth follow RoWorld (Rules.luau:133-163); gold from territory value and
## buildings, supplies from factories and the army upkeep are VolnaLabs' own economy.

const TRADE_EVERY := 50

var st: SimState
var rules: Rules
var structures: StructureSystem
var mods: Modifiers


func _init(state: SimState, rules_: Rules, structs: StructureSystem) -> void:
	st = state
	rules = rules_
	structures = structs


func tick() -> void:
	if st.tick % TRADE_EVERY == 0:
		_update_trade()
	var e := rules.e
	var desertion: float = e["desertion_rate"]
	var sup_max: float = e["supplies_max"]
	for id in range(1, st.owner_count + 1):
		if st.o_alive[id] == 0 or st.o_spawned[id] == 0 or st.o_tiles[id] <= 0:
			continue
		var kind := st.o_kind[id]
		var cities := st.blevel(id, Rules.B_CITY)
		var factories := st.blevel(id, Rules.B_FACTORY)
		var cap := rules.troop_cap(kind, st.o_tiles[id], cities) * mods.mult("cap_mult", id)
		var troops := st.o_troops[id]
		var income := rules.gold_income(kind, st.o_value[id], cities, st.o_port_trade[id], factories) * mods.mult("gold_mult", id)
		var upkeep := rules.upkeep(troops, cap) * mods.mult("upkeep_mult", id)
		var sup := rules.supplies_income(factories) * mods.mult("supply_mult", id)
		var gold := st.o_gold[id] + income - upkeep
		var growth := 0.0
		if gold < 0.0:
			# Bankrupt: no growth, part of the army above the free share deserts.
			var excess := maxf(0.0, troops - cap * float(e["upkeep_free_share"]))
			growth = -excess * desertion
			gold = 0.0
		else:
			growth = rules.troop_growth(kind, troops, cap)
			if growth > 0.0:
				growth *= mods.mult("growth_mult", id)
		st.add_gold(id, gold - st.o_gold[id])
		st.stat_gold(id, income, 0.0, minf(upkeep, st.o_gold[id] + upkeep))
		st.add_supplies(id, minf(sup, sup_max - st.o_supplies[id]))
		st.set_troops(id, troops + growth)
		st.set_economy(id, cap, income, upkeep, sup, growth)


## Port trade: each port level earns a base income plus a bonus for the port levels of other
## owners on the same water body (abstract trade routes; trade ships come in a later phase).
func _update_trade() -> void:
	var e := rules.e
	var by_body: Dictionary = {}
	var ports := []
	for s in structures.structs:
		if s.alive and s.kind == Rules.B_PORT and s.counted() > 0:
			var body := st.map.coast_body[s.tile]
			if not by_body.has(body):
				by_body[body] = {}
			var d: Dictionary = by_body[body]
			d[s.owner] = int(d.get(s.owner, 0)) + s.counted()
			ports.append(s)
	var trade := PackedFloat64Array()
	trade.resize(st.owner_count + 1)
	for s in ports:
		var d: Dictionary = by_body[st.map.coast_body[s.tile]]
		var others := 0
		for o: int in d:
			if o != s.owner:
				others += int(d[o])
		var bonus := minf(float(others) * float(e["port_trade_partner"]), e["port_trade_partner_max"])
		trade[s.owner] += float(s.counted()) * (float(e["port_trade_base"]) + bonus)
	for id in range(1, st.owner_count + 1):
		st.set_port_trade(id, trade[id])
