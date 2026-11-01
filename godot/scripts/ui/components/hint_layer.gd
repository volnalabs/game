extends CanvasLayer
## Autoload "HintLayer": rich hints for interface elements and map objects. A hint appears on mouse
## hover AND on keyboard focus, never leaves the screen, and explains what an element is, what it
## does and — for unavailable actions — why it is unavailable. Use the static helpers in `Hints`.
## Data: {"title", "icon", "text", "rows": [[label, value], ...], "effect", "reason", "hotkey"}.

const DELAY := 0.3

var _panel: PanelContainer
var _box: VBoxContainer
var _target: Control
var _provider: Variant
var _timer: float = -1.0


func _ready() -> void:
	layer = 60
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_box)


func attach(c: Control, provider: Variant) -> void:
	c.set_meta("hint", provider)
	c.tooltip_text = ""
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	if not c.mouse_entered.is_connected(_on_enter):
		c.mouse_entered.connect(_on_enter.bind(c))
		c.mouse_exited.connect(_on_exit.bind(c))
		c.focus_entered.connect(_on_focus.bind(c))
		c.focus_exited.connect(_on_exit.bind(c))
		c.tree_exiting.connect(_on_exit.bind(c))


func _on_enter(c: Control) -> void:
	_target = c
	_provider = c.get_meta("hint")
	_timer = DELAY


func _on_focus(c: Control) -> void:
	_target = c
	_provider = c.get_meta("hint")
	_timer = 0.0


func _on_exit(c: Control) -> void:
	if c == _target:
		hide_hint()


func hide_hint() -> void:
	_target = null
	_timer = -1.0
	_panel.visible = false


func _process(delta: float) -> void:
	if _timer < 0.0:
		return
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		hide_hint()
		return
	_timer -= delta
	if _timer <= 0.0 and not _panel.visible:
		var d: Variant = (_provider as Callable).call() if _provider is Callable else _provider
		if d is Dictionary and not (d as Dictionary).is_empty():
			show_at(_target.get_global_rect(), d)
		_timer = -2.0


## Shows a hint next to a screen rectangle (below it, or above when there is no room).
func show_at(anchor: Rect2, d: Dictionary) -> void:
	_build(d)
	_panel.visible = true
	_panel.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var sz := _panel.size
	var p := Vector2(anchor.position.x, anchor.end.y + 6.0)
	if p.y + sz.y > vs.y - 6.0:
		p.y = anchor.position.y - sz.y - 6.0
	if p.y < 6.0:
		p.y = clampf(anchor.position.y, 6.0, vs.y - sz.y - 6.0)
		p.x = anchor.end.x + 8.0
	p.x = clampf(p.x, 6.0, maxf(6.0, vs.x - sz.x - 6.0))
	_panel.position = p


func is_showing() -> bool:
	return _panel.visible


func _build(d: Dictionary) -> void:
	_panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, 8, Color.TRANSPARENT, 9))
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	if String(d.get("icon", "")) != "":
		head.add_child(Icons.rect(String(d["icon"]), 18, d.get("icon_color", UITheme.TEXT)))
	var t := UITheme.label(String(d.get("title", "")), UITheme.T_BODY, UITheme.TEXT)
	t.add_theme_font_override("font", UITheme.font_medium)
	head.add_child(t)
	if String(d.get("hotkey", "")) != "":
		head.add_child(UITheme.spacer())
		head.add_child(UITheme.key_cap(String(d["hotkey"])))
	_box.add_child(head)
	for k in ["text", "effect"]:
		if String(d.get(k, "")) != "":
			_box.add_child(_wrap(UITheme.label(String(d[k]), 13, UITheme.TEXT if k == "effect" else UITheme.TEXT_DIM)))
	var rows: Array = d.get("rows", [])
	if not rows.is_empty():
		_box.add_child(UITheme.separator())
		for r: Array in rows:
			var v := String(r[1])
			if v.length() > 24:
				# Explanations: label above, wrapped text below.
				_box.add_child(UITheme.label(String(r[0]), UITheme.T_CAPTION, UITheme.TEXT_FAINT))
				_box.add_child(_wrap(UITheme.label(v, UITheme.T_BODY, UITheme.TEXT)))
			else:
				_box.add_child(UITheme.key_value(String(r[0]), v, r[2] if r.size() > 2 else UITheme.TEXT))
	if String(d.get("reason", "")) != "":
		var rl := UITheme.label(String(d["reason"]), UITheme.T_BODY, UITheme.BAD)
		_box.add_child(_wrap(rl))
	for c in _box.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 260
	return l
