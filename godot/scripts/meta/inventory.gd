class_name Inventory
extends RefCounted
## Owned cosmetic items: granting (duplicates → fragments + Credits), equipping per category,
## crafting with fragments, and listing with search / filter / sort for the inventory screen.


## Gives an item; a duplicate is converted. Returns {"duplicate", "fragments", "credits"}.
static func grant(p: ProfileData, item_id: String) -> Dictionary:
	var it := MetaData.item(item_id)
	if it.is_empty():
		return {"duplicate": false, "fragments": 0, "credits": 0}
	if p.owns(item_id):
		var R := MetaData.rarity()
		var fr := int(R["duplicate_fragments"][it["rarity"]])
		var cr := int(R["duplicate_credits"][it["rarity"]])
		p.data["fragments"] = p.fragments() + fr
		p.data["credits"] = p.credits() + cr
		p.data["owned"][item_id] = int(p.data["owned"][item_id]) + 1
		return {"duplicate": true, "fragments": fr, "credits": cr}
	p.data["owned"][item_id] = 1
	return {"duplicate": false, "fragments": 0, "credits": 0}


static func equip(p: ProfileData, item_id: String) -> bool:
	if not p.owns(item_id):
		return false
	var it := MetaData.item(item_id)
	p.data["equipped"][String(it["category"])] = item_id
	return true


## Removes the item of a category (the four identity categories always keep one item).
static func unequip(p: ProfileData, category: String) -> bool:
	if category in ["avatar", "emblem", "frame", "title"]:
		return false
	return (p.data["equipped"] as Dictionary).erase(category)


static func craft_cost(item_id: String) -> int:
	var it := MetaData.item(item_id)
	return int(MetaData.rarity()["craft_cost"][it["rarity"]]) if not it.is_empty() else 0


## Crafts an unowned item with fragments.
static func craft(p: ProfileData, item_id: String) -> bool:
	if MetaData.item(item_id).is_empty() or p.owns(item_id):
		return false
	var cost := craft_cost(item_id)
	if p.fragments() < cost:
		return false
	p.data["fragments"] = p.fragments() - cost
	grant(p, item_id)
	return true


## Items for the inventory screen. filter: {"category", "rarity", "owned_only", "search"};
## sort: "rarity" (best first), "name", "category".
static func list(p: ProfileData, filter: Dictionary = {}, sort: String = "rarity") -> Array:
	var order: Array = MetaData.rarity_order()
	var out: Array = []
	var q := String(filter.get("search", "")).to_lower()
	for it: Dictionary in MetaData.items():
		if filter.get("category", "") != "" and it["category"] != filter["category"]:
			continue
		if filter.get("rarity", "") != "" and it["rarity"] != filter["rarity"]:
			continue
		if bool(filter.get("owned_only", false)) and not p.owns(String(it["id"])):
			continue
		if q != "" and not MetaData.text(it["name"]).to_lower().contains(q):
			continue
		out.append(it)
	match sort:
		"name":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return MetaData.text(a["name"]) < MetaData.text(b["name"]))
		"category":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a["category"] < b["category"] or (a["category"] == b["category"] and order.find(a["rarity"]) > order.find(b["rarity"])))
		_:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ra := order.find(a["rarity"])
				var rb := order.find(b["rarity"])
				return ra > rb or (ra == rb and MetaData.text(a["name"]) < MetaData.text(b["name"])))
	return out
