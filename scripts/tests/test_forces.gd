extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func make(seed: int) -> BattleState:
	return BattleState.new(32, seed)

func hashes(s: BattleState) -> Array:
	var fine := SpatialHash.new()
	fine.setup(s.arena, 2 * 8.0)
	fine.build(s.px, s.py, s.state, s.n)
	var coarse := SpatialHash.new()
	coarse.setup(s.arena, 12 * 8.0)
	coarse.build(s.px, s.py, s.state, s.n)
	return [fine, coarse]

func _init() -> void:
	var t := TestKit.new()

	# 1. Attraction toward target.
	var s1 := make(1)
	var a1 := s1.spawn(100, 100, 0, 0, 1, false)
	var b1 := s1.spawn(180.0, 100.0, 1, 0, 1, false)
	var hs1 := hashes(s1)
	var coarse1: SpatialHash = hs1[1]
	Forces.retarget(s1, coarse1, 0)
	t.check(s1.target_id[a1] == b1, "case1 target_id[0] == 1 at tick 0")
	t.check(s1.target_id[b1] == -1, "case1 target_id[1] == -1 at tick 0")
	Forces.retarget(s1, coarse1, 14)
	t.check(s1.target_id[b1] == a1, "case1 target_id[1] == 0 at tick 14")

	# 2. Attraction magnitude (reuses case 1's state; positions unchanged
	# since case 1, so the fine hash built in hashes(s1) is still valid).
	var fine1: SpatialHash = hs1[0]
	s1.faction_cx[0] = 100.0
	s1.faction_cy[0] = 100.0
	s1.faction_cx[1] = 180.0
	s1.faction_cy[1] = 100.0
	s1.ax.fill(0.0)
	s1.ay.fill(0.0)
	Forces.accumulate(s1, fine1)
	t.check(t.approx(s1.ax[a1], 32.0, 1e-3), "case2 ax[0] approx 32.0")
	t.check(t.approx(s1.ay[a1], 0.0, 1e-3), "case2 ay[0] approx 0")
	t.check(t.approx(s1.ax[b1], -32.0, 1e-3), "case2 ax[1] approx -32.0")

	# 3. Out of engage range.
	var s3 := make(3)
	var a3 := s3.spawn(100, 100, 0, 0, 1, false)
	var b3 := s3.spawn(400, 100, 1, 0, 1, false)
	var hs3 := hashes(s3)
	Forces.retarget(s3, hs3[1], 0)
	t.check(s3.target_id[a3] == -1, "case3 target_id[0] == -1 (300 > 96)")
	s3.faction_cx[0] = 100.0
	s3.faction_cy[0] = 100.0
	s3.faction_cx[1] = 400.0
	s3.faction_cy[1] = 100.0
	s3.ax.fill(0.0)
	s3.ay.fill(0.0)
	Forces.accumulate(s3, hs3[0])
	t.check(t.approx(s3.ax[a3], 0.0, 1e-3), "case3 ax[0] approx 0")

	# 4. Retreat flips attraction and adds the home-edge pull.
	var s4 := make(4)
	var a4 := s4.spawn(100, 100, 0, 0, 1, false)
	var b4 := s4.spawn(180.0, 100.0, 1, 0, 1, false)
	var hs4 := hashes(s4)
	Forces.retarget(s4, hs4[1], 0)
	s4.state[a4] = BattleState.State.RETREAT
	s4.faction_cx[0] = 100.0
	s4.faction_cy[0] = 100.0
	s4.faction_cx[1] = 180.0
	s4.faction_cy[1] = 100.0
	s4.ax.fill(0.0)
	s4.ay.fill(0.0)
	Forces.accumulate(s4, hs4[0])
	t.check(t.approx(s4.ax[a4], -72.0, 0.01), "case4 ax[0] approx -72.0")
	t.check(t.approx(s4.ay[a4], 0.0, 0.01), "case4 ay[0] approx 0")

	# 5. Separation between two same-faction marbles.
	var s5 := make(5)
	var a5 := s5.spawn(100, 100, 0, 0, 0, false)
	var b5 := s5.spawn(110, 100, 0, 0, 0, false)
	var hs5 := hashes(s5)
	s5.faction_cx[0] = 105.0
	s5.faction_cy[0] = 100.0
	s5.ax.fill(0.0)
	s5.ay.fill(0.0)
	Forces.accumulate(s5, hs5[0])
	t.check(t.approx(s5.ax[a5], -57.5, 0.05), "case5 ax[0] approx -57.5")
	t.check(t.approx(s5.ax[b5], 57.5, 0.05), "case5 ax[1] approx 57.5")
	t.check(t.approx(s5.ay[a5], 0.0, 0.05), "case5 ay[0] approx 0")
	t.check(t.approx(s5.ay[b5], 0.0, 0.05), "case5 ay[1] approx 0")

	# 6. Separation ignores enemies.
	var s6 := make(6)
	var a6 := s6.spawn(100, 100, 0, 0, 0, false)
	var b6 := s6.spawn(110, 100, 1, 0, 0, false)
	var hs6 := hashes(s6)
	s6.faction_cx[0] = 100.0
	s6.faction_cy[0] = 100.0
	s6.faction_cx[1] = 110.0
	s6.faction_cy[1] = 100.0
	s6.ax.fill(0.0)
	s6.ay.fill(0.0)
	Forces.accumulate(s6, hs6[0])
	t.check(t.approx(s6.ax[a6], 0.0, 1e-3), "case6 ax[0] approx 0")

	# 7. Cohesion toward centroid.
	var s7 := make(7)
	var m0 := s7.spawn(100, 100, 0, 0, 0, false)
	var m1 := s7.spawn(300, 100, 0, 0, 0, false)
	var m2 := s7.spawn(500, 100, 0, 0, 0, false)
	var hs7 := hashes(s7)
	s7.faction_cx[0] = 300.0
	s7.faction_cy[0] = 100.0
	s7.ax.fill(0.0)
	s7.ay.fill(0.0)
	Forces.accumulate(s7, hs7[0])
	t.check(t.approx(s7.ax[m0], 15.0, 1e-3), "case7 ax[0] approx +15.0")
	t.check(t.approx(s7.ax[m2], -15.0, 1e-3), "case7 ax[2] approx -15.0")
	t.check(t.approx(s7.ax[m1], 0.0, 1e-3), "case7 ax[1] approx 0")

	# 8. Cohesion toward captain overrides centroid.
	var s8 := make(8)
	var a8 := s8.spawn(100, 100, 0, 0, 0, false)
	var c8 := s8.spawn(100, 400, 0, 0, 0, true)
	var hs8 := hashes(s8)
	s8.faction_cx[0] = 100.0
	s8.faction_cy[0] = 250.0
	s8.ax.fill(0.0)
	s8.ay.fill(0.0)
	Forces.accumulate(s8, hs8[0])
	t.check(t.approx(s8.ay[a8], 15.0, 1e-3), "case8 ay[0] approx +15.0")
	t.check(t.approx(s8.ax[a8], 0.0, 1e-3), "case8 ax[0] approx 0")
	t.check(t.approx(s8.ay[c8], 0.0, 1e-3), "case8 ay[captain] approx 0")

	# 9. Dead target cleared.
	var s9 := make(9)
	var a9 := s9.spawn(100, 100, 0, 0, 1, false)
	var b9 := s9.spawn(180.0, 100.0, 1, 0, 1, false)
	var hs9 := hashes(s9)
	Forces.retarget(s9, hs9[1], 0)
	s9.state[b9] = BattleState.State.DEAD
	Forces.retarget(s9, hs9[1], 1)
	t.check(s9.target_id[a9] == -1, "case9 target_id[0] == -1 after target death")

	# 10. Coincident separation is finite and nonzero.
	var s10 := make(10)
	var a10 := s10.spawn(100, 100, 0, 0, 0, false)
	var b10 := s10.spawn(100, 100, 0, 0, 0, false)
	var hs10 := hashes(s10)
	s10.faction_cx[0] = 100.0
	s10.faction_cy[0] = 100.0
	s10.ax.fill(0.0)
	s10.ay.fill(0.0)
	Forces.accumulate(s10, hs10[0])
	var v10 := Vector2(s10.ax[a10], s10.ay[a10])
	t.check(t.approx(v10.length(), 120.0, 0.01), "case10 length approx 120.0")
	t.check(is_finite(s10.ax[a10]) and is_finite(s10.ay[a10]), "case10 finite")
	t.check(not (v10.x == 0.0 and v10.y == 0.0), "case10 nonzero")

	t.finish()
	quit()
