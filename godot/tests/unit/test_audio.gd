extends TestCase
## Phase 2G: synthesized sounds — every sound builds, is deterministic, never clips, fits its bus;
## events that concern the player sound; volumes reach the buses; buttons click.


func _audio() -> Node:
	return Engine.get_main_loop().root.get_node("Audio")


func test_every_sound_builds_and_never_clips() -> void:
	var a := _audio()
	check(a.defs.size() >= 20, "a sound library (%d)" % a.defs.size())
	for id: String in a.defs:
		var w: AudioStreamWAV = SoundSynth.build(a.defs[id])
		check(w.data.size() > 200, "%s has samples" % id)
		var peak := 0
		for i in range(0, w.data.size(), 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		check(peak > 3000 and peak <= 32767, "%s audible, not clipped (peak %d)" % [id, peak])
		check(String(a.defs[id]["bus"]) in ["ui", "sfx", "alerts", "ambience"], "%s on a known bus" % id)
		check(w.get_length() <= 8.0, "%s short enough" % id)


func test_sounds_are_deterministic_and_the_ambience_loops() -> void:
	var a := _audio()
	var w1: AudioStreamWAV = SoundSynth.build(a.defs["nuke"])
	var w2: AudioStreamWAV = SoundSynth.build(a.defs["nuke"])
	check(w1.data == w2.data, "same description, same samples (noise included)")
	var amb: AudioStreamWAV = a.stream("ambience")
	check_eq(amb.loop_mode, AudioStreamWAV.LOOP_FORWARD, "ambience loops")
	# Seamless: the last and first samples are close (whole cycles fit the loop).
	var first := amb.data.decode_s16(0)
	var last := amb.data.decode_s16(amb.data.size() - 2)
	check(absi(first - last) < 1500, "no click at the loop seam (%d vs %d)" % [first, last])


func test_events_rate_limits_and_volumes() -> void:
	var a := _audio()
	a.played.clear()
	a._last.clear()
	a.on_event({"type": SimEvents.ATTACK_STARTED, "attacker": 2, "target": 1, "troops": 10.0}, 1)
	a.on_event({"type": SimEvents.ATTACK_STARTED, "attacker": 2, "target": 1, "troops": 10.0}, 1)
	check_eq(int(a.played.get("alert_attack", 0)), 1, "an invasion alarms once, not twice in a row")
	a.on_event({"type": SimEvents.BUILD_DONE, "owner": 3, "kind": 0, "tile": 0, "id": 0}, 1)
	check(not a.played.has("build_done"), "other states' buildings are silent")
	a.on_event({"type": SimEvents.DIPLO_REQUEST, "from": 2, "to": 1, "kind": "nap"}, 1)
	check(a.played.has("diplo_offer"), "a treaty offer chimes")
	var s: Node = Engine.get_main_loop().root.get_node("Settings")
	var old: float = s.volume_sfx
	s.volume_sfx = 0.0
	a.apply_volumes()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "zero volume mutes the bus")
	s.volume_sfx = 0.5
	a.apply_volumes()
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")) - linear_to_db(0.5)) < 0.01, "volume reaches the bus")
	s.volume_sfx = old
	a.apply_volumes()


func test_buttons_click() -> void:
	var a := _audio()
	a.played.clear()
	a._last.clear()
	var b := Button.new()
	Engine.get_main_loop().root.add_child(b)
	b.pressed.emit()
	check(a.played.has("ui_click"), "a button press clicks")
	b.queue_free()
