class_name LabelLayer
extends Control
## Screen-space text over the map: state names and armies (sized by territory and zoom), troops of
## attack fronts and transports. Drawn in screen space so text stays crisp at every zoom.

var sim: Sim
var cam: MapCamera
## Fronts are read from the effects layer (same smoothed positions as the arrows).
var effects: EffectsLayer
## Equipped emblem drawn next to the player's name.
var player_emblem: String = ""
var font: Font
var _centroids: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = UITheme.font_medium if UITheme.font_medium != null else ThemeDB.fallback_font


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 and sim != null:
		_timer = 0.4
		_update_centroids()
	queue_redraw()


func _update_centroids() -> void:
	var st := sim.st
	_centroids.clear()
	for id in range(1, st.owner_count + 1):
		if st.o_alive[id] == 1 and st.o_tiles[id] > 0:
			var c := st.centroid(id)
			var t := sim.map.tile_at(int(c.x), int(c.y))
			# A concave territory's centroid can fall outside it: use the spawn tile instead.
			if t < 0 or st.owner[t] != id:
				var sp := st.o_spawn_tile[id]
				if sp >= 0 and st.owner[sp] == id:
					c = Vector2(sp % sim.map.width, sp / sim.map.width)
			_centroids[id] = c + Vector2(0.5, 0.5)


func _to_screen(p: Vector2) -> Vector2:
	return cam.get_canvas_transform() * p


func _draw() -> void:
	if sim == null or cam == null:
		return
	var st := sim.st
	var z := cam.zoom.x
	var vs := get_viewport_rect().size
	for id: int in _centroids:
		if st.o_alive[id] == 0:
			continue
		var tiles := st.o_tiles[id]
		var size := sqrt(float(tiles)) * z * 0.12
		if size < 10.0:
			continue
		size = minf(size, 24.0)
		var sp := _to_screen(_centroids[id])
		if sp.x < -100 or sp.y < -50 or sp.x > vs.x + 100 or sp.y > vs.y + 50:
			continue
		var name := st.o_name[id]
		var col := Color("#f2efe8") if id != sim.player_id else Color("#ffe9d6")
		_text_c(name, sp, int(size), col)
		if id == sim.player_id and player_emblem != "":
			var tex := Icons.tex(player_emblem, int(size * 1.3))
			var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
			if tex != null:
				draw_texture_rect(tex, Rect2(sp + Vector2(-w * 0.5 - size * 1.5, -size * 1.05), Vector2(size, size) * 1.3), false, col)
		_text_c(UITheme.num(st.o_troops[id]), sp + Vector2(0, size * 0.95), int(size * 0.7), Color("#f2efe8", 0.75))
	# Attack fronts involving the player.
	var W := sim.map.width
	for a in sim.attacks.attacks:
		if not a.alive or a.last_tile < 0:
			continue
		if a.attacker != sim.player_id and a.target != sim.player_id:
			continue
		var fp: Vector2 = effects._fronts.get(a.id, {}).get("p", Vector2(a.last_tile % W + 0.5, a.last_tile / W + 0.5)) if effects != null else Vector2(a.last_tile % W + 0.5, a.last_tile / W + 0.5)
		var p := _to_screen(fp)
		var c := UITheme.GOOD if a.attacker == sim.player_id else UITheme.BAD
		_badge(UITheme.num(a.troops), p, c)
	for b in sim.naval.boats:
		if b.alive and (b.owner == sim.player_id or z > 2.0):
			_badge(UITheme.num(b.troops), _to_screen(b.position()) + Vector2(0, -14), st.o_color[b.owner])


func _text_c(s: String, p: Vector2, size: int, c: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := p - Vector2(w * 0.5, 0)
	# A soft, thin halo is enough for legibility on the map.
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 8), Color(0.08, 0.07, 0.06, 0.55))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _badge(s: String, p: Vector2, c: Color) -> void:
	var size := 13
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var r := Rect2(p - Vector2(w * 0.5 + 5, 10), Vector2(w + 10, 17))
	draw_rect(r, Color(0.14, 0.13, 0.12, 0.88))
	draw_rect(Rect2(r.position, Vector2(3, r.size.y)), c)
	draw_string(font, p - Vector2(w * 0.5, -3), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
