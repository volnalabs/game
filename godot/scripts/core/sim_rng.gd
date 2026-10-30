class_name SimRng
extends RefCounted
## The only source of randomness for the simulation, the AI and the map generator.
## Wraps Godot's PCG32 RandomNumberGenerator with an explicit, saveable seed and state, so the same
## seed always replays the same match (the original RoWorld sim relied on the same generator,
## see src/shared/Core/GodotRng.luau).

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_rng.seed = hash(seed_value)


func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


## Uniform integer in [lo, hi] (inclusive).
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return _rng.randi_range(lo, hi)


## Uniform integer in [0, n).
func below(n: int) -> int:
	if n <= 1:
		return 0
	return _rng.randi_range(0, n - 1)


func randf() -> float:
	return _rng.randf()


func range_f(lo: float, hi: float) -> float:
	return _rng.randf_range(lo, hi)


func chance(p: float) -> bool:
	return _rng.randf() < p


## Symmetric noise in [-amp, amp].
func noise(amp: float) -> float:
	return (_rng.randf() * 2.0 - 1.0) * amp


## A derived, independent generator (for subsystems that must not disturb the main stream).
func fork(salt: int) -> SimRng:
	return SimRng.new(hash([_rng.seed, salt]))


## Fisher-Yates shuffle of an Array in place.
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
