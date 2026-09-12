extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# Case 1: World.create(42) — shape, counts, captains, passability.
	var w := World.create(42)
	t.check(w.faction_count == 6, "faction_count == 6")
	t.check(w.towns.size() == 24, "towns.size() == 24")

	var owners_ok := true
	for f in range(6):
		if w.town_owner[f] != f:
			owners_ok = false
	t.check(owners_ok, "town_owner[0..5] == 0..5")
	t.check(w.town_owner[6] == -1, "town_owner[6] == -1")

	t.check(w.stacks.n == 18, "stacks.n == 18")

	var all_alive := true
	var counts_ok := true
	var sum_counts := 0
	for si in range(w.stacks.n):
		if w.stacks.alive[si] == 0:
			all_alive = false
		var c := w.stacks.count[si]
		if c < 61 or c > 121:
			counts_ok = false
		sum_counts += c
	t.check(all_alive, "every stack alive")
	t.check(counts_ok, "every stack count in [61, 121]")
	t.check(w.units.n == sum_counts, "units.n == sum of counts")

	var captains_ok := true
	for ci in range(w.stacks.n):
		var cu := w.stacks.captain_unit[ci]
		if cu < 0 or w.units.is_captain[cu] != 1 or not w.units.names.has(cu):
			captains_ok = false
	t.check(captains_ok, "every stack has captain_unit >= 0, is_captain, named")

	var tiles_passable := true
	for ti in range(w.stacks.n):
		var tile := w.stack_tile(ti)
		if not w.map.passable(tile.x, tile.y):
			tiles_passable = false
	t.check(tiles_passable, "every stack position's tile is passable")

	# Case 2: determinism.
	var w1 := World.create(42)
	var w2 := World.create(42)
	t.check(w1.units.weapon == w2.units.weapon, "units.weapon arrays equal")
	t.check(w1.stacks.names == w2.stacks.names, "stacks.names equal")
	t.check(w1.stacks.x == w2.stacks.x, "stacks.x equal")

	# Case 3: blank world.
	var wb := World.new()
	wb.setup_blank(12, 8, 1)
	t.check(wb.map.cols == 12, "map.cols == 12")
	t.check(wb.towns.size() == 0, "towns.size() == 0")
	t.check(wb.stacks.n == 0, "stacks.n == 0")
	t.check(wb.pathing != null, "pathing != null")

	# Case 4: helpers on a hand-built blank world.
	var w4 := World.new()
	w4.setup_blank(12, 8, 1)

	w4.towns.append(Vector2(2, 2))
	w4.town_owner.append(0)
	w4.towns.append(Vector2(9, 2))
	w4.town_owner.append(1)
	w4.towns.append(Vector2(5, 6))
	w4.town_owner.append(-1)
	w4.map.kind[w4.map.idx(2, 2)] = WorldMap.Kind.TOWN
	w4.map.kind[w4.map.idx(9, 2)] = WorldMap.Kind.TOWN
	w4.map.kind[w4.map.idx(5, 6)] = WorldMap.Kind.TOWN

	var c0 := w4.map.center_of(2, 2)
	var s0 := w4.stacks.add(0, c0.x, c0.y, "S0")
	w4.stacks.count[s0] = 50

	var c1 := w4.map.center_of(9, 2)
	var s1 := w4.stacks.add(1, c1.x, c1.y, "S1")
	w4.stacks.count[s1] = 30

	var c2 := w4.map.center_of(9, 6)
	var s2 := w4.stacks.add(1, c2.x, c2.y, "S2")
	w4.stacks.count[s2] = 80

	t.check(w4.town_at(Vector2i(9, 2)) == 1, "town_at((9,2)) == 1")
	t.check(w4.town_at(Vector2i(0, 0)) == -1, "town_at((0,0)) == -1")

	var x0 := c0.x
	var y0 := c0.y
	t.check(w4.nearest_town(x0, y0, 0, 0) == 0, "nearest_town mode 0 (own) == 0")
	t.check(w4.nearest_town(x0, y0, 0, 1) == 1, "nearest_town mode 1 (enemy) == 1")
	t.check(w4.nearest_town(x0, y0, 0, 2) == 2, "nearest_town mode 2 (neutral) == 2")
	t.check(w4.nearest_enemy_stack(0, false) == 1, "nearest_enemy_stack(0, false) == 1")
	t.check(w4.nearest_enemy_stack(0, true) == 1, "nearest_enemy_stack(0, true) == 1")
	t.check(w4.nearest_enemy_stack(1, true) == -1, "nearest_enemy_stack(1, true) == -1")
	t.check(w4.stack_tile(s2) == Vector2i(9, 6), "stack_tile(s2) == (9,6)")

	# Case 5: World.create(42) — town/plinko fields, borders.
	var w5 := World.create(42)

	t.check(w5.town_state.size() == 24, "town_state.size() == 24")
	var town_state_all_zero := true
	for st in w5.town_state:
		if st != 0:
			town_state_all_zero = false
	t.check(town_state_all_zero, "town_state all 0")
	t.check(t.approx(w5.town_pop[0], 50.0), "town_pop[0] approx 50.0")

	t.check(w5.plinko_rows.size() == 6, "plinko_rows.size() == 6")
	var plinko_rows_all_7 := true
	for pr in w5.plinko_rows:
		if pr != 7:
			plinko_rows_all_7 = false
	t.check(plinko_rows_all_7, "plinko_rows all 7")

	t.check(w5.plinko_order.size() == 6, "plinko_order.size() == 6")
	var plinko_orders_ok := true
	for f in range(w5.plinko_order.size()):
		var order: PackedInt32Array = w5.plinko_order[f]
		var seen := {}
		for v in order:
			seen[v] = true
		if seen.size() != Tuning.PLINKO_SLOTS:
			plinko_orders_ok = false
	t.check(plinko_orders_ok, "each plinko_order[f] a permutation of 0..8")

	t.check(w5.borders_version >= 1, "borders_version >= 1")

	var capital2_tile := Vector2i(int(w5.towns[2].x), int(w5.towns[2].y))
	t.check(w5.map.owner[w5.map.idx(capital2_tile.x, capital2_tile.y)] == 2, "map.owner at the capital of faction 2 == 2")

	var east_tile := capital2_tile + Vector2i(3, 0)
	if w5.map.in_bounds(east_tile.x, east_tile.y) and w5.map.passable(east_tile.x, east_tile.y):
		var expected_owner := -1
		var expected_dist := 1 << 30
		for ti in range(w5.towns.size()):
			var owner: int = w5.town_owner[ti]
			if owner < 0:
				continue
			var tt := Vector2i(int(w5.towns[ti].x), int(w5.towns[ti].y))
			var d := maxi(absi(east_tile.x - tt.x), absi(east_tile.y - tt.y))
			if d <= Tuning.BORDER_RANGE and d < expected_dist:
				expected_dist = d
				expected_owner = owner
		t.check(w5.map.owner[w5.map.idx(east_tile.x, east_tile.y)] == expected_owner, "map.owner 3 tiles east of capital 2 == 2 unless another owned town is nearer")

	var mountain_i := -1
	for i in range(w5.map.kind.size()):
		if w5.map.kind[i] == WorldMap.Kind.MOUNTAIN:
			mountain_i = i
			break
	if mountain_i >= 0:
		t.check(w5.map.owner[mountain_i] == -1, "map.owner of a MOUNTAIN tile == -1")

	# Case 6: add_town + recompute_borders on a hand-built blank world.
	var w6 := World.new()
	w6.setup_blank(12, 8, 1)

	t.check(w6.add_town(Vector2i(2, 2), 0) == 0, "add_town((2,2), 0) == 0")
	t.check(w6.add_town(Vector2i(9, 2), 1) == 1, "add_town((9,2), 1) == 1")
	t.check(w6.add_town(Vector2i(5, 6), -1) == 2, "add_town((5,6), -1) == 2")
	t.check(w6.map.kind[w6.map.idx(2, 2)] == WorldMap.Kind.TOWN, "map.kind[idx(2,2)] == TOWN")

	t.check(w6.borders_version == 0, "borders_version == 0 before recompute_borders (blank starts 0)")
	w6.recompute_borders()
	t.check(w6.map.owner[w6.map.idx(3, 2)] == 0, "map.owner[idx(3,2)] == 0")
	t.check(w6.map.owner[w6.map.idx(8, 2)] == 1, "map.owner[idx(8,2)] == 1")
	t.check(w6.map.owner[w6.map.idx(5, 2)] == 0, "map.owner[idx(5,2)] == 0 (distance 3 vs 4)")
	t.check(w6.map.owner[w6.map.idx(6, 2)] == 1, "map.owner[idx(6,2)] == 1 (4 vs 3)")
	t.check(w6.map.owner[w6.map.idx(5, 6)] == 0, "map.owner[idx(5,6)] == 0 (neutral town does not own; tie -> lowest id 0)")
	t.check(w6.borders_version == 1, "borders_version == 1 after the call")

	t.check(w6.plinko_order[0] == PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8]), "plinko_order[0] == identity for setup_blank")

	# Case 7: determinism of plinko_order.
	var wd1 := World.create(42)
	var wd2 := World.create(42)
	t.check(wd1.plinko_order[3] == wd2.plinko_order[3], "plinko_order[3] equal across two World.create(42) calls")

	t.finish()
	quit()
