extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

const DT := 1.0 / 60.0

func make() -> BattleState:
	return BattleState.new(16, 5)

func fine(s: BattleState) -> SpatialHash:
	var h := SpatialHash.new()
	h.setup(s.arena, 32.0)
	h.build(s.px, s.py, s.state, s.n)
	return h

func _init() -> void:
	var t := TestKit.new()

	# 1. Head-on equal masses
	var s1 := make()
	var a1 := s1.spawn(100.0, 100.0, 0, 0, 1, false)
	var b1 := s1.spawn(110.0, 100.0, 0, 0, 1, false)
	s1.vx[a1] = 10.0
	s1.vx[b1] = -10.0
	Collision.resolve(s1, fine(s1), DT)
	t.check(t.approx(s1.px[a1], 97.0, 1e-3), "case1 px[0]")
	t.check(t.approx(s1.px[b1], 113.0, 1e-3), "case1 px[1]")
	t.check(t.approx(s1.vx[a1], -9.0, 1e-3), "case1 vx[0]")
	t.check(t.approx(s1.vx[b1], 9.0, 1e-3), "case1 vx[1]")
	t.check(t.approx(s1.py[a1], 100.0, 1e-3), "case1 py[0] unchanged")
	t.check(t.approx(s1.py[b1], 100.0, 1e-3), "case1 py[1] unchanged")
	t.check(t.approx(s1.vy[a1], 0.0, 1e-3), "case1 vy[0] unchanged")
	t.check(t.approx(s1.vy[b1], 0.0, 1e-3), "case1 vy[1] unchanged")

	# 2. Spin transfer
	var s2 := make()
	var a2 := s2.spawn(100.0, 100.0, 0, 0, 1, false)
	var b2 := s2.spawn(110.0, 100.0, 0, 0, 1, false)
	s2.spin[a2] = 100.0
	s2.spin[b2] = 50.0
	Collision.resolve(s2, fine(s2), DT)
	t.check(t.approx(s2.spin[a2], 107.5, 1e-3), "case2 spin[0]")
	t.check(t.approx(s2.spin[b2], 42.5, 1e-3), "case2 spin[1]")

	# 3. Cap
	var s3 := make()
	var a3 := s3.spawn(100.0, 100.0, 0, 0, 1, false)
	var b3 := s3.spawn(110.0, 100.0, 0, 0, 1, false)
	s3.spin[a3] = 118.0
	s3.spin[b3] = 50.0
	Collision.resolve(s3, fine(s3), DT)
	t.check(t.approx(s3.spin[a3], 120.0, 1e-3), "case3 spin[0] capped")
	t.check(t.approx(s3.spin[b3], 42.5, 1e-3), "case3 spin[1] full loss")

	# 4. Enemy contact cost, equal spin
	var s4 := make()
	var a4 := s4.spawn(100.0, 100.0, 0, 0, 1, false)
	var b4 := s4.spawn(110.0, 100.0, 1, 0, 1, false)
	Collision.resolve(s4, fine(s4), DT)
	t.check(t.approx(s4.spin[a4], 99.9, 1e-4), "case4 spin[0]")
	t.check(t.approx(s4.spin[b4], 99.9, 1e-4), "case4 spin[1]")

	# 5. Not touching
	var s5 := make()
	var a5 := s5.spawn(100.0, 100.0, 0, 0, 1, false)
	var b5 := s5.spawn(120.0, 100.0, 0, 0, 1, false)
	var px5a := s5.px[a5]
	var px5b := s5.px[b5]
	var vx5a := s5.vx[a5]
	var spin5a := s5.spin[a5]
	var spin5b := s5.spin[b5]
	Collision.resolve(s5, fine(s5), DT)
	t.check(t.approx(s5.px[a5], px5a, 1e-6), "case5 px[0] unchanged")
	t.check(t.approx(s5.px[b5], px5b, 1e-6), "case5 px[1] unchanged")
	t.check(t.approx(s5.vx[a5], vx5a, 1e-6), "case5 vx[0] unchanged")
	t.check(t.approx(s5.spin[a5], spin5a, 1e-6), "case5 spin[0] unchanged")
	t.check(t.approx(s5.spin[b5], spin5b, 1e-6), "case5 spin[1] unchanged")

	# 6. Separating pair
	var s6 := make()
	var a6 := s6.spawn(100.0, 100.0, 0, 0, 1, false)
	var b6 := s6.spawn(110.0, 100.0, 0, 0, 1, false)
	s6.vx[a6] = -10.0
	s6.vx[b6] = 10.0
	Collision.resolve(s6, fine(s6), DT)
	t.check(t.approx(s6.px[a6], 97.0, 1e-3), "case6 px[0]")
	t.check(t.approx(s6.px[b6], 113.0, 1e-3), "case6 px[1]")
	t.check(t.approx(s6.vx[a6], -10.0, 1e-3), "case6 vx[0] unchanged (separating)")
	t.check(t.approx(s6.vx[b6], 10.0, 1e-3), "case6 vx[1] unchanged (separating)")

	# 7. Unequal mass
	var s7 := make()
	var a7 := s7.spawn(100.0, 100.0, 0, 0, 1, false)
	var b7 := s7.spawn(110.0, 100.0, 0, 3, 1, false)
	Collision.resolve(s7, fine(s7), DT)
	t.check(t.approx(s7.px[a7], 93.3804, 0.01), "case7 px[0] unequal mass split")
	t.check(t.approx(s7.px[b7], 111.7804, 0.01), "case7 px[1] unequal mass split")

	# 8. Dead skipped
	var s8 := make()
	var a8 := s8.spawn(100.0, 100.0, 0, 0, 1, false)
	var b8 := s8.spawn(110.0, 100.0, 0, 0, 1, false)
	s8.state[b8] = BattleState.State.DEAD
	var px8a := s8.px[a8]
	var px8b := s8.px[b8]
	Collision.resolve(s8, fine(s8), DT)
	t.check(t.approx(s8.px[a8], px8a, 1e-6), "case8 px[0] unchanged (dead partner)")
	t.check(t.approx(s8.px[b8], px8b, 1e-6), "case8 px[1] unchanged (dead)")

	# 9. Coincident
	var s9 := make()
	var a9 := s9.spawn(100.0, 100.0, 0, 0, 1, false)
	var b9 := s9.spawn(100.0, 100.0, 0, 0, 1, false)
	Collision.resolve(s9, fine(s9), DT)
	var ddx9 := s9.px[b9] - s9.px[a9]
	var ddy9 := s9.py[b9] - s9.py[a9]
	var d9 := sqrt(ddx9 * ddx9 + ddy9 * ddy9)
	t.check(t.approx(d9, 16.0, 1e-3), "case9 coincident separation distance")
	t.check(is_finite(s9.px[a9]) and is_finite(s9.py[a9]) and is_finite(s9.px[b9]) and is_finite(s9.py[b9]), "case9 finite")

	# 10. Determinism
	var s10a := BattleState.new(16, 7)
	var a10a := s10a.spawn(100.0, 100.0, 0, 0, 1, false)
	var b10a := s10a.spawn(100.0, 100.0, 0, 0, 1, false)
	Collision.resolve(s10a, fine(s10a), DT)
	var s10b := BattleState.new(16, 7)
	var a10b := s10b.spawn(100.0, 100.0, 0, 0, 1, false)
	var b10b := s10b.spawn(100.0, 100.0, 0, 0, 1, false)
	Collision.resolve(s10b, fine(s10b), DT)
	t.check(t.approx(s10a.px[a10a], s10b.px[a10b], 1e-6), "case10 px[0] deterministic")
	t.check(t.approx(s10a.py[a10a], s10b.py[a10b], 1e-6), "case10 py[0] deterministic")
	t.check(t.approx(s10a.px[b10a], s10b.px[b10b], 1e-6), "case10 px[1] deterministic")
	t.check(t.approx(s10a.py[b10a], s10b.py[b10b], 1e-6), "case10 py[1] deterministic")

	# 11. Three-way chain
	var s11 := make()
	var a11 := s11.spawn(100.0, 100.0, 0, 0, 1, false)
	var b11 := s11.spawn(110.0, 100.0, 0, 0, 1, false)
	var c11 := s11.spawn(120.0, 100.0, 0, 0, 1, false)
	Collision.resolve(s11, fine(s11), DT)
	t.check(s11.px[a11] < s11.px[b11] and s11.px[b11] < s11.px[c11], "case11 ordering preserved")
	t.check(s11.px[b11] - s11.px[a11] >= 11.0 - 1e-6, "case11 gap a-b >= 11.0")
	t.check(s11.px[c11] - s11.px[b11] >= 11.0 - 1e-6, "case11 gap b-c >= 11.0")

	t.finish()
	quit()
