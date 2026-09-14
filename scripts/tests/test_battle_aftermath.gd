extends SceneTree
## Tests for BattleAftermath (docs/ARCHITECTURE.md §18) and the
## BattleSim.integrate(apply_hazards) split it relies on.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Side 0 wins: captain at (800,450) plus four regulars around it. Side 1 is
## routed: two RETREAT marbles close to the winners, one far away (out of
## CHASE_RANGE). Returns [state, sim, captain, winners, near_losers, far_loser].
func mk_rout(seed: int) -> Array:
	var s := BattleState.new(16, seed)
	var cap := s.spawn(800.0, 450.0, 0, 1, 1, true)
	var winners: Array = []
	winners.append(s.spawn(740.0, 420.0, 0, 0, 1, false))
	winners.append(s.spawn(740.0, 480.0, 0, 0, 1, false))
	winners.append(s.spawn(860.0, 420.0, 0, 0, 1, false))
	winners.append(s.spawn(860.0, 480.0, 0, 0, 1, false))
	var near: Array = []
	near.append(s.spawn(1000.0, 430.0, 1, 0, 1, false))
	near.append(s.spawn(1020.0, 480.0, 1, 0, 1, false))
	var far := s.spawn(1300.0, 100.0, 1, 0, 1, false)
	for m in near:
		s.state[m] = BattleState.State.RETREAT
	s.state[far] = BattleState.State.RETREAT
	var sim := BattleSim.new(s)
	return [s, sim, cap, winners, near, far]


func _init() -> void:
	var t := TestKit.new()
	var dt := Tuning.DT

	# 1. chase assignment.
	var r1 := mk_rout(3)
	var s1: BattleState = r1[0]
	var cap1: int = r1[2]
	var winners1: Array = r1[3]
	var near1: Array = r1[4]
	var far1: int = r1[5]
	var a1 := BattleAftermath.new(s1, r1[1], 0)
	t.check(a1.chase_of[cap1] == -1, "case1 captain does not chase")
	var chased_near := 0
	var chased_far := 0
	for w in winners1:
		var target: int = a1.chase_of[w]
		if near1.has(target):
			chased_near += 1
		if target == far1:
			chased_far += 1
	t.check(chased_near >= 1 and chased_near <= 2 * near1.size(), "case1 near fleers get chasers")
	t.check(chased_far == 0, "case1 fleer out of CHASE_RANGE gets no chaser")
	for m in near1:
		t.check(a1.chase_of[m] == -1, "case1 fleers never chase")
	t.check(a1.is_celebrant(cap1) and a1.is_fleer(far1), "case1 roles")

	# 2. no damage, losers leave, winners keep dancing.
	var hp_before := s1.hp.duplicate()
	var kills_before := s1.kills.duplicate()
	var angle_before: float = s1.weapon_angle[winners1[0]]
	var saw_kill := false
	var steps := 0
	for _i in range(900):
		a1.step(dt)
		steps += 1
		for ev in s1.events:
			if ev[0] == BattleState.Event.KILL or ev[0] == BattleState.Event.HIT or ev[0] == BattleState.Event.BUMP:
				saw_kill = true
	t.check(s1.hp == hp_before, "case2 hp unchanged")
	t.check(s1.kills == kills_before, "case2 kills unchanged")
	t.check(not saw_kill, "case2 no KILL/HIT/BUMP events")
	t.check(s1.tick == steps, "case2 tick advances once per step")
	var all_fled := true
	for m in near1 + [far1]:
		if s1.state[m] != BattleState.State.DEAD or s1.fled[m] != 1:
			all_fled = false
	t.check(all_fled, "case2 every loser fled off its home edge")
	var winners_alive := s1.state[cap1] != BattleState.State.DEAD
	var ring_ok := true
	var moving := false
	var ring_max := BattleAftermath.RING_BASE + BattleAftermath.RING_PER_SQRT * sqrt(5.0)
	for w in winners1:
		if s1.state[w] == BattleState.State.DEAD:
			winners_alive = false
			continue
		var d := Vector2(s1.px[w], s1.py[w]).distance_to(Vector2(s1.px[cap1], s1.py[cap1]))
		if d > ring_max + 40.0:
			ring_ok = false
		if Vector2(s1.vx[w], s1.vy[w]).length() > 10.0:
			moving = true
		t.check(a1.chase_of[w] == -1, "case2 chase released after CHASE_TIME")
	t.check(winners_alive, "case2 no winner removed")
	t.check(ring_ok, "case2 winners gathered around the captain")
	t.check(moving, "case2 winners still moving (orbit)")
	t.check(not is_equal_approx(s1.weapon_angle[winners1[0]], angle_before), "case2 winner weapons twirl")

	# 3. hazards never hurt during the aftermath.
	var r3 := mk_rout(4)
	var s3: BattleState = r3[0]
	var sim3: BattleSim = r3[1]
	var tg := TerrainGrid.new()
	tg.setup(s3.arena, Tuning.TERRAIN_CELL)
	tg.fill_rect(0, 0, tg.cols - 1, tg.rows - 1, TerrainGrid.Kind.FIRE)
	sim3.set_terrain(tg)
	var a3 := BattleAftermath.new(s3, sim3, 0)
	var hp3 := s3.hp.duplicate()
	for _i in range(120):
		a3.step(dt)
	t.check(s3.hp == hp3, "case3 FIRE terrain deals no damage in aftermath")

	# 3b. control: the same terrain does burn through BattleSim.integrate(.., true).
	var s3b := BattleState.new(4, 5)
	var m3b := s3b.spawn(400.0, 400.0, 0, 0, 1, false)
	var sim3b := BattleSim.new(s3b)
	sim3b.set_terrain(tg)
	sim3b.integrate(s3b, dt, true)
	t.check(s3b.hp[m3b] < s3b.hp_max[m3b], "case3b integrate with hazards still burns")

	# 4. stalemate: ENGAGE marbles hold, RETREAT marbles flee.
	var s4 := BattleState.new(4, 6)
	var hold4 := s4.spawn(600.0, 450.0, 0, 0, 1, false)
	var run4 := s4.spawn(1000.0, 450.0, 1, 0, 1, false)
	s4.state[run4] = BattleState.State.RETREAT
	var a4 := BattleAftermath.new(s4, BattleSim.new(s4), -1)
	t.check(not a4.is_celebrant(hold4) and not a4.is_fleer(hold4), "case4 stalemate ENGAGE marble idles")
	t.check(a4.is_fleer(run4), "case4 stalemate RETREAT marble flees")
	for _i in range(60):
		a4.step(dt)
	t.check(t.approx(s4.px[hold4], 600.0, 1.0) and t.approx(s4.py[hold4], 450.0, 1.0), "case4 idle marble stays put")
	t.check(s4.px[run4] > 1000.0 + 20.0, "case4 fleer moved toward its home edge")

	# 5. banner text.
	var w5 := World.new()
	w5.setup_blank(12, 8, 12)
	w5.faction_names = ["Alpha", "Beta"]
	var tile5 := Vector2i(5, 4)
	var c5 := w5.map.center_of(tile5.x, tile5.y)
	var st0 := w5.stacks.add(0, c5.x, c5.y, "Iron Band")
	var st1 := w5.stacks.add(1, c5.x, c5.y, "Red Hand")
	for _u in range(3):
		w5.units.add(0, 0, 1, false, st0)
		w5.units.add(1, 0, 1, false, st1)
	w5.stacks.recount(w5.units)
	w5.stacks.prev_x[st0] = c5.x - 64.0
	w5.stacks.prev_y[st0] = c5.y
	w5.stacks.prev_x[st1] = c5.x + 64.0
	w5.stacks.prev_y[st1] = c5.y
	var inst5 := BattleBridge.start(w5, st0, st1)
	var side0 := -1
	for e in range(inst5.faction_map.size()):
		if inst5.faction_map[e] == 0:
			side0 = e
	var lines5 := BattleAftermath.banner_lines(inst5, w5, side0)
	t.check(lines5[0] == "ALPHA VICTORY", "case5 title names the winning faction")
	t.check(lines5[1] == "Iron Band", "case5 subtitle lists the winning stacks only")
	t.check(BattleAftermath.banner_lines(inst5, w5, -2)[0] == "STALEMATE", "case5 stalemate title")

	t.finish()
	quit()
