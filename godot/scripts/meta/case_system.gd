class_name CaseSystem
extends RefCounted
## Cases: buying with Credits, odds, pity and opening. The result is decided completely by roll()
## before any animation; the opening screen only shows it. Duplicates become fragments + Credits.
## The RNG state lives in the profile (case_seed), so a result cannot be re-rolled by reopening
## the screen.


## Odds (percent by rarity) for a case.
static func odds(case_id: String) -> Dictionary:
	return MetaData.case_def(case_id).get("odds", MetaData.rarity()["odds"])


## Whether a seasonal case is available on a date ("MM-DD").
static func available(case_id: String, month_day: String) -> bool:
	var c := MetaData.case_def(case_id)
	if c.is_empty():
		return false
	if not c.has("event"):
		return true
	var from := String(c["event"]["from"])
	var to := String(c["event"]["to"])
	if from <= to:
		return month_day >= from and month_day <= to
	return month_day >= from or month_day <= to


static func today_md() -> String:
	var d := Time.get_date_dict_from_system()
	return "%02d-%02d" % [int(d["month"]), int(d["day"])]


static func buy(p: ProfileData, case_id: String) -> bool:
	var c := MetaData.case_def(case_id)
	if c.is_empty() or not available(case_id, today_md()):
		return false
	var price := int(c["price"])
	if p.credits() < price:
		return false
	p.data["credits"] = p.credits() - price
	p.data["cases"][case_id] = p.case_count(case_id) + 1
	return true


## Rolls a case: rarity by the case odds with pity guarantees, then an item of that rarity from the
## case's categories (unowned items preferred 2:1). Pure given the RNG; pity counters are inputs.
static func roll(case_id: String, pity: Dictionary, rng: RandomNumberGenerator, owned: Dictionary) -> Dictionary:
	var c := MetaData.case_def(case_id)
	var order: Array = MetaData.rarity_order()
	var o := odds(case_id)
	var P: Dictionary = MetaData.rarity()["pity"]
	var rarity := ""
	var forced := ""
	if int(pity.get("legendary", 0)) + 1 >= int(P["legendary_after"]) and float(o.get("legendary", 0)) > 0.0:
		rarity = "legendary"
		forced = "legendary"
	elif int(pity.get("epic", 0)) + 1 >= int(P["epic_or_better_after"]):
		# Epic or better, keeping the case's relative odds between them.
		var ep := float(o.get("epic", 0))
		var lg := float(o.get("legendary", 0))
		rarity = "legendary" if rng.randf() * maxf(ep + lg, 0.0001) < lg else "epic"
		forced = "epic"
	else:
		var x := rng.randf() * 100.0
		var acc := 0.0
		for r: String in order:
			acc += float(o.get(r, 0))
			if x < acc:
				rarity = r
				break
		if rarity == "":
			rarity = order[0]
	var pool: Array = []
	for it: Dictionary in MetaData.items():
		if it["rarity"] == rarity and (c["categories"] as Array).has(it["category"]):
			pool.append(it)
	if pool.is_empty():
		return {}
	var weights: Array = []
	var total := 0.0
	for it: Dictionary in pool:
		var w := 1.0 if owned.has(it["id"]) else 2.0
		weights.append(w)
		total += w
	var y := rng.randf() * total
	var pick: Dictionary = pool[pool.size() - 1]
	for i in pool.size():
		y -= float(weights[i])
		if y <= 0.0:
			pick = pool[i]
			break
	return {"item": pick["id"], "rarity": rarity, "pity_forced": forced}


## Opens one owned case of `case_id`: rolls, grants the item (or converts a duplicate), updates
## pity. Returns the outcome for the opening screen: {"item", "rarity", "duplicate", "fragments",
## "credits", "pity_forced"} or {} when no such case is owned.
static func open_case(p: ProfileData, case_id: String) -> Dictionary:
	if p.case_count(case_id) <= 0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.data["case_seed"])
	var out := roll(case_id, p.data["pity"], rng, p.data["owned"])
	p.data["case_seed"] = int(rng.randi())
	if out.is_empty():
		return {}
	p.data["cases"][case_id] = p.case_count(case_id) - 1
	p.data["cases_opened"] = int(p.data["cases_opened"]) + 1
	var rar := String(out["rarity"])
	var order: Array = MetaData.rarity_order()
	var pity: Dictionary = p.data["pity"]
	pity["epic"] = 0 if order.find(rar) >= order.find("epic") else int(pity["epic"]) + 1
	pity["legendary"] = 0 if rar == "legendary" else int(pity["legendary"]) + 1
	out.merge(Inventory.grant(p, String(out["item"])))
	return out
