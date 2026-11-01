class_name DecisionLog
extends RefCounted
## Ring buffer of one bot's decisions and refusals with their reasons (AI debug panel, AI sim).

var capacity: int = 64
var entries: Array[Dictionary] = []
var counts: Dictionary = {}


func add(tick: int, kind: String, target: int, data: Dictionary = {}) -> void:
	data["tick"] = tick
	data["kind"] = kind
	data["target"] = target
	entries.append(data)
	if entries.size() > capacity:
		entries.pop_front()
	counts[kind] = int(counts.get(kind, 0)) + 1


func last(n: int = 12) -> Array[Dictionary]:
	return entries.slice(maxi(0, entries.size() - n))


static func format(e: Dictionary, name_of: Callable) -> String:
	var s := "t=%d %s" % [e["tick"], String(e["kind"]).to_upper()]
	var tg: int = e.get("target", -1)
	if tg >= 0:
		s += " → %s" % (name_of.call(tg) if tg > 0 else tr_free())
	for k in ["troops", "u", "captured", "loss", "reason", "state", "building"]:
		if e.has(k):
			var v: Variant = e[k]
			s += " %s=%s" % [k, ("%.1f" % v) if typeof(v) == TYPE_FLOAT else str(v)]
	return s


static func tr_free() -> String:
	return TranslationServer.translate("FREE_LAND")


func to_dict() -> Dictionary:
	return {"entries": entries, "counts": counts}


func from_dict(d: Dictionary) -> void:
	entries.assign(d.get("entries", []))
	counts = d.get("counts", {})
