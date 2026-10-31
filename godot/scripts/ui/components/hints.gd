class_name Hints
extends RefCounted
## Static helpers for the HintLayer autoload (works without it: tests, tools).


static func _layer() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("HintLayer") if tree != null and tree.root != null else null


## Attaches a hint (Dictionary or Callable returning one) to a control.
static func attach(c: Control, provider: Variant) -> Control:
	var l := _layer()
	if l != null:
		l.attach(c, provider)
	else:
		c.set_meta("hint", provider)
	return c


static func show_at(anchor: Rect2, d: Dictionary) -> void:
	var l := _layer()
	if l != null:
		l.show_at(anchor, d)


static func hide() -> void:
	var l := _layer()
	if l != null:
		l.hide_hint()


## Marks a disabled control with the reason it is unavailable (shown in its hint).
static func disable(c: BaseButton, reason: String) -> void:
	c.disabled = reason != ""
	c.set_meta("reason", reason)
