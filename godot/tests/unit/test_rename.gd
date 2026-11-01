extends TestCase
## The game is TerraFront; data saved under the old name moves over once and is never overwritten.


func test_project_is_called_terrafront() -> void:
	check_eq(String(ProjectSettings.get_setting("application/config/name")), "TerraFront", "project name")
	check(tr("FOOTER_COPYRIGHT").contains("© OpenFront and Contributors"), "AGPL §7 notice kept")
	check(not String(ProjectSettings.get_setting("application/config/name")).contains("OpenFront"), "not titled OpenFront")


func test_old_user_data_is_migrated_once() -> void:
	var base := OS.get_user_data_dir().path_join("rename_test")
	var old := base.path_join("old")
	var here := base.path_join("new")
	DirAccess.make_dir_recursive_absolute(old.path_join("saves"))
	var f := FileAccess.open(old.path_join("profile.json"), FileAccess.WRITE)
	f.store_string("{\"old\": true}")
	f.close()
	f = FileAccess.open(old.path_join("saves/a.sav"), FileAccess.WRITE)
	f.store_string("save")
	f.close()
	check(Settings.migrate_dir(old, here), "copied into the empty new folder")
	check(FileAccess.file_exists(here.path_join("profile.json")) and FileAccess.file_exists(here.path_join("saves/a.sav")), "profile and saves moved")
	f = FileAccess.open(here.path_join("profile.json"), FileAccess.WRITE)
	f.store_string("{\"new\": true}")
	f.close()
	check(not Settings.migrate_dir(old, here), "never again once the new folder has data")
	check(FileAccess.get_file_as_string(here.path_join("profile.json")).contains("new"), "new data is not overwritten")
	for p in [old.path_join("saves/a.sav"), old.path_join("profile.json"), here.path_join("saves/a.sav"), here.path_join("profile.json")]:
		DirAccess.remove_absolute(p)
	for p in [old.path_join("saves"), here.path_join("saves"), old, here, base]:
		DirAccess.remove_absolute(p)
