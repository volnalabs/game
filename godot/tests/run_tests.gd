extends SceneTree
## Headless test runner: godot --headless --path godot -s res://tests/run_tests.gd [-- filter]
## Runs every test_* method of every tests/**/test_*.gd; exits with 1 if anything failed.

func _init() -> void:
	# Autoloads are not ready inside _init: run on the first frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Tests never touch the player's real profile.
	var prof := root.get_node_or_null("Profile")
	if prof != null:
		prof.store = ProfileStore.new("user://test_profile.json")
		prof.data = ProfileData.fresh()
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files: Array[String] = []
	for sub in ["unit", "integration", "ui", "ai", "performance"]:
		_collect("res://tests/" + sub, files)
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		if filter != "" and not path.contains(filter):
			continue
		var script: GDScript = load(path)
		if script == null:
			print("LOAD FAIL ", path)
			failed += 1
			continue
		var inst: Object = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and filter.contains(":") and not (path + ":" + mname).contains(filter):
				continue
			total += 1
			inst.set("_current", path.get_file() + ":" + mname)
			inst.call("before_each")
			var before: int = (inst.get("failures") as Array).size()
			var ts := Time.get_ticks_msec()
			await inst.call(mname)
			var dt := Time.get_ticks_msec() - ts
			var fails: Array = inst.get("failures")
			if fails.size() > before:
				failed += 1
				print("FAIL  %s:%s (%d ms)" % [path.get_file(), mname, dt])
				for k in range(before, fails.size()):
					print("      ", fails[k])
			else:
				print("ok    %s:%s (%d ms)" % [path.get_file(), mname, dt])
	print("\n%d tests, %d failed, %.1f s" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
