extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")


# Adds `count` units (rank 0, given weapon) to a new stack at `tile`; when
# `add_captain` the last unit is a rank-1 captain instead of a rank-0 regular.
func mk_stack(w: World, faction: int, tile: Vector2i, count: int, weapon: int = 1, add_captain: bool = true) -> int:
	var c := w.map.center_of(tile.x, tile.y)
	var sid := w.stacks.add(faction, c.x, c.y, "S%d" % w.stacks.n)
	var regulars := count
	if add_captain:
		regulars = count - 1
	for _u in range(regulars):
		w.units.add(faction, 0, weapon, false, sid)
	if add_captain:
		var cap := w.units.add(faction, 1, weapon, true, sid)
		w.stacks.captain_unit[sid] = cap
	w.stacks.recount(w.units)
	return sid


# Blank 12x8 world seed 12; faction 0 stack west of the shared tile, faction 1
# east of it (so BattleBridge.edge_for maps 0 -> local 0, 1 -> local 1);
# starts the battle via BattleBridge.start.
func mk_battle(count_a: int, count_b: int, add_captain_a: bool = true, add_captain_b: bool = true) -> Dictionary:
	var w := World.new()
	w.setup_blank(12, 8, 12)
	var tile := Vector2i(5, 4)
	var c := w.map.center_of(tile.x, tile.y)
	var s0 := mk_stack(w, 0, tile, count_a, 1, add_captain_a)
	var s1 := mk_stack(w, 1, tile, count_b, 1, add_captain_b)
	w.stacks.prev_x[s0] = c.x - 64.0
	w.stacks.prev_y[s0] = c.y
	w.stacks.prev_x[s1] = c.x + 64.0
	w.stacks.prev_y[s1] = c.y
	var inst := BattleBridge.start(w, s0, s1)
	return {"w": w, "inst": inst}


func _init() -> void:
	var t := TestKit.new()

	# Case 1: rates.
	var b1 := mk_battle(10, 10, false, false)
	var inst1: BattleInstance = b1["inst"]

	var hp_before0 := 0.0
	var hp_before1 := 0.0
	for i in range(inst1.state.n):
		if inst1.state.faction_id[i] == 0:
			hp_before0 += inst1.state.hp[i]
		else:
			hp_before1 += inst1.state.hp[i]

	BattleLod.step(inst1, 1.0)

	var hp_after0 := 0.0
	var hp_after1 := 0.0
	var hit_found1 := false
	for i in range(inst1.state.n):
		if inst1.state.faction_id[i] == 0:
			hp_after0 += inst1.state.hp[i]
		else:
			hp_after1 += inst1.state.hp[i]
	for ev in inst1.state.events:
		if ev[0] == BattleState.Event.HIT:
			hit_found1 = true

	t.check(t.approx(hp_before1 - hp_after1, 66.667, 0.5), "case1 side1 hp loss ~66.667")
	t.check(t.approx(hp_before0 - hp_after0, 66.667, 0.5), "case1 side0 hp loss ~66.667")
	t.check(hit_found1, "case1 HIT event present")
	t.check(inst1.state.tick == 1, "case1 tick == 1")
	t.check(t.approx(inst1.state.time, 1.0, 1e-4), "case1 time ~1.0")

	# Case 2: lethality & winner.
	var b2 := mk_battle(40, 5)
	var inst2: BattleInstance = b2["inst"]

	var steps2 := 0
	var winner2 := -1
	var kill_seen2 := false
	while winner2 == -1 and steps2 < 20000:
		BattleLod.step(inst2, Tuning.DT)
		for ev in inst2.state.events:
			if ev[0] == BattleState.Event.KILL:
				kill_seen2 = true
		winner2 = inst2.sim.winner(inst2.state)
		steps2 += 1

	t.check(winner2 == 0, "case2 winner == 0")
	t.check(inst2.state.faction_alive[1] == 0, "case2 faction_alive[1] == 0")
	t.check(kill_seen2, "case2 KILL event produced across the run")

	var some_side0_ok := false
	for i in range(inst2.state.n):
		if inst2.state.faction_id[i] == 0 and inst2.state.kills[i] > 0 and inst2.state.xp[i] >= Tuning.XP_PER_KILL:
			some_side0_ok = true
	t.check(some_side0_ok, "case2 some side0 marble kills>0 and xp>=XP_PER_KILL")

	# Case 3: duration parity vs full sim (second world, same seed/setup).
	var b3a := mk_battle(40, 5)
	var inst3a: BattleInstance = b3a["inst"]
	var steps3a := 0
	var win3a := -1
	while win3a == -1 and steps3a < 20000:
		BattleLod.step(inst3a, Tuning.DT)
		win3a = inst3a.sim.winner(inst3a.state)
		steps3a += 1
	var lod_duration := inst3a.state.time

	var b3b := mk_battle(40, 5)
	var inst3b: BattleInstance = b3b["inst"]
	var steps3b := 0
	var win3b := -1
	while win3b == -1 and steps3b < 20000:
		inst3b.sim.step(inst3b.state, Tuning.DT)
		win3b = inst3b.sim.winner(inst3b.state)
		steps3b += 1
	var full_duration := inst3b.state.time

	t.check(lod_duration >= 0.33 * full_duration and lod_duration <= 3.0 * full_duration, "case3 LOD duration within 0.33x-3x full-sim duration")

	# Case 4: retreat & flee.
	var b4 := mk_battle(5, 1, false, false)
	var inst4: BattleInstance = b4["inst"]

	var idx4 := -1
	for i in range(inst4.state.n):
		if inst4.state.faction_id[i] == 1:
			idx4 = i
	inst4.state.morale[idx4] = 0.1

	BattleLod.step(inst4, Tuning.DT)
	t.check(inst4.state.state[idx4] == BattleState.State.RETREAT, "case4 marble RETREAT after one step")

	var fled_found4 := false
	var steps4 := 0
	while inst4.state.state[idx4] != BattleState.State.DEAD and steps4 < 400:
		BattleLod.step(inst4, Tuning.DT)
		if inst4.state.state[idx4] == BattleState.State.DEAD:
			for ev in inst4.state.events:
				if ev[0] == BattleState.Event.FLED and ev[1] == idx4:
					fled_found4 = true
		steps4 += 1

	t.check(inst4.state.fled[idx4] == 1, "case4 fled == 1")
	t.check(inst4.state.state[idx4] == BattleState.State.DEAD, "case4 state == DEAD")
	t.check(fled_found4, "case4 FLED event occurred")

	# Case 5: captain death under LOD.
	var b5 := mk_battle(10, 5, false, true)
	var inst5: BattleInstance = b5["inst"]

	var captain_idx5 := -1
	for i in range(inst5.state.n):
		if inst5.state.faction_id[i] == 1 and inst5.state.is_captain[i] == 1:
			captain_idx5 = i
	inst5.state.hp[captain_idx5] = 0.5

	var side1_allies5: Array = []
	for i in range(inst5.state.n):
		if inst5.state.faction_id[i] == 1 and inst5.state.is_captain[i] == 0:
			side1_allies5.append(i)

	var morale_before5 := {}
	for m in side1_allies5:
		morale_before5[m] = inst5.state.morale[m]

	var captain_dead5 := false
	var captain_dead_event5 := false
	var steps5 := 0
	while not captain_dead5 and steps5 < 600:
		BattleLod.step(inst5, Tuning.DT)
		steps5 += 1
		if inst5.state.state[captain_idx5] == BattleState.State.DEAD:
			captain_dead5 = true
			for ev in inst5.state.events:
				if ev[0] == BattleState.Event.CAPTAIN_DEAD:
					captain_dead_event5 = true
		else:
			for m in side1_allies5:
				morale_before5[m] = inst5.state.morale[m]

	t.check(captain_dead5, "case5 captain dies within 600 steps")
	t.check(inst5.state.faction_captain[1] == -1, "case5 faction_captain[1] == -1")
	t.check(captain_dead_event5, "case5 CAPTAIN_DEAD event")

	var morale_dropped5 := false
	for m in side1_allies5:
		if inst5.state.state[m] != BattleState.State.DEAD and morale_before5[m] - inst5.state.morale[m] >= 0.4 - 1e-4:
			morale_dropped5 = true
	t.check(morale_dropped5, "case5 ally morale dropped by >= 0.4")

	# Case 6: positions untouched.
	var b6 := mk_battle(10, 10)
	var inst6: BattleInstance = b6["inst"]
	var px_before6 := inst6.state.px.duplicate()
	var py_before6 := inst6.state.py.duplicate()
	for _i in range(100):
		BattleLod.step(inst6, Tuning.DT)
	t.check(inst6.state.px == px_before6, "case6 px unchanged after 100 LOD steps")
	t.check(inst6.state.py == py_before6, "case6 py unchanged after 100 LOD steps")

	# Case 7: WorldSim switch on w.watched_battle.
	var w7 := World.new()
	w7.setup_blank(12, 8, 12)
	var tile7 := Vector2i(5, 4)
	var c7 := w7.map.center_of(tile7.x, tile7.y)
	var s0_7 := mk_stack(w7, 0, tile7, 10)
	var s1_7 := mk_stack(w7, 1, tile7, 10)
	w7.stacks.x[s1_7] = c7.x + 10.0
	w7.stacks.prev_x[s0_7] = c7.x - 64.0
	w7.stacks.prev_x[s1_7] = c7.x + 64.0

	WorldSim.check_collisions(w7)
	t.check(w7.battles.size() == 1, "case7 battle started")
	var inst7: BattleInstance = w7.battles[0]
	var px_spawn7 := inst7.state.px.duplicate()

	w7.watched_battle = -1
	for _i in range(10):
		WorldSim.step(w7, Tuning.DT)
	t.check(inst7.state.px == px_spawn7, "case7 px unchanged while unwatched")

	w7.watched_battle = inst7.id
	for _i in range(10):
		WorldSim.step(w7, Tuning.DT)
	t.check(inst7.state.px != px_spawn7, "case7 px changed once watched")

	# Case 8: rank-up under LOD.
	var b8 := mk_battle(1, 1, false, false)
	var inst8: BattleInstance = b8["inst"]

	var idx8 := -1
	for i in range(inst8.state.n):
		if inst8.state.faction_id[i] == 0:
			idx8 = i
	inst8.state.xp[idx8] = 29

	var level_found8 := false
	var steps8 := 0
	while inst8.state.rank[idx8] < 1 and steps8 < 3000:
		BattleLod.step(inst8, Tuning.DT)
		steps8 += 1

	for ev in inst8.state.events:
		if ev[0] == BattleState.Event.LEVEL and ev[1] == idx8:
			level_found8 = true

	t.check(inst8.state.rank[idx8] == 1, "case8 rank == 1")
	t.check(t.approx(inst8.state.spin_cap[idx8], 150.0, 0.01), "case8 spin_cap ~150")
	t.check(level_found8, "case8 LEVEL event")

	t.finish()
	quit()
