extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")


# Blank world helper, seed 3 per slice m4-outcomes.
func mk_world(cols: int, rows: int) -> World:
	var w := World.new()
	w.setup_blank(cols, rows, 3)
	return w


# Stack of `n` units at tile (tx, ty): n-1 rank-0 sword units + one rank-1
# captain, recounted.
func mk_stack(w: World, f: int, tx: int, ty: int, n: int) -> int:
	var c := w.map.center_of(tx, ty)
	var sid := w.stacks.add(f, c.x, c.y, "S%d" % w.stacks.n)
	for _u in range(n - 1):
		w.units.add(f, 0, 1, false, sid)
	var cap := w.units.add(f, 1, 1, true, sid)
	w.stacks.captain_unit[sid] = cap
	w.stacks.recount(w.units)
	return sid


func _init() -> void:
	var t := TestKit.new()
	var logs: Array = []

	# Case 1: SETTLE — neutral town at (4,2) preferred over nearer enemy
	# town at (3,2) (32 world units vs 64).
	var w1 := mk_world(12, 8)
	var s1 := mk_stack(w1, 0, 2, 2, 5)
	var neutral_town := w1.towns.size()
	w1.add_town(Vector2i(4, 2), -1)
	var enemy_town1 := w1.towns.size()
	w1.add_town(Vector2i(3, 2), 1)
	w1.recompute_borders()
	for u1 in range(w1.units.n):
		if w1.units.stack[u1] == s1:
			w1.units.hp_frac[u1] = 0.3
			break
	var bv1 := w1.borders_version
	logs.append(PlinkoOutcomes.apply(w1, s1, PlinkoOutcomes.Slot.SETTLE))
	t.check(w1.town_owner[neutral_town] == 0, "case1 SETTLE neutral town (4,2) owner == 0")
	t.check(w1.town_owner[enemy_town1] == 1, "case1 SETTLE nearer enemy town (3,2) untouched")
	var wounded1_ok := true
	for u1b in range(w1.units.n):
		if w1.units.stack[u1b] == s1 and w1.units.hp_frac[u1b] != 1.0:
			wounded1_ok = false
	t.check(wounded1_ok, "case1 SETTLE all stack units hp_frac == 1.0")
	t.check(w1.borders_version > bv1, "case1 SETTLE borders_version increased")

	# Case 2a: RECRUIT — own INTACT town pop 50 within range.
	var w2a := mk_world(12, 8)
	var s2a := mk_stack(w2a, 0, 2, 2, 5)
	var town2a := w2a.towns.size()
	w2a.add_town(Vector2i(3, 2), 0)
	w2a.town_state[town2a] = 0
	w2a.town_pop[town2a] = 50.0
	w2a.recompute_borders()
	logs.append(PlinkoOutcomes.apply(w2a, s2a, PlinkoOutcomes.Slot.RECRUIT))
	t.check(w2a.stacks.count[s2a] == 15, "case2a RECRUIT count == 15")
	t.check(absf(w2a.town_pop[town2a] - 40.0) < 1.0, "case2a RECRUIT town_pop approx 40")

	# Case 2b: RECRUIT — own INTACT town pop 4.0 within range.
	var w2b := mk_world(12, 8)
	var s2b := mk_stack(w2b, 0, 2, 2, 5)
	var town2b := w2b.towns.size()
	w2b.add_town(Vector2i(3, 2), 0)
	w2b.town_state[town2b] = 0
	w2b.town_pop[town2b] = 4.0
	w2b.recompute_borders()
	logs.append(PlinkoOutcomes.apply(w2b, s2b, PlinkoOutcomes.Slot.RECRUIT))
	t.check(w2b.stacks.count[s2b] == 9, "case2b RECRUIT count == 9 (+4)")

	# Case 2c: RECRUIT — no own town within range (wilds).
	var w2c := mk_world(12, 8)
	var s2c := mk_stack(w2c, 0, 2, 2, 5)
	logs.append(PlinkoOutcomes.apply(w2c, s2c, PlinkoOutcomes.Slot.RECRUIT))
	t.check(w2c.stacks.count[s2c] == 10, "case2c RECRUIT wilds count == 10 (+5)")

	# Case 3a: RAID — enemy town at (5,2), within range.
	var w3a := mk_world(12, 8)
	var s3a := mk_stack(w3a, 0, 2, 2, 5)
	var town3a := w3a.towns.size()
	w3a.add_town(Vector2i(5, 2), 1)
	w3a.town_state[town3a] = 0
	w3a.town_pop[town3a] = 50.0
	w3a.recompute_borders()
	var bv3a := w3a.borders_version
	logs.append(PlinkoOutcomes.apply(w3a, s3a, PlinkoOutcomes.Slot.RAID))
	t.check(w3a.town_state[town3a] == 1, "case3a RAID state == RAIDED")
	t.check(w3a.town_owner[town3a] == -1, "case3a RAID owner == -1")
	t.check(absf(w3a.town_pop[town3a] - 25.0) < 1.0, "case3a RAID pop approx 25")
	var xp_ok3a := true
	for u3a in range(w3a.units.n):
		if w3a.units.stack[u3a] == s3a and w3a.units.xp[u3a] != 5:
			xp_ok3a = false
	t.check(xp_ok3a, "case3a RAID every unit xp == 5")
	t.check(w3a.borders_version > bv3a, "case3a RAID borders_version increased")
	t.check(absf(w3a.town_timer[town3a] - 300.0) < 1.0, "case3a RAID town_timer approx 300.0")

	# Case 3b: RAID — enemy town 11 tiles away, out of RAID_RANGE.
	var w3b := mk_world(20, 8)
	var s3b := mk_stack(w3b, 0, 2, 2, 5)
	var town3b := w3b.towns.size()
	w3b.add_town(Vector2i(13, 2), 1)
	w3b.town_state[town3b] = 0
	w3b.town_pop[town3b] = 50.0
	w3b.recompute_borders()
	logs.append(PlinkoOutcomes.apply(w3b, s3b, PlinkoOutcomes.Slot.RAID))
	t.check(w3b.town_state[town3b] == 0, "case3b RAID out of range: state unchanged")
	t.check(w3b.town_owner[town3b] == 1, "case3b RAID out of range: owner unchanged")

	# Case 4: RAZE.
	var w4 := mk_world(12, 8)
	var s4 := mk_stack(w4, 0, 2, 2, 5)
	var town4 := w4.towns.size()
	w4.add_town(Vector2i(5, 2), 1)
	w4.town_state[town4] = 0
	w4.town_pop[town4] = 50.0
	w4.recompute_borders()
	logs.append(PlinkoOutcomes.apply(w4, s4, PlinkoOutcomes.Slot.RAZE))
	t.check(w4.town_state[town4] == 2, "case4 RAZE state == RAZED")
	t.check(w4.town_owner[town4] == -1, "case4 RAZE owner == -1")
	t.check(w4.town_pop[town4] == 0.0, "case4 RAZE pop == 0")
	t.check(absf(w4.town_timer[town4] - 900.0) < 1.0, "case4 RAZE timer approx 900")
	t.check(w4.map.kind[w4.map.idx(5, 2)] == WorldMap.Kind.RUIN, "case4 RAZE tile kind == RUIN")

	# Case 5: FORGE — 12 rank-0 units + captain.
	var w5 := mk_world(12, 8)
	var s5 := mk_stack(w5, 0, 2, 2, 13)
	logs.append(PlinkoOutcomes.apply(w5, s5, PlinkoOutcomes.Slot.FORGE))
	var rank1_count5 := 0
	for u5 in range(w5.units.n):
		if w5.units.stack[u5] == s5 and w5.units.rank[u5] == 1:
			rank1_count5 += 1
	t.check(rank1_count5 == 11, "case5 FORGE rank-1 count == 11 (10 promoted + captain)")

	# Case 6: DRILL — repeated applies, capped at 3.
	var w6 := mk_world(12, 8)
	var s6 := mk_stack(w6, 0, 2, 2, 5)
	logs.append(PlinkoOutcomes.apply(w6, s6, PlinkoOutcomes.Slot.DRILL))
	var drill_ok1 := true
	for u6a in range(w6.units.n):
		if w6.units.stack[u6a] == s6 and w6.units.drill[u6a] != 1:
			drill_ok1 = false
	t.check(drill_ok1, "case6 DRILL all units drill == 1 after first apply")

	logs.append(PlinkoOutcomes.apply(w6, s6, PlinkoOutcomes.Slot.DRILL))
	var drill_ok2 := true
	for u6b in range(w6.units.n):
		if w6.units.stack[u6b] == s6 and w6.units.drill[u6b] != 2:
			drill_ok2 = false
	t.check(drill_ok2, "case6 DRILL all units drill == 2 after second apply")

	logs.append(PlinkoOutcomes.apply(w6, s6, PlinkoOutcomes.Slot.DRILL))
	logs.append(PlinkoOutcomes.apply(w6, s6, PlinkoOutcomes.Slot.DRILL))
	var drill_ok3 := true
	for u6c in range(w6.units.n):
		if w6.units.stack[u6c] == s6 and w6.units.drill[u6c] != 3:
			drill_ok3 = false
	t.check(drill_ok3, "case6 DRILL all units drill == 3 after four applies (cap)")

	# Case 7: HERO_TRIAL.
	var w7 := mk_world(12, 8)
	var s7 := mk_stack(w7, 0, 2, 2, 5)
	var cap7 := w7.stacks.captain_unit[s7]
	logs.append(PlinkoOutcomes.apply(w7, s7, PlinkoOutcomes.Slot.HERO_TRIAL))
	t.check(w7.units.xp[cap7] == 50, "case7 HERO_TRIAL captain xp == 50")
	t.check(w7.units.rank[cap7] == 2, "case7 HERO_TRIAL captain rank == 2")

	# Case 8a: HEIR — dead captain, most-kills unit becomes captain.
	var w8a := mk_world(12, 8)
	var s8a := mk_stack(w8a, 0, 2, 2, 5)
	var cap8a := w8a.stacks.captain_unit[s8a]
	w8a.units.kill(cap8a)
	w8a.stacks.captain_unit[s8a] = -1
	var unit_a := -1
	var unit_b := -1
	for u8a in range(w8a.units.n):
		if w8a.units.stack[u8a] == s8a and w8a.units.alive[u8a] == 1:
			if unit_a == -1:
				unit_a = u8a
			elif unit_b == -1:
				unit_b = u8a
	w8a.units.kills[unit_a] = 7
	w8a.units.kills[unit_b] = 3
	logs.append(PlinkoOutcomes.apply(w8a, s8a, PlinkoOutcomes.Slot.HEIR))
	t.check(w8a.stacks.captain_unit[s8a] == unit_a, "case8a HEIR captain_unit == A (most kills)")
	t.check(w8a.units.is_captain[unit_a] == 1, "case8a HEIR is_captain[A] == 1")
	t.check(w8a.units.names.has(unit_a), "case8a HEIR names.has(A)")

	# Case 8b: HEIR — living captain, no change.
	var w8b := mk_world(12, 8)
	var s8b := mk_stack(w8b, 0, 2, 2, 5)
	var cap8b := w8b.stacks.captain_unit[s8b]
	logs.append(PlinkoOutcomes.apply(w8b, s8b, PlinkoOutcomes.Slot.HEIR))
	t.check(w8b.stacks.captain_unit[s8b] == cap8b, "case8b HEIR living captain unchanged")

	# Case 9: CURSE — 20 units + captain, three lowest-xp non-captain units die.
	var w9 := mk_world(12, 8)
	var s9 := mk_stack(w9, 0, 2, 2, 21)
	var cap9 := w9.stacks.captain_unit[s9]
	var non_captain_ids9: Array = []
	for u9 in range(w9.units.n):
		if w9.units.stack[u9] == s9 and u9 != cap9:
			non_captain_ids9.append(u9)
	for i9 in range(non_captain_ids9.size()):
		w9.units.xp[non_captain_ids9[i9]] = i9
	logs.append(PlinkoOutcomes.apply(w9, s9, PlinkoOutcomes.Slot.CURSE))
	t.check(w9.stacks.count[s9] == 18, "case9 CURSE count == 18")
	t.check(w9.units.alive[cap9] == 1, "case9 CURSE captain alive")
	var lowest_three_dead9 := true
	for i9b in range(3):
		if w9.units.alive[non_captain_ids9[i9b]] != 0:
			lowest_three_dead9 = false
	t.check(lowest_three_dead9, "case9 CURSE three lowest-xp units dead")
	var rest_alive9 := true
	for i9c in range(3, non_captain_ids9.size()):
		if w9.units.alive[non_captain_ids9[i9c]] != 1:
			rest_alive9 = false
	t.check(rest_alive9, "case9 CURSE remaining non-captain units alive")

	# Case 10: every apply returns a non-empty String.
	var logs_ok := true
	for log_line in logs:
		if String(log_line).length() == 0:
			logs_ok = false
	t.check(logs_ok, "case10 every apply returns a non-empty String")

	t.finish()
	quit()
