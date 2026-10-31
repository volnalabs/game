extends TestCase
## Ownership changes keep tile counts and per-owner border lists exactly consistent.


func _brute_border_count(st: SimState, id: int) -> int:
	var n := 0
	for t in st.N:
		if st.owner[t] == id and st.map.land[t] == 1 and st.is_border(t):
			n += 1
	return n


func test_border_lists_stay_consistent() -> void:
	var m := TestMaps.rect(60, 40)
	var st := SimState.new(m, Rules.for_k(1.0))
	var a := st.add_owner("A", Rules.KIND_NATION, Color.RED)
	var b := st.add_owner("B", Rules.KIND_NATION, Color.BLUE)
	var rng := SimRng.new(3)
	for i in 3000:
		var t := m.land_tiles[rng.below(m.land_count)]
		st.set_owner(t, [0, a, b][rng.below(3)])
	for id in [a, b]:
		var tiles := 0
		for t in st.N:
			if st.owner[t] == id:
				tiles += 1
		check_eq(st.o_tiles[id], tiles, "tile count of %d" % id)
		check_eq(st.o_border_count[id], _brute_border_count(st, id), "border count of %d" % id)
		var walked := st.border_tiles(id)
		check_eq(walked.size(), st.o_border_count[id], "list length of %d" % id)
		for t in walked:
			check(st.owner[t] == id and st.is_border(t), "listed tile %d is a border of %d" % [t, id])


func test_last_tile_queues_elimination() -> void:
	var m := TestMaps.rect(20, 20)
	var st := SimState.new(m, Rules.for_k(1.0))
	var a := st.add_owner("A", Rules.KIND_NATION, Color.RED)
	var b := st.add_owner("B", Rules.KIND_NATION, Color.BLUE)
	var t := m.tile_at(10, 10)
	st.set_owner(t, a)
	st.set_owner(t, b)
	check(st.pending_elim.has(a))
	check_eq(st.o_killer[a], b)
