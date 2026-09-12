extends SceneTree
## Tests for Lineage.update_trait / note_settle / note_raze /
## on_battle_finished. See .warboss-horde/slices/m5-lineage.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Blank 12x8 world, seed 4; `n_units` rank-0 sword units + one rank-1
## captain via Lineage.make_captain(w, u, "Toby").
func mk_stack(w: World, f: int, tx: int, ty: int, n_units: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	for _i in range(n_units):
		w.units.add(f, 0, 1, false, id)
	var cap_id := w.units.add(f, 1, 1, true, id)
	Lineage.make_captain(w, cap_id, "Toby")
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. update_trait: threshold crossings, tie stays, later counter wins.
	var w1 := World.new()
	w1.setup_blank(12, 8, 4)
	var s1 := mk_stack(w1, 0, 5, 4, 0)
	var cap1 := w1.stacks.captain_unit[s1]

	w1.units.c_fights[cap1] = 3
	Lineage.update_trait(w1, cap1)
	t.check(w1.units.ctrait[cap1] == Lineage.Trait.CHARGER, "case1 c_fights=3 -> CHARGER")

	w1.units.c_razes[cap1] = 4
	Lineage.update_trait(w1, cap1)
	t.check(w1.units.ctrait[cap1] == Lineage.Trait.TYRANT, "case1 c_razes=4 -> TYRANT")

	w1.units.c_fights[cap1] = 4
	Lineage.update_trait(w1, cap1)
	t.check(w1.units.ctrait[cap1] == Lineage.Trait.TYRANT, "case1 c_fights=4 tie with razes -> stays TYRANT")

	w1.units.c_settles[cap1] = 5
	Lineage.update_trait(w1, cap1)
	t.check(w1.units.ctrait[cap1] == Lineage.Trait.BUILDER, "case1 c_settles=5 -> BUILDER")

	# 2. Succession: captain C dies, heir B (most kills) takes over.
	var w2 := World.new()
	w2.setup_blank(12, 8, 4)
	var s0 := mk_stack(w2, 0, 5, 4, 0)
	var cap_c := w2.stacks.captain_unit[s0]
	w2.units.rank[cap_c] = 2
	w2.units.xp[cap_c] = 80
	w2.units.ctrait[cap_c] = Lineage.Trait.CAUTIOUS
	var unit_a := w2.units.add(0, 0, 1, false, s0)
	var unit_b := w2.units.add(0, 0, 1, false, s0)
	w2.units.kills[unit_a] = 5
	w2.units.kills[unit_b] = 9
	w2.stacks.recount(w2.units)

	var inst2 := BattleInstance.new(0, Vector2i(1, 1))
	inst2.stack_ids = PackedInt32Array([s0])
	inst2.captain_before = PackedInt32Array([cap_c])
	var result2 := {"winner": 1}
	w2.units.kill(cap_c)
	w2.stacks.captain_unit[s0] = cap_c
	Lineage.on_battle_finished(w2, inst2, result2)

	t.check(w2.stacks.captain_unit[s0] == unit_b, "case2 captain_unit[s0] == B")
	t.check(w2.units.is_captain[unit_b] == 1, "case2 is_captain[B] == 1")
	t.check(w2.units.names[unit_b] == "Toby II", "case2 names[B] == Toby II")
	var dyn2: Array = w2.units.dynasty[unit_b]
	t.check(dyn2[0] == "Toby" and int(dyn2[1]) == 2, "case2 dynasty[B] == [Toby, 2]")
	t.check(w2.units.rank[unit_b] == 1, "case2 rank[B] == 1")
	t.check(w2.units.xp[unit_b] == 40, "case2 xp[B] == 40")
	t.check(w2.units.ctrait[unit_b] == Lineage.Trait.CAUTIOUS, "case2 ctrait[B] == CAUTIOUS")
	var last_line2 := String(w2.events_log[w2.events_log.size() - 1])
	t.check(last_line2.find("Toby II") != -1, "case2 events_log last line contains Toby II")

	# 3. Counters: winner stack with living captain -> c_fights += 1;
	# stack in state RETREATING -> c_retreats += 1.
	var w3 := World.new()
	w3.setup_blank(12, 8, 4)
	var s3a := mk_stack(w3, 0, 5, 4, 0)
	var cap3a := w3.stacks.captain_unit[s3a]
	var s3b := mk_stack(w3, 0, 6, 4, 0)
	var cap3b := w3.stacks.captain_unit[s3b]
	w3.stacks.state[s3b] = Stacks.State.RETREATING

	var inst3 := BattleInstance.new(0, Vector2i(1, 1))
	inst3.stack_ids = PackedInt32Array([s3a, s3b])
	inst3.captain_before = PackedInt32Array([cap3a, cap3b])
	Lineage.on_battle_finished(w3, inst3, {"winner": 0})

	t.check(w3.units.c_fights[cap3a] == 1, "case3 winner stack living captain: c_fights == 1")
	t.check(w3.units.c_retreats[cap3b] == 1, "case3 retreating stack: c_retreats == 1")

	# 4. No heir: captain dead and no other alive units -> captain_unit == -1.
	var w4 := World.new()
	w4.setup_blank(12, 8, 4)
	var s4 := mk_stack(w4, 0, 5, 4, 0)
	var cap4 := w4.stacks.captain_unit[s4]
	w4.units.kill(cap4)

	var inst4 := BattleInstance.new(0, Vector2i(1, 1))
	inst4.stack_ids = PackedInt32Array([s4])
	inst4.captain_before = PackedInt32Array([cap4])
	Lineage.on_battle_finished(w4, inst4, {"winner": -1})

	t.check(w4.stacks.captain_unit[s4] == -1, "case4 no heir: captain_unit[s4] == -1")

	# 5. note_settle x3 -> BUILDER; note_raze x3 (fresh captain) -> TYRANT.
	var w5 := World.new()
	w5.setup_blank(12, 8, 4)
	var s5a := mk_stack(w5, 0, 5, 4, 0)
	var cap5a := w5.stacks.captain_unit[s5a]
	for _i in range(3):
		Lineage.note_settle(w5, cap5a)
	t.check(w5.units.ctrait[cap5a] == Lineage.Trait.BUILDER, "case5 note_settle x3 -> BUILDER")

	var s5b := mk_stack(w5, 0, 6, 4, 0)
	var cap5b := w5.stacks.captain_unit[s5b]
	for _j in range(3):
		Lineage.note_raze(w5, cap5b)
	t.check(w5.units.ctrait[cap5b] == Lineage.Trait.TYRANT, "case5 note_raze x3 -> TYRANT")

	# 6a. Integration: BattleBridge.start s0(20+cap) vs s1(2+cap); kill s1's
	# captain and every other s1 marble -> no heir; s0's captain fights.
	var w6a := World.new()
	w6a.setup_blank(12, 8, 4)
	var s0_6a := mk_stack(w6a, 0, 5, 4, 20)
	var s1_6a := mk_stack(w6a, 1, 5, 4, 2)
	var cap0_6a := w6a.stacks.captain_unit[s0_6a]
	var inst6a := BattleBridge.start(w6a, s0_6a, s1_6a)

	for i6a in range(inst6a.state.n):
		var uid6a: int = inst6a.unit_of[i6a]
		if w6a.units.stack[uid6a] == s1_6a:
			inst6a.state.state[i6a] = BattleState.State.DEAD

	BattleBridge.finish(inst6a, w6a)
	t.check(w6a.stacks.captain_unit[s1_6a] == -1, "case6a no heir: captain_unit[s1] == -1")
	t.check(w6a.units.c_fights[cap0_6a] == 1, "case6a s0 captain c_fights == 1")

	# 6b. s1(5+cap): only the captain marble dies, the rest retreat; kill
	# nothing on s0 -> winner 0; s1 gets a new captain named "... II".
	var w6b := World.new()
	w6b.setup_blank(12, 8, 4)
	var s0_6b := mk_stack(w6b, 0, 5, 4, 20)
	var s1_6b := mk_stack(w6b, 1, 5, 4, 5)
	var old_cap1_6b := w6b.stacks.captain_unit[s1_6b]
	var inst6b := BattleBridge.start(w6b, s0_6b, s1_6b)

	for i6b in range(inst6b.state.n):
		var uid6b: int = inst6b.unit_of[i6b]
		if w6b.units.stack[uid6b] == s1_6b:
			if w6b.units.is_captain[uid6b] == 1:
				inst6b.state.state[i6b] = BattleState.State.DEAD
			else:
				inst6b.state.state[i6b] = BattleState.State.RETREAT

	var result6b := BattleBridge.finish(inst6b, w6b)
	t.check(result6b["winner"] == 0, "case6b winner == 0")
	var new_cap1_6b: int = w6b.stacks.captain_unit[s1_6b]
	t.check(new_cap1_6b != -1 and new_cap1_6b != old_cap1_6b, "case6b captain_unit[s1] changed")
	t.check(String(w6b.units.names[new_cap1_6b]).ends_with(" II"), "case6b new captain name ends with ' II'")

	t.finish()
	quit()
