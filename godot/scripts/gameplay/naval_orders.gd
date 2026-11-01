class_name NavalOrders
extends RefCounted
## Player-facing helpers for sea landings: human-readable reasons, what blocks sending right now
## (troops, supplies, boats in use) and transport lookup. The route itself always comes from
## LandingPlanner — the same code the simulation runs when the order is executed.


static func reason_text(reason: String) -> String:
	match reason:
		"no_land_path":
			return TranslationServer.translate("NAVAL_NO_LAND_PATH")
		"no_landing":
			return TranslationServer.translate("NAVAL_NO_LANDING")
		"no_coast":
			return TranslationServer.translate("NAVAL_NO_COAST")
		"no_route":
			return TranslationServer.translate("NAVAL_NO_ROUTE")
	return TranslationServer.translate("REJECT_" + reason.to_upper())


## Why the prepared order cannot be sent now ("" = it can).
static func blocker(sim: Sim, who: int, plan: Dictionary, troops: float) -> String:
	if plan.is_empty() or not plan.get("ok", false):
		return reason_text(String(plan.get("reason", "no_route")))
	if sim.phase != Sim.Phase.PLAYING:
		return TranslationServer.translate("REJECT_NOT_PLAYING")
	if sim.st.o_boats[who] >= sim.naval.max_boats(who):
		return TranslationServer.translate("REJECT_TOO_MANY_BOATS")
	if sim.st.o_supplies[who] < float(sim.rules.n["boat_supplies"]):
		return TranslationServer.translate("REJECT_NO_SUPPLIES")
	if troops < 1.0:
		return TranslationServer.translate("REJECT_NO_TROOPS")
	return ""


static func boat_by_id(sim: Sim, id: int) -> NavalSystem.Boat:
	if id < 0:
		return null
	for b in sim.naval.boats:
		if b.alive and b.id == id:
			return b
	return null


## A sensible inland goal in state `id` for the "Landing" button (LandingPlanner.key_tile).
static func default_goal(sim: Sim, id: int) -> int:
	return LandingPlanner.key_tile(sim.naval, id)
