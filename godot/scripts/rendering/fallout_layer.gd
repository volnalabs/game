class_name FalloutLayer
extends Sprite2D
## Radioactive fallout over the map: one texel per tile, a muted yellow-green veil with a fine
## diagonal hatch, updated only for tiles whose fallout appeared or cleared
## (WeaponSystem.drain_fallout_changes). Hidden while there is none.

const COLOR_A := Color(0.66, 0.7, 0.28, 0.42)
const COLOR_B := Color(0.5, 0.55, 0.2, 0.3)

var sim: Sim
var _img: Image
var _tex: ImageTexture


func setup(s: Sim) -> void:
	sim = s
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_img = Image.create(s.map.width, s.map.height, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	texture = _tex
	visible = false
	for t: int in s.weapons.fallout:
		_paint(t, true)
	s.weapons.drain_fallout_changes()
	s.weapons.fallout_resync = false
	if not s.weapons.fallout.is_empty():
		_tex.update(_img)
		visible = true


func _paint(t: int, on: bool) -> void:
	var x := t % sim.map.width
	var y := t / sim.map.width
	_img.set_pixel(x, y, (COLOR_A if (x + y) % 3 != 0 else COLOR_B) if on else Color(0, 0, 0, 0))


func _process(_delta: float) -> void:
	if sim == null:
		return
	if sim.weapons.fallout_resync:
		sim.weapons.fallout_resync = false
		sim.weapons.drain_fallout_changes()
		_img.fill(Color(0, 0, 0, 0))
		for t: int in sim.weapons.fallout:
			_paint(t, true)
		_tex.update(_img)
		visible = not sim.weapons.fallout.is_empty()
		return
	var ch := sim.weapons.drain_fallout_changes()
	if ch.is_empty():
		return
	for t in ch:
		_paint(t, sim.weapons.is_fallout(t))
	_tex.update(_img)
	visible = not sim.weapons.fallout.is_empty()
