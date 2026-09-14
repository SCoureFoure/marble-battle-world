extends SceneTree
## Tests for Settling.found_site / check_aging / found_town / retire and the
## M9 Lineage edits (make_captain career_start, succeed verb). See
## .warboss-horde/slices/m9-settling.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## World.new(); setup_blank(12, 8, 9); 2 factions "Alpha"/"Beta", both alive.
func make_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 9)
	w.faction_count = 2
	w.faction_alive[0] = 1
	w.faction_alive[1] = 1
	w.faction_names = ["Alpha", "Beta"]
	return w


## stacks.add(f, centre, "S"); n rank-0 sword units where unit k gets
## kills = k (so the last one has most kills); captain rank 1 via
## Lineage.make_captain(w, id, "Toby"); captain_unit; recount.
func mk_stack(w: World, f: int, tx: int, ty: int, n: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	for k in range(n):
		var uid := w.units.add(f, 0, 1, false, id)
		w.units.kills[uid] = k
	var cap_id := w.units.add(f, 1, 1, true, id)
	Lineage.make_captain(w, cap_id, "Toby")
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. make_captain sets career_start = w.time.
	var w1 := make_world()
	w1.time = 7.0
	var s1 := mk_stack(w1, 0, 5, 4, 5)
	var cap1 := w1.stacks.captain_unit[s1]
	t.check(w1.units.career_start[cap1] == 7.0, "case1 career_start == 7.0")

	# 2. succeed / _succeed.
	var w2 := make_world()
	var start2a := w2.units.n
	var s2a := mk_stack(w2, 0, 5, 4, 3)
	var cap2a := w2.stacks.captain_unit[s2a]
	w2.time = 50.0
	Lineage.succeed(w2, s2a, cap2a, "retires")
	var heir2a: int = w2.stacks.captain_unit[s2a]
	t.check(heir2a == start2a + 2, "case2 heir == top-kill unit")
	t.check(w2.units.career_start[heir2a] == 50.0, "case2 career_start[heir] == 50.0")
	var last2a := String(w2.events_log[w2.events_log.size() - 1])
	t.check(last2a == "Toby I retires; Toby II rises", "case2 succeed retires verb log")

	var s2b := mk_stack(w2, 0, 6, 4, 3)
	var cap2b := w2.stacks.captain_unit[s2b]
	Lineage._succeed(w2, s2b, cap2b)
	var last2b := String(w2.events_log[w2.events_log.size() - 1])
	t.check(last2b == "Toby I fell; Toby II rises", "case2 _succeed fell verb log")

	# 3. found_site.
	var w3a := make_world()
	var s3a := mk_stack(w3a, 0, 5, 4, 0)
	t.check(Settling.found_site(w3a, s3a) == Vector2i(5, 4), "case3a no towns -> (5,4)")

	var w3b := make_world()
	var s3b := mk_stack(w3b, 0, 5, 4, 0)
	w3b.add_town(Vector2i(5, 4), -1)
	t.check(Settling.found_site(w3b, s3b) == Vector2i(1, 0), "case3b town at stack tile -> (1,0)")

	var w3c := make_world()
	var s3c := mk_stack(w3c, 0, 0, 0, 0)
	w3c.add_town(Vector2i(0, 0), -1)
	t.check(Settling.found_site(w3c, s3c) == Vector2i(4, 0), "case3c corner stack -> (4,0)")
	w3c.map.kind[w3c.map.idx(4, 0)] = WorldMap.Kind.FOREST
	t.check(Settling.found_site(w3c, s3c) == Vector2i(4, 1), "case3c (4,0) blocked -> (4,1)")

	var w3d := make_world()
	for i in range(w3d.map.kind.size()):
		w3d.map.kind[i] = WorldMap.Kind.MOUNTAIN
	var s3d := mk_stack(w3d, 0, 5, 4, 0)
	w3d.add_town(Vector2i(5, 4), -1)
	t.check(Settling.found_site(w3d, s3d) == Vector2i(-1, -1), "case3d all MOUNTAIN -> (-1,-1)")

	# 4. found_town, own faction already has a town.
	var w4 := make_world()
	w4.add_town(Vector2i(0, 0), 0)
	var s4 := mk_stack(w4, 0, 8, 4, 20)
	var cap4 := w4.stacks.captain_unit[s4]
	w4.stacks.gold[s4] = 120.0
	var t4 := Settling.found_town(w4, s4, Vector2i(8, 4))
	t.check(t4 == 1, "case4 t == 1")
	t.check(w4.town_owner[1] == 0, "case4 town_owner[1] == 0")
	t.check(w4.town_gold[1] == 120.0, "case4 town_gold[1] == 120.0")
	t.check(w4.stacks.gold[s4] == 0.0, "case4 gold[s] == 0.0")
	t.check(w4.town_lord[1] == cap4, "case4 town_lord[1] == old captain")
	t.check(w4.units.fate[cap4] == Units.Fate.LORD, "case4 fate[c] == LORD")
	t.check(w4.units.is_captain[cap4] == 0, "case4 is_captain[c] == 0")
	t.check(w4.units.stack[cap4] == -1, "case4 units.stack[c] == -1")
	t.check(w4.units.alive[cap4] == 1, "case4 alive[c] == 1")
	t.check(w4.stacks.captain_unit[s4] != cap4, "case4 captain_unit[s] top-kill (not c)")
	t.check(w4.stacks.goal[s4] == Stacks.Goal.DEFEND, "case4 goal[s] == DEFEND")
	t.check(w4.stacks.state[s4] == Stacks.State.IDLE, "case4 state[s] == IDLE")
	t.check(w4.stacks.idle_timer[s4] == 30.0, "case4 idle_timer[s] == 30.0")
	t.check(w4.stacks.count[s4] == 20, "case4 count[s] == 20")
	t.check(w4.map.kind[w4.map.idx(8, 4)] == WorldMap.Kind.TOWN, "case4 map.kind (8,4) == TOWN")
	t.check(w4.map.owner[w4.map.idx(8, 4)] == 0, "case4 map.owner (8,4) == 0")
	t.check(w4.history["foundings"] == 1, "case4 history foundings == 1")
	t.check(String(w4.events_log[w4.events_log.size() - 2]) == "Toby I settles at (8,4), founding a town of Alpha", "case4 events_log[-2]")
	t.check(String(w4.events_log[w4.events_log.size() - 1]) == "Toby I settles; Toby II rises", "case4 events_log[-1]")

	# 5. found_town allegiance for a free company (owns no town).
	var w5a := make_world()
	w5a.add_town(Vector2i(1, 1), 0)
	w5a.recompute_borders()
	var s5a := mk_stack(w5a, 1, 8, 4, 5)
	w5a.add_relation(0, 1, 0.6)
	var t5a := Settling.found_town(w5a, s5a, Vector2i(8, 4))
	t.check(w5a.town_owner[t5a] == 0, "case5a allied -> owner 0")
	t.check(w5a.stacks.faction[s5a] == 0, "case5a stacks.faction[s] == 0")
	var all_f0 := true
	for u in range(w5a.units.n):
		if w5a.units.stack[u] == s5a and w5a.units.faction[u] != 0:
			all_f0 = false
	t.check(all_f0, "case5a every unit with stack==s has faction 0")

	var w5b := make_world()
	w5b.add_town(Vector2i(1, 1), 0)
	w5b.recompute_borders()
	var s5b := mk_stack(w5b, 1, 8, 4, 5)
	var t5b := Settling.found_town(w5b, s5b, Vector2i(8, 4))
	t.check(w5b.town_owner[t5b] == 1, "case5b fresh relation -> owner 1")
	t.check(w5b.stacks.faction[s5b] == 1, "case5b stack stays f1")

	var w5c := make_world()
	var s5c := mk_stack(w5c, 1, 8, 4, 5)
	var t5c := Settling.found_town(w5c, s5c, Vector2i(8, 4))
	t.check(w5c.town_owner[t5c] == 1, "case5c no f0 town -> owner 1")

	# 6. gold cap.
	var w6 := make_world()
	var s6 := mk_stack(w6, 0, 8, 4, 5)
	w6.stacks.gold[s6] = 900.0
	var t6 := Settling.found_town(w6, s6, Vector2i(8, 4))
	t.check(w6.town_gold[t6] == 500.0, "case6 town_gold capped at 500.0")

	# 7. guards.
	var w7a := make_world()
	w7a.add_town(Vector2i(8, 4), -1)
	var s7a := mk_stack(w7a, 0, 8, 4, 5)
	var before7a := w7a.towns.size()
	var t7a := Settling.found_town(w7a, s7a, Vector2i(8, 4))
	t.check(t7a == -1, "case7a tile already a town -> -1")
	t.check(w7a.towns.size() == before7a, "case7a towns.size() unchanged")

	var w7b := make_world()
	w7b.add_town(Vector2i(6, 4), -1)
	var s7b := mk_stack(w7b, 0, 8, 4, 5)
	var t7b := Settling.found_town(w7b, s7b, Vector2i(8, 4))
	t.check(t7b == -1, "case7b too close to an existing town -> -1")

	var w7c := make_world()
	var s7c := mk_stack(w7c, 0, 8, 4, 5)
	w7c.stacks.captain_unit[s7c] = -1
	var t7c := Settling.found_town(w7c, s7c, Vector2i(8, 4))
	t.check(t7c != -1, "case7c no captain still founds")
	var any_lord := false
	for u in range(w7c.units.n):
		if w7c.units.fate[u] == Units.Fate.LORD:
			any_lord = true
	t.check(not any_lord, "case7c no LORD set anywhere")
	t.check(String(w7c.events_log[w7c.events_log.size() - 1]) == "S settles at (8,4), founding a town of Alpha", "case7c log uses stack name")

	# 8. retire.
	var w8 := make_world()
	var s8 := mk_stack(w8, 0, 5, 4, 5)
	var cap8 := w8.stacks.captain_unit[s8]
	Settling.retire(w8, s8)
	t.check(w8.units.fate[cap8] == Units.Fate.RETIRED, "case8 fate[c] == RETIRED")
	t.check(w8.units.is_captain[cap8] == 0, "case8 is_captain[c] == 0")
	t.check(w8.units.stack[cap8] == -1, "case8 stack[c] == -1")
	t.check(w8.stacks.captain_unit[s8] != cap8 and w8.stacks.captain_unit[s8] != -1, "case8 heir captain")
	t.check(w8.stacks.goal[s8] == Stacks.Goal.IDLE_HEAL, "case8 goal == IDLE_HEAL")
	t.check(w8.stacks.state[s8] == Stacks.State.IDLE, "case8 state == IDLE")
	t.check(w8.history["retirements"] == 1, "case8 history retirements == 1")
	t.check(String(w8.events_log[w8.events_log.size() - 2]) == "Toby I retires", "case8 events_log[-2]")

	var w8b := make_world()
	var s8b := mk_stack(w8b, 0, 5, 4, 5)
	w8b.stacks.captain_unit[s8b] = -1
	var goal8b_before := w8b.stacks.goal[s8b]
	var state8b_before := w8b.stacks.state[s8b]
	Settling.retire(w8b, s8b)
	t.check(w8b.stacks.goal[s8b] == goal8b_before and w8b.stacks.state[s8b] == state8b_before, "case8b no captain -> no change")
	t.check(int(w8b.history.get("retirements", 0)) == 0, "case8b history unchanged")

	# 9. check_aging.
	var w9a := make_world()
	var s9a := mk_stack(w9a, 0, 5, 4, 5)
	w9a.time = 899.0
	var goal9a_before := w9a.stacks.goal[s9a]
	var state9a_before := w9a.stacks.state[s9a]
	Settling.check_aging(w9a)
	t.check(w9a.stacks.goal[s9a] == goal9a_before and w9a.stacks.state[s9a] == state9a_before, "case9a age<900 no change")
	t.check(w9a.towns.size() == 0, "case9a no town founded")

	var w9b := make_world()
	var s9b := mk_stack(w9b, 0, 5, 4, 60)
	w9b.stacks.gold[s9b] = 150.0
	w9b.time = 900.0
	Settling.check_aging(w9b)
	t.check(w9b.towns.size() == 1, "case9b founds on own tile")

	var w9c := make_world()
	w9c.add_town(Vector2i(5, 4), 0)
	var s9c := mk_stack(w9c, 0, 6, 4, 60)
	w9c.stacks.gold[s9c] = 150.0
	w9c.time = 900.0
	var expected_site9c := Settling.found_site(w9c, s9c)
	Settling.check_aging(w9c)
	t.check(w9c.stacks.goal[s9c] == Stacks.Goal.FOUND, "case9c goal FOUND")
	t.check(w9c.stacks.state[s9c] == Stacks.State.MOVING, "case9c state MOVING")
	t.check(Vector2i(w9c.stacks.goal_tx[s9c], w9c.stacks.goal_ty[s9c]) == expected_site9c, "case9c goal tile == found_site")
	t.check(w9c.stacks.path[s9c].size() > 0, "case9c path non-empty")
	t.check(w9c.towns.size() == 1, "case9c no new town yet")

	var w9d := make_world()
	var s9d := mk_stack(w9d, 0, 5, 4, 10)
	w9d.stacks.gold[s9d] = 0.0
	w9d.time = 900.0
	Settling.check_aging(w9d)
	t.check(int(w9d.history.get("retirements", 0)) == 1, "case9d low score retires")

	var w9e := make_world()
	var s9e := mk_stack(w9e, 0, 5, 4, 5)
	var cap9e := w9e.stacks.captain_unit[s9e]
	var site9e := Settling.found_site(w9e, s9e)
	w9e.stacks.goal[s9e] = Stacks.Goal.FOUND
	w9e.stacks.goal_tx[s9e] = site9e.x
	w9e.stacks.goal_ty[s9e] = site9e.y
	w9e.stacks.state[s9e] = Stacks.State.IDLE
	var pos9e := w9e.map.center_of(site9e.x, site9e.y)
	w9e.stacks.x[s9e] = pos9e.x
	w9e.stacks.y[s9e] = pos9e.y
	w9e.time = 950.0
	Settling.check_aging(w9e)
	t.check(w9e.towns.size() == 1, "case9e founded at valid site")
	t.check(w9e.units.fate[cap9e] == Units.Fate.LORD, "case9e captain became LORD")

	var w9f := make_world()
	var s9f := mk_stack(w9f, 0, 5, 4, 5)
	w9f.stacks.goal[s9f] = Stacks.Goal.FOUND
	w9f.stacks.goal_tx[s9f] = 5
	w9f.stacks.goal_ty[s9f] = 4
	w9f.time = 1020.0
	Settling.check_aging(w9f)
	t.check(int(w9f.history.get("retirements", 0)) == 1, "case9f grace expired retires")

	var w9g := make_world()
	var s9g := mk_stack(w9g, 0, 5, 4, 5)
	w9g.stacks.state[s9g] = Stacks.State.BATTLE
	w9g.time = 2000.0
	var goal9g_before := w9g.stacks.goal[s9g]
	Settling.check_aging(w9g)
	t.check(w9g.stacks.goal[s9g] == goal9g_before, "case9g BATTLE no change")
	t.check(w9g.towns.size() == 0, "case9g no town founded")

	var w9h := make_world()
	var s9h := mk_stack(w9h, 0, 5, 4, 5)
	w9h.stacks.captain_unit[s9h] = -1
	w9h.time = 2000.0
	Settling.check_aging(w9h)
	t.check(w9h.towns.size() == 0, "case9h no captain no change")

	t.finish()
	quit()
