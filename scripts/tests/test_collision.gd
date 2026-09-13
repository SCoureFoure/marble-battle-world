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

	# §15.5 enemy clash / ally spin boost. Two rank-0 marbles radius 8 mass 64,
	# overlapping by 2 on the x axis, i at x=100, j at x=114; spins default 100.
	Damage.force_mult = 1.0

	# 12. Enemy clash, vrel = -100: kick + body damage each way
	var s12 := make()
	var a12 := s12.spawn(100.0, 100.0, 0, 0, 1, false)
	var b12 := s12.spawn(114.0, 100.0, 1, 0, 1, false)
	s12.vx[a12] = 50.0
	s12.vx[b12] = -50.0
	Collision.resolve(s12, fine(s12), DT)
	t.check(t.approx(s12.vx[a12], -100.0, 1e-3), "case12 vx[i] clash kick")  # M8 pace
	t.check(t.approx(s12.vx[b12], 100.0, 1e-3), "case12 vx[j] clash kick")  # M8 pace
	t.check(t.approx(s12.hp[a12], 97.0, 1e-3), "case12 hp[i]")
	t.check(t.approx(s12.hp[b12], 97.0, 1e-3), "case12 hp[j]")
	t.check(t.approx(s12.spin[a12], 96.0, 1e-3), "case12 spin[i]")
	t.check(t.approx(s12.spin[b12], 96.0, 1e-3), "case12 spin[j]")
	t.check(t.approx(s12.bump_cd[a12], 0.35, 1e-3), "case12 bump_cd[i]")
	t.check(t.approx(s12.bump_cd[b12], 0.35, 1e-3), "case12 bump_cd[j]")
	t.check(s12.events.size() == 2, "case12 events.size")
	t.check(s12.events[0][0] == BattleState.Event.BUMP and s12.events[0][1] == a12 and s12.events[0][2] == b12 and t.approx(s12.events[0][3], 3.0, 1e-3), "case12 events[0] i->j")
	t.check(s12.events[1][0] == BattleState.Event.BUMP and s12.events[1][1] == b12 and s12.events[1][2] == a12 and t.approx(s12.events[1][3], 3.0, 1e-3), "case12 events[1] j->i")

	# 13. Enemy clash below CLASH_MIN_VREL, vrel = -10: no kick, no damage, no events
	var s13 := make()
	var a13 := s13.spawn(100.0, 100.0, 0, 0, 1, false)
	var b13 := s13.spawn(114.0, 100.0, 1, 0, 1, false)
	s13.vx[a13] = 5.0
	s13.vx[b13] = -5.0
	Collision.resolve(s13, fine(s13), DT)
	t.check(t.approx(s13.hp[a13], 100.0, 1e-6), "case13 hp[i] unchanged")
	t.check(t.approx(s13.hp[b13], 100.0, 1e-6), "case13 hp[j] unchanged")
	t.check(t.approx(s13.spin[a13], 100.0, 1e-6), "case13 spin[i] unchanged")
	t.check(t.approx(s13.spin[b13], 100.0, 1e-6), "case13 spin[j] unchanged")
	t.check(s13.events.size() == 0, "case13 no events")

	# 14. Bump cooldown blocks only the dealer on cooldown; kick still applies
	var s14 := make()
	var a14 := s14.spawn(100.0, 100.0, 0, 0, 1, false)
	var b14 := s14.spawn(114.0, 100.0, 1, 0, 1, false)
	s14.vx[a14] = 50.0
	s14.vx[b14] = -50.0
	s14.bump_cd[a14] = 0.2
	Collision.resolve(s14, fine(s14), DT)
	t.check(t.approx(s14.vx[a14], -100.0, 1e-3), "case14 vx[i] kick still applies")  # M8 pace
	t.check(t.approx(s14.vx[b14], 100.0, 1e-3), "case14 vx[j] kick still applies")  # M8 pace
	t.check(s14.events.size() == 1, "case14 only j deals damage")
	t.check(s14.events[0][0] == BattleState.Event.BUMP and s14.events[0][1] == b14 and s14.events[0][2] == a14 and t.approx(s14.events[0][3], 3.0, 1e-3), "case14 events[0]")
	t.check(t.approx(s14.spin[a14], 100.0, 1e-6), "case14 spin[i] unchanged")
	t.check(t.approx(s14.spin[b14], 96.0, 1e-3), "case14 spin[j]")

	# 15. RETREAT marble still bounces but deals no clash damage
	var s15 := make()
	var a15 := s15.spawn(100.0, 100.0, 0, 0, 1, false)
	var b15 := s15.spawn(114.0, 100.0, 1, 0, 1, false)
	s15.vx[a15] = 50.0
	s15.vx[b15] = -50.0
	s15.state[a15] = BattleState.State.RETREAT
	Collision.resolve(s15, fine(s15), DT)
	t.check(t.approx(s15.vx[a15], -100.0, 1e-3), "case15 vx[i] still bounces")  # M8 pace
	t.check(t.approx(s15.vx[b15], 100.0, 1e-3), "case15 vx[j] still bounces")  # M8 pace
	t.check(s15.events.size() == 1, "case15 only j deals damage")
	t.check(s15.events[0][0] == BattleState.Event.BUMP and s15.events[0][1] == b15 and s15.events[0][2] == a15, "case15 events[0] j is dealer")

	# 16. Spin scales both the kick and the body damage
	var s16 := make()
	var a16 := s16.spawn(100.0, 100.0, 0, 0, 1, false)
	var b16 := s16.spawn(114.0, 100.0, 1, 0, 1, false)
	s16.vx[a16] = 50.0
	s16.vx[b16] = -50.0
	s16.spin[a16] = 50.0
	s16.spin[b16] = 50.0
	Collision.resolve(s16, fine(s16), DT)
	t.check(t.approx(s16.vx[a16], -72.5, 1e-3), "case16 vx[i] scaled kick")  # M8 pace
	t.check(t.approx(s16.hp[a16], 98.5, 1e-3), "case16 hp[i] scaled damage")
	t.check(t.approx(s16.hp[b16], 98.5, 1e-3), "case16 hp[j] scaled damage")

	# 17. Kill mid-pair: the victim deals no damage back
	var s17 := make()
	var a17 := s17.spawn(100.0, 100.0, 0, 0, 1, false)
	var b17 := s17.spawn(114.0, 100.0, 1, 0, 1, false)
	s17.vx[a17] = 50.0
	s17.vx[b17] = -50.0
	s17.hp[b17] = 2.0
	Collision.resolve(s17, fine(s17), DT)
	t.check(s17.events.size() == 2, "case17 events.size")
	t.check(s17.events[0][0] == BattleState.Event.BUMP and s17.events[0][1] == a17 and s17.events[0][2] == b17 and t.approx(s17.events[0][3], 3.0, 1e-3), "case17 events[0] i's clash")
	t.check(s17.events[1][0] == BattleState.Event.KILL and s17.events[1][1] == a17 and s17.events[1][2] == b17, "case17 events[1] KILL")
	t.check(s17.state[b17] == BattleState.State.DEAD, "case17 j dead")

	# 18. Ally bounce, vrel = -100: spin boost each, no damage, no kick
	var s18 := make()
	var a18 := s18.spawn(100.0, 100.0, 0, 0, 1, false)
	var b18 := s18.spawn(114.0, 100.0, 0, 0, 1, false)
	s18.vx[a18] = 50.0
	s18.vx[b18] = -50.0
	Collision.resolve(s18, fine(s18), DT)
	t.check(t.approx(s18.vx[a18], -45.0, 1e-3), "case18 vx[i] restitution only, no kick")
	t.check(t.approx(s18.vx[b18], 45.0, 1e-3), "case18 vx[j] restitution only, no kick")
	t.check(t.approx(s18.hp[a18], 100.0, 1e-6), "case18 hp[i] unchanged")
	t.check(t.approx(s18.hp[b18], 100.0, 1e-6), "case18 hp[j] unchanged")
	t.check(t.approx(s18.bump_cd[a18], 0.0, 1e-6), "case18 bump_cd[i] unchanged")
	t.check(t.approx(s18.spin[a18], 105.0, 1e-3), "case18 spin[i]")
	t.check(t.approx(s18.spin[b18], 105.0, 1e-3), "case18 spin[j]")
	t.check(s18.events.size() == 1, "case18 events.size")
	t.check(s18.events[0][0] == BattleState.Event.BOOST and s18.events[0][1] == a18 and s18.events[0][2] == b18 and t.approx(s18.events[0][3], 5.0, 1e-3), "case18 events[0]")

	# 19. Ally bounce below ALLY_MIN_VREL, vrel = -60: no boost, no events
	var s19 := make()
	var a19 := s19.spawn(100.0, 100.0, 0, 0, 1, false)
	var b19 := s19.spawn(114.0, 100.0, 0, 0, 1, false)
	s19.vx[a19] = 30.0
	s19.vx[b19] = -30.0
	Collision.resolve(s19, fine(s19), DT)
	t.check(s19.events.size() == 0, "case19 no events")
	t.check(t.approx(s19.spin[a19], 100.0, 1e-6), "case19 spin[i] unchanged")
	t.check(t.approx(s19.spin[b19], 100.0, 1e-6), "case19 spin[j] unchanged")

	# 20. Ally bounce gain cap, vrel = -400: gain capped at ALLY_SPIN_GAIN_MAX,
	# spin further capped at spin_cap
	var s20 := make()
	var a20 := s20.spawn(100.0, 100.0, 0, 0, 1, false)
	var b20 := s20.spawn(114.0, 100.0, 0, 0, 1, false)
	s20.vx[a20] = 200.0
	s20.vx[b20] = -200.0
	s20.spin_cap[a20] = 102.0
	Collision.resolve(s20, fine(s20), DT)
	t.check(s20.events[0][0] == BattleState.Event.BOOST and t.approx(s20.events[0][3], 8.0, 1e-3), "case20 gain capped at ALLY_SPIN_GAIN_MAX")
	t.check(t.approx(s20.spin[a20], 102.0, 1e-3), "case20 spin[i] capped at spin_cap")

	# 21. Dead partner already DEAD before resolve, still present in the fine hash
	var s21 := make()
	var a21 := s21.spawn(100.0, 100.0, 0, 0, 1, false)
	var b21 := s21.spawn(114.0, 100.0, 1, 0, 1, false)
	var h21 := fine(s21)
	s21.state[b21] = BattleState.State.DEAD
	s21.vx[a21] = 50.0
	s21.vx[b21] = -50.0
	var px21a := s21.px[a21]
	var px21b := s21.px[b21]
	var spin21a := s21.spin[a21]
	Collision.resolve(s21, h21, DT)
	t.check(t.approx(s21.px[a21], px21a, 1e-6), "case21 px[i] unchanged (dead partner in hash)")
	t.check(t.approx(s21.px[b21], px21b, 1e-6), "case21 px[j] unchanged")
	t.check(t.approx(s21.vx[a21], 50.0, 1e-6), "case21 vx[i] unchanged")
	t.check(t.approx(s21.spin[a21], spin21a, 1e-6), "case21 spin[i] unchanged")
	t.check(s21.events.size() == 0, "case21 no events")

	# 22. Ally bounce, boost_cd_i active: no spin change, no event, boost_cd unchanged
	var s22 := make()
	var a22 := s22.spawn(100.0, 100.0, 0, 0, 1, false)
	var b22 := s22.spawn(114.0, 100.0, 0, 0, 1, false)
	s22.vx[a22] = 50.0
	s22.vx[b22] = -50.0
	s22.boost_cd[a22] = 0.5
	Collision.resolve(s22, fine(s22), DT)
	t.check(t.approx(s22.spin[a22], 100.0, 1e-6), "case22 spin[i] unchanged (boost_cd active)")
	t.check(t.approx(s22.spin[b22], 100.0, 1e-6), "case22 spin[j] unchanged (boost_cd active)")
	t.check(s22.events.size() == 0, "case22 no events (boost_cd active)")
	t.check(t.approx(s22.boost_cd[a22], 0.5, 1e-6), "case22 boost_cd[i] unchanged")
	t.check(t.approx(s22.boost_cd[b22], 0.0, 1e-6), "case22 boost_cd[j] unchanged")

	# 23. Ally bounce, both boost_cd 0: both spin +5, both boost_cd == 1.5, one BOOST event
	var s23 := make()
	var a23 := s23.spawn(100.0, 100.0, 0, 0, 1, false)
	var b23 := s23.spawn(114.0, 100.0, 0, 0, 1, false)
	s23.vx[a23] = 50.0
	s23.vx[b23] = -50.0
	Collision.resolve(s23, fine(s23), DT)
	t.check(t.approx(s23.spin[a23], 105.0, 1e-3), "case23 spin[i] +5")
	t.check(t.approx(s23.spin[b23], 105.0, 1e-3), "case23 spin[j] +5")
	t.check(t.approx(s23.boost_cd[a23], 1.5, 1e-6), "case23 boost_cd[i] == 1.5")
	t.check(t.approx(s23.boost_cd[b23], 1.5, 1e-6), "case23 boost_cd[j] == 1.5")
	t.check(s23.events.size() == 1, "case23 one BOOST event")
	t.check(s23.events[0][0] == BattleState.Event.BOOST, "case23 event is BOOST")

	# 24. Enemy clash never reads or writes boost_cd
	var s24 := make()
	var a24 := s24.spawn(100.0, 100.0, 0, 0, 1, false)
	var b24 := s24.spawn(114.0, 100.0, 1, 0, 1, false)
	s24.vx[a24] = 50.0
	s24.vx[b24] = -50.0
	s24.boost_cd[a24] = 0.7
	s24.boost_cd[b24] = 0.7
	Collision.resolve(s24, fine(s24), DT)
	t.check(t.approx(s24.boost_cd[a24], 0.7, 1e-6), "case24 boost_cd[i] unaffected by enemy clash")
	t.check(t.approx(s24.boost_cd[b24], 0.7, 1e-6), "case24 boost_cd[j] unaffected by enemy clash")

	Damage.force_mult = -1.0

	t.finish()
	quit()
