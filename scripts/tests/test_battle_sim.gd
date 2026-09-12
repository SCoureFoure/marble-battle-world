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
	t.check(s5.px[b5] < 740.0, "case5 px[1] < 740.0 (B advances toward A)")
	for _i in range(10):
		sim5.step(s5, dt)
	t.check(s5.px[a5] > 700.0, "case5 px[0] > 700 after 11 steps")
	t.check(s5.px[b5] < 740.0, "case5 px[1] < 740 after 11 steps")
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

	# 11. Mud slows.
	var s11 := BattleState.new(8, 3)
	var m11 := s11.spawn(100.0, 100.0, 0, 0, 1, false)
	var g11 := TerrainGrid.new()
	g11.setup(s11.arena, Tuning.TERRAIN_CELL)
	g11.fill_rect(0, 0, 39, 22, TerrainGrid.Kind.MUD)
	s11.vx[m11] = 60.0
	var sim11 := BattleSim.new(s11)
	sim11.set_terrain(g11)
	sim11.step(s11, dt)
	t.check(t.approx(s11.vx[m11], 48.0, 1e-2), "case11 vx[0] approx 48.0 (mud)")

	# 12. Slope pushes.
	var s12 := BattleState.new(8, 3)
	var m12 := s12.spawn(100.0, 100.0, 0, 0, 1, false)
	var g12 := TerrainGrid.new()
	g12.setup(s12.arena, Tuning.TERRAIN_CELL)
	for cy12 in range(g12.rows):
		for cx12 in range(g12.cols):
			g12.set_slope(cx12, cy12, Vector2(0, 100))
	var sim12 := BattleSim.new(s12)
	sim12.set_terrain(g12)
	sim12.step(s12, dt)
	t.check(t.approx(s12.vy[m12], 100.0 * 12.0 * dt * 0.92, 1e-3), "case12 vy[0] approx 18.4")
	t.check(s12.py[m12] > 100.0, "case12 py[0] > 100.0")

	# 13. Obstacle blocks.
	var s13 := BattleState.new(8, 3)
	var m13 := s13.spawn(190.0, 220.0, 0, 0, 1, false)
	var g13 := TerrainGrid.new()
	g13.setup(s13.arena, Tuning.TERRAIN_CELL)
	g13.set_cell(5, 5, TerrainGrid.Kind.ROCK)
	s13.vx[m13] = 300.0
	var sim13 := BattleSim.new(s13)
	sim13.set_terrain(g13)
	var never_inside13 := true
	for _step13 in range(10):
		sim13.step(s13, dt)
		var d13 := Vector2(s13.px[m13], s13.py[m13]).distance_to(Vector2(220.0, 220.0))
		if d13 < 24.0 - 1e-3:
			never_inside13 = false
	t.check(never_inside13, "case13 marble never inside obstacle")
	t.check(s13.vx[m13] < 0.0, "case13 vx[0] < 0 (bounced)")

	# 14. Fire burns.
	var s14 := BattleState.new(8, 3)
	var m14 := s14.spawn(100.0, 100.0, 0, 0, 1, false)
	var g14 := TerrainGrid.new()
	g14.setup(s14.arena, Tuning.TERRAIN_CELL)
	g14.set_cell(2, 2, TerrainGrid.Kind.FIRE)
	s14.hp[m14] = 0.1
	var sim14 := BattleSim.new(s14)
	sim14.set_terrain(g14)
	sim14.step(s14, dt)
	t.check(t.approx(s14.hp[m14], 0.0, 1e-3), "case14 hp[0] == 0.0")
	t.check(s14.state[m14] == BattleState.State.DEAD, "case14 state[0] == DEAD")
	t.check(s14.faction_alive[0] == 0, "case14 faction_alive[0] == 0")
	var found_kill14 := false
	for ev14 in s14.events:
		if ev14[0] == BattleState.Event.KILL and ev14[1] == -1 and ev14[2] == m14:
			found_kill14 = true
	t.check(found_kill14, "case14 events contains KILL actor -1")

	# 15. Tower capture and aura.
	var s15 := BattleState.new(8, 3)
	var a15 := s15.spawn(420.0, 420.0, 0, 0, 1, false)
	var g15 := TerrainGrid.new()
	g15.setup(s15.arena, Tuning.TERRAIN_CELL)
	g15.set_cell(10, 10, TerrainGrid.Kind.TOWER)
	s15.spin[a15] = 50.0
	s15.hp[a15] = 50.0
	s15.hit_cd[a15] = 10.0
	var sim15 := BattleSim.new(s15)
	sim15.set_terrain(g15)
	sim15.step(s15, dt)
	t.check(g15.owner[10 * g15.cols + 10] == 0, "case15 owner[tower] == 0")
	t.check(t.approx(s15.spin[a15], 50.0 + 10.0 * dt - 4.0 * dt, 1e-3), "case15 spin[0] approx 50.1")
	t.check(t.approx(s15.hp[a15], 50.0 + 5.0 * dt, 1e-3), "case15 hp[0] approx tower heal")

	var b15 := s15.spawn(430.0, 420.0, 1, 0, 1, false)
	s15.hit_cd[a15] = 10.0
	s15.hit_cd[b15] = 10.0
	s15.hp[b15] = 50.0
	sim15.step(s15, dt)
	t.check(g15.owner[10 * g15.cols + 10] == 0, "case15 owner stays 0 (contested unchanged)")
	t.check(t.approx(s15.hp[b15], 50.0, 1e-3), "case15 f1 gets no regen while contested")

	# 16. Weapons run in step.
	var s16 := BattleState.new(8, 3)
	var a16 := s16.spawn(100.0, 100.0, 0, 0, 1, false)
	var b16 := s16.spawn(118.0, 100.0, 1, 0, 1, false)
	s16.weapon_angle[a16] = 0.0
	s16.weapon_angle[b16] = 0.0
	Weapons.force_roll = 0.5
	var sim16 := BattleSim.new(s16)
	sim16.step(s16, dt)
	t.check(s16.hp[b16] < 100.0, "case16 hp[1] < 100.0")
	var found_hit16 := false
	for ev16 in s16.events:
		if ev16[0] == BattleState.Event.HIT and ev16[1] == a16:
			found_hit16 = true
	t.check(found_hit16, "case16 events contains HIT actor 0")
	Weapons.force_roll = -1.0

	# 17. Retreat on low hp.
	var s17 := BattleState.new(8, 3)
	var m17 := s17.spawn(100.0, 100.0, 0, 0, 1, false)
	s17.hp[m17] = 10.0
	var sim17 := BattleSim.new(s17)
	sim17.step(s17, dt)
	t.check(s17.state[m17] == BattleState.State.RETREAT, "case17 state[0] == RETREAT (low hp)")

	# 18. Retreat on low morale.
	var s18 := BattleState.new(8, 3)
	var m18 := s18.spawn(100.0, 100.0, 0, 0, 1, false)
	s18.morale[m18] = 0.1
	var sim18 := BattleSim.new(s18)
	sim18.step(s18, dt)
	t.check(s18.state[m18] == BattleState.State.RETREAT, "case18 state[0] == RETREAT (low morale)")

	# 19. Captain death routs.
	var s19 := BattleState.new(8, 3)
	var c19 := s19.spawn(300.0, 300.0, 0, 0, 1, true)
	var sol19 := s19.spawn(100.0, 100.0, 0, 0, 1, false)
	var sim19 := BattleSim.new(s19)
	t.check(sim19.captain_seen[0] == 1, "case19 captain_seen[0] == 1")
	s19.state[c19] = BattleState.State.DEAD
	s19.faction_captain[0] = -1
	sim19.step(s19, dt)
	t.check(s19.state[sol19] == BattleState.State.RETREAT, "case19 soldier routs on captain death")

	# Control: faction that never had a captain, full hp/morale -> stays ENGAGE.
	var s19b := BattleState.new(8, 3)
	var sol19b := s19b.spawn(100.0, 100.0, 0, 0, 1, false)
	var sim19b := BattleSim.new(s19b)
	sim19b.step(s19b, dt)
	t.check(s19b.state[sol19b] == BattleState.State.ENGAGE, "case19 control stays ENGAGE (no captain ever)")

	# 20. Fled at home edge.
	var s20 := BattleState.new(8, 3)
	var m20 := s20.spawn(8.0, 300.0, 0, 0, 1, false)
	s20.state[m20] = BattleState.State.RETREAT
	var sim20 := BattleSim.new(s20)
	sim20.step(s20, dt)
	t.check(s20.fled[m20] == 1, "case20 fled[0] == 1")
	t.check(s20.state[m20] == BattleState.State.DEAD, "case20 state[0] == DEAD")
	t.check(s20.faction_alive[0] == 0, "case20 faction_alive[0] == 0")
	var found_fled20 := false
	for ev20 in s20.events:
		if ev20[0] == BattleState.Event.FLED and ev20[1] == m20 and ev20[2] == -1:
			found_fled20 = true
	t.check(found_fled20, "case20 events contains FLED")
	t.check(s20.survivors_count(0) == 1, "case20 survivors_count(0) == 1")

	# 21. Captain aura regen.
	var s21 := BattleState.new(8, 3)
	s21.spawn(300.0, 300.0, 0, 2, 1, true)
	var sold21 := s21.spawn(340.0, 300.0, 0, 0, 1, false)
	s21.morale[sold21] = 0.5
	var sim21 := BattleSim.new(s21)
	sim21.step(s21, dt)
	t.check(t.approx(s21.morale[sold21], 0.5 + 0.05 * dt, 1e-4), "case21 morale[S] approx aura regen")

	var s21b := BattleState.new(8, 3)
	s21b.spawn(300.0, 300.0, 0, 2, 1, true)
	var sold21b := s21b.spawn(500.0, 300.0, 0, 0, 1, false)
	s21b.morale[sold21b] = 0.5
	var sim21b := BattleSim.new(s21b)
	sim21b.step(s21b, dt)
	t.check(t.approx(s21b.morale[sold21b], 0.5, 1e-4), "case21 morale unchanged out of aura")

	# 22. Full battle terminates.
	var s22 := BattleState.new(120, 21)
	var g22 := TerrainGrid.new()
	g22.setup(s22.arena, Tuning.TERRAIN_CELL)
	TerrainGen.demo(g22, s22.rng)
	s22.spawn(350.0, 450.0, 0, 1, 1, true)
	s22.spawn(1250.0, 450.0, 1, 1, 1, true)
	s22.spawn_block(0, 50, Rect2(100, 100, 500, 700), -1)
	s22.spawn_block(1, 50, Rect2(1000, 100, 500, 700), -1)
	var sim22 := BattleSim.new(s22)
	sim22.set_terrain(g22)
	var w22 := -1
	var steps22 := 0
	var hits22 := 0
	var kills22 := 0
	while w22 == -1 and steps22 < 7300:
		sim22.step(s22, dt)
		for ev22 in s22.events:
			if ev22[0] == BattleState.Event.HIT:
				hits22 += 1
			elif ev22[0] == BattleState.Event.KILL:
				kills22 += 1
		w22 = sim22.winner(s22)
		steps22 += 1
	t.check(w22 != -1, "case22 winner decided or timeout")
	t.check(hits22 >= 200, "case22 hits >= 200")
	t.check(kills22 >= 1, "case22 kills >= 1")
	var finite22 := true
	for idx22 in range(s22.n):
		if not is_finite(s22.px[idx22]) or not is_finite(s22.py[idx22]):
			finite22 = false
	t.check(finite22, "case22 positions finite")

	t.finish()
	quit()
