extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")


# Builds a stack of `count` units (count-1 regular + 1 captain) at `tile`,
# recounts, and returns the stack id.
func mk_stack(w: World, faction: int, tile: Vector2i, count: int) -> int:
	var c := w.map.center_of(tile.x, tile.y)
	var sid := w.stacks.add(faction, c.x, c.y, "S%d" % w.stacks.n)
	for _u in range(count - 1):
		w.units.add(faction, 0, 1, false, sid)
	var cap := w.units.add(faction, 1, 1, true, sid)
	w.stacks.captain_unit[sid] = cap
	w.stacks.recount(w.units)
	return sid


# Case 4/5/6/7/8 share a "collision" world: s0 (faction 0) and s1 (faction 1)
# overlapping on tile (5,4), offset 10 world units so distance < 2*STACK_RADIUS.
func mk_collision_world(cols: int, rows: int, count_a: int, count_b: int) -> Dictionary:
	var w := World.new()
	w.setup_blank(cols, rows, 7)
	var c := w.map.center_of(5, 4)
	var s0 := mk_stack(w, 0, Vector2i(5, 4), count_a)
	var s1 := mk_stack(w, 1, Vector2i(5, 4), count_b)
	w.stacks.x[s0] = c.x
	w.stacks.y[s0] = c.y
	w.stacks.prev_x[s0] = c.x - 64.0
	w.stacks.x[s1] = c.x + 10.0
	w.stacks.y[s1] = c.y
	w.stacks.prev_x[s1] = c.x + 64.0
	return {"w": w, "s0": s0, "s1": s1}


func _init() -> void:
	var t := TestKit.new()

	# Case 1: Goal -> path.
	var w1 := World.new()
	w1.setup_blank(12, 8, 7)
	w1.towns.append(Vector2(9, 4))
	w1.town_owner.append(-1)
	w1.map.kind[w1.map.idx(9, 4)] = WorldMap.Kind.TOWN
	w1.pathing.refresh(w1.map)
	var s0_1 := mk_stack(w1, 0, Vector2i(2, 4), 50)

	t.check(WorldSim.set_goal(w1, s0_1, Stacks.Goal.EXPAND) == true, "case1 set_goal EXPAND true")
	t.check(w1.stacks.state[s0_1] == Stacks.State.MOVING, "case1 state MOVING")
	t.check(w1.stacks.goal_tx[s0_1] == 9, "case1 goal_tx == 9")
	t.check(w1.stacks.path[s0_1].size() == 7, "case1 path size == 7")

	# Case 2: Movement.
	for _i in range(60):
		WorldSim.step(w1, Tuning.DT)
	var start_c := w1.map.center_of(2, 4)
	t.check(w1.stacks.x[s0_1] > start_c.x + 40.0, "case2 x[0] moved > 40 east")
	t.check(w1.stacks.prev_x[s0_1] < w1.stacks.x[s0_1], "case2 prev_x < x")

	var ticks2 := 0
	while w1.stacks.state[s0_1] != Stacks.State.IDLE and ticks2 < 1200:
		WorldSim.step(w1, Tuning.DT)
		ticks2 += 1
	t.check(w1.stacks.state[s0_1] == Stacks.State.IDLE, "case2 reaches IDLE")
	t.check(w1.stack_tile(s0_1) == Vector2i(9, 4), "case2 tile == (9,4)")

	# Case 3: Retreat speed.
	var w3 := World.new()
	w3.setup_blank(12, 8, 7)
	var sa := mk_stack(w3, 0, Vector2i(1, 1), 50)
	var sb := mk_stack(w3, 1, Vector2i(1, 6), 50)
	w3.stacks.state[sa] = Stacks.State.RETREATING
	w3.stacks.path[sa] = w3.pathing.find(Vector2i(1, 1), Vector2i(4, 1))
	w3.stacks.path_i[sa] = 0
	w3.stacks.state[sb] = Stacks.State.MOVING
	w3.stacks.path[sb] = w3.pathing.find(Vector2i(1, 6), Vector2i(4, 6))
	w3.stacks.path_i[sb] = 0

	for _i in range(60):
		WorldSim.move_stacks(w3, Tuning.DT)

	var dist_a := Vector2(w3.stacks.x[sa], w3.stacks.y[sa]).distance_to(w3.map.center_of(1, 1))
	var dist_b := Vector2(w3.stacks.x[sb], w3.stacks.y[sb]).distance_to(w3.map.center_of(1, 6))
	t.check(dist_a > dist_b, "case3 retreating stack outpaces moving stack")

	# Case 4: Collision starts a battle.
	var setup4 := mk_collision_world(12, 8, 40, 5)
	var w4: World = setup4["w"]
	var s0_4: int = setup4["s0"]
	var s1_4: int = setup4["s1"]
	WorldSim.check_collisions(w4)
	t.check(w4.battles.size() == 1, "case4 one battle started")
	t.check(w4.stacks.state[s0_4] == Stacks.State.BATTLE, "case4 s0 BATTLE")
	t.check(w4.stacks.state[s1_4] == Stacks.State.BATTLE, "case4 s1 BATTLE")

	# Case 5: no battle when immune / same faction / already in battle.
	var setup5a := mk_collision_world(12, 8, 40, 5)
	var w5a: World = setup5a["w"]
	w5a.stacks.immunity[setup5a["s1"]] = Tuning.RETREAT_IMMUNITY
	WorldSim.check_collisions(w5a)
	t.check(w5a.battles.size() == 0, "case5a immune stack starts no battle")

	var setup5b := mk_collision_world(12, 8, 40, 5)
	var w5b: World = setup5b["w"]
	w5b.stacks.faction[setup5b["s1"]] = w5b.stacks.faction[setup5b["s0"]]
	WorldSim.check_collisions(w5b)
	t.check(w5b.battles.size() == 0, "case5b same-faction stacks start no battle")

	var setup5c := mk_collision_world(12, 8, 40, 5)
	var w5c: World = setup5c["w"]
	w5c.stacks.state[setup5c["s0"]] = Stacks.State.BATTLE
	WorldSim.check_collisions(w5c)
	t.check(w5c.battles.size() == 0, "case5c already-battling stack starts no battle")

	# Case 6: Reinforcement.
	var setup6 := mk_collision_world(12, 8, 40, 5)
	var w6: World = setup6["w"]
	var s0_6: int = setup6["s0"]
	WorldSim.check_collisions(w6)
	t.check(w6.battles.size() == 1, "case6 setup battle started")
	var live6: BattleInstance = w6.battles[0]

	var s2_6 := mk_stack(w6, 0, Vector2i(2, 4), 30)
	WorldSim.reinforce(w6)
	t.check(w6.stacks.state[s2_6] == Stacks.State.MOVING, "case6 s2 MOVING after reinforce")
	t.check(w6.stacks.goal_tx[s2_6] == 5 and w6.stacks.goal_ty[s2_6] == 4, "case6 s2 goal (5,4)")

	var n_before6 := live6.state.n
	var ticks6 := 0
	while w6.stack_tile(s2_6) != Vector2i(5, 4) and ticks6 < 1200:
		WorldSim.step(w6, Tuning.DT)
		ticks6 += 1
	t.check(w6.stacks.state[s2_6] == Stacks.State.BATTLE, "case6 s2 joined battle")
	t.check(live6.stack_ids.has(s2_6), "case6 battle.stack_ids has s2")
	t.check(live6.state.n == n_before6 + w6.stacks.count[s2_6], "case6 battle.state.n grew by s2 count")

	# Case 7: out of range stays.
	var setup7 := mk_collision_world(20, 10, 40, 5)
	var w7: World = setup7["w"]
	WorldSim.check_collisions(w7)
	t.check(w7.battles.size() == 1, "case7 setup battle started")
	var s3_7 := mk_stack(w7, 0, Vector2i(13, 4), 20)
	WorldSim.reinforce(w7)
	t.check(w7.stacks.state[s3_7] == Stacks.State.IDLE, "case7 s3 stays IDLE (out of range)")

	# Case 8: battle runs and finishes.
	var setup8 := mk_collision_world(12, 8, 40, 5)
	var w8: World = setup8["w"]
	var s0_8: int = setup8["s0"]
	var s1_8: int = setup8["s1"]
	WorldSim.check_collisions(w8)
	t.check(w8.battles.size() == 1, "case8 battle started")

	var initial_alive8 := 0
	for u in range(w8.units.n):
		if w8.units.alive[u] == 1:
			initial_alive8 += 1

	var ticks8 := 0
	while w8.battles.size() > 0 and ticks8 < 7300:
		WorldSim.step(w8, Tuning.DT)
		ticks8 += 1
	t.check(w8.battles.size() == 0, "case8 battle finished within 7300 ticks")
	t.check(w8.stacks.state[s0_8] == Stacks.State.IDLE or w8.stacks.state[s0_8] == Stacks.State.RETREATING, "case8 s0 IDLE or RETREATING")
	t.check(w8.scars.size() == 1, "case8 scars recorded")

	var final_alive8 := 0
	for u2 in range(w8.units.n):
		if w8.units.alive[u2] == 1:
			final_alive8 += 1
	t.check(final_alive8 < initial_alive8, "case8 units died")

	# Case 9: retire.
	t.check(w8.stacks.count[s1_8] != 0 or w8.stacks.alive[s1_8] == 0, "case9 count==0 implies alive==0")

	# Case 10: determinism.
	var wa := World.create(5)
	var wb := World.create(5)
	for _i in range(300):
		WorldSim.step(wa, Tuning.DT)
	for _i in range(300):
		WorldSim.step(wb, Tuning.DT)
	t.check(wa.stacks.x == wb.stacks.x, "case10 stacks.x equal")
	t.check(wa.next_battle_id == wb.next_battle_id, "case10 next_battle_id equal")

	# Case 11: a battle finishing ahead of another in w.battles must not drop
	# the later one (it used to be skipped and lost, its stacks stuck in BATTLE).
	var w11 := World.new()
	w11.setup_blank(20, 10, 7)
	var battles11: Array = []
	for tx in [3, 12]:
		var c11 := w11.map.center_of(tx, 4)
		var a11 := mk_stack(w11, 0, Vector2i(tx, 4), 20)
		var b11 := mk_stack(w11, 1, Vector2i(tx, 4), 20)
		w11.stacks.prev_x[a11] = c11.x - 64.0
		w11.stacks.prev_y[a11] = c11.y
		w11.stacks.prev_x[b11] = c11.x + 64.0
		w11.stacks.prev_y[b11] = c11.y
		battles11.append(BattleBridge.start(w11, a11, b11))
	var first11: BattleInstance = battles11[0]
	var second11: BattleInstance = battles11[1]
	t.check(w11.battles.size() == 2 and w11.battles[0] == first11, "case11 setup two battles, first listed first")
	var side1_11 := -1
	for e11 in range(first11.faction_map.size()):
		if first11.faction_map[e11] == 1:
			side1_11 = e11
	for m11 in range(first11.state.n):
		if first11.state.faction_id[m11] == side1_11:
			first11.state.state[m11] = BattleState.State.DEAD
	WorldSim.step_battles(w11)
	t.check(not w11.battles.has(first11), "case11 finished battle removed")
	t.check(w11.battles.has(second11), "case11 later battle still live")
	var stuck11 := false
	for sid11 in first11.stack_ids:
		if w11.stacks.alive[sid11] == 1 and w11.stacks.state[sid11] == Stacks.State.BATTLE:
			stuck11 = true
	t.check(not stuck11, "case11 finished battle's stacks left BATTLE")
	var live11 := true
	for sid11b in second11.stack_ids:
		if w11.stacks.state[sid11b] != Stacks.State.BATTLE:
			live11 = false
	t.check(live11, "case11 later battle's stacks still BATTLE")
	t.check(second11.state.tick == 1, "case11 later battle stepped this tick")

	# Case 12: town recruitment with a full stack table writes nothing through -1.
	var w12 := World.new()
	w12.setup_blank(12, 8, 7)
	var town12 := w12.add_town(Vector2i(5, 4), 0)
	w12.sync_town_arrays()
	w12.town_pop[town12] = 50.0
	w12.town_recruit[town12] = 5.0
	while w12.stacks.n < w12.stacks.cap:
		w12.stacks.add(1, 0.0, 0.0, "Filler")
	var last12: int = w12.stacks.cap - 1
	var count_last12: int = w12.stacks.count[last12]
	var goal_last12: int = w12.stacks.goal[last12]
	var units_before12 := w12.units.n
	TownSim.step(w12, Tuning.DT)
	t.check(w12.units.n == units_before12, "case12 no unit added with full stack table")
	t.check(w12.stacks.count[last12] == count_last12 and w12.stacks.goal[last12] == goal_last12, "case12 last stack untouched (no -1 writes)")
	t.check(t.approx(w12.town_pop[town12], 50.0, 0.01), "case12 town pop not consumed")

	t.finish()
	quit()
