class_name BuildingInfo
extends RefCounted
## Everything the interface says about a building kind, in one place: name, plain description,
## effect lines computed from data/buildings/buildings.json and data/rules (numbers never drift),
## key figures and requirements, menu category. Used by the build menu, quick build, map hints, the
## inspector and the encyclopedia.

const CATEGORIES := ["economy", "military", "defense", "science"]
const CATEGORY_OF := {"city": "economy", "port": "economy", "factory": "economy", "power_plant": "economy",
	"military_academy": "military", "airbase": "military", "command_center": "military", "naval_base": "military",
	"defense": "defense", "bunker": "defense", "radar": "defense", "sam": "defense", "silo": "military",
	"research_center": "science", "logistics_hub": "science"}


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


static func id_of(rules: Rules, kind: int) -> String:
	return rules.b_ids[kind]


static func title(rules: Rules, kind: int) -> String:
	return _t("B_" + id_of(rules, kind).to_upper())


## One plain sentence: what the building is for.
static func short(rules: Rules, kind: int) -> String:
	return _t("B_%s_SHORT" % id_of(rules, kind).to_upper())


static func category(rules: Rules, kind: int) -> String:
	return CATEGORY_OF.get(id_of(rules, kind), "economy")


## Effect lines with exact numbers from the data.
static func effects(rules: Rules, kind: int) -> Array[String]:
	var out: Array[String] = []
	var e := rules.e
	var per_s := float(rules.tick_rate)
	var ef := rules.building_effect(kind)
	var r := roundi(rules.building_radius(kind))
	match id_of(rules, kind):
		"city":
			out.append(_t("FX_CITY_CAP") % UITheme.num(float(e["troop_cap_city"])))
			out.append(_t("FX_CITY_GOLD") % UITheme.num(float(e["gold_city"]) * per_s))
		"port":
			out.append(_t("FX_PORT_TRADE") % UITheme.num(float(e["port_trade_base"]) * per_s))
			out.append(_t("FX_PORT_PARTNER") % [UITheme.num(float(e["port_trade_partner"]) * per_s), UITheme.num(float(e["port_trade_partner_max"]) * per_s)])
		"factory":
			out.append(_t("FX_FACTORY_INCOME") % [roundi(float(e["factory_income_bonus"]) * 100.0), roundi(float(e["factory_income_bonus_max"]) * 100.0)])
			out.append(_t("FX_FACTORY_SUPPLIES") % UITheme.num(float(e["supplies_factory"]) * per_s))
		"defense":
			var d: Dictionary = rules.b_kinds[kind]
			out.append(_t("FX_DEFENSE") % [r, float(d.get("mag_mult", 1.0)), float(d.get("cost_mult", 1.0))])
			out.append(_t("FX_DEFENSE_LOST"))
		"research_center":
			out.append(_t("FX_RESEARCH") % str(ef.get("research_per_level", 0)))
		"radar":
			out.append(_t("FX_RADAR") % [r, roundi(float(ef.get("landing_loss", 0)) * 100.0)])
		"airbase":
			out.append(_t("FX_AIRBASE") % [r, roundi((1.0 - float(ef.get("attack_loss_mult", 1.0))) * 100.0)])
		"military_academy":
			out.append(_t("FX_ACADEMY") % [roundi(float(ef.get("attack_loss_per_level", 0)) * 100.0), int(ef.get("max_levels", 1))])
		"logistics_hub":
			out.append(_t("FX_LOGISTICS") % [roundi(float(ef.get("growth_per_level", 0)) * 100.0), int(ef.get("max_levels", 1))])
		"command_center":
			out.append(_t("FX_COMMAND") % [roundi(float(ef.get("retreat_keep_per_level", 0)) * 100.0),
				roundi(float(ef.get("attack_speed_per_level", 0)) * 100.0), int(ef.get("max_levels", 1))])
		"bunker":
			out.append(_t("FX_BUNKER") % r)
		"power_plant":
			out.append(_t("FX_POWER") % [roundi(float(ef.get("factory_output_per_level", 0)) * 100.0), int(ef.get("max_levels", 1))])
		"naval_base":
			out.append(_t("FX_NAVAL") % [roundi(float(ef.get("boat_speed_per_level", 0)) * 100.0), int(ef.get("boat_limit_per_level", 0)), int(ef.get("max_levels", 1))])
	if rules.building_upgradable(kind) and not ["defense", "bunker", "radar"].has(id_of(rules, kind)):
		out.append(_t("FX_UPGRADE"))
	return out


## Key figures as [label, value] rows (cost for `who`, supplies, build time, radius, placement).
static func rows(sim: Sim, kind: int, who: int) -> Array:
	var r := sim.rules
	var out: Array = []
	out.append([_t("BI_COST"), UITheme.num(sim.structures.cost(who, kind)) if who > 0 else UITheme.num(r.building_cost(kind, 0)), UITheme.GOLD])
	if r.building_supplies(kind) > 0.0:
		out.append([_t("BI_SUPPLIES"), UITheme.num(r.building_supplies(kind)), UITheme.SUPPLY])
	out.append([_t("BI_TIME"), "%d %s" % [ceili(float(r.building_ticks(kind)) / float(r.tick_rate)), _t("SEC_SHORT")]])
	if r.building_radius(kind) > 0.0:
		out.append([_t("BI_RADIUS"), _t("BI_TILES") % roundi(r.building_radius(kind))])
	if r.building_coastal(kind):
		out.append([_t("BI_PLACE"), _t("BI_COAST")])
	var req := r.building_requires(kind)
	if req != "":
		var ok := who > 0 and sim.research.has_tech(who, req)
		out.append([_t("BI_REQUIRES"), MetaData.text(ResearchSystem.tech(req).get("name", {})), UITheme.GOOD if ok else UITheme.WARN])
	return out


## Why `who` cannot order this kind right now ("" if it can, ignoring placement).
static func blocker(sim: Sim, kind: int, who: int) -> String:
	if who <= 0 or not sim.is_player_alive():
		return ""
	var r := sim.rules
	if not sim.structures.unlocked(who, kind):
		return _t("BUILD_REQUIRES") % MetaData.text(ResearchSystem.tech(r.building_requires(kind)).get("name", {}))
	var gold := sim.structures.cost(who, kind) - sim.st.o_gold[who]
	if gold > 0.0:
		return _t("NEED_GOLD") % UITheme.num(gold)
	var sup := r.building_supplies(kind) - sim.st.o_supplies[who]
	if sup > 0.0:
		return _t("NEED_SUPPLIES") % UITheme.num(sup)
	return ""


## Hint dictionary for a building kind (build menu, quick build).
static func hint(sim: Sim, kind: int, who: int, hotkey: String = "") -> Dictionary:
	var lines := "\n".join(effects(sim.rules, kind))
	return {"title": title(sim.rules, kind), "icon": Symbols.building_id(sim.rules, kind), "text": short(sim.rules, kind),
		"effect": lines, "rows": rows(sim, kind, who), "reason": blocker(sim, kind, who), "hotkey": hotkey}


## Hint for a built structure on the map.
static func structure_hint(sim: Sim, s: StructureSystem.Structure) -> Dictionary:
	var rows_: Array = [[_t("BI_OWNER"), sim.st.o_name[s.owner], sim.st.o_color[s.owner].lightened(0.3)]]
	if s.level > 1 or sim.rules.building_upgradable(s.kind):
		rows_.append([_t("BI_LEVEL"), str(s.level)])
	if s.done_tick > 0:
		rows_.append([_t("BI_STATUS"), _t("BI_BUILDING_LEFT") % ceili(float(s.done_tick - sim.st.tick) / float(sim.rules.tick_rate)), UITheme.WARN])
	if sim.rules.building_radius(s.kind) > 0.0:
		rows_.append([_t("BI_RADIUS"), _t("BI_TILES") % roundi(sim.rules.building_radius(s.kind))])
	return {"title": title(sim.rules, s.kind), "icon": Symbols.building_id(sim.rules, s.kind), "text": short(sim.rules, s.kind),
		"effect": "\n".join(effects(sim.rules, s.kind)), "rows": rows_}


## Compact hover card: name, what it is for, one or two key figures.
static func structure_brief(sim: Sim, s: StructureSystem.Structure) -> Dictionary:
	var rows_: Array = []
	var eff := effects(sim.rules, s.kind)
	if s.done_tick > 0:
		rows_.append([_t("BI_STATUS"), _t("BI_BUILDING_LEFT") % ceili(float(s.done_tick - sim.st.tick) / float(sim.rules.tick_rate)), UITheme.WARN])
	elif s.level > 1:
		rows_.append([_t("BI_LEVEL"), str(s.level)])
	if s.owner != sim.player_id:
		rows_.append([_t("BI_OWNER"), sim.st.o_name[s.owner]])
	return {"title": title(sim.rules, s.kind), "icon": Symbols.building_id(sim.rules, s.kind),
		"text": eff[0] if not eff.is_empty() else short(sim.rules, s.kind), "rows": rows_}
