class_name WeaponInfo
extends RefCounted
## Everything the interface says about a weapon, computed from data/weapons/weapons.json and the
## simulation (WeaponSystem), so the arsenal panel, the targeting bar, hints and the encyclopedia
## always show the same numbers.

const GROUPS := {"missile": "missiles", "heavy_missile": "missiles", "cluster": "missiles", "emp": "missiles",
	"artillery": "support", "air_strike": "support", "tactical_nuke": "nuclear", "strategic_nuke": "nuclear", "mirv": "nuclear"}
const GROUP_ORDER := ["support", "missiles", "nuclear"]


static func _t(k: String) -> String:
	return TranslationServer.translate(k)


static func symbol(rules: Rules, w: int) -> String:
	return "w_" + String(rules.weapon(w)["id"])


static func title(rules: Rules, w: int) -> String:
	return _t("WPN_" + String(rules.weapon(w)["id"]).to_upper())


static func short(rules: Rules, w: int) -> String:
	return _t("WPN_" + String(rules.weapon(w)["id"]).to_upper() + "_SHORT")


static func group(rules: Rules, w: int) -> String:
	return String(GROUPS.get(String(rules.weapon(w)["id"]), "missiles"))


## Launcher building kind and its name.
static func launcher_title(rules: Rules, w: int) -> String:
	var k := rules.weapon_launcher_kind(w)
	return BuildingInfo.title(rules, k) if k >= 0 else "?"


## Seconds of flight over `tiles` tiles.
static func flight_secs(rules: Rules, w: int, tiles: float) -> float:
	return tiles / maxf(float(rules.weapon(w)["speed"]), 0.01) / float(rules.tick_rate)


## Effect sentences with exact numbers.
static func effects(rules: Rules, w: int) -> Array[String]:
	var wd := rules.weapon(w)
	var ef: Dictionary = wd["effect"]
	var out: Array[String] = []
	var r := roundi(float(wd["radius"]))
	match String(ef["kind"]):
		"blast":
			out.append(_t("WFX_BLAST") % [r, roundi(float(ef["kill_frac"]) * 100.0)])
			if int(ef.get("struct_levels", 0)) > 0:
				out.append(_t("WFX_STRUCT") % int(ef["struct_levels"]))
		"cluster":
			out.append(_t("WFX_CLUSTER") % [int(ef["bomblets"]), roundi(float(ef["spread"])), r, roundi(float(ef["kill_frac"]) * 100.0)])
			out.append(_t("WFX_STRUCT") % int(ef.get("struct_levels", 0)))
		"nuke":
			out.append(_t("WFX_NUKE") % [roundi(float(wd["radius_inner"])), r])
			out.append(_t("WFX_NUKE_TROOPS"))
			out.append(_t("WFX_FALLOUT") % [roundi(float(rules.w_fallout.get("ticks", 1800)) / float(rules.tick_rate)),
				roundi((1.0 - float(rules.w_fallout.get("value_mult", 0.2))) * 100.0)])
		"mirv":
			out.append(_t("WFX_MIRV") % [int(ef["warheads"]), r])
			out.append(_t("WFX_MIRV_INTERCEPT") % roundi(float(ef.get("warhead_intercept", 0.0)) * 100.0))
		"emp":
			out.append(_t("WFX_EMP") % [r, roundi(float(ef["disable_ticks"]) / float(rules.tick_rate))])
	var p := float(wd.get("intercept", 0.0))
	if String(ef["kind"]) != "mirv":
		out.append(_t("WFX_INTERCEPT") % roundi(p * 100.0) if p > 0.0 else _t("WFX_NO_INTERCEPT"))
	return out


## Key figures: [label, value, colour?].
static func rows(rules: Rules, w: int) -> Array:
	var wd := rules.weapon(w)
	var out: Array = [[_t("BI_COST"), UITheme.num(float(wd["cost"])), UITheme.GOLD],
		[_t("BI_SUPPLIES"), UITheme.num(float(wd["supplies"])), UITheme.SUPPLY],
		[_t("WPN_LAUNCHER"), launcher_title(rules, w)]]
	var rg := float(wd.get("range", 0.0))
	out.append([_t("WPN_RANGE"), _t("BI_TILES") % roundi(rg) if rg > 0.0 else _t("WPN_RANGE_ANY")])
	out.append([_t("WPN_RELOAD"), "%d %s" % [ceili(float(rules.launcher_reload(w)) / float(rules.tick_rate)), _t("SEC_SHORT")]])
	return out


## Ready charges of `who`'s launchers for `w`: {"ready", "total", "launchers", "reload_left" (ticks)}.
static func readiness(sim: Sim, w: int, who: int) -> Dictionary:
	var ready := 0
	var total := 0
	var soon := -1
	var per := sim.rules.launcher_charges_per_level(w)
	var ls := sim.weapons.launchers_for(who, w, -1)
	for l: Dictionary in ls:
		ready += int(l["charges"])
		total += sim.weapons.capacity(l["s"], per)
		var rl := int(l["reload_left"])
		if rl > 0 and (soon < 0 or rl < soon):
			soon = rl
	return {"ready": ready, "total": total, "launchers": ls.size(), "reload_left": soon}


## Human-readable launch refusal.
static func reason_text(sim: Sim, w: int, reason: String) -> String:
	match reason:
		"locked":
			return _t("WPN_NEEDS_TECH") % MetaData.text(ResearchSystem.tech(String(sim.rules.weapon(w)["requires"])).get("name", {}))
		"no_launcher":
			return _t("WPN_NEEDS_LAUNCHER") % launcher_title(sim.rules, w)
		"out_of_range":
			return _t("WPN_OUT_OF_RANGE") % roundi(float(sim.rules.weapon(w).get("range", 0.0)))
		"reloading":
			return _t("WPN_RELOADING")
		"own_land":
			return _t("WPN_OWN_LAND")
	return _t("REJECT_" + reason.to_upper())


## What blocks aiming at all right now (before a target is chosen): "" = can aim.
static func blocker(sim: Sim, w: int, who: int) -> String:
	if not sim.weapons.unlocked(who, w):
		return reason_text(sim, w, "locked")
	var rd := readiness(sim, w, who)
	if int(rd["launchers"]) == 0:
		return reason_text(sim, w, "no_launcher")
	var wd := sim.rules.weapon(w)
	if sim.st.o_gold[who] < float(wd["cost"]):
		return _t("REJECT_NO_GOLD")
	if sim.st.o_supplies[who] < float(wd["supplies"]):
		return _t("REJECT_NO_SUPPLIES")
	if int(rd["ready"]) == 0:
		return reason_text(sim, w, "reloading")
	return ""


## Hint card for a weapon (title, short text, key figures, reason when unavailable).
static func hint(sim: Sim, w: int, who: int) -> Dictionary:
	var rows_: Array = rows(sim.rules, w)
	var rd := readiness(sim, w, who)
	rows_.append([_t("WPN_READY"), "%d / %d" % [int(rd["ready"]), int(rd["total"])]])
	return {"title": title(sim.rules, w), "text": short(sim.rules, w), "rows": rows_, "reason": blocker(sim, w, who),
		"effect": "\n".join(effects(sim.rules, w))}


## One line summarising a preview estimate: losses by state, buildings, our own land, interception.
static func estimate_lines(sim: Sim, who: int, est: Dictionary) -> Array:
	var out: Array = []
	var killed: Dictionary = est.get("killed", {})
	var tiles: Dictionary = est.get("tiles", {})
	var parts := PackedStringArray()
	var owners: Array = tiles.keys()
	owners.sort_custom(func(a: int, b: int) -> bool: return int(tiles[a]) > int(tiles[b]))
	for o: int in owners:
		if o == who:
			continue
		var k := float(killed.get(o, 0.0))
		parts.append(_t("WPN_EST_OWNER") % [sim.st.o_name[o], UITheme.num(k)] if k > 0.0 else sim.st.o_name[o])
		if parts.size() >= 2:
			break
	if not parts.is_empty():
		out.append([", ".join(parts), UITheme.TEXT_DIM])
	var n_struct := (est.get("structures", []) as Array).size()
	if n_struct > 0:
		out.append([_t("WPN_EST_BUILDINGS") % n_struct, UITheme.TEXT_DIM])
	if int(est.get("own_tiles", 0)) > 0 or int(est.get("own_structures", 0)) > 0:
		out.append([_t("WPN_EST_FRIENDLY") % [int(est.get("own_tiles", 0)), int(est.get("own_structures", 0))], UITheme.WARN])
	var ir: Dictionary = est.get("intercept", {})
	if int(ir.get("sams", 0)) > 0:
		out.append([_t("WPN_EST_INTERCEPT") % [roundi(float(ir["chance"]) * 100.0), int(ir["sams"])], UITheme.WARN if float(ir["chance"]) > 0.3 else UITheme.TEXT_DIM])
	return out
