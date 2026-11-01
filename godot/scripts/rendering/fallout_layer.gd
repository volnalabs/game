class_name FalloutLayer
extends Sprite2D
## Radioactive fallout over the map: one texel per tile in the reserved acid green of radiation
## (SimState.RADIATION_COLOR, which no state may use), mottled, with black charred specks that
## thicken towards the crater's rim (WeaponSystem.fallout_edge). Updated only for tiles whose
## fallout appeared or cleared (WeaponSystem.drain_fallout_changes). Hidden while there is none.

const CHAR := Color(0.04, 0.05, 0.03, 0.9)

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
	if not on:
		_img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	var edge := float(sim.weapons.fallout_edge.get(t, 1.0))
	var h := WeaponSystem._h01(t, 7331)
	# Charred specks: rare near ground zero, dense at the rim.
	var char_p := 0.04 + 0.6 * smoothstep(0.45, 1.0, edge)
	if h < char_p:
		_img.set_pixel(x, y, CHAR)
		return
	var g := SimState.RADIATION_COLOR
	var k := WeaponSystem._h01(t, 911)
	var c := g.darkened(0.25 * k) if k > 0.5 else g.lightened(0.15 * k)
	_img.set_pixel(x, y, Color(c, 0.58 - 0.18 * edge))


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
