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
	t.check(t.approx(s3.ax[a3], 20.0, 1e-3), "case3 ax[0] approx 20.0")
	t.check(t.approx(s3.ay[a3], 0.0, 1e-3), "case3 ay[0] approx 0")

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
	# §16: SEPARATION_RANGE_MULT now 2.0 (was 1.2) -> range 32 not 19.2, smag 82.5 not 57.5.
	t.check(t.approx(s5.ax[a5], -82.5, 0.05), "case5 ax[0] approx -82.5")
	t.check(t.approx(s5.ax[b5], 82.5, 0.05), "case5 ax[1] approx 82.5")
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
	t.check(t.approx(s6.ax[a6], 20.0, 1e-3), "case6 ax[0] approx 20.0")

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

	# 11. Advance magnitude and direction.
	var s11 := make(11)
	var a11 := s11.spawn(100, 100, 0, 0, 0, false)
	var b11 := s11.spawn(400, 300, 1, 0, 0, false)
	var hs11 := hashes(s11)
	s11.faction_cx[0] = 100.0
	s11.faction_cy[0] = 100.0
	s11.faction_cx[1] = 400.0
	s11.faction_cy[1] = 300.0
	s11.ax.fill(0.0)
	s11.ay.fill(0.0)
	Forces.accumulate(s11, hs11[0])
	var dir_11 := Vector2(300.0, 200.0).normalized()
	t.check(t.approx(s11.ax[a11], 20.0 * dir_11.x, 1e-3), "case11 ax[0] approx 16.641")
	t.check(t.approx(s11.ay[a11], 20.0 * dir_11.y, 1e-3), "case11 ay[0] approx 11.094")
	var dir_11_neg := Vector2(-300.0, -200.0).normalized()
	t.check(t.approx(s11.ax[b11], 20.0 * dir_11_neg.x, 1e-3), "case11 ax[1] approx -16.641")
	t.check(t.approx(s11.ay[b11], 20.0 * dir_11_neg.y, 1e-3), "case11 ay[1] approx -11.094")

	# 12. Target suppresses advance.
	var s12 := make(12)
	var a12 := s12.spawn(100, 100, 0, 0, 1, false)
	var b12 := s12.spawn(180.0, 100.0, 1, 0, 1, false)
	var hs12 := hashes(s12)
	Forces.retarget(s12, hs12[1], 0)
	s12.faction_cx[0] = 100.0
	s12.faction_cy[0] = 100.0
	s12.faction_cx[1] = 180.0
	s12.faction_cy[1] = 100.0
	s12.ax.fill(0.0)
	s12.ay.fill(0.0)
	Forces.accumulate(s12, hs12[0])
	t.check(t.approx(s12.ax[a12], 32.0, 1e-3), "case12 ax[0] approx 32.0")

	# 13. Retreat suppresses advance.
	var s13 := make(13)
	var a13 := s13.spawn(100, 100, 0, 0, 1, false)
	var b13 := s13.spawn(400, 100, 1, 0, 1, false)
	var hs13 := hashes(s13)
	s13.state[a13] = BattleState.State.RETREAT
	s13.target_id[a13] = -1
	s13.faction_cx[0] = 100.0
	s13.faction_cy[0] = 100.0
	s13.faction_cx[1] = 400.0
	s13.faction_cy[1] = 100.0
	s13.ax.fill(0.0)
	s13.ay.fill(0.0)
	Forces.accumulate(s13, hs13[0])
	t.check(t.approx(s13.ax[a13], -40.0, 1e-3), "case13 ax[0] approx -40.0")

	# 14. No live enemy → no advance.
	var s14 := make(14)
	var a14 := s14.spawn(100, 100, 0, 0, 1, false)
	var b14 := s14.spawn(400, 100, 1, 0, 1, false)
	var hs14 := hashes(s14)
	s14.faction_cx[0] = 100.0
	s14.faction_cy[0] = 100.0
	s14.faction_cx[1] = 400.0
	s14.faction_cy[1] = 100.0
	s14.faction_alive[1] = 0
	s14.ax.fill(0.0)
	s14.ay.fill(0.0)
	Forces.accumulate(s14, hs14[0])
	t.check(t.approx(s14.ax[a14], 0.0, 1e-3), "case14 ax[0] approx 0.0")

	# 15. Nearest enemy faction wins, then update.
	var s15 := make(15)
	var a15 := s15.spawn(100, 100, 0, 0, 1, false)
	var b15 := s15.spawn(400, 100, 1, 0, 1, false)
	var c15 := s15.spawn(100, 400, 2, 0, 1, false)
	var hs15 := hashes(s15)
	s15.faction_cx[0] = 100.0
	s15.faction_cy[0] = 100.0
	s15.faction_cx[1] = 400.0
	s15.faction_cy[1] = 100.0
	s15.faction_cx[2] = 100.0
	s15.faction_cy[2] = 400.0
	s15.ax.fill(0.0)
	s15.ay.fill(0.0)
	Forces.accumulate(s15, hs15[0])
	t.check(t.approx(s15.ax[a15], 20.0, 1e-3), "case15a ax[0] approx 20.0")
	t.check(t.approx(s15.ay[a15], 0.0, 1e-3), "case15a ay[0] approx 0")
	# Move C nearer
	s15.px[c15] = 100.0
	s15.py[c15] = 350.0
	s15.faction_cx[2] = 100.0
	s15.faction_cy[2] = 350.0
	s15.ax.fill(0.0)
	s15.ay.fill(0.0)
	Forces.accumulate(s15, hs15[0])
	t.check(t.approx(s15.ax[a15], 0.0, 1e-3), "case15b ax[0] approx 0")
	t.check(t.approx(s15.ay[a15], 20.0, 1e-3), "case15b ay[0] approx 20.0")

	# §16.3 retarget cases (i faction 0 at (100,100); enemies faction 1).

	# retarget1/2: scored retarget prefers j2 (unengaged) over nearest j1
	# (already worked by ally k), then attackers reflects the new pick.
	var s16 := make(16)
	var i16 := s16.spawn(100, 100, 0, 0, 1, false)
	var j1_16 := s16.spawn(140, 100, 1, 0, 1, false)
	var j2_16 := s16.spawn(160, 100, 1, 0, 1, false)
	var k16 := s16.spawn(100, 130, 0, 0, 1, false)
	var hs16 := hashes(s16)
	s16.target_id[k16] = j1_16
	Forces.retarget(s16, hs16[1], 0)
	t.check(s16.target_id[i16] == j2_16, "retarget1 target_id[i] == j2 (scored: j1 13 > j2 7.5)")
	t.check(s16.attackers[j1_16] == 1, "retarget2 attackers[j1] == 1")
	t.check(s16.attackers[j2_16] == 1, "retarget2 attackers[j2] == 1")

	# retarget3: outmatched target (power 225 > 1.25*125) wants 2 -> no penalty, picks j1.
	var s17 := make(17)
	var i17 := s17.spawn(100, 100, 0, 0, 1, false)
	var j1_17 := s17.spawn(140, 100, 1, 0, 1, false)
	var j2_17 := s17.spawn(160, 100, 1, 0, 1, false)
	var k17 := s17.spawn(100, 130, 0, 0, 1, false)
	var hs17 := hashes(s17)
	s17.target_id[k17] = j1_17
	s17.spin[j1_17] = 200.0
	Forces.retarget(s17, hs17[1], 0)
	t.check(s17.target_id[i17] == j1_17, "retarget3 outmatched picks j1 (score 5)")

	# retarget4: finish-off bonus (hp[j1] below FINISH_HP_FRAC) beats a farther, healthy j2.
	var s18 := make(18)
	var i18 := s18.spawn(100, 100, 0, 0, 1, false)
	var j1_18 := s18.spawn(140, 100, 1, 0, 1, false)
	var j2_18 := s18.spawn(190, 100, 1, 0, 1, false)
	var k18 := s18.spawn(100, 130, 0, 0, 1, false)
	var hs18 := hashes(s18)
	s18.target_id[k18] = j1_18
	s18.hp[j1_18] = 30.0
	Forces.retarget(s18, hs18[1], 0)
	t.check(s18.target_id[i18] == j1_18, "retarget4 finish-off picks j1 (5+8-4=9 < 11.25)")

	# retarget5: sticky bonus keeps the current target j2 over a nearer j1.
	var s19 := make(19)
	var i19 := s19.spawn(100, 100, 0, 0, 1, false)
	var j1_19 := s19.spawn(140, 100, 1, 0, 1, false)
	var j2_19 := s19.spawn(148, 100, 1, 0, 1, false)
	var hs19 := hashes(s19)
	s19.target_id[i19] = j2_19
	Forces.retarget(s19, hs19[1], 0)
	t.check(s19.target_id[i19] == j2_19, "retarget5 sticky keeps j2 (6-2=4 < 5)")

	# retarget6: captain wants +1 attacker, absorbing the crowd penalty; picks j1.
	var s20 := make(20)
	var i20 := s20.spawn(100, 100, 0, 0, 1, false)
	var j1_20 := s20.spawn(140, 100, 1, 0, 1, true)
	var j2_20 := s20.spawn(160, 100, 1, 0, 1, false)
	var k20 := s20.spawn(100, 130, 0, 0, 1, false)
	var hs20 := hashes(s20)
	s20.target_id[k20] = j1_20
	Forces.retarget(s20, hs20[1], 0)
	t.check(s20.target_id[i20] == j1_20, "retarget6 captain picks j1 (want 2, no penalty, score 5)")

	# retarget7: a RETREAT ally's target is never counted in attackers.
	var s21 := make(21)
	var i21 := s21.spawn(100, 100, 0, 0, 1, false)
	var j1_21 := s21.spawn(140, 100, 1, 0, 1, false)
	var j2_21 := s21.spawn(160, 100, 1, 0, 1, false)
	var k21 := s21.spawn(100, 130, 0, 0, 1, false)
	var hs21 := hashes(s21)
	s21.target_id[k21] = j1_21
	s21.state[k21] = BattleState.State.RETREAT
	Forces.retarget(s21, hs21[1], 0)
	t.check(s21.attackers[j1_21] == 1, "retarget7 attackers[j1] == 1 (i counted, RETREAT ally not)")
	t.check(s21.target_id[i21] == j1_21, "retarget7 i picks j1 (nearest, no crowd)")

	# §16.3 accumulate cases (lone faction-0 marble i unless stated).

	# accum8: no target -> advance toward the enemy centroid, no spread offset.
	var s22 := make(22)
	var i22 := s22.spawn(400, 450, 0, 0, 1, false)
	var hs22 := hashes(s22)
	s22.faction_alive[1] = 1
	s22.faction_count = 2
	s22.faction_cx[0] = 400.0
	s22.faction_cy[0] = 450.0
	s22.faction_cx[1] = 1200.0
	s22.faction_cy[1] = 450.0
	s22.ax.fill(0.0)
	s22.ay.fill(0.0)
	Forces.accumulate(s22, hs22[0])
	t.check(t.approx(s22.ax[i22], 20.0, 1e-3), "accum8 ax approx K_ADVANCE 20.0")
	t.check(t.approx(s22.ay[i22], 0.0, 1e-3), "accum8 ay approx 0")

	# accum9: cruise cap (v_par 80 >= 70) drops the advance drive entirely.
	var s23 := make(23)
	var i23 := s23.spawn(400, 450, 0, 0, 1, false)
	var hs23 := hashes(s23)
	s23.faction_alive[1] = 1
	s23.faction_cx[0] = 400.0
	s23.faction_cy[0] = 450.0
	s23.faction_cx[1] = 1200.0
	s23.faction_cy[1] = 450.0
	s23.vx[i23] = 80.0
	s23.ax.fill(0.0)
	s23.ay.fill(0.0)
	Forces.accumulate(s23, hs23[0])
	t.check(t.approx(s23.ax[i23], 0.0, 1e-3), "accum9 ax dropped by cruise cap")
	t.check(t.approx(s23.ay[i23], 0.0, 1e-3), "accum9 ay dropped by cruise cap")

	# accum10: lateral offset from own centroid spreads the aim point along the line.
	var s24 := make(24)
	var i24 := s24.spawn(400, 250, 0, 0, 1, false)
	var hs24 := hashes(s24)
	s24.faction_alive[1] = 1
	s24.faction_count = 2
	s24.faction_cx[0] = 400.0
	s24.faction_cy[0] = 450.0
	s24.faction_cx[1] = 1200.0
	s24.faction_cy[1] = 450.0
	s24.ax.fill(0.0)
	s24.ay.fill(0.0)
	Forces.accumulate(s24, hs24[0])
	t.check(t.approx(s24.ax[i24], 20.0, 1e-3), "accum10 ax approx 20.0 (spread aim)")
	t.check(t.approx(s24.ay[i24], 15.0, 1e-3), "accum10 ay approx 15.0 (spread + cohesion)")

	# accum11: within strike range (dist 40 < 48) -> charge cap allows the attraction drive.
	var s25 := make(25)
	var i25 := s25.spawn(400, 450, 0, 0, 1, false)
	var t25 := s25.spawn(440, 450, 1, 0, 1, false)
	var hs25 := hashes(s25)
	s25.target_id[i25] = t25
	s25.vx[i25] = 150.0
	s25.ax.fill(0.0)
	s25.ay.fill(0.0)
	Forces.accumulate(s25, hs25[0])
	t.check(t.approx(s25.ax[i25], 32.0, 1e-3), "accum11 charge ax approx K_ATTR*1*0.8=32")

	# accum12: too far to charge (dist 100 >= 48) -> cruise cap (70) drops the drive.
	var s26 := make(26)
	var i26 := s26.spawn(400, 450, 0, 0, 1, false)
	var t26 := s26.spawn(500, 450, 1, 0, 1, false)
	var hs26 := hashes(s26)
	s26.target_id[i26] = t26
	s26.vx[i26] = 150.0
	s26.ax.fill(0.0)
	s26.ay.fill(0.0)
	Forces.accumulate(s26, hs26[0])
	t.check(t.approx(s26.ax[i26], 0.0, 1e-3), "accum12 ax dropped, cruise cap 70 (dist 100 >= 48)")

	# accum13: recoiling replaces attraction with a back-off term.
	var s27 := make(27)
	var i27 := s27.spawn(400, 450, 0, 0, 1, false)
	var t27 := s27.spawn(440, 450, 1, 0, 1, false)
	var hs27 := hashes(s27)
	s27.target_id[i27] = t27
	s27.recoil_t[i27] = 0.3
	s27.ax.fill(0.0)
	s27.ay.fill(0.0)
	Forces.accumulate(s27, hs27[0])
	t.check(t.approx(s27.ax[i27], -25.0, 1e-3), "accum13 recoil ax approx -K_RECOIL=-25, no attraction")

	# accum14: cohesion only fires when untargeted.
	var s28 := make(28)
	var cap28 := s28.spawn(100, 450, 0, 0, 1, true)
	var i28 := s28.spawn(400, 450, 0, 0, 1, false)
	var t28 := s28.spawn(440, 450, 1, 0, 1, false)
	var hs28 := hashes(s28)
	s28.target_id[i28] = t28
	s28.ax.fill(0.0)
	s28.ay.fill(0.0)
	Forces.accumulate(s28, hs28[0])
	t.check(t.approx(s28.ax[i28], 32.0, 1e-3), "accum14a targeted: attraction only, no cohesion")
	s28.target_id[i28] = -1
	s28.faction_alive[1] = 0
	s28.ax.fill(0.0)
	s28.ay.fill(0.0)
	Forces.accumulate(s28, hs28[0])
	t.check(s28.ax[i28] < 0.0, "accum14b untargeted, no enemy alive: cohesion pulls toward captain")

	# accum15: RETREAT speed cap (v_par 120 >= 110) drops the home pull.
	var s29 := make(29)
	var i29 := s29.spawn(400, 450, 0, 0, 1, false)
	var hs29 := hashes(s29)
	s29.state[i29] = BattleState.State.RETREAT
	s29.vx[i29] = -120.0
	s29.ax.fill(0.0)
	s29.ay.fill(0.0)
	Forces.accumulate(s29, hs29[0])
	t.check(t.approx(s29.ax[i29], 0.0, 1e-3), "accum15 retreat cap drops home pull (v_par 120 >= 110)")

	# accum16: separation at range 2.0 (32) reaches a 30-apart pair; 1.2 range (19.2) would not.
	var s30 := make(30)
	var i30 := s30.spawn(400, 450, 0, 0, 1, false)
	var j30 := s30.spawn(430, 450, 0, 0, 1, false)
	var hs30 := hashes(s30)
	s30.faction_cx[0] = 415.0
	s30.faction_cy[0] = 450.0
	s30.ax.fill(0.0)
	s30.ay.fill(0.0)
	Forces.accumulate(s30, hs30[0])
	t.check(s30.ax[i30] < 0.0 and s30.ax[j30] > 0.0, "accum16 separation at range 2.0 pushes both apart (guard: 1.2 range 19.2 would give 0)")

	t.finish()
	quit()
