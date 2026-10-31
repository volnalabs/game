class_name MapCamera
extends Camera2D
## Pan (right / middle drag, WASD / arrows, screen edges) and zoom to the cursor (wheel) over the
## map, clamped to its bounds. Zoom = screen pixels per tile.

var map_size: Vector2 = Vector2(1000, 500)
var min_zoom: float = 0.4
var max_zoom: float = 40.0
var edge_scroll: bool = true
var _dragging: bool = false


func setup(size_tiles: Vector2) -> void:
	map_size = size_tiles
	fit()


func fit() -> void:
	var vp := get_viewport_rect().size
	var z := minf(vp.x / map_size.x, vp.y / map_size.y)
	min_zoom = z * 0.8
	zoom = Vector2(z, z)
	position = map_size * 0.5


func focus(tile_pos: Vector2, z: float = -1.0) -> void:
	position = tile_pos
	if z > 0.0:
		zoom = Vector2.ONE * clampf(z, min_zoom, max_zoom)
	_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.15, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp()


func _zoom_at(f: float, screen_pos: Vector2) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_pos
	var z := clampf(zoom.x * f, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_pos
	position += before - after
	_clamp()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if edge_scroll and DisplayServer.window_is_focused():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if mp.x >= 0 and mp.y >= 0 and mp.x < vs.x and mp.y < vs.y:
			if mp.x < 6:
				move.x -= 1
			elif mp.x > vs.x - 6:
				move.x += 1
			if mp.y < 6:
				move.y -= 1
			elif mp.y > vs.y - 6:
				move.y += 1
	if move != Vector2.ZERO:
		position += move.normalized() * 700.0 * delta / zoom.x
		_clamp()


func _clamp() -> void:
	position = position.clamp(Vector2.ZERO, map_size)


## Visible map rectangle in tile coordinates.
func visible_rect() -> Rect2:
	var vs := get_viewport_rect().size / zoom
	return Rect2(position - vs * 0.5, vs)
