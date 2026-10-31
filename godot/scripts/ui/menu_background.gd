class_name MenuBackground
extends SubViewportContainer
## Living strategic map behind the main menu: VolnaLabs' own world (a generated "continents" world
## with a fixed seed, the same every launch) with a real AI-only match running on it, drawn with the
## game's own layers — territories, buildings, state names, attack arrows and ships.
## The world is generated once per session and keeps running across menu visits; its first
## minutes are fast-forwarded within a small per-frame budget, so states visibly grow when the menu
## first opens and the frame rate never drops. The camera glides slowly
## between the largest states, offset to the right so the menu column never covers the action.

const WARM_TICKS := 700
const RESTART_TICK := 14000
const SHOT_SECS := 16.0

static var _sim: Sim

var renderer: MapRenderer
var structures: StructureLayer
var effects: EffectsLayer
var labels: LabelLayer
var cam: MapCamera
var vp: SubViewport
var _acc: float = 0.0
var _t: float = 0.0
var _from: Vector2
var _to: Vector2
var _shot_t: float = 0.0
var _attached: Sim
var _target_index: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.disable_3d = true
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	add_child(vp)
	if _sim == null:
		_sim = _new_world()


## VolnaLabs' world with an AI-only match (pure simulation, no nodes).
static func _new_world() -> Sim:
	var res := MapGenerator.new().generate(GenParams.from_preset("continents", 20261031, "S"))
	var cfg := MatchConfig.new()
	cfg.has_player = false
	cfg.bots = 14
	cfg.tribes = 22
	cfg.seed = 7 + int(Time.get_unix_time_from_system()) % 1000
	cfg.victory.domination_share = 1.0
	cfg.victory.eliminate_all = false
	return Sim.new(cfg, MapGenerator.definition_for(res), res.map)


## One backdrop tick; during the warm-up bots get extra gold so the world looks inhabited early.
func _step(s: Sim) -> void:
	if s.st.tick < WARM_TICKS and s.st.tick % 60 == 0 and s.phase == Sim.Phase.PLAYING:
		for o in range(1, s.st.owner_count + 1):
			if s.st.o_alive[o] == 1 and s.st.o_kind[o] != Rules.KIND_TRIBE:
				s.st.add_gold(o, 120000.0)
	s.step()
	for e in s.events.drain():
		if s.st.tick >= WARM_TICKS:
			effects.on_event(e)


func _attach(s: Sim) -> void:
	for c in vp.get_children():
		c.queue_free()
	_attached = s
	renderer = MapRenderer.new()
	vp.add_child(renderer)
	renderer.setup(s)
	structures = StructureLayer.new()
	vp.add_child(structures)
	effects = EffectsLayer.new()
	vp.add_child(effects)
	cam = MapCamera.new()
	cam.edge_scroll = false
	vp.add_child(cam)
	cam.set_process(false)
	cam.set_process_unhandled_input(false)
	cam.set_process_input(false)
	cam.map_size = Vector2(s.map.width, s.map.height)
	cam.min_zoom = 0.1
	cam.make_current()
	structures.sim = s
	structures.cam = cam
	effects.sim = s
	effects.cam = cam
	effects.quality = 1
	var ui := CanvasLayer.new()
	vp.add_child(ui)
	labels = LabelLayer.new()
	labels.sim = s
	labels.cam = cam
	labels.effects = effects
	ui.add_child(labels)
	_from = _target()
	_to = _target()
	_shot_t = 0.0


## Next point of interest: the centroid of one of the largest living states, in turn.
func _target() -> Vector2:
	var st := _attached.st
	var list: Array = []
	for o in range(1, st.owner_count + 1):
		if st.o_alive[o] == 1 and st.o_tiles[o] > 0 and st.o_kind[o] != Rules.KIND_TRIBE:
			list.append(o)
	if list.is_empty():
		return Vector2(_attached.map.width, _attached.map.height) * 0.5
	list.sort_custom(func(a: int, b: int) -> bool: return st.o_tiles[a] > st.o_tiles[b])
	_target_index = (_target_index + 1) % mini(list.size(), 5)
	return st.centroid(list[_target_index])


func zoom_level() -> float:
	var vs := Vector2(vp.size)
	# About twice the "whole world" zoom: several states at once, names and buildings legible.
	return maxf(vs.x / float(_attached.map.width), vs.y / float(_attached.map.height)) * 1.9


func _process(delta: float) -> void:
	if _sim == null:
		return
	if _attached != _sim:
		_attach(_sim)
	var s := _sim
	_t += delta
	if s.st.tick < WARM_TICKS:
		# Fast-forward the opening within ~8 ms per frame.
		var t0 := Time.get_ticks_usec()
		while s.st.tick < WARM_TICKS and Time.get_ticks_usec() - t0 < 8000:
			_step(s)
	else:
		_acc += delta
		# ~6 ticks per second, at most one per frame.
		if _acc >= 0.16:
			_acc = 0.0
			_step(s)
			if s.st.tick > RESTART_TICK:
				_sim = _new_world()
				return
	renderer.apply_changes(s.st.drain_changed_tiles())
	renderer.flush(2.0)
	# Camera: ease from one point of interest to the next, with a slow drift in between.
	_shot_t += delta
	if _shot_t > SHOT_SECS:
		_shot_t = 0.0
		_from = _to
		_to = _target()
	var k := smoothstep(0.0, 1.0, clampf(_shot_t / 6.0, 0.0, 1.0))
	var z := zoom_level()
	cam.zoom = Vector2(z, z)
	var vs := Vector2(vp.size) / z
	var drift := Vector2(sin(_t * 0.07), cos(_t * 0.05)) * 6.0
	# The focus sits right of centre: the menu occupies the left part of the screen.
	var p := _from.lerp(_to, k) + drift - Vector2(vs.x * 0.16, 0.0)
	var half := vs * 0.5
	var size := Vector2(_attached.map.width, _attached.map.height)
	p.x = clampf(p.x, half.x, maxf(half.x, size.x - half.x))
	p.y = clampf(p.y, half.y, maxf(half.y, size.y - half.y))
	cam.position = p
