extends SceneTree
## Tests for the M9 hookup: Economy/Heroes/Settling wired into the world tick,
## RESTOCK/FOUND goals, slayers, PlinkoOutcomes raid gold. See
## .warboss-horde/slices/m9-hookup.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Blank 12x8 world, seed 21; 2 factions, both alive.
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 21)
	w.faction_count = 2
	w.faction_alive[0] = 1
	w.faction_alive[1] = 1
	w.faction_names = ["Alpha", "Beta"]
	return w


## n rank_ weapon_ units + (if captain) one rank-1 sword captain via
## Lineage.make_captain.
func mk_stack(w: World, f: int, tx: int, ty: int, n: int, rank: int = 0, weapon: int = 1, captain: bool = true) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S%d" % w.stacks.n)
	for _i in range(n):
		w.units.add(f, rank, weapon, false, id)
	if captain:
		var cap_id := w.units.add(f, 1, 1, true, id)
		Lineage.make_captain(w, cap_id, "Cap%d" % id)
		w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. accrue in tick: neutral town, no stacks, one world second.
	var w1 := mk_world()
	var t1 := w1.add_town(Vector2i(6, 6), -1)
	w1.town_pop[t1] = 100.0
	WorldSim.step_world(w1, 1.0)
	t.check(t.approx(w1.town_gold[t1], 0.2, 1e-3), "case1 town_gold ~= 0.2")

	# 2. set_goal RESTOCK: paths to the nearest affordable town; FOUND refuses.
	var w2 := mk_world()
	var s2 := mk_stack(w2, 0, 1, 1, 10, 0, 1, false)
	w2.stacks.gold[s2] = 100.0
	var town2 := w2.add_town(Vector2i(6, 1), -1)
	w2.town_pop[town2] = 50.0

	var ok2 := WorldSim.set_goal(w2, s2, Stacks.Goal.RESTOCK)
	t.check(ok2, "case2 set_goal RESTOCK -> true")
	t.check(w2.stacks.state[s2] == Stacks.State.MOVING, "case2 state MOVING")
	t.check(w2.stacks.goal[s2] == Stacks.Goal.RESTOCK, "case2 goal RESTOCK")
	t.check(w2.stacks.goal_tx[s2] == 6 and w2.stacks.goal_ty[s2] == 1, "case2 goal tile (6,1)")
	t.check(WorldSim.set_goal(w2, s2, Stacks.Goal.FOUND) == false, "case2 set_goal FOUND -> false")

	# 3. arrival restock: continue case 2, step until it stops moving.
	var steps3 := 0
	while steps3 < 2000 and w2.stacks.state[s2] == Stacks.State.MOVING:
		WorldSim.step_world(w2, Tuning.DT)
		steps3 += 1
	t.check(w2.stacks.state[s2] != Stacks.State.MOVING, "case3 reaches non-MOVING within 2000 steps")
	t.check(w2.stacks.count[s2] == 43, "case3 count == 43")
	t.check(t.approx(w2.stacks.gold[s2], 1.0), "case3 gold ~= 1.0")
	t.check(w2.stacks.goal[s2] == Stacks.Goal.IDLE_HEAL, "case3 goal IDLE_HEAL")
	t.check(int(w2.history.get("restocks", 0)) == 1, "case3 history restocks == 1")

	# 4. on-tile restock: stack already stands on the target town.
	var w4 := mk_world()
	var s4 := mk_stack(w4, 0, 6, 1, 10, 0, 1, false)
	w4.stacks.gold[s4] = 30.0
	var town4 := w4.add_town(Vector2i(6, 1), -1)
	w4.town_pop[town4] = 50.0

	var ok4 := WorldSim.set_goal(w4, s4, Stacks.Goal.RESTOCK)
	t.check(ok4, "case4 set_goal RESTOCK -> true")
	t.check(w4.stacks.state[s4] == Stacks.State.IDLE, "case4 state IDLE")
	t.check(w4.stacks.goal[s4] == Stacks.Goal.IDLE_HEAL, "case4 goal IDLE_HEAL")
	t.check(w4.stacks.count[s4] == 20, "case4 count == 20")

	# 5. FOUND arrival: a stack marched to (5,1) founds a town there.
	var w5 := mk_world()
	var s5 := mk_stack(w5, 0, 1, 1, 20)
	var c5: int = w5.stacks.captain_unit[s5]
	w5.stacks.gold[s5] = 50.0
	w5.stacks.goal[s5] = Stacks.Goal.FOUND
	w5.stacks.goal_tx[s5] = 5
	w5.stacks.goal_ty[s5] = 1
	w5.stacks.path[s5] = w5.pathing.find(Vector2i(1, 1), Vector2i(5, 1))
	w5.stacks.path_i[s5] = 0
	w5.stacks.state[s5] = Stacks.State.MOVING

	var steps5 := 0
	while steps5 < 2000 and w5.stacks.state[s5] == Stacks.State.MOVING:
		WorldSim.step_world(w5, Tuning.DT)
		steps5 += 1
	t.check(w5.towns.size() == 1, "case5 towns.size() == 1")
	t.check(w5.towns.size() > 0 and w5.towns[0] == Vector2(5, 1), "case5 towns[0] == (5,1)")
	t.check(w5.units.fate[c5] == Units.Fate.LORD, "case5 fate[c] == LORD")
	t.check(w5.town_lord.size() > 0 and w5.town_lord[0] == c5, "case5 town_lord[0] == c")

	# 6. pick skip: an IDLE stack with goal FOUND is left alone by the AI.
	var w6 := mk_world()
	var s6 := mk_stack(w6, 0, 5, 4, 20)
	w6.stacks.state[s6] = Stacks.State.IDLE
	w6.stacks.goal[s6] = Stacks.Goal.FOUND
	w6.stacks.goal_tx[s6] = 9
	w6.stacks.goal_ty[s6] = 6
	w6.stacks.ai_timer[s6] = 0.0
	w6.stacks.idle_timer[s6] = 0.0

	WorldSim.step_world(w6, Tuning.DT)

	t.check(w6.stacks.goal[s6] == Stacks.Goal.FOUND, "case6 goal remains FOUND")
	t.check(w6.stacks.state[s6] == Stacks.State.IDLE, "case6 state remains IDLE")

	# 7. battle finish: lopsided win -> loot gold, slayers, no legend renames.
	var w7 := mk_world()
	var a7 := mk_stack(w7, 0, 5, 4, 60, 2, 3, true)
	w7.stacks.gold[a7] = 0.0
	var b7 := mk_stack(w7, 1, 5, 4, 5, 0, 0, true)
	w7.stacks.gold[b7] = 40.0
	var b_cap7: int = w7.stacks.captain_unit[b7]

	var inst7 := BattleBridge.start(w7, a7, b7)
	if not w7.battles.has(inst7):
		w7.battles.append(inst7)

	var steps7 := 0
	while w7.battles.size() > 0 and steps7 < 30000:
		WorldSim.step_battles(w7)
		steps7 += 1
	t.check(w7.battles.size() == 0, "case7 battle finished within 30000 steps")

	var kills_sum7 := 0
	for u7 in range(w7.units.n):
		if w7.units.faction[u7] == 0:
			kills_sum7 += w7.units.kills[u7]
	t.check(t.approx(w7.stacks.gold[a7], 20.0 + 0.5 * kills_sum7, 0.05), "case7 A gold ~= 20 + 0.5*kills")
	t.check(t.approx(w7.stacks.gold[b7], 20.0, 0.05), "case7 B gold ~= 20.0")

	var slayers_hero_ok := true
	for su7 in inst7.slayers:
		if w7.units.alive[su7] == 1 and w7.units.hero[su7] != 1:
			slayers_hero_ok = false
	t.check(slayers_hero_ok, "case7 every alive slayer has hero == 1")

	var no_killer_of := true
	for nm7 in w7.units.names.values():
		if String(nm7).contains(", killer of"):
			no_killer_of = false
	t.check(no_killer_of, "case7 no unit name contains ', killer of'")

	if inst7.slayers.size() > 0:
		t.check(int(w7.history.get("promotions", 0)) >= 1, "case7 slayers present -> history promotions >= 1")

	if w7.units.alive[b_cap7] == 0:
		t.check(inst7.slayers.size() >= 1, "case7 B captain died -> slayers recorded")

	# 8. raid gold: PlinkoOutcomes.RAID transfers town gold before its writes.
	var w8 := mk_world()
	var s8 := mk_stack(w8, 0, 5, 4, 10)
	var t8 := w8.add_town(Vector2i(7, 4), 1)
	w8.town_gold[t8] = 30.0

	PlinkoOutcomes.apply(w8, s8, PlinkoOutcomes.Slot.RAID)

	t.check(t.approx(w8.stacks.gold[s8], 30.0), "case8 stack gold ~= 30.0")
	t.check(t.approx(w8.town_gold[t8], 0.0), "case8 town_gold ~= 0.0")

	# 9. meta aging: an ancient captain with a poor stack retires.
	var w9 := mk_world()
	var s9 := mk_stack(w9, 0, 5, 4, 10)
	var cap9: int = w9.stacks.captain_unit[s9]
	w9.units.career_start[cap9] = -2000.0
	w9.stacks.gold[s9] = 0.0

	WorldSim.step_world(w9, 1.0)
	WorldSim.step_world(w9, 1.0)

	t.check(int(w9.history.get("retirements", 0)) >= 1, "case9 history retirements >= 1")
	t.check(w9.units.fate[cap9] == Units.Fate.RETIRED, "case9 fate[old captain] == RETIRED")

	# 10. meta breakaway: an eligible hero eventually breaks away.
	var w10 := mk_world()
	var s10 := mk_stack(w10, 0, 5, 4, 60)
	var h10 := w10.units.add(0, 0, 1, false, s10)
	w10.units.hero[h10] = 1
	w10.units.career_start[h10] = -100.0
	w10.stacks.recount(w10.units)

	# Stop at the first breakaway: past HERO_LIFESPAN the new captain would retire.
	for _i in range(1000):
		WorldSim.step_world(w10, 1.0)
		if int(w10.history.get("breakaways", 0)) >= 1:
			break

	t.check(int(w10.history.get("breakaways", 0)) >= 1, "case10 history breakaways >= 1")
	var found_h10 := false
	for si10 in range(w10.stacks.n):
		if w10.stacks.captain_unit[si10] == h10:
			found_h10 = true
	t.check(found_h10, "case10 captain_unit of some stack == h")

	t.finish()
	quit()
