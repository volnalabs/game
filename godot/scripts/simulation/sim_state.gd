class_name SimState
extends RefCounted
## All mutable simulation state in packed arrays, plus the only code that changes tile ownership.
## Ported from RoWorld's SimState.luau (owner buffer, intrusive per-owner border lists kept by
## set_owner, so no system ever rescans the map). AGPL-3.0.
##
## Other systems READ these arrays through local aliases but WRITE only through methods of this
## class: packed arrays are copy-on-write, and `state.owner[i] = v` from outside would copy them.

var map: MapData
var rules: Rules
var W: int
var H: int
var N: int
var max_owners: int
var tick: int = 0

# ---- per tile ----
var owner: PackedInt32Array
var in_border: PackedByteArray
var bnext: PackedInt32Array
var bprev: PackedInt32Array
var struct_at: PackedInt32Array
var front_mark: PackedInt32Array
## 1 where radioactive fallout lies (maintained by WeaponSystem; capturing it costs more).
var fallout: PackedByteArray
## Economic value of each land tile (terrain value + river + coast).
var tile_value: PackedFloat32Array

# ---- per owner (index = owner id, 0 = nobody) ----
var owner_count: int = 0
var o_name: PackedStringArray
var o_kind: PackedInt32Array
var o_alive: PackedByteArray
var o_spawned: PackedByteArray
var o_color: PackedColorArray
var o_flag: PackedStringArray
var o_nation: PackedInt32Array
var o_tiles: PackedInt32Array
var o_value: PackedFloat64Array
var o_troops: PackedFloat64Array
var o_gold: PackedFloat64Array
var o_supplies: PackedFloat64Array
var o_cap: PackedFloat64Array
var o_income: PackedFloat64Array
var o_upkeep: PackedFloat64Array
var o_supply_income: PackedFloat64Array
var o_port_trade: PackedFloat64Array
var o_growth: PackedFloat64Array
var o_border_head: PackedInt32Array
var o_border_count: PackedInt32Array
var o_sx: PackedFloat64Array
var o_sy: PackedFloat64Array
var o_spawn_tile: PackedInt32Array
var o_boats: PackedInt32Array
var o_attacked_tick: PackedInt32Array
var o_killer: PackedInt32Array
var o_elim_tick: PackedInt32Array
## Active building levels: [id * Rules.MAX_BUILDING_KINDS + kind].
var o_blevels: PackedInt32Array
## Building levels owned including those under construction (drives costs).
var o_bowned: PackedInt32Array
# statistics
var o_st_attacks: PackedInt32Array
var o_st_conquered: PackedInt32Array
var o_st_lost_tiles: PackedInt32Array
var o_st_troops_lost: PackedFloat64Array
var o_st_gold_earned: PackedFloat64Array
var o_st_gold_spent: PackedFloat64Array
var o_st_peak_tiles: PackedInt32Array
var o_st_upkeep_paid: PackedFloat64Array
## Accepted commands (player activity for anti-AFK rewards) and buildings ordered.
var o_st_commands: PackedInt32Array
var o_st_built: PackedInt32Array

## Tiles whose owner changed since the renderer last drained them.
var changed_tiles: PackedInt32Array = PackedInt32Array()
## Owners that reached zero tiles this tick.
var pending_elim: Array[int] = []
## Called with (tile, old_owner, new_owner) when a tile holding a structure changes hands.
var on_struct_tile: Callable


func _init(map_data: MapData, rules_: Rules) -> void:
	map = map_data
	rules = rules_
	W = map.width
	H = map.height
	N = map.size
	max_owners = rules.max_owners
	owner = _i32(N, 0)
	in_border = _u8(N)
	bnext = _i32(N, -1)
	bprev = _i32(N, -1)
	struct_at = _i32(N, -1)
	front_mark = _i32(N, 0)
	fallout = _u8(N)
	tile_value = PackedFloat32Array()
	tile_value.resize(N)
	for i in N:
		if map.land[i] == 1:
			var v: float = rules.t_value[map.terrain[i] & MapData.CODE_MASK]
			if (map.terrain[i] & MapData.RIVER_BIT) != 0:
				v += rules.river_value_add
			if map.coastal[i] == 1:
				v += rules.coast_value_add
			tile_value[i] = v
	var m := max_owners
	o_name = PackedStringArray()
	o_name.resize(m)
	o_flag = PackedStringArray()
	o_flag.resize(m)
	o_color = PackedColorArray()
	o_color.resize(m)
	o_kind = _i32(m, -1)
	o_alive = _u8(m)
	o_spawned = _u8(m)
	o_nation = _i32(m, -1)
	o_tiles = _i32(m, 0)
	o_value = _f64(m)
	o_troops = _f64(m)
	o_gold = _f64(m)
	o_supplies = _f64(m)
	o_cap = _f64(m)
	o_income = _f64(m)
	o_upkeep = _f64(m)
	o_supply_income = _f64(m)
	o_port_trade = _f64(m)
	o_growth = _f64(m)
	o_border_head = _i32(m, -1)
	o_border_count = _i32(m, 0)
	o_sx = _f64(m)
	o_sy = _f64(m)
	o_spawn_tile = _i32(m, -1)
	o_boats = _i32(m, 0)
	o_attacked_tick = _i32(m, -100000)
	o_killer = _i32(m, 0)
	o_elim_tick = _i32(m, -1)
	o_blevels = _i32(m * Rules.MAX_BUILDING_KINDS, 0)
	o_bowned = _i32(m * Rules.MAX_BUILDING_KINDS, 0)
	o_st_attacks = _i32(m, 0)
	o_st_conquered = _i32(m, 0)
	o_st_lost_tiles = _i32(m, 0)
	o_st_troops_lost = _f64(m)
	o_st_gold_earned = _f64(m)
	o_st_gold_spent = _f64(m)
	o_st_peak_tiles = _i32(m, 0)
	o_st_upkeep_paid = _f64(m)
	o_st_commands = _i32(m, 0)
	o_st_built = _i32(m, 0)


static func _i32(n: int, v: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	if v != 0:
		a.fill(v)
	return a


static func _u8(n: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(n)
	return a


static func _f64(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	return a


# ---------------------------------------------------------------------------------------------
# Owners
# ---------------------------------------------------------------------------------------------

## Acid green of radiation (nuclear bursts, fallout): reserved — no state may wear it.
const RADIATION_COLOR := Color("#a6ff2b")
const RADIATION_HUE_GAP := 0.08


## `c`, moved away from the radiation green when it is too close (hue within the gap and bright /
## saturated enough to be mistaken for fallout).
static func radiation_safe(c: Color) -> Color:
	var rh := RADIATION_COLOR.h
	var dh := c.h - rh
	if dh > 0.5:
		dh -= 1.0
	elif dh < -0.5:
		dh += 1.0
	if absf(dh) >= RADIATION_HUE_GAP or c.s < 0.55 or c.v < 0.7:
		return c
	var h := rh - RADIATION_HUE_GAP - 0.01 if dh < 0.0 else rh + RADIATION_HUE_GAP + 0.01
	return Color.from_hsv(fposmod(h, 1.0), minf(c.s, 0.75), minf(c.v, 0.85), c.a)


func add_owner(name: String, kind: int, color: Color, flag: String = "", nation: int = -1) -> int:
	owner_count += 1
	var id := owner_count
	if id >= max_owners:
		push_error("SimState: too many owners")
		owner_count -= 1
		return -1
	o_name[id] = name
	o_kind[id] = kind
	o_color[id] = radiation_safe(color)
	o_flag[id] = flag
	o_nation[id] = nation
	o_alive[id] = 1
	return id


func is_alive(id: int) -> bool:
	return id > 0 and id <= owner_count and o_alive[id] == 1


func blevel(id: int, kind: int) -> int:
	return o_blevels[id * Rules.MAX_BUILDING_KINDS + kind]


func bowned(id: int, kind: int) -> int:
	return o_bowned[id * Rules.MAX_BUILDING_KINDS + kind]


func add_blevel(id: int, kind: int, d: int) -> void:
	o_blevels[id * Rules.MAX_BUILDING_KINDS + kind] += d


func add_bowned(id: int, kind: int, d: int) -> void:
	o_bowned[id * Rules.MAX_BUILDING_KINDS + kind] += d


func add_troops(id: int, d: float) -> void:
	o_troops[id] = maxf(0.0, o_troops[id] + d)


func set_troops(id: int, v: float) -> void:
	o_troops[id] = maxf(0.0, v)


func add_gold(id: int, d: float) -> void:
	o_gold[id] += d


func add_supplies(id: int, d: float) -> void:
	o_supplies[id] = maxf(0.0, o_supplies[id] + d)


func set_economy(id: int, cap: float, income: float, upkeep: float, supply_income: float, growth: float) -> void:
	o_cap[id] = cap
	o_income[id] = income
	o_upkeep[id] = upkeep
	o_supply_income[id] = supply_income
	o_growth[id] = growth


func set_port_trade(id: int, v: float) -> void:
	o_port_trade[id] = v


func add_boats(id: int, d: int) -> void:
	o_boats[id] += d


func mark_attacked(id: int) -> void:
	o_attacked_tick[id] = tick


func stat_attack(id: int) -> void:
	o_st_attacks[id] += 1


## Display colour (cosmetic; no rule reads colours).
func set_display_color(id: int, c: Color) -> void:
	o_color[id] = radiation_safe(c)


func stat_command(id: int, type: String) -> void:
	if id > 0 and id < o_st_commands.size():
		o_st_commands[id] += 1
		if type == "build":
			o_st_built[id] += 1


func stat_troops_lost(id: int, v: float) -> void:
	o_st_troops_lost[id] += v


func stat_gold(id: int, earned: float, spent: float, upkeep: float) -> void:
	o_st_gold_earned[id] += earned
	o_st_gold_spent[id] += spent
	o_st_upkeep_paid[id] += upkeep


func set_spawn_tile(id: int, t: int) -> void:
	o_spawn_tile[id] = t
	o_spawned[id] = 1


func kill(id: int, killer: int) -> void:
	o_alive[id] = 0
	o_killer[id] = killer
	o_elim_tick[id] = tick
	o_troops[id] = 0.0


func set_color(id: int, c: Color) -> void:
	o_color[id] = radiation_safe(c)


func set_struct_at(t: int, sid: int) -> void:
	struct_at[t] = sid


func set_front_mark(t: int, v: int) -> void:
	front_mark[t] = v


func centroid(id: int) -> Vector2:
	var n := maxi(o_tiles[id], 1)
	return Vector2(o_sx[id] / n, o_sy[id] / n)


# ---------------------------------------------------------------------------------------------
# Tiles
# ---------------------------------------------------------------------------------------------

## True when land tile t has a 4-neighbour land tile of another owner.
func is_border(t: int) -> bool:
	var o := owner[t]
	var x := t % W
	var land := map.land
	if x > 0 and land[t - 1] == 1 and owner[t - 1] != o:
		return true
	if x < W - 1 and land[t + 1] == 1 and owner[t + 1] != o:
		return true
	if t >= W and land[t - W] == 1 and owner[t - W] != o:
		return true
	if t + W < N and land[t + W] == 1 and owner[t + W] != o:
		return true
	return false


## True when tile t has a 4-neighbour owned by `who`.
func touches(t: int, who: int) -> bool:
	var x := t % W
	if x > 0 and owner[t - 1] == who:
		return true
	if x < W - 1 and owner[t + 1] == who:
		return true
	if t >= W and owner[t - W] == who:
		return true
	if t + W < N and owner[t + W] == who:
		return true
	return false


func _border_add(t: int, o: int) -> void:
	in_border[t] = 1
	var h := o_border_head[o]
	bnext[t] = h
	bprev[t] = -1
	if h >= 0:
		bprev[h] = t
	o_border_head[o] = t
	o_border_count[o] += 1


func _border_remove(t: int, o: int) -> void:
	in_border[t] = 0
	var p := bprev[t]
	var nx := bnext[t]
	if p >= 0:
		bnext[p] = nx
	else:
		o_border_head[o] = nx
	if nx >= 0:
		bprev[nx] = p
	bnext[t] = -1
	bprev[t] = -1
	o_border_count[o] -= 1


func _refresh_border(t: int) -> void:
	var o := owner[t]
	if o == 0:
		return
	var want := is_border(t)
	if want and in_border[t] == 0:
		_border_add(t, o)
	elif not want and in_border[t] == 1:
		_border_remove(t, o)


## Changes the owner of land tile t; keeps tile counts, value, centroids, border lists and
## structures consistent. The single entry point for every ownership change.
func set_owner(t: int, new_owner: int) -> void:
	var old := owner[t]
	if old == new_owner:
		return
	if old != 0:
		if in_border[t] == 1:
			_border_remove(t, old)
		o_tiles[old] -= 1
		o_value[old] -= tile_value[t]
		o_sx[old] -= t % W
		o_sy[old] -= t / W
		o_st_lost_tiles[old] += 1
		if o_tiles[old] <= 0:
			o_killer[old] = new_owner
			pending_elim.append(old)
	owner[t] = new_owner
	if new_owner != 0:
		o_tiles[new_owner] += 1
		o_value[new_owner] += tile_value[t]
		o_sx[new_owner] += t % W
		o_sy[new_owner] += t / W
		o_st_conquered[new_owner] += 1
		if o_tiles[new_owner] > o_st_peak_tiles[new_owner]:
			o_st_peak_tiles[new_owner] = o_tiles[new_owner]
	changed_tiles.append(t)
	_refresh_border(t)
	var x := t % W
	if x > 0:
		_refresh_border(t - 1)
	if x < W - 1:
		_refresh_border(t + 1)
	if t >= W:
		_refresh_border(t - W)
	if t + W < N:
		_refresh_border(t + W)
	if struct_at[t] >= 0 and on_struct_tile.is_valid():
		on_struct_tile.call(t, old, new_owner)


func drain_changed_tiles() -> PackedInt32Array:
	var out := changed_tiles
	changed_tiles = PackedInt32Array()
	return out


## Border tiles of `id` (a copy; cost ~ border length).
func border_tiles(id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(o_border_count[id])
	var t := o_border_head[id]
	var i := 0
	while t >= 0 and i < out.size():
		out[i] = t
		i += 1
		t = bnext[t]
	return out


## Every tile of `id`, by flood fill from its border (cheap for small owners only).
func owned_tiles(id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if o_tiles[id] <= 0:
		return out
	var seen := {}
	var stack: Array[int] = []
	var t := o_border_head[id]
	while t >= 0:
		stack.append(t)
		seen[t] = true
		t = bnext[t]
	if stack.is_empty() and o_spawn_tile[id] >= 0 and owner[o_spawn_tile[id]] == id:
		stack.append(o_spawn_tile[id])
		seen[o_spawn_tile[id]] = true
	while not stack.is_empty():
		var c: int = stack.pop_back()
		out.append(c)
		var x := c % W
		for nb: int in [c - 1 if x > 0 else -1, c + 1 if x < W - 1 else -1, c - W, c + W]:
			if nb >= 0 and nb < N and owner[nb] == id and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return out


## Distinct neighbour owners of `id` (0 = unclaimed land) with their contact tile counts, from a
## walk of up to `limit` border tiles. Returns {owner_id: contact_count}.
func neighbours(id: int, limit: int = 100000) -> Dictionary:
	var out := {}
	var t := o_border_head[id]
	var steps := 0
	var land := map.land
	while t >= 0 and steps < limit:
		steps += 1
		var x := t % W
		if x > 0 and land[t - 1] == 1 and owner[t - 1] != id:
			out[owner[t - 1]] = int(out.get(owner[t - 1], 0)) + 1
		if x < W - 1 and land[t + 1] == 1 and owner[t + 1] != id:
			out[owner[t + 1]] = int(out.get(owner[t + 1], 0)) + 1
		if t >= W and land[t - W] == 1 and owner[t - W] != id:
			out[owner[t - W]] = int(out.get(owner[t - W], 0)) + 1
		if t + W < N and land[t + W] == 1 and owner[t + W] != id:
			out[owner[t + W]] = int(out.get(owner[t + W], 0)) + 1
		t = bnext[t]
	return out


## Sum of contestable land owned by alive owners (for land shares).
func land_share(id: int) -> float:
	return float(o_tiles[id]) / maxf(1.0, float(map.land_count))


# ---------------------------------------------------------------------------------------------
# Serialization (save system)
# ---------------------------------------------------------------------------------------------

const OWNER_FIELDS := ["o_name", "o_kind", "o_alive", "o_spawned", "o_color", "o_flag", "o_nation",
	"o_tiles", "o_value", "o_troops", "o_gold", "o_supplies", "o_cap", "o_income", "o_upkeep",
	"o_supply_income", "o_port_trade", "o_growth", "o_border_head", "o_border_count", "o_sx", "o_sy",
	"o_spawn_tile", "o_boats", "o_attacked_tick", "o_killer", "o_elim_tick", "o_blevels", "o_bowned",
	"o_st_attacks", "o_st_conquered", "o_st_lost_tiles", "o_st_troops_lost", "o_st_gold_earned",
	"o_st_gold_spent", "o_st_peak_tiles", "o_st_upkeep_paid", "o_st_commands", "o_st_built"]
const TILE_FIELDS := ["owner", "in_border", "bnext", "bprev", "struct_at", "front_mark"]


func to_dict() -> Dictionary:
	var d := {"tick": tick, "owner_count": owner_count}
	for f: String in OWNER_FIELDS:
		d[f] = get(f)
	for f: String in TILE_FIELDS:
		d[f] = get(f)
	return d


func from_dict(d: Dictionary) -> void:
	tick = d["tick"]
	owner_count = d["owner_count"]
	for f: String in OWNER_FIELDS:
		if d.has(f):
			set(f, d[f])
	for f: String in TILE_FIELDS:
		if d.has(f):
			set(f, d[f])
	changed_tiles = PackedInt32Array()
	pending_elim.clear()
