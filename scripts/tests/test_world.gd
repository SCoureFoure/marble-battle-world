extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# Case 1: World.create(42) — mirror the population rng (seed + 2) and
	# check the shape it should have produced.
	var w := World.create(42)
	var p := RandomNumberGenerator.new()
	p.seed = 44
	var k := p.randi_range(Tuning.KINGDOMS_MIN, Tuning.KINGDOMS_MAX)
	var c := p.randi_range(Tuning.COMPANIES_MIN, Tuning.COMPANIES_MAX)
	var nt := p.randi_range(maxi(Tuning.TOWNS_MIN, k), Tuning.TOWNS_MAX)

	t.check(w.towns.size() <= nt, "towns.size() <= nt")
	t.check(w.towns.size() >= k, "towns.size() >= k")

	var owned := 0
	for ti in range(w.towns.size()):
		if w.town_owner[ti] >= 0:
			owned += 1
	t.check(owned == k, "owned towns count == k")
	t.check(w.faction_count == k + c, "faction_count == k + c")
	t.check(w.stacks.n == k * Tuning.STACKS_PER_FACTION + c, "stacks.n == k*STACKS_PER_FACTION + c")

	# Case 2: kingdom stacks (i < k*3) vs. company stacks (i >= k*3).
	var kingdom_stacks_ok := true
	for i in range(k * Tuning.STACKS_PER_FACTION):
		if w.stacks.faction[i] >= k:
			kingdom_stacks_ok = false
		if not t.approx(w.stacks.gold[i], 40.0):
			kingdom_stacks_ok = false
	t.check(kingdom_stacks_ok, "kingdom stacks: faction < k, gold == 40.0")

	var company_stacks_ok := true
	for i in range(k * Tuning.STACKS_PER_FACTION, w.stacks.n):
		if w.stacks.faction[i] != k + (i - k * Tuning.STACKS_PER_FACTION):
			company_stacks_ok = false
		if not t.approx(w.stacks.gold[i], 80.0):
			company_stacks_ok = false
		var cnt := w.stacks.count[i]
		if cnt < 13 or cnt > 31:
			company_stacks_ok = false
		var cap := w.stacks.captain_unit[i]
		if cap < 0 or w.units.hero[cap] != 1 or w.units.is_captain[cap] != 1:
			company_stacks_ok = false
		var tile := w.stack_tile(i)
		if w.map.kind[w.map.idx(tile.x, tile.y)] == WorldMap.Kind.MOUNTAIN or not w.map.passable(tile.x, tile.y):
			company_stacks_ok = false
	t.check(company_stacks_ok, "company stacks: faction, gold, count, captain, tile")

	# Case 3: every captain's career_start in [-450, 0] (-HERO_LIFESPAN * START_AGE_SPREAD).
	var career_ok := true
	for si in range(w.stacks.n):
		var cap2 := w.stacks.captain_unit[si]
		if cap2 < 0:
			career_ok = false
			continue
		var cs := w.units.career_start[cap2]
		if cs < -450.0 or cs > 0.0:
			career_ok = false
	t.check(career_ok, "every captain's career_start in [-450, 0]")

	# Case 4: faction_alive / faction_names / plinko_order / faction_color shape.
	var alive_ok := true
	for f in range(w.faction_count):
		if w.faction_alive[f] != 1:
			alive_ok = false
	for f in range(w.faction_count, Tuning.MAX_FACTIONS_WORLD):
		if w.faction_alive[f] != 0:
			alive_ok = false
	t.check(alive_ok, "faction_alive == 1 for f < faction_count, 0 for faction_count <= f < 64")
	t.check(w.faction_names.size() == w.faction_count, "faction_names.size() == faction_count")
	t.check(w.plinko_order.size() == w.faction_count, "plinko_order.size() == faction_count")
	var color_ok := true
	for f in range(Tuning.MAX_FACTIONS_WORLD):
		if w.faction_color[f] != f % 16:
			color_ok = false
	t.check(color_ok, "faction_color[f] == f % 16")

	# Case 5: determinism.
	var w1 := World.create(42)
	var w2 := World.create(42)
	t.check(w1.units.weapon == w2.units.weapon, "units.weapon arrays equal")
	t.check(w1.stacks.names == w2.stacks.names, "stacks.names equal")
	t.check(w1.stacks.x == w2.stacks.x, "stacks.x equal")
	t.check(w1.faction_count == w2.faction_count, "faction_count equal")
	t.check(w1.units.n == w2.units.n, "units.n equal")
	t.check(w1.stacks.y == w2.stacks.y, "stacks.y equal")
	t.check(w1.towns == w2.towns, "towns equal")
	t.check(w1.rng.state == w2.rng.state, "rng.state equal")

	# Case 6: spread across seeds 1..12.
	var spread_ok := true
	var spread_passable_ok := true
	for sd in range(1, 13):
		var ws := World.create(sd)
		if ws.faction_count < 5 or ws.faction_count > 13:
			spread_ok = false
		for si in range(ws.stacks.n):
			var tile3 := ws.stack_tile(si)
			if not ws.map.passable(tile3.x, tile3.y):
				spread_passable_ok = false
	t.check(spread_ok, "faction_count (k + c) in [5, 13] for seeds 1..12")
	t.check(spread_passable_ok, "every stack tile passable for seeds 1..12")

	# Case 7: WorldGen.generate town_count parameter.
	var wm7 := WorldMap.new(96, 54, 5)
	var towns7: Array = WorldGen.generate(wm7)
	t.check(towns7.size() <= Tuning.N_FACTIONS * Tuning.TOWNS_PER_FACTION + Tuning.NEUTRAL_TOWNS, "generate() town count <= formula")
	t.check(towns7.size() >= 20, "generate() town count >= 20")

	var wm8 := WorldMap.new(96, 54, 5)
	var towns8: Array = WorldGen.generate(wm8, 17)
	t.check(towns8.size() <= 17, "generate(m, 17).size() <= 17")
	t.check(towns8.size() >= 15, "generate(m, 17).size() >= 15")

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

	# Case 5: World.create(42) — town/plinko fields, borders. Counts derived
	# from the world itself (population is randomized; only faction 0 is
	# guaranteed to exist as a kingdom, since KINGDOMS_MIN == 2).
	var w5 := World.create(42)

	t.check(w5.town_state.size() == w5.towns.size(), "town_state.size() == towns.size()")
	var town_state_all_zero := true
	for st in w5.town_state:
		if st != 0:
			town_state_all_zero = false
	t.check(town_state_all_zero, "town_state all 0")
	t.check(t.approx(w5.town_pop[0], 50.0), "town_pop[0] approx 50.0")

	t.check(w5.plinko_rows.size() == w5.faction_count, "plinko_rows.size() == faction_count")
	var plinko_rows_all_7 := true
	for pr in w5.plinko_rows:
		if pr != 7:
			plinko_rows_all_7 = false
	t.check(plinko_rows_all_7, "plinko_rows all 7")

	t.check(w5.plinko_order.size() == w5.faction_count, "plinko_order.size() == faction_count")
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

	var capital2_tile := Vector2i(int(w5.towns[0].x), int(w5.towns[0].y))
	t.check(w5.map.owner[w5.map.idx(capital2_tile.x, capital2_tile.y)] == 0, "map.owner at the capital of faction 0 == 0")

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
		t.check(w5.map.owner[w5.map.idx(east_tile.x, east_tile.y)] == expected_owner, "map.owner 3 tiles east of capital 0 == 0 unless another owned town is nearer")

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
