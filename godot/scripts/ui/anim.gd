class_name Anim
extends RefCounted
## Small, consistent UI motions (respecting the "effects" setting).

static func enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	var s: Node = tree.root.get_node_or_null("Settings")
	if s == null:
		return true
	var v: Variant = s.get("ui_animations")
	return v == null or bool(v)


static func fade_in(n: CanvasItem, dur: float = 0.18, delay: float = 0.0) -> void:
	if not enabled() or not n.is_inside_tree():
		return
	n.modulate.a = 0.0
	var t := n.create_tween()
	t.tween_property(n, "modulate:a", 1.0, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func slide_in(n: Control, offset: Vector2, dur: float = 0.22, delay: float = 0.0) -> void:
	if not enabled() or not n.is_inside_tree():
		return
	n.modulate.a = 0.0
	# Children of a container get their final position only after the container sorts them.
	if n.get_parent() is Container:
		await n.get_tree().process_frame
		if not is_instance_valid(n):
			return
	var end := n.position
	n.position = end + offset
	var t := n.create_tween().set_parallel(true)
	t.tween_property(n, "position", end, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(n, "modulate:a", 1.0, dur).set_delay(delay)


static func pop(n: Control, scale_from: float = 0.85, dur: float = 0.25) -> void:
	if not enabled() or not n.is_inside_tree():
		return
	n.pivot_offset = n.size * 0.5
	n.scale = Vector2.ONE * scale_from
	var t := n.create_tween()
	t.tween_property(n, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func pulse(n: CanvasItem, color: Color, dur: float = 0.6) -> void:
	if not enabled() or not n.is_inside_tree():
		return
	var base := n.modulate
	var t := n.create_tween()
	t.tween_property(n, "modulate", color, dur * 0.3)
	t.tween_property(n, "modulate", base, dur * 0.7)
