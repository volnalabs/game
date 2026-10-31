class_name Encyclopedia
extends RefCounted
## The in-game encyclopedia: handwritten articles (data/help/encyclopedia.json) plus articles
## generated from the game data — every building (BuildingInfo, Symbols), every technology
## (tech_tree.json) and every glossary term — so the numbers always match the game.

static var _rules: Rules


static func rules() -> Rules:
	if _rules == null:
		_rules = Rules.for_k(1.0)
	return _rules


static func categories() -> Array:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/help/encyclopedia.json"))
	return d["categories"]


## All articles: {"id", "category", "title", "icon", "kind": "text"|"building"|"tech"|"term", ...}.
static func articles() -> Array:
	var out: Array = []
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/help/encyclopedia.json"))
	for a: Dictionary in d["articles"]:
		out.append({"id": a["id"], "category": a["category"], "title": MetaData.text(a["title"]), "icon": a.get("icon", ""),
			"kind": "text", "body": MetaData.text(a["body"])})
	var r := rules()
	for k in GameHUD.build_kinds(r):
		out.append({"id": "b_" + r.b_ids[k], "category": "buildings", "title": BuildingInfo.title(r, k),
			"icon": Symbols.building_id(r, k), "kind": "building", "building": k})
	for w in r.w_list.size():
		out.append({"id": "w_" + String(r.weapon(w)["id"]), "category": "weapons", "title": WeaponInfo.title(r, w),
			"icon": WeaponInfo.symbol(r, w), "kind": "weapon", "weapon": w})
	for t: Dictionary in ResearchSystem.techs():
		out.append({"id": "t_" + String(t["id"]), "category": "research", "title": MetaData.text(t["name"]), "icon": "r_research",
			"kind": "tech", "tech": t["id"]})
	for term: String in Glossary.data():
		var cat := "economy" if term in ["gold", "income", "upkeep", "supplies", "army", "army_cap", "research", "territory", "cost", "build_time"] else "interface"
		if term in ["launcher", "fallout"]:
			cat = "weapons"
		elif term == "interception":
			cat = "air_defence"
		out.append({"id": "g_" + term, "category": cat,
			"title": Glossary.term_name(term), "icon": String(Glossary.data()[term].get("icon", "")), "kind": "term", "term": term})
	return out


static func find(id: String) -> Dictionary:
	for a: Dictionary in articles():
		if a["id"] == id:
			return a
	return {}
