extends TestCase
## Phase 2G: settings v2 — rebindable hotkeys (no shared keys, Esc reserved, the match obeys the new
## key), colour-vision modes (daltonised colours stay apart for that viewer, radiation green reserved,
## the map palette follows the mode), effects quality reaches the layers, the settings tabs.

var main: Node
var app: Node
var root: Window
var _saved: Dictionary = {}


func _wait(n: int) -> void:
	for i in n:
		await Engine.get_main_loop().process_frame


func _settings() -> Node:
	return Engine.get_main_loop().root.get_node("Settings")


func before_each() -> void:
	var s := _settings()
	_saved = {"keys": (s.key_overrides as Dictionary).duplicate(), "mode": s.color_mode, "fx": s.effects_quality}


func after_each() -> void:
	var s := _settings()
	s.key_overrides = _saved["keys"]
	s.color_mode = _saved["mode"]
	s.effects_quality = _saved["fx"]
	s.apply()


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = true
	return ev


func test_rebinding_moves_a_key_and_never_shares_it() -> void:
	var ov := {}
	Keys.install(ov)
	check(InputMap.event_is_action(_key(KEY_B), Keys.action("build")), "B builds by default")
	check_eq(Keys.rebind("build", KEY_N, ov), "", "N is free")
	check(InputMap.event_is_action(_key(KEY_N), Keys.action("build")), "N builds now")
	check(not InputMap.event_is_action(_key(KEY_B), Keys.action("build")), "B no longer does")
	check_eq(Keys.rebind("zones", KEY_N, ov), "build", "giving N to zones takes it from build")
	check_eq(Keys.key("build", ov), KEY_NONE, "build is left unbound, never shared")
	check_eq(Keys.label("build") if false else Keys.key_name(Keys.key("build", ov)), "—", "shown as unbound")
	check_eq(Keys.rebind("pause", KEY_ESCAPE, ov), "reserved", "Esc cannot be bound")
	# An extra default key given away stays with its new action only.
	Keys.rebind("home", KEY_LEFT, ov)
	check(InputMap.event_is_action(_key(KEY_LEFT), Keys.action("home")), "Left arrow now goes home")
	check(not InputMap.event_is_action(_key(KEY_LEFT), Keys.action("cam_left")), "and no longer pans")
	check(InputMap.event_is_action(_key(KEY_A), Keys.action("cam_left")), "A still pans left")
	Keys.install({})


func _match() -> Node:
	root = Engine.get_main_loop().root
	root.size = Vector2i(1600, 900)
	app = root.get_node("App")
	if main == null:
		main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
	var m := TestMaps.rect(200, 100)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(2, true, 19, 0)
	app.start_new_match()
	await _wait(4)
	var ctl: Node = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	var sim: Sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(40, 50)))
	sim._start_playing()
	sim.ai.brains.clear()
	return ctl


func test_the_match_obeys_rebound_keys_and_display_settings() -> void:
	var s := _settings()
	s.key_overrides = {}
	Keys.rebind("build", KEY_N, s.key_overrides)
	s.apply()
	var ctl: Node = await _match()
	ctl._unhandled_input(_key(KEY_B))
	check(not ctl.build_open, "the old key does nothing")
	ctl._unhandled_input(_key(KEY_N))
	check(ctl.build_open, "the new key opens construction")
	ctl._unhandled_input(_key(KEY_ESCAPE))
	check(not ctl.build_open, "Esc still closes it")
	# Display settings reach the match at once.
	s.effects_quality = 0
	s.color_mode = "deuteranopia"
	s.apply()
	check_eq(ctl.effects.quality, 0, "effects layer quality")
	check_eq(ctl.weapons_fx.quality, 0, "weapon layer quality")
	var pid: int = ctl.sim.player_id
	var shown: Color = ctl.renderer.palette_img.get_pixel(pid, 0)
	var want := ColorAccess.color_for(ctl.sim.st.o_color[pid], "deuteranopia")
	check(_dist(shown, want) < 0.02, "the map palette uses the colour mode")


func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func test_daltonised_colours_stay_apart_for_that_viewer() -> void:
	var red := Color("#c8524a")
	var green := Color("#5f9a46")
	for m: String in ["deuteranopia", "protanopia"]:
		var before := _dist(ColorAccess.simulate(red, m), ColorAccess.simulate(green, m))
		var after := _dist(ColorAccess.simulate(ColorAccess.color_for(red, m), m), ColorAccess.simulate(ColorAccess.color_for(green, m), m))
		check(after > before * 1.2, "%s: red and green further apart as seen (%.3f -> %.3f)" % [m, before, after])
	var blue := Color("#4a6fc8")
	var violet := Color("#7a4ac8")
	var tb := _dist(ColorAccess.simulate(blue, "tritanopia"), ColorAccess.simulate(violet, "tritanopia"))
	var ta := _dist(ColorAccess.simulate(ColorAccess.color_for(blue, "tritanopia"), "tritanopia"), ColorAccess.simulate(ColorAccess.color_for(violet, "tritanopia"), "tritanopia"))
	check(ta >= tb, "tritanopia: blue and violet not closer (%.3f -> %.3f)" % [tb, ta])
	# The radiation green stays reserved: state colours are made safe when assigned, and the modes
	# that recalculate colours keep them so.
	for m: String in ["deuteranopia", "protanopia", "tritanopia"]:
		for h in ["#9cff3a", "#a6ff2b", "#b0f040"]:
			var c := ColorAccess.color_for(Color(h), m)
			check(SimState.radiation_safe(c).is_equal_approx(c), "%s keeps %s away from radiation green" % [m, h])


func test_settings_tabs_and_rebinding_screen() -> void:
	root = Engine.get_main_loop().root
	var scr: Control = (load("res://scripts/ui/screens/settings_screen.gd") as GDScript).new()
	root.add_child(scr)
	await _wait(2)
	for id in ["general", "display", "audio", "controls"]:
		check(scr.find_child("Tab_" + id, true, false) != null, "tab %s" % id)
	scr.show_tab("controls")
	await _wait(2)
	var keys := scr.find_children("Key_*", "Button", true, false)
	check_eq(keys.size(), Keys.ids().size(), "a key button per action")
	var s := _settings()
	s.key_overrides = {}
	s.apply()
	scr.bind("zones", KEY_B)
	await _wait(2)
	check_eq(Keys.key("zones", s.key_overrides), KEY_B, "bound from the screen")
	check(String(scr._notice).contains(tr("KEYS_BUILD")), "the screen says which action lost the key")
	scr.show_tab("display")
	await _wait(2)
	check(scr.find_child("ColorMode", true, false) != null and scr.find_child("EffectsQuality", true, false) != null, "display options")
	scr.queue_free()


func test_cleanup() -> void:
	if main != null:
		main.queue_free()
		main = null
	if app != null:
		app.goto(app.State.MAIN_MENU)
