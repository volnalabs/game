class_name ToastStack
extends VBoxContainer
## The single notification slot: one short message at a time (a newer one replaces it), auto-dismissed.

var _current: PanelContainer
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Whether a notification is on screen (tips wait for it).
func busy() -> bool:
	return _current != null and is_instance_valid(_current)


func push(text: String, color: Color = UITheme.TEXT, icon: String = "ui_info", secs: float = 3.0) -> void:
	if busy():
		remove_child(_current)
		_current.queue_free()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, 10, Color.TRANSPARENT, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UITheme.hbox(8)
	h.add_child(Icons.rect(icon, 16, color))
	var l := UITheme.label(text, UITheme.T_BODY, UITheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 280
	h.add_child(l)
	p.add_child(h)
	add_child(p)
	_current = p
	Anim.fade_in(p, 0.15)
	_tween = create_tween()
	_tween.tween_interval(secs)
	_tween.tween_property(p, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		_current = null)
