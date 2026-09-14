extends SceneTree
## Tests for the M4 hookup: TownSim in WorldSim.step_world, plinko after a
## battle win in WorldSim.step_battles, drill spin bonus in BattleBridge.join.
## See .warboss-horde/slices/m4-hookup.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


# Stack of `count` units (count-1 regular rank-0 sword units + 1 rank-1
# sword captain) at `tile`, recounted.
func mk_stack(w: World, f: int, tile: Vector2i, count: int) -> int:
	var c := w.map.center_of(tile.x, tile.y)
	var sid := w.stacks.add(f, c.x, c.y, "S%d" % w.stacks.n)
	for _u in range(count - 1):
		w.units.add(f, 0, 1, false, sid)
	var cap := w.units.add(f, 1, 1, true, sid)
	w.stacks.captain_unit[sid] = cap
	w.stacks.recount(w.units)
	return sid


# Stack of `count` rank-0 sword units, no captain.
func mk_stack_no_captain(w: World, f: int, tile: Vector2i, count: int) -> int:
	var c := w.map.center_of(tile.x, tile.y)
	var sid := w.stacks.add(f, c.x, c.y, "S%d" % w.stacks.n)
	for _u in range(count):
		w.units.add(f, 0, 1, false, sid)
	w.stacks.recount(w.units)
	return sid


func _init() -> void:
	var t := TestKit.new()

	# 1. Towns tick through the world: own town recruits into the nearby stack.
	var w1 := World.new()
	w1.setup_blank(12, 8, 9)
	w1.add_town(Vector2i(3, 3), 0)
	var s0_1 := mk_stack(w1, 0, Vector2i(4, 3), 10)

	for _i in range(1440):
		WorldSim.step(w1, Tuning.DT)
	t.check(w1.stacks.count[s0_1] == 11, "case1 count[s0] == 11 after 24s of town recruiting")

	# 2. Drill in bridge: spin_cap bonus applied on join.
	var w2 := World.new()
	w2.setup_blank(12, 8, 9)
	var s0_2 := mk_stack(w2, 0, Vector2i(5, 4), 20)
	for u in range(w2.units.n):
		if w2.units.stack[u] == s0_2:
			w2.units.drill[u] = 2
	w2.units.rank[w2.stacks.captain_unit[s0_2]] = 0
	var s1_2 := mk_stack(w2, 1, Vector2i(6, 4), 15)
	var inst2 := BattleBridge.start(w2, s0_2, s1_2)

	var ok2 := true
	for i in range(inst2.state.n):
		var wf2: int = inst2.faction_map[inst2.state.faction_id[i]]
		if wf2 == 0 and not t.approx(inst2.state.spin_cap[i], 160.0, 1e-4):
			ok2 = false
	t.check(ok2, "case2 every faction-0 marble spin_cap == 120 + 40")

	# 3. Plinko after a win: s0 (41, incl. captain) crushes s1 (3, no captain).
	var w3 := World.new()
	w3.setup_blank(12, 8, 9)
	var s0_3 := mk_stack(w3, 0, Vector2i(5, 4), 41)
	var s1_3 := mk_stack_no_captain(w3, 1, Vector2i(5, 4), 3)
	var c3 := w3.map.center_of(5, 4)
	w3.stacks.prev_x[s0_3] = c3.x - 64.0
	w3.stacks.prev_x[s1_3] = c3.x + 64.0
	BattleBridge.start(w3, s0_3, s1_3)

	var ticks3 := 0
	while w3.battles.size() > 0 and ticks3 < 7300:
		WorldSim.step(w3, Tuning.DT)
		ticks3 += 1
	t.check(w3.battles.size() == 0, "case3 battle finished within 7300 ticks")
	t.check(w3.plinko_log.size() >= 1, "case3 plinko_log has an entry")

	if w3.plinko_log.size() >= 1:
		var entry3: Array = w3.plinko_log[w3.plinko_log.size() - 1]
		t.check(entry3[0] == s0_3, "case3 entry stack == s0 (s0 has 41 vs s1's 3, s0 wins)")
		var slots3: PackedInt32Array = entry3[1]
		t.check(slots3.size() >= 1 and slots3.size() <= 3, "case3 slots.size() in 1..3")
		var lines3: Array = entry3[2]
		t.check(lines3.size() == slots3.size(), "case3 lines.size() == slots.size()")
	t.check(w3.events_log.size() >= 1, "case3 events_log has an entry")

	# 4. No plinko on stalemate.
	var w4 := World.new()
	w4.setup_blank(12, 8, 9)
	var s0_4 := mk_stack(w4, 0, Vector2i(5, 4), 41)
	var s1_4 := mk_stack_no_captain(w4, 1, Vector2i(5, 4), 3)
	var c4 := w4.map.center_of(5, 4)
	w4.stacks.prev_x[s0_4] = c4.x - 64.0
	w4.stacks.prev_x[s1_4] = c4.x + 64.0
	var inst4 := BattleBridge.start(w4, s0_4, s1_4)
	inst4.state.time = 200.0

	WorldSim.step(w4, Tuning.DT)
	t.check(w4.battles.size() == 0, "case4 stalemate battle finished")
	t.check(w4.plinko_log.size() == 0, "case4 no plinko on stalemate")

	# 5. No plinko without a living captain.
	var w5 := World.new()
	w5.setup_blank(12, 8, 9)
	var s0_5 := mk_stack(w5, 0, Vector2i(5, 4), 41)
	var s1_5 := mk_stack_no_captain(w5, 1, Vector2i(5, 4), 3)
	var c5 := w5.map.center_of(5, 4)
	w5.stacks.prev_x[s0_5] = c5.x - 64.0
	w5.stacks.prev_x[s1_5] = c5.x + 64.0
	var cap5 := w5.stacks.captain_unit[s0_5]
	w5.units.kill(cap5)
	w5.stacks.captain_unit[s0_5] = -1
	BattleBridge.start(w5, s0_5, s1_5)

	var ticks5 := 0
	while w5.battles.size() > 0 and ticks5 < 7300:
		WorldSim.step(w5, Tuning.DT)
		ticks5 += 1
	t.check(w5.battles.size() == 0, "case5 battle finished within 7300 ticks")
	t.check(w5.plinko_log.size() == 0, "case5 no plinko without a living captain")

	t.finish()
	quit()
