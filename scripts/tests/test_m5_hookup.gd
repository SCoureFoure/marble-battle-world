extends SceneTree
## Tests for the M5 hookup: Kingdoms/Lineage wired into WorldSim, PILGRIMAGE/
## AVENGE goals, allies, rebirth/mercenaries. See .warboss-horde/slices/m5-hookup.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


# Blank 12x8 world seed 8, faction_count = 3, faction_alive[0..2] = 1.
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 8)
	w.faction_count = 3
	for f in range(3):
		w.faction_alive[f] = 1
	w.faction_names = ["Alpha", "Beta", "Gamma"]
	return w


# Stack of n_units rank-0 sword units + one rank-1 sword captain (via
# Lineage.make_captain), as in test_lineage.gd.
func mk_stack(w: World, f: int, tx: int, ty: int, n_units: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S%d" % w.stacks.n)
	for _i in range(n_units):
		w.units.add(f, 0, 1, false, id)
	var cap_id := w.units.add(f, 1, 1, true, id)
	Lineage.make_captain(w, cap_id, "Cap%d" % id)
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. Goal weights in use: aggression 1.0 -> HUNT_WEAK (4.5) drawn more
	# often than EXPAND (1.5) over 200 pick_goal calls.
	var w1 := mk_world()
	w1.add_ktrait(0, 0, 0.5)  # aggression 0.5 -> 1.0
	var s0_1 := mk_stack(w1, 0, 5, 4, 10)
	mk_stack(w1, 1, 7, 4, 10)             # enemy stack
	w1.add_town(Vector2i(2, 2), -1)       # neutral town
	w1.add_town(Vector2i(9, 2), 1)        # enemy town
	w1.add_town(Vector2i(5, 2), 0)        # own town
	w1.map.kind[w1.map.idx(3, 5)] = WorldMap.Kind.RUIN

	var hunt_count := 0
	var expand_count := 0
	for _i in range(200):
		w1.stacks.ai_timer[s0_1] = 0.0
		w1.stacks.state[s0_1] = Stacks.State.IDLE
		WorldSim.pick_goal(w1, s0_1)
		if w1.stacks.goal[s0_1] == Stacks.Goal.HUNT_WEAK:
			hunt_count += 1
		elif w1.stacks.goal[s0_1] == Stacks.Goal.EXPAND:
			expand_count += 1
	t.check(hunt_count > expand_count, "case1 HUNT_WEAK count (%d) > EXPAND count (%d)" % [hunt_count, expand_count])

	# 2. PILGRIMAGE: set_goal targets the nearest RUIN; arrival -> pilgrim
	# kingdom-trait bump, then IDLE.
	var w2 := mk_world()
	var s0_2 := mk_stack(w2, 0, 2, 4, 10)
	w2.map.kind[w2.map.idx(8, 4)] = WorldMap.Kind.RUIN

	var ok2 := WorldSim.set_goal(w2, s0_2, Stacks.Goal.PILGRIMAGE)
	t.check(ok2, "case2 set_goal PILGRIMAGE succeeds")
	t.check(w2.stacks.state[s0_2] == Stacks.State.MOVING, "case2 state MOVING")
	t.check(w2.stacks.goal_tx[s0_2] == 8 and w2.stacks.goal_ty[s0_2] == 4, "case2 goal tile (8,4)")

	var steps2 := 0
	while steps2 < 2000 and w2.stacks.state[s0_2] != Stacks.State.IDLE:
		WorldSim.step(w2, Tuning.DT)
		steps2 += 1
	t.check(w2.stacks.state[s0_2] == Stacks.State.IDLE, "case2 reaches IDLE within 2000 steps")
	t.check(t.approx(w2.ktrait(0, 3), 0.55, 1e-3), "case2 ktrait(0,3) piety approx 0.55")

	# 3. AVENGE: targets the most-hated (lowest relation < 0) faction's
	# nearest stack; with no negative relation, falls back (false).
	var w3 := mk_world()
	var s0_3 := mk_stack(w3, 0, 4, 4, 5)
	mk_stack(w3, 1, 8, 4, 5)
	mk_stack(w3, 2, 4, 0, 5)
	w3.add_relation(0, 2, -0.5)
	var ok3 := WorldSim.set_goal(w3, s0_3, Stacks.Goal.AVENGE)
	t.check(ok3, "case3 set_goal AVENGE succeeds")
	t.check(w3.stacks.goal_tx[s0_3] == 4 and w3.stacks.goal_ty[s0_3] == 0, "case3 targets faction-2 stack's tile")

	var w3b := mk_world()
	var s0_3b := mk_stack(w3b, 0, 4, 4, 5)
	mk_stack(w3b, 1, 8, 4, 5)
	mk_stack(w3b, 2, 4, 0, 5)
	var ok3b := WorldSim.set_goal(w3b, s0_3b, Stacks.Goal.AVENGE)
	t.check(not ok3b, "case3 no negative relation -> false")

	# 4. Recruit weapon: TownSim recruits draw via Kingdoms.recruit_weapon.
	var w4 := mk_world()
	w4.add_ktrait(0, 0, 0.5)   # aggression 0.5 -> 1.0
	w4.add_ktrait(0, 4, -0.5)  # cohesion 0.5 -> 0.0
	var town4 := w4.add_town(Vector2i(3, 3), 0)
	w4.town_pop[town4] = 1000.0
	mk_stack(w4, 0, 4, 3, 5)
	var before_n4 := w4.units.n

	TownSim.step(w4, 200.0)  # RECRUIT_RATE 0.10/s * 200s = 20 recruits

	var added4 := w4.units.n - before_n4
	t.check(added4 == 20, "case4 20 units recruited")
	var dagger_axe4 := 0
	for u in range(before_n4, w4.units.n):
		if w4.units.weapon[u] == 0 or w4.units.weapon[u] == 3:
			dagger_axe4 += 1
	t.check(dagger_axe4 >= 8, "case4 at least 8 of 20 recruits are dagger or axe")

	# 5. Captain killers: a CAPTAIN_DEAD event during the live sim is recorded
	# on the bridge and feeds Kingdoms relations on finish.
	var w5 := mk_world()
	var s0_5 := mk_stack(w5, 0, 5, 4, 20)
	var s1_5 := mk_stack(w5, 1, 5, 4, 5)
	var inst5 := BattleBridge.start(w5, s0_5, s1_5)

	var cap_marble5 := -1
	for i in range(inst5.state.n):
		var u: int = inst5.unit_of[i]
		if w5.units.is_captain[u] == 1 and w5.units.faction[u] == 1:
			cap_marble5 = i
			break
	t.check(cap_marble5 != -1, "case5 s1 captain marble found")
	if cap_marble5 != -1:
		# Spawned near its own (faction-1) home edge, hp = 0.1 alone would just
		# trigger an instant ENGAGE -> RETREAT -> fled (Tuning.RETREAT_HP_FRAC)
		# before any of faction 0's 20 marbles could close the distance and
		# land a hit. Reposition it into faction 0's spawn area first so it's
		# already surrounded when the low hp forces it to flee.
		inst5.state.px[cap_marble5] = 220.0
		inst5.state.py[cap_marble5] = 450.0
		inst5.state.hp[cap_marble5] = 0.1

	var found_cd := false
	var steps5 := 0
	while steps5 < 3000 and not found_cd:
		WorldSim.step(w5, Tuning.DT)
		steps5 += 1
		if inst5.captain_killers.size() > 0:
			found_cd = true
	t.check(found_cd, "case5 CAPTAIN_DEAD recorded in captain_killers within 3000 ticks")
	if found_cd:
		var entry5: Array = inst5.captain_killers[0]
		t.check(entry5[0] == 1 and entry5[1] == 0, "case5 captain_killers[0] == [1, 0]")

	var steps5b := 0
	while w5.battles.size() > 0 and steps5b < 7300:
		WorldSim.step(w5, Tuning.DT)
		steps5b += 1
	t.check(w5.battles.size() == 0, "case5 battle finished")
	t.check(w5.relation(1, 0) <= -0.5, "case5 relation(1,0) <= -0.5")

	# 6. Allies: a stack of an allied faction joins the same local side
	# regardless of its approach edge; that side wins together.
	var w6 := mk_world()
	w6.add_relation(0, 2, 0.6)
	var tile6 := Vector2i(5, 4)
	var c6 := w6.map.center_of(tile6.x, tile6.y)

	var s0_6 := mk_stack(w6, 0, tile6.x, tile6.y, 20)
	w6.stacks.prev_x[s0_6] = c6.x - 200.0
	w6.stacks.prev_y[s0_6] = c6.y

	var s1_6 := mk_stack(w6, 1, tile6.x, tile6.y, 15)
	w6.stacks.prev_x[s1_6] = c6.x + 200.0
	w6.stacks.prev_y[s1_6] = c6.y

	var inst6 := BattleBridge.start(w6, s0_6, s1_6)

	var s2_6 := mk_stack(w6, 2, tile6.x, tile6.y, 10)
	w6.stacks.prev_x[s2_6] = c6.x
	w6.stacks.prev_y[s2_6] = c6.y + 200.0  # from below

	var joined6 := BattleBridge.join(inst6, w6, s2_6)
	t.check(joined6, "case6 s2 joins")

	var s2_local_ok := true
	for i in range(inst6.state.n):
		var u6: int = inst6.unit_of[i]
		if w6.units.stack[u6] == s2_6 and inst6.state.faction_id[i] != 0:
			s2_local_ok = false
	t.check(s2_local_ok, "case6 s2's marbles have local faction_id == 0")
	t.check(inst6.side_factions[0].has(2), "case6 side_factions[0] contains 2")
	t.check(inst6.faction_map[3] == -1, "case6 faction_map[3] == -1")

	for i in range(inst6.state.n):
		var u6b: int = inst6.unit_of[i]
		if w6.units.faction[u6b] == 1:
			inst6.state.state[i] = BattleState.State.DEAD

	var result6 := BattleBridge.finish(inst6, w6)
	t.check(result6["winner_side"] == 0, "case6 winner_side == 0")
	t.check(w6.stacks.state[s0_6] == Stacks.State.IDLE, "case6 s0 IDLE (winner)")
	t.check(w6.stacks.state[s2_6] == Stacks.State.IDLE, "case6 s2 IDLE (winner)")
	t.check(w6.stacks.state[s1_6] == Stacks.State.RETREATING, "case6 s1 RETREATING (loser)")

	# 7. Rebirth: faction 1's only stack is wiped except a rank-3 survivor L
	# (fled); no towns -> L founds a new faction at the nearest RUIN.
	var w7 := mk_world()
	w7.map.kind[w7.map.idx(10, 6)] = WorldMap.Kind.RUIN
	var s0_7 := mk_stack(w7, 0, 5, 4, 39)  # 39 + captain = 40
	var c7 := w7.map.center_of(5, 4)
	var s1_7 := w7.stacks.add(1, c7.x, c7.y, "S1_7")
	var l_unit7 := w7.units.add(1, 3, 1, false, s1_7)
	w7.units.add(1, 0, 1, false, s1_7)
	w7.units.add(1, 0, 1, false, s1_7)
	w7.stacks.recount(w7.units)

	var inst7 := BattleBridge.start(w7, s0_7, s1_7)
	var l_marble7 := -1
	for i in range(inst7.state.n):
		var u7: int = inst7.unit_of[i]
		if u7 == l_unit7:
			l_marble7 = i
		elif w7.units.stack[u7] == s1_7:
			inst7.state.state[i] = BattleState.State.DEAD
	inst7.state.fled[l_marble7] = 1
	inst7.state.state[l_marble7] = BattleState.State.DEAD

	BattleBridge.finish(inst7, w7)
	t.check(w7.faction_count == 4, "case7 faction_count == 4")
	t.check(w7.units.faction[l_unit7] == 3, "case7 L faction == 3")

	var new_stack7 := -1
	for i in range(w7.stacks.n):
		if w7.stacks.alive[i] == 1 and w7.stacks.faction[i] == 3:
			new_stack7 = i
	t.check(new_stack7 != -1, "case7 a new stack of faction 3 exists")
	if new_stack7 != -1:
		t.check(w7.stack_tile(new_stack7) == Vector2i(10, 6), "case7 new stack at the nearest RUIN tile")
	t.check(String(w7.events_log[w7.events_log.size() - 1]).contains("founds"), "case7 events_log last line contains 'founds'")

	# 8. Mercenaries: same setup but L is rank 1 (not a legend) -> joins the
	# winner stack instead of founding a kingdom.
	var w8 := mk_world()
	var s0_8 := mk_stack(w8, 0, 5, 4, 39)
	var c8 := w8.map.center_of(5, 4)
	var s1_8 := w8.stacks.add(1, c8.x, c8.y, "S1_8")
	var l_unit8 := w8.units.add(1, 1, 1, false, s1_8)
	w8.units.add(1, 0, 1, false, s1_8)
	w8.units.add(1, 0, 1, false, s1_8)
	w8.stacks.recount(w8.units)

	var inst8 := BattleBridge.start(w8, s0_8, s1_8)
	var l_marble8 := -1
	for i in range(inst8.state.n):
		var u8: int = inst8.unit_of[i]
		if u8 == l_unit8:
			l_marble8 = i
		elif w8.units.stack[u8] == s1_8:
			inst8.state.state[i] = BattleState.State.DEAD
	inst8.state.fled[l_marble8] = 1
	inst8.state.state[l_marble8] = BattleState.State.DEAD

	BattleBridge.finish(inst8, w8)
	t.check(w8.units.faction[l_unit8] == 0, "case8 L faction == 0")
	t.check(w8.units.stack[l_unit8] == s0_8, "case8 L stack == s0")
	var found_merc := false
	for line in w8.events_log:
		if String(line).contains("mercenar"):
			found_merc = true
	t.check(found_merc, "case8 events_log contains a mercenary line")

	# 9. Split/death via step: an overgrown, low-cohesion faction splits; a
	# faction with no towns/stacks dies within the first second.
	var w9 := mk_world()
	w9.add_ktrait(2, 4, -0.3)  # cohesion 0.5 -> 0.2
	mk_stack(w9, 2, 2, 2, 500)
	mk_stack(w9, 2, 9, 2, 199)
	var fc9_before := w9.faction_count

	for _i in range(3660):  # 61 s at Tuning.DT
		WorldSim.step(w9, Tuning.DT)

	t.check(w9.faction_count > fc9_before, "case9 faction_count increased (split)")
	t.check(w9.faction_alive[1] == 0, "case9 faction_alive[1] == 0 (no towns/stacks)")

	t.finish()
	quit()
