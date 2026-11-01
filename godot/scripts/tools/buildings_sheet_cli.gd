extends SceneTree
## Building readability check (Phase 2A.3-A): renders the real match scene with every building type on
## six territory colours (light, dark, green, yellow, grey, blue) at three zooms, the normal game
## zoom, and a crowded area where buildings are grouped.
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/buildings_sheet_cli.gd -- <out_dir> [WxH]

const COLORS := [Color("#e9e3d3"), Color("#34343f"), Color("#5f9e58"), Color("#e2c247"), Color("#8b8a86"), Color("#3c6fd1")]

var out_dir := "/tmp/bsheet"
var win := Vector2i(1600, 900)
var ctl: Node
var sim: Sim


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1 and args[1].contains("x"):
		win = Vector2i(int(args[1].get_slice("x", 0)), int(args[1].get_slice("x", 1)))
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _wait(4)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


## Adds a finished building directly (bypasses spacing rules; review tool only).
func _put(owner: int, kind: int, x: int, y: int, level: int = 1) -> void:
	var ss := sim.structures
	var s := StructureSystem.Structure.new()
	s.id = ss.structs.size()
	s.kind = kind
	s.owner = owner
	s.tile = sim.map.tile_at(x, y)
	s.level = level
	s.active_levels = level
	ss.structs.append(s)
	sim.st.set_struct_at(s.tile, s.id)
	ss._grid_add(s)


func _run() -> void:
	root.get_node("Settings").show_tips = false
	root.size = win
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _wait(2)
	var app := root.get_node("App")
	var m := TestMaps.rect(1400, 640)
	app.select_map(TestMaps.definition(m), m)
	app.config = TestMaps.config(5, true, 3, 0)
	app.start_new_match()
	await _wait(4)
	ctl = main._current
	while ctl.sim == null:
		await _wait(2)
	ctl.paused = true
	sim = ctl.sim
	sim.apply_command(Commands.spawn(sim.player_id, m.tile_at(20, 20)))
	sim._start_playing()
	ctl.hud.visible = false
	# Six owners in horizontal bands, one territory colour each.
	var owners: Array[int] = [sim.player_id]
	for o in range(1, sim.st.owner_count + 1):
		if o != sim.player_id and owners.size() < 6:
			owners.append(o)
	for i in owners.size():
		var o: int = owners[i]
		sim.st.o_color[o] = COLORS[i]
		sim.st.o_alive[o] = 1
		for y in range(2 + i * 24, mini(2 + (i + 1) * 24, 638)):
			for x in range(2, 420):
				sim.st.set_owner(m.tile_at(x, y), o)
	ctl.renderer.refresh_palette()
	# Every kind once per band, spaced 20 tiles apart; a second row of levels in band 0.
	var kinds := sim.rules.b_ids.size()
	for i in owners.size():
		for k in kinds:
			_put(owners[i], k, 14 + k * 20, 2 + i * 24 + 12, 1 + (k % 3 if i == 0 else 0))
	await _wait(10)
	# Absolute zooms (≈ a 1400-tile map): whole map, normal play, closer, close.
	for zz: Array in [["far", 1.2, Vector2(170, 80)], ["normal", 3.2, Vector2(160, 75)], ["mid", 5.0, Vector2(150, 75)], ["near", 10.0, Vector2(80, 50)]]:
		ctl.cam.focus(zz[2], float(zz[1]))
		await _wait(6)
		await _shot("buildings_%s" % zz[0])
	# Crowded: many buildings packed in a small area (grouping with counts at far zoom).
	for y in range(0, 6):
		for x in range(0, 10):
			_put(owners[(x + y) % owners.size()], (x * 7 + y * 3) % kinds, 30 + x * 5, 100 + y * 5)
	for zz: Array in [["crowded_far", 1.2], ["crowded_normal", 3.2], ["crowded_near", 7.0]]:
		ctl.cam.focus(Vector2(52, 112), float(zz[1]))
		await _wait(6)
		await _shot("buildings_%s" % zz[0])
	# Hover and selection states.
	ctl.cam.focus(Vector2(80, 40), 6.0)
	ctl.structures.hovered = sim.st.struct_at[m.tile_at(54, 38)]
	ctl.select_structure(sim.st.struct_at[m.tile_at(94, 38)])
	ctl.hud.visible = true
	await _wait(6)
	await _shot("buildings_hover_selected")
	quit()
