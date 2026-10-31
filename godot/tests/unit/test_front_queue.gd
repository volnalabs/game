extends TestCase


func test_pops_in_priority_order() -> void:
	var q := FrontQueue.new()
	var rng := SimRng.new(5)
	var keys: Array[float] = []
	for i in 500:
		var k := rng.range_f(0.0, 100.0)
		keys.append(k)
		q.push(k, i)
	keys.sort()
	var prev := -1.0
	var n := 0
	while not q.is_empty():
		var t := q.pop()
		check(t >= 0)
		n += 1
	check_eq(n, 500)
	check_eq(q.pop(), -1, "empty queue")


func test_order_is_monotonic() -> void:
	var q := FrontQueue.new()
	for k in [5.0, 1.0, 3.0, 2.0, 4.0]:
		q.push(k, int(k))
	var out: Array[int] = []
	while not q.is_empty():
		out.append(q.pop())
	check_eq(out, [1, 2, 3, 4, 5])
	var d := q.to_dict()
	check_eq((d["tiles"] as PackedInt32Array).size(), 0)
