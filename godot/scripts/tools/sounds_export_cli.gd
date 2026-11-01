extends SceneTree
## Writes every synthesized sound (data/audio/sounds.json) to a WAV file for listening.
##   godot --headless --path godot -s res://scripts/tools/sounds_export_cli.gd -- <out_dir>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/sounds"
	DirAccess.make_dir_recursive_absolute(out)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/sounds.json"))
	for id: String in d["sounds"]:
		var w := SoundSynth.build(d["sounds"][id])
		w.save_to_wav(out.path_join(id + ".wav"))
		print("%-16s %.2f s" % [id, w.get_length()])
	quit()
