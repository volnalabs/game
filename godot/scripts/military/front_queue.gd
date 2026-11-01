class_name FrontQueue
extends RefCounted
## Min-priority queue of attack-front tiles (binary heap on packed arrays). RoWorld used a bucket
## queue (SimAttacks.luau:121-308); the ordering semantics — lowest priority first — are the same.

var keys: PackedFloat64Array = PackedFloat64Array()
var tiles: PackedInt32Array = PackedInt32Array()
var count: int = 0


func push(key: float, tile: int) -> void:
	if count >= keys.size():
		var cap := maxi(64, keys.size() * 2)
		keys.resize(cap)
		tiles.resize(cap)
	var i := count
	count += 1
	while i > 0:
		var p := (i - 1) >> 1
		if keys[p] <= key:
			break
		keys[i] = keys[p]
		tiles[i] = tiles[p]
		i = p
	keys[i] = key
	tiles[i] = tile


## Removes and returns the lowest-priority tile, or -1 when empty.
func pop() -> int:
	if count == 0:
		return -1
	var top := tiles[0]
	count -= 1
	if count > 0:
		var key := keys[count]
		var tile := tiles[count]
		var i := 0
		while true:
			var l := 2 * i + 1
			if l >= count:
				break
			var r := l + 1
			var c := l
			if r < count and keys[r] < keys[l]:
				c = r
			if keys[c] >= key:
				break
			keys[i] = keys[c]
			tiles[i] = tiles[c]
			i = c
		keys[i] = key
		tiles[i] = tile
	return top


func clear() -> void:
	count = 0


func is_empty() -> bool:
	return count == 0


func to_dict() -> Dictionary:
	return {"keys": keys.slice(0, count), "tiles": tiles.slice(0, count)}


static func from_dict(d: Dictionary) -> FrontQueue:
	var q := FrontQueue.new()
	q.keys = d["keys"]
	q.tiles = d["tiles"]
	q.count = q.keys.size()
	return q
