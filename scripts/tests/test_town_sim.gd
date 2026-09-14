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


func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 5)
	return w


func _init() -> void:
	var t := TestKit.new()

	# Case 1: growth.
	var w1 := mk_world()
	var town1 := w1.add_town(Vector2i(3, 3), -1)
	var town1b := w1.add_town(Vector2i(8, 5), -1)
	w1.town_pop[town1b] = Tuning.TOWN_POP_MAX
	TownSim.step(w1, 1.0)
	t.check(t.approx(w1.town_pop[town1], 50.05, 1e-4), "case1 pop 50 -> ~50.05")
	t.check(t.approx(w1.town_pop[town1b], Tuning.TOWN_POP_MAX, 1e-4), "case1 pop at cap stays capped")

	# Case 2: recruit to an existing own stack.
	var w2 := mk_world()
	var town2 := w2.add_town(Vector2i(3, 3), 0)
	var s0_2 := mk_stack(w2, 0, Vector2i(4, 3), 10)
	for _i in range(20):
		TownSim.step(w2, 1.0)
	t.check(w2.stacks.count[s0_2] == 11, "case2 count[0] == 11")
	t.check(t.approx(w2.town_recruit[town2], 0.0, 1e-4), "case2 town_recruit ~0")
	t.check(t.approx(w2.town_pop[town2], 50.0, 1e-4), "case2 pop ~50.0")

	# Case 3: no own stack -> garrison created and recruited into.
	var w3 := mk_world()
	w3.add_town(Vector2i(3, 3), 0)
	for _i in range(20):
		TownSim.step(w3, 1.0)
	t.check(w3.stacks.n == 1, "case3 stacks.n == 1")
	t.check(w3.stacks.faction[0] == 0, "case3 faction[0] == 0")
	t.check(w3.stack_tile(0) == Vector2i(3, 3), "case3 stack_tile(0) == (3,3)")
	t.check(w3.stacks.goal[0] == Stacks.Goal.DEFEND, "case3 goal[0] == DEFEND")
	t.check(w3.stacks.count[0] == 1, "case3 count[0] == 1")

	# Case 4: own stack out of range -> garrison created instead.
	var w4 := mk_world()
	w4.add_town(Vector2i(0, 3), 0)
	var far4 := mk_stack(w4, 0, Vector2i(9, 3), 5)   # Chebyshev dist 9 > TOWN_RECRUIT_RANGE (8)
	for _i in range(20):
		TownSim.step(w4, 1.0)
	t.check(w4.stacks.n == 2, "case4 stacks.n == 2 (far stack + garrison)")
	var garrison4 := -1
	for si in range(w4.stacks.n):
		if si != far4:
			garrison4 = si
	t.check(garrison4 != -1 and w4.stack_tile(garrison4) == Vector2i(0, 3), "case4 garrison on town tile")
	t.check(garrison4 != -1 and w4.stacks.goal[garrison4] == Stacks.Goal.DEFEND, "case4 garrison goal DEFEND")
	t.check(w4.stacks.count[far4] == 5, "case4 far stack untouched")

	# Case 5: own stack adjacent but BATTLE -> garrison created instead.
	var w5 := mk_world()
	w5.add_town(Vector2i(3, 3), 0)
	var adj5 := mk_stack(w5, 0, Vector2i(4, 3), 5)
	w5.stacks.state[adj5] = Stacks.State.BATTLE
	for _i in range(20):
		TownSim.step(w5, 1.0)
	t.check(w5.stacks.n == 2, "case5 stacks.n == 2 (battling stack + garrison)")
	var garrison5 := -1
	for si in range(w5.stacks.n):
		if si != adj5:
			garrison5 = si
	t.check(garrison5 != -1 and w5.stack_tile(garrison5) == Vector2i(3, 3), "case5 garrison on town tile")
	t.check(garrison5 != -1 and w5.stacks.goal[garrison5] == Stacks.Goal.DEFEND, "case5 garrison goal DEFEND")

	# Case 6: RAIDED recovery.
	var w6 := mk_world()
	var town6 := w6.add_town(Vector2i(2, 2), -1)
	w6.town_state[town6] = 1
	w6.town_timer[town6] = 2.0
	for _i in range(2):
		TownSim.step(w6, 1.0)
	t.check(w6.town_state[town6] == 0, "case6 state RAIDED -> INTACT")
	t.check(w6.town_owner[town6] == -1, "case6 owner stays -1")

	# Case 7: RAZED recovery.
	var w7 := mk_world()
	var town7 := w7.add_town(Vector2i(6, 4), -1)
	w7.map.kind[w7.map.idx(6, 4)] = WorldMap.Kind.RUIN
	w7.town_state[town7] = 2
	w7.town_timer[town7] = 1.0
	var borders_before7 := w7.borders_version
	TownSim.step(w7, 1.0)
	t.check(w7.town_state[town7] == 0, "case7 state RAZED -> INTACT")
	t.check(t.approx(w7.town_pop[town7], 25.0, 1e-4), "case7 pop ~25")
	t.check(w7.map.kind[w7.map.idx(6, 4)] == WorldMap.Kind.TOWN, "case7 tile kind -> TOWN")
	t.check(w7.borders_version > borders_before7, "case7 borders_version increased")

	# Case 8: occupation capture (IDLE stack) vs. no capture (MOVING stack).
	var w8 := mk_world()
	var town8 := w8.add_town(Vector2i(5, 5), -1)
	var c8 := w8.map.center_of(5, 5)
	var s8 := w8.stacks.add(0, c8.x, c8.y, "S8")
	w8.stacks.state[s8] = Stacks.State.IDLE
	w8.stacks.idle_timer[s8] = 0.0
	var borders_before8 := w8.borders_version
	for _i in range(3):
		TownSim.step(w8, 1.0)
	t.check(w8.town_owner[town8] == 0, "case8 town_owner == 0 after capture")
	t.check(w8.borders_version > borders_before8, "case8 borders_version increased")

	var w8b := mk_world()
	var town8b := w8b.add_town(Vector2i(5, 5), -1)
	var c8b := w8b.map.center_of(5, 5)
	var s8b := w8b.stacks.add(0, c8b.x, c8b.y, "S8b")
	w8b.stacks.state[s8b] = Stacks.State.MOVING
	for _i in range(3):
		TownSim.step(w8b, 1.0)
	t.check(w8b.town_owner[town8b] == -1, "case8 MOVING stack does not capture")

	t.finish()
	quit()
