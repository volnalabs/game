class_name MenuBackground
extends SubViewportContainer
## Living backdrop of the menus: a real AI-only match on a small generated world, rendered with
## the game's map renderer, stepped slowly while the camera drifts over it.

static var _map: MapData
static var _def: MapDefinition

var sim: Sim
var renderer: MapRenderer
var cam: Camera2D
var vp: SubViewport
var _acc: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	add_child(vp)
	if _map == null:
		var res := MapGenerator.new().generate(GenParams.from_preset("continents", 20261031, "S"))
		_map = res.map
		_def = MapGenerator.definition_for(res)
	var cfg := MatchConfig.new()
	cfg.has_player = false
	cfg.bots = 14
	cfg.tribes = 24
	cfg.seed = randi() % 100000
	cfg.victory.domination_share = 1.0
	cfg.victory.eliminate_all = false
	sim = Sim.new(cfg, _def, _map)
	for i in 120:
		sim.step()
	sim.events.drain()
	renderer = MapRenderer.new()
	vp.add_child(renderer)
	renderer.setup(sim)
	cam = Camera2D.new()
	vp.add_child(cam)
	cam.make_current()


func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	_acc += delta
	# ~6 ticks per second, at most one per frame.
	if _acc >= 0.16:
		_acc = 0.0
		sim.step()
		sim.events.drain()
		if sim.st.tick > 9000:
			sim = null
			_ready_restart()
			return
	renderer.apply_changes(sim.st.drain_changed_tiles())
	renderer.flush(2.0)
	var size := Vector2(_map.width, _map.height)
	var vs := Vector2(vp.size)
	var z := maxf(vs.x / size.x, vs.y / size.y) * 1.6
	cam.zoom = Vector2(z, z)
	var half := vs / z * 0.5
	var cx := lerpf(half.x, size.x - half.x, 0.5 + 0.5 * sin(_t * 0.035))
	var cy := lerpf(half.y, size.y - half.y, 0.5 + 0.5 * sin(_t * 0.05 + 1.3))
	cam.position = Vector2(cx, cy)


func _ready_restart() -> void:
	for c in vp.get_children():
		c.queue_free()
	_ready()
