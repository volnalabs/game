class_name MapRenderer
extends Node2D
## Draws the map: one static terrain texture and a grid of 256 x 256 territory chunks (owner id +
## border flag per texel, coloured by assets/shaders/territory.gdshader through a palette). Only
## chunks touched by ownership changes are re-uploaded, under a per-frame time budget. No node per
## tile: a 2000 x 1000 map is 1 terrain sprite + 32 chunk sprites.

const CHUNK := 256

var sim: Sim
var map: MapData
var cw: int = 0
var ch: int = 0
var owner_bytes: PackedByteArray
var chunk_tex: Array[ImageTexture] = []
var chunk_sprites: Array[Sprite2D] = []
var dirty: PackedByteArray
var dirty_list: Array[int] = []
var palette_img: Image
var palette_tex: ImageTexture
var material_shared: ShaderMaterial
var terrain_sprite: Sprite2D
## Milliseconds spent uploading chunks in the last frame (profiling).
var last_upload_ms: float = 0.0
## Cosmetic terrain style (profile item), "" = standard.
var map_style: String = ""


func setup(sim_: Sim) -> void:
	sim = sim_
	map = sim.map
	cw = ceili(float(map.width) / CHUNK)
	ch = ceili(float(map.height) / CHUNK)
	terrain_sprite = Sprite2D.new()
	terrain_sprite.centered = false
	terrain_sprite.texture = ImageTexture.create_from_image(TerrainColors.terrain_image(map, map_style))
	terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(terrain_sprite)
	palette_img = Image.create(512, 1, false, Image.FORMAT_RGBA8)
	palette_tex = ImageTexture.create_from_image(palette_img)
	material_shared = ShaderMaterial.new()
	material_shared.shader = load("res://assets/shaders/territory.gdshader")
	material_shared.set_shader_parameter("palette", palette_tex)
	material_shared.set_shader_parameter("player", sim.player_id)
	refresh_palette()
	owner_bytes = PackedByteArray()
	owner_bytes.resize(cw * ch * CHUNK * CHUNK * 4)
	dirty = PackedByteArray()
	dirty.resize(cw * ch)
	var owner := sim.st.owner
	for t in map.size:
		if owner[t] != 0:
			_write(t)
	for cy in ch:
		for cx in cw:
			var ci := cy * cw + cx
			var img := Image.create_from_data(CHUNK, CHUNK, false, Image.FORMAT_RGBA8, _chunk_slice(ci))
			var tex := ImageTexture.create_from_image(img)
			chunk_tex.append(tex)
			var s := Sprite2D.new()
			s.centered = false
			s.position = Vector2(cx * CHUNK, cy * CHUNK)
			s.texture = tex
			s.material = material_shared
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(s)
			chunk_sprites.append(s)
	dirty.fill(0)
	dirty_list.clear()


## Owner colours into the palette texture, through the colour-vision mode (ColorAccess); also sets the
## mode's border / fill strength.
func refresh_palette() -> void:
	var st := sim.st
	var m := ColorAccess.mode()
	for id in range(1, mini(st.owner_count + 1, 512)):
		palette_img.set_pixel(id, 0, ColorAccess.color_for(st.o_color[id], m))
	palette_tex.update(palette_img)
	if material_shared == null:
		return
	var p := ColorAccess.territory_params(m)
	material_shared.set_shader_parameter("border_dark", p[0])
	material_shared.set_shader_parameter("border_alpha", p[1])
	material_shared.set_shader_parameter("fill_alpha", p[2])


func set_highlight(selected: int, hovered: int) -> void:
	material_shared.set_shader_parameter("selected", selected)
	material_shared.set_shader_parameter("hovered", hovered)


func _chunk_slice(ci: int) -> PackedByteArray:
	var start := ci * CHUNK * CHUNK * 4
	return owner_bytes.slice(start, start + CHUNK * CHUNK * 4)


func _offset(t: int) -> int:
	var x := t % map.width
	var y := t / map.width
	var ci := (y / CHUNK) * cw + (x / CHUNK)
	return ((ci * CHUNK + (y % CHUNK)) * CHUNK + (x % CHUNK)) * 4


func _mark(t: int) -> void:
	var ci := ((t / map.width) / CHUNK) * cw + ((t % map.width) / CHUNK)
	if dirty[ci] == 0:
		dirty[ci] = 1
		dirty_list.append(ci)


## Writes tile t's owner and border flag into the chunk buffer.
func _write(t: int) -> void:
	var owner := sim.st.owner
	var o := owner[t]
	var off := _offset(t)
	if o == 0:
		owner_bytes[off] = 0
		owner_bytes[off + 1] = 0
		owner_bytes[off + 2] = 0
		owner_bytes[off + 3] = 0
		return
	var W := map.width
	var x := t % W
	var border := false
	if x == 0 or owner[t - 1] != o:
		border = true
	elif x == W - 1 or owner[t + 1] != o:
		border = true
	elif t < W or owner[t - W] != o:
		border = true
	elif t + W >= map.size or owner[t + W] != o:
		border = true
	owner_bytes[off] = o & 255
	owner_bytes[off + 1] = (o >> 8) & 255
	owner_bytes[off + 2] = 1 if border else 0
	owner_bytes[off + 3] = 255


## Applies ownership changes (tile and its 4 neighbours, for borders).
func apply_changes(tiles: PackedInt32Array) -> void:
	var W := map.width
	var N := map.size
	for t in tiles:
		_write(t)
		_mark(t)
		var x := t % W
		if x > 0:
			_write(t - 1)
			_mark(t - 1)
		if x < W - 1:
			_write(t + 1)
			_mark(t + 1)
		if t >= W:
			_write(t - W)
			_mark(t - W)
		if t + W < N:
			_write(t + W)
			_mark(t + W)


## Uploads dirty chunks, at most `budget_ms` per frame.
func flush(budget_ms: float = 4.0) -> void:
	var t0 := Time.get_ticks_usec()
	while not dirty_list.is_empty():
		var ci: int = dirty_list.pop_front()
		dirty[ci] = 0
		chunk_tex[ci].update(Image.create_from_data(CHUNK, CHUNK, false, Image.FORMAT_RGBA8, _chunk_slice(ci)))
		if float(Time.get_ticks_usec() - t0) / 1000.0 > budget_ms:
			break
	last_upload_ms = float(Time.get_ticks_usec() - t0) / 1000.0
