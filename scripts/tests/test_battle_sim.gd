extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func one(x: float, y: float, f: int) -> BattleState:
	var s := BattleState.new(8, 3)
	s.spawn(x, y, f, 0, 1, false)
	return s

func _init() -> void:
	var t := TestKit.new()
	var dt := Tuning.DT

	# 1. Free flight.
	var s1 := one(100.0, 100.0, 0)
	s1.vx[0] = 60.0
	var sim1 := BattleSim.new(s1)
	sim1.step(s1, dt)
	t.check(t.approx(s1.vx[0], 55.2, 1e-3), "case1 vx[0] approx 55.2")
	t.check(t.approx(s1.px[0], 100.92, 1e-3), "case1 px[0] approx 100.92")
	t.check(t.approx(s1.spin[0], 99.93333, 1e-3), "case1 spin[0] approx 99.93333")
	t.check(s1.tick == 1, "case1 tick == 1")
	t.check(t.approx(s1.time, dt, 1e-6), "case1 time approx dt")

	# 2. Left wall.
	var s2 := one(10.0, 100.0, 0)
	s2.vx[0] = -600.0
	var sim2 := BattleSim.new(s2)
	sim2.step(s2, dt)
	t.check(t.approx(s2.px[0], 8.0, 1e-3), "case2 px[0] approx 8.0")
	t.check(t.approx(s2.vx[0], 360.0, 1e-3), "case2 vx[0] approx 360.0")

	# 3. Bottom wall.
	var s3 := one(800.0, 895.0, 0)
	s3.vy[0] = 300.0
	var sim3 := BattleSim.new(s3)
	sim3.step(s3, dt)
	t.check(t.approx(s3.py[0], 892.0, 1e-3), "case3 py[0] approx 892.0")
	t.check(s3.vy[0] < 0.0, "case3 vy[0] < 0")

	# 4. Speed clamp.
	var s4 := one(800.0, 450.0, 0)
	s4.vx[0] = 1000.0
	s4.vy[0] = 0.0
	var sim4 := BattleSim.new(s4)
	sim4.step(s4, dt)
	t.check(t.approx(s4.vx[0], 400.0, 1e-3), "case4 vx[0] approx 400.0")

	# 5. Attraction pulls, staggered.
	var s5 := BattleState.new(8, 3)
	var a5 := s5.spawn(700.0, 450.0, 0, 0, 1, false)
	var b5 := s5.spawn(740.0, 450.0, 1, 0, 1, false)
	var sim5 := BattleSim.new(s5)
	sim5.step(s5, dt)
	t.check(s5.px[a5] > 700.0, "case5 px[0] > 700 after tick 0")
	t.check(t.approx(s5.px[b5], 740.0, 1e-3), "case5 px[1] approx 740 (not retargeted yet)")
	for _i in range(30):
		sim5.step(s5, dt)
	t.check(s5.px[a5] > 700.0, "case5 px[0] > 700 after 31 steps")
	t.check(s5.px[b5] < 740.0, "case5 px[1] < 740 after 31 steps")
	var dx5 := s5.px[b5] - s5.px[a5]
	var dy5 := s5.py[b5] - s5.py[a5]
	var dist5 := sqrt(dx5 * dx5 + dy5 * dy5)
	t.check(dist5 >= 15.9, "case5 distance >= 15.9")

	# 6. Centroids & alive.
	var s6 := BattleState.new(8, 3)
	var m0 := s6.spawn(100.0, 100.0, 0, 0, 1, false)
	var m1 := s6.spawn(200.0, 100.0, 0, 0, 1, false)
	var m2 := s6.spawn(300.0, 100.0, 0, 0, 1, false)
	var sim6 := BattleSim.new(s6)
	sim6.step(s6, dt)
	t.check(s6.faction_alive[0] == 3, "case6 faction_alive[0] == 3")
	var expect_cx6 := (s6.px[m0] + s6.px[m1] + s6.px[m2]) / 3.0
	t.check(t.approx(s6.faction_cx[0], expect_cx6, 2.0), "case6 faction_cx[0] approx avg (post-step, eps 2.0)")
	t.check(t.approx(s6.faction_cy[0], 100.0, 2.0), "case6 faction_cy[0] approx 100")

	# 7. Dead excluded.
	var s7 := BattleState.new(8, 3)
	var p0 := s7.spawn(100.0, 100.0, 0, 0, 1, false)
	var p1 := s7.spawn(200.0, 100.0, 0, 0, 1, false)
	var p2 := s7.spawn(300.0, 100.0, 0, 0, 1, false)
	s7.state[p1] = BattleState.State.DEAD
	var px7 := s7.px[p1]
	var sim7 := BattleSim.new(s7)
	sim7.step(s7, dt)
	t.check(s7.faction_alive[0] == 2, "case7 faction_alive[0] == 2")
	t.check(t.approx(s7.px[p1], px7, 1e-6), "case7 dead marble unchanged")
	t.check(p0 >= 0 and p2 >= 0, "case7 marbles spawned")

	# 8. winner.
	var sw := BattleState.new(8, 3)
	var aw := sw.spawn(100.0, 100.0, 0, 0, 1, false)
	var bw := sw.spawn(200.0, 100.0, 1, 0, 1, false)
	var simw := BattleSim.new(sw)
	t.check(simw.winner(sw) == -1, "case8 winner -1 both engaged")
	sw.state[bw] = BattleState.State.DEAD
	t.check(simw.winner(sw) == 0, "case8 winner 0 after enemy dead")

	var sw2 := BattleState.new(8, 3)
	sw2.spawn(100.0, 100.0, 0, 0, 1, false)
	sw2.spawn(200.0, 100.0, 1, 0, 1, false)
	sw2.time = 200.0
	var simw2 := BattleSim.new(sw2)
	t.check(simw2.winner(sw2) == -2, "case8 winner -2 on timeout, both engaged")

	var sw3 := BattleState.new(8, 3)
	var aw3 := sw3.spawn(100.0, 100.0, 0, 0, 1, false)
	var bw3 := sw3.spawn(200.0, 100.0, 1, 0, 1, false)
	sw3.state[aw3] = BattleState.State.RETREAT
	sw3.state[bw3] = BattleState.State.RETREAT
	var simw3 := BattleSim.new(sw3)
	t.check(simw3.winner(sw3) == -2, "case8 winner -2 zero ENGAGE factions")

	var sw4 := BattleState.new(8, 3)
	sw4.spawn(100.0, 100.0, 0, 0, 1, false)
	var bw4 := sw4.spawn(200.0, 100.0, 1, 0, 1, false)
	sw4.state[bw4] = BattleState.State.DEAD
	sw4.time = 200.0
	var simw4 := BattleSim.new(sw4)
	t.check(simw4.winner(sw4) == 0, "case8 winner 0, decided winner beats timeout")

	# 9. Determinism.
	var s9a := BattleState.new(500, 9)
	s9a.spawn_block(0, 250, Rect2(100, 100, 500, 700), 1)
	s9a.spawn_block(1, 250, Rect2(1000, 100, 500, 700), 1)
	var sim9a := BattleSim.new(s9a)
	for _j in range(120):
		sim9a.step(s9a, dt)

	var s9b := BattleState.new(500, 9)
	s9b.spawn_block(0, 250, Rect2(100, 100, 500, 700), 1)
	s9b.spawn_block(1, 250, Rect2(1000, 100, 500, 700), 1)
	var sim9b := BattleSim.new(s9b)
	for _j in range(120):
		sim9b.step(s9b, dt)

	t.check(s9a.px == s9b.px, "case9 px deterministic")
	t.check(s9a.spin == s9b.spin, "case9 spin deterministic")

	# 10. Stays in arena, stays finite.
	var in_bounds := true
	var finite := true
	for marble_idx in range(s9a.n):
		var r := s9a.radius[marble_idx]
		if s9a.px[marble_idx] < r or s9a.px[marble_idx] > Tuning.ARENA_W - r:
			in_bounds = false
		if s9a.py[marble_idx] < r or s9a.py[marble_idx] > Tuning.ARENA_H - r:
			in_bounds = false
		if not is_finite(s9a.px[marble_idx]):
			finite = false
	t.check(in_bounds, "case10 positions within arena bounds")
	t.check(s9a.alive_count() == 500, "case10 alive_count == 500")
	t.check(finite, "case10 positions finite")

	t.finish()
	quit()
