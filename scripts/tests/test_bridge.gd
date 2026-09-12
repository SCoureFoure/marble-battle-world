extends SceneTree
## Tests for BattleBridge.start / join / finish. See .warboss-horde/slices/m3-bridge.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## stacks.add(f, cx, cy, "S"); prev_x = cx + prev_dx * 64; n_units rank-0 sword
## units + one rank-1 sword captain, all stack = id, captain_unit, recount.
func mk_stack(w: World, f: int, tx: int, ty: int, n_units: int, prev_dx: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	w.stacks.prev_x[id] = c.x + prev_dx * 64
	for i in range(n_units):
		w.units.add(f, 0, 1, false, id)
	var cap_id := w.units.add(f, 1, 1, true, id)
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. start: two stacks from opposite sides.
	var w := World.new()
	w.setup_blank(12, 8, 7)
	var s0 := mk_stack(w, 0, 5, 4, 20, -1)
	var s1 := mk_stack(w, 1, 5, 4, 15, 1)
	var inst := BattleBridge.start(w, s0, s1)

	t.check(inst.state.n == 37, "case1 state.n == 37")
	t.check(inst.faction_map[0] == 0, "case1 faction_map[0] == 0")
	t.check(inst.faction_map[1] == 1, "case1 faction_map[1] == 1")
	t.check(w.stacks.state[s0] == Stacks.State.BATTLE, "case1 stacks.state[s0] == BATTLE")
	t.check(w.stacks.battle_id[s0] == inst.id, "case1 battle_id[s0] == inst.id")
	t.check(w.battles.size() == 1, "case1 battles.size() == 1")

	var f0_px_ok := true
	var f1_px_ok := true
	var captain_count := 0
	for i in range(inst.state.n):
		if inst.state.faction_id[i] == 0 and inst.state.px[i] >= 400:
			f0_px_ok = false
		if inst.state.faction_id[i] == 1 and inst.state.px[i] <= 1200:
			f1_px_ok = false
		if inst.state.is_captain[i] == 1:
			captain_count += 1
	t.check(f0_px_ok, "case1 every faction-0 marble px < 400")
	t.check(f1_px_ok, "case1 every faction-1 marble px > 1200")
	t.check(inst.unit_of.size() == 37, "case1 unit_of.size() == 37")
	t.check(captain_count == 2, "case1 two captains")
	t.check(inst.state.faction_captain[0] >= 0, "case1 faction_captain[0] >= 0")
	t.check(inst.state.faction_captain[1] >= 0, "case1 faction_captain[1] >= 0")
	t.check(inst.sim.terrain == inst.terrain, "case1 sim.terrain == inst.terrain")

	var non_plain := false
	for k in inst.terrain.kind:
		if k != TerrainGrid.Kind.PLAIN:
			non_plain = true
			break
	t.check(non_plain, "case1 terrain has a non-PLAIN cell")

	# 2. join third faction from below.
	var s2 := mk_stack(w, 2, 5, 4, 10, 0)
	w.stacks.prev_y[s2] = w.map.center_of(5, 4).y + 64.0
	var joined2 := BattleBridge.join(inst, w, s2)
	t.check(joined2, "case2 join true")
	t.check(inst.faction_map[3] == 2, "case2 faction_map[3] == 2")

	var f2_py_ok := true
	for i2 in range(inst.state.n):
		if inst.state.faction_id[i2] == 3 and inst.state.py[i2] <= 620:
			f2_py_ok = false
	t.check(f2_py_ok, "case2 every faction-2 marble py > 620")

	# 3. join refused when full.
	var w3 := World.new()
	w3.setup_blank(12, 8, 7)
	var s0_3 := mk_stack(w3, 0, 5, 4, 20, -1)
	var s1_3 := mk_stack(w3, 1, 5, 4, 15, 1)
	var inst3 := BattleBridge.start(w3, s0_3, s1_3)
	var n_before3 := inst3.state.n
	var s3 := mk_stack(w3, 2, 5, 4, 700, 0)
	var joined3 := BattleBridge.join(inst3, w3, s3)
	t.check(not joined3, "case3 join false when full")
	t.check(w3.stacks.state[s3] == Stacks.State.IDLE, "case3 stacks.state[s3] still IDLE")
	t.check(inst3.state.n == n_before3, "case3 state.n unchanged")

	# 4. finish, winner 0.
	var w4 := World.new()
	w4.setup_blank(12, 8, 7)
	var s0_4 := mk_stack(w4, 0, 5, 4, 20, -1)
	var s1_4 := mk_stack(w4, 1, 5, 4, 15, 1)
	var inst4 := BattleBridge.start(w4, s0_4, s1_4)

	var picked_i := -1
	for i4 in range(inst4.state.n):
		if inst4.state.faction_id[i4] == 1:
			inst4.state.state[i4] = BattleState.State.DEAD
		elif picked_i == -1 and inst4.state.faction_id[i4] == 0:
			picked_i = i4
	inst4.state.hp[picked_i] = 30.0
	inst4.state.hp_max[picked_i] = 100.0
	inst4.state.xp[picked_i] = 35
	inst4.state.kills[picked_i] = 2
	var picked_u4 := inst4.unit_of[picked_i]

	var result4 := BattleBridge.finish(inst4, w4)
	t.check(result4["winner"] == 0, "case4 winner == 0")
	t.check(result4["dead"] == 16, "case4 dead == 16")

	var f1_alive_sum := 0
	for u4 in range(w4.units.n):
		if w4.units.faction[u4] == 1:
			f1_alive_sum += w4.units.alive[u4]
	t.check(f1_alive_sum == 0, "case4 units.alive sum for f1 == 0")
	t.check(w4.stacks.count[s1_4] == 0, "case4 stacks.count[s1] == 0")
	t.check(w4.stacks.alive[s1_4] == 0, "case4 stacks.alive[s1] == 0")
	t.check(w4.stacks.count[s0_4] == 21, "case4 stacks.count[s0] == 21")
	t.check(t.approx(w4.units.hp_frac[picked_u4], 0.3, 1e-4), "case4 hp_frac approx 0.3")
	t.check(w4.units.xp[picked_u4] == 35, "case4 xp == 35")
	t.check(w4.units.kills[picked_u4] == 2, "case4 kills == 2")
	t.check(w4.units.rank[picked_u4] == 0, "case4 rank copied")
	t.check(w4.stacks.state[s0_4] == Stacks.State.IDLE, "case4 stacks.state[s0] == IDLE")
	t.check(t.approx(w4.stacks.idle_timer[s0_4], 3.0, 1e-4), "case4 idle_timer[s0] approx 3.0")
	t.check(w4.battles.size() == 0, "case4 battles.size() == 0")
	t.check(w4.scars.size() == 1, "case4 scars.size() == 1")

	# 5. finish, loser retreats to own town.
	# NOTE: the slice text says the town is "owned by faction 1", but the
	# expected goal tile equals that town's tile for stack s0_5 (world
	# faction 0) — the fork tag's algorithm ("nearest own town") only
	# matches faction 0's own town. Implemented with the town owned by
	# faction 0 so the algorithm and the expected goal_tx/goal_ty agree.
	var w5 := World.new()
	w5.setup_blank(12, 8, 7)
	var s0_5 := mk_stack(w5, 0, 5, 4, 20, -1)
	var s1_5 := mk_stack(w5, 1, 5, 4, 15, 1)
	var inst5 := BattleBridge.start(w5, s0_5, s1_5)

	w5.towns.append(Vector2(1, 4))
	w5.town_owner.append(0)
	w5.map.kind[w5.map.idx(1, 4)] = WorldMap.Kind.TOWN

	var retreat_count := 0
	var toggle := true
	for i5 in range(inst5.state.n):
		if inst5.state.faction_id[i5] == 0:
			if toggle:
				inst5.state.state[i5] = BattleState.State.RETREAT
				retreat_count += 1
			else:
				inst5.state.state[i5] = BattleState.State.DEAD
			toggle = not toggle

	var result5 := BattleBridge.finish(inst5, w5)
	t.check(result5["winner"] == 1, "case5 winner == 1")
	t.check(w5.stacks.count[s0_5] == retreat_count, "case5 stacks.count[s0] == retreating survivors")
	t.check(w5.stacks.state[s0_5] == Stacks.State.RETREATING, "case5 stacks.state[s0] == RETREATING")
	t.check(t.approx(w5.stacks.immunity[s0_5], 10.0, 1e-4), "case5 immunity[s0] approx 10.0")
	t.check(w5.stacks.goal_tx[s0_5] == 1 and w5.stacks.goal_ty[s0_5] == 4, "case5 goal tile == (1,4)")
	t.check(w5.stacks.path[s0_5].size() > 0, "case5 path[s0].size() > 0")

	# 6. stalemate.
	var w6 := World.new()
	w6.setup_blank(12, 8, 7)
	var s0_6 := mk_stack(w6, 0, 5, 4, 20, -1)
	var s1_6 := mk_stack(w6, 1, 5, 4, 15, 1)
	var inst6 := BattleBridge.start(w6, s0_6, s1_6)
	inst6.state.time = 200.0

	var result6 := BattleBridge.finish(inst6, w6)
	t.check(result6["winner"] == -1, "case6 winner == -1")
	t.check(w6.stacks.state[s0_6] == Stacks.State.RETREATING, "case6 stacks.state[s0] == RETREATING")
	t.check(w6.stacks.state[s1_6] == Stacks.State.RETREATING, "case6 stacks.state[s1] == RETREATING")

	# 7. fled survivor.
	var w7 := World.new()
	w7.setup_blank(12, 8, 7)
	var s0_7 := mk_stack(w7, 0, 5, 4, 20, -1)
	var s1_7 := mk_stack(w7, 1, 5, 4, 15, 1)
	var inst7 := BattleBridge.start(w7, s0_7, s1_7)

	var fled_i := -1
	for i7 in range(inst7.state.n):
		if inst7.state.faction_id[i7] == 1:
			if fled_i == -1:
				fled_i = i7
				inst7.state.fled[i7] = 1
				inst7.state.state[i7] = BattleState.State.DEAD
				inst7.state.hp[i7] = 40.0
			else:
				inst7.state.state[i7] = BattleState.State.DEAD
	var fled_u7 := inst7.unit_of[fled_i]

	var result7 := BattleBridge.finish(inst7, w7)
	t.check(result7["winner"] == 0, "case7 winner == 0")
	t.check(w7.units.alive[fled_u7] == 1, "case7 fled unit alive")
	t.check(t.approx(w7.units.hp_frac[fled_u7], 0.4, 1e-4), "case7 hp_frac approx 0.4")
	t.check(w7.stacks.count[s1_7] == 1, "case7 stacks.count[s1] == 1")

	t.finish()
	quit()
