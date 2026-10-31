extends SceneTree
## Renders every symbol at map sizes and LODs into a sheet for review and documentation:
##   xvfb-run -a godot --rendering-driver opengl3 --path godot -s res://scripts/tools/symbols_sheet_cli.gd -- <out.png>

var out := "res://../docs/ui/symbols_sheet.png"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var ids := Symbols.ids()
	var sizes := [12, 16, 24, 40]
	var cell := 56
	var w := 200 + sizes.size() * cell * 2
	var h := 30 + ids.size() * cell
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#24221f"))
	var plate := Color("#38332d")
	for i in ids.size():
		var id: String = ids[i]
		var y := 30 + i * cell
		for j in sizes.size():
			var px: int = sizes[j]
			# Owner-coloured silhouette on the map background, then on a plate.
			for k in 2:
				var x := 200 + (j * 2 + k) * cell
				var lod := Symbols.lod_for(px)
				var t := Symbols.tex_px(id, px, lod)
				var si := t.get_image()
				si.convert(Image.FORMAT_RGBA8)
				var col := Color("#d9b46a") if k == 0 else Color.WHITE
				if k == 1:
					img.fill_rect(Rect2i(x - 4, y - 4, px + 8, px + 8), plate)
				for yy in si.get_height():
					for xx in si.get_width():
						var c := si.get_pixel(xx, yy)
						if c.a > 0.0:
							var tint := Color(c.r * col.r, c.g * col.g, c.b * col.b, c.a)
							var bg := img.get_pixel(x + xx, y + yy)
							img.set_pixel(x + xx, y + yy, bg.lerp(Color(tint, 1.0), c.a))
	img.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	print("sheet: ", out, " ", ids)
	quit()
