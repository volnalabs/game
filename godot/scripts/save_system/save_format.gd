class_name SaveFormat
extends RefCounted
## Save format versions and the migration chain. Each step upgrades a save by one version; a
## save is migrated step by step up to VERSION when it is loaded.
##   v1 — 0.1.0: first format.

const VERSION := 1

## version -> Callable(header: Dictionary, state: Dictionary) upgrading to version + 1.
static var _steps: Dictionary = {}


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
