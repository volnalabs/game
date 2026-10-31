class_name SaveFormat
extends RefCounted
## Save format versions and the migration chain. Each step upgrades a save by one version; a
## save is migrated step by step up to VERSION when it is loaded.
##   v1 — 0.1.0: first format.
##   v2 — Phase 2D: building arrays with stride Rules.MAX_BUILDING_KINDS (was 6); research state.

const VERSION := 2
const V1_BUILDING_STRIDE := 6

## version -> Callable(header: Dictionary, state: Dictionary) upgrading to version + 1.
static var _steps: Dictionary = {1: _v1_to_v2}


## Re-strides the per-owner building arrays and adds an empty research state.
static func _v1_to_v2(_header: Dictionary, state: Dictionary) -> void:
	var s: Dictionary = state.get("state", {})
	for f in ["o_blevels", "o_bowned"]:
		if not s.has(f):
			continue
		var old: PackedInt32Array = PackedInt32Array(s[f])
		var owners := old.size() / V1_BUILDING_STRIDE
		var out := PackedInt32Array()
		out.resize(owners * Rules.MAX_BUILDING_KINDS)
		for o in owners:
			for k in V1_BUILDING_STRIDE:
				out[o * Rules.MAX_BUILDING_KINDS + k] = old[o * V1_BUILDING_STRIDE + k]
		s[f] = out
	if not state.has("research"):
		state["research"] = {}


static func migrate(version: int, header: Dictionary, state: Dictionary) -> Dictionary:
	var v := version
	while v < VERSION:
		if not _steps.has(v):
			push_error("SaveFormat: no migration from version %d" % v)
			return {}
		(_steps[v] as Callable).call(header, state)
		v += 1
	if v > VERSION:
		push_error("SaveFormat: save version %d is newer than this game (%d)" % [v, VERSION])
		return {}
	header["version"] = VERSION
	return {"header": header, "state": state}
