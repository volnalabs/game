class_name Glossary
extends RefCounted
## Plain-language explanations of resources and game terms (data/help/glossary.json): what it is,
## where it comes from, what it is spent on, what happens when it runs short, how to get more.

static var _d: Dictionary = {}


static func data() -> Dictionary:
	if _d.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/help/glossary.json"))
		_d = (v as Dictionary)["terms"] if v is Dictionary else {}
	return _d


static func has(term: String) -> bool:
	return data().has(term)


static func term_name(term: String) -> String:
	return MetaData.text(data().get(term, {}).get("name", term))


## A hint dictionary for HintLayer; `extra_rows` are prepended (live numbers).
static func hint(term: String, extra_rows: Array = []) -> Dictionary:
	var t: Dictionary = data().get(term, {})
	if t.is_empty():
		return {}
	var rows: Array = extra_rows.duplicate()
	for k in ["from", "spend", "short", "more"]:
		if t.has(k):
			rows.append([TranslationServer.translate("GLOSS_" + k.to_upper()), MetaData.text(t[k])])
	return {"title": MetaData.text(t["name"]), "icon": String(t.get("icon", "")), "text": MetaData.text(t["what"]), "rows": rows}
