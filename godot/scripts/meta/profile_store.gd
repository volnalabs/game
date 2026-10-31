class_name ProfileStore
extends RefCounted
## Reads and writes the profile file safely: write to a temporary file, keep the previous version as
## .bak, then replace. A corrupted file is kept aside (.corrupt-<time>) and the backup is used; if
## that fails too a fresh profile starts. Never throws away data silently.

var path: String
## What happened on the last load: "ok", "new", "restored_backup", "reset_corrupt".
var last_load: String = ""


func _init(path_: String = "user://profile.json") -> void:
	path = path_


func load_profile() -> ProfileData:
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		last_load = "new"
		return ProfileData.fresh()
	var d := _read(path)
	if not d.is_empty():
		last_load = "ok"
		return ProfileData.from_dict(d)
	if FileAccess.file_exists(path):
		_quarantine(path)
	var b := _read(path + ".bak")
	if not b.is_empty():
		last_load = "restored_backup"
		var p := ProfileData.from_dict(b)
		save_profile(p)
		return p
	last_load = "reset_corrupt"
	return ProfileData.fresh()


func save_profile(p: ProfileData) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("ProfileStore: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(p.to_dict(), "\t"))
	f.close()
	# The just-written file must read back before it replaces anything.
	if _read(tmp).is_empty():
		push_warning("ProfileStore: verification of %s failed" % tmp)
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(tmp, path) == OK


func _read(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var j := JSON.new()
	if j.parse(txt) != OK or not j.data is Dictionary:
		return {}
	var d: Dictionary = j.data
	if not d.has("version") and not d.has("xp"):
		return {}
	return d


func _quarantine(p: String) -> void:
	var dst := "%s.corrupt-%d" % [p, int(Time.get_unix_time_from_system())]
	DirAccess.rename_absolute(p, dst)
	push_warning("ProfileStore: %s was unreadable, kept as %s" % [p, dst])
