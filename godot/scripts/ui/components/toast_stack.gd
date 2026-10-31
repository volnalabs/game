class_name ToastStack
extends VBoxContainer
## Stacked notifications (icon, title, text, colour), auto-dismissed, newest on top.

const MAX := 5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)


func push(text: String, color: Color = UITheme.TEXT, icon: String = "ui_info", secs: float = 3.5) -> void:
	var p := PanelContainer.new()
	var s := UITheme.box(Color(0.06, 0.08, 0.11, 0.94), UITheme.R_M, Color(color, 0.5), 8)
	s.border_width_left = 3
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UITheme.hbox(8)
	h.add_child(Icons.rect(icon, 18, color))
	var l := UITheme.label(text, UITheme.T_BODY, UITheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	h.add_child(l)
	p.add_child(h)
	add_child(p)
	move_child(p, 0)
	Anim.slide_in(p, Vector2(0, -12))
	while get_child_count() > MAX:
		var last := get_child(get_child_count() - 1)
		remove_child(last)
		last.queue_free()
	var t := create_tween()
	t.tween_interval(secs)
	t.tween_property(p, "modulate:a", 0.0, 0.4)
	t.tween_callback(p.queue_free)
