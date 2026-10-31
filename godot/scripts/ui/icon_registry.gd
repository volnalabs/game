class_name Icons
extends RefCounted
## The game's icon library: interface icons (Tabler, MIT) and cosmetic / achievement art
## (Game-icons.net, CC BY 3.0) from data/ui/icons.json (tools/icons/import_icons.py); building and
## resource ids (b_*, r_*) resolve to the game's own symbols (Symbols, data/ui/symbols.json). Icons are rasterised at the exact pixel size they are
## shown at (crisp at any UI scale) and tinted with modulate.

const PATH := "res://data/ui/icons.json"

static var _icons: Dictionary = {}
static var _cache: Dictionary = {}


static func _load() -> void:
	if not _icons.is_empty():
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_icons = d["icons"]


static func has(id: String) -> bool:
	_load()
	return _icons.has(id) or Symbols.has(id)


static func ids() -> Array:
	_load()
	return _icons.keys()


## Texture of icon `id` at `px` pixels (cached).
static func tex(id: String, px: int = 24) -> Texture2D:
	_load()
	var scale := 1.0
	if DisplayServer.get_name() != "headless" and Engine.get_main_loop() != null:
		var root: Window = (Engine.get_main_loop() as SceneTree).root
		if root != null:
			scale = root.content_scale_factor
	var size := maxi(8, int(round(px * scale)))
	# Buildings and resources: the game's own symbol set (same everywhere).
	if Symbols.has(id):
		return Symbols.tex_px(id, size, "full" if px < 40 else "near")
	var key := "%s@%d" % [id, size]
	if _cache.has(key):
		return _cache[key]
	if not _icons.has(id):
		push_warning("Icons: unknown icon '%s'" % id)
		id = "ui_info"
	var e: Dictionary = _icons[id]
	var svg: String = e["svg"]
	var base := 512.0 if e["source"] == "game-icons" else 24.0
	var img := Image.new()
	img.load_svg_from_string(svg, float(size) / base)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## A TextureRect showing icon `id`, tinted.
static func rect(id: String, px: int = 20, color: Color = Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(id, px)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func attribution() -> PackedStringArray:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var out := PackedStringArray()
	for k: String in d["_sources"]:
		out.append(String(d["_sources"][k]["attribution"]))
	return out
