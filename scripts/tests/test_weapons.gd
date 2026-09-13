extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

const DT := Tuning.DT

func make() -> BattleState:
	return BattleState.new(16, 5)

func hash_for(s: BattleState) -> SpatialHash:
	var h := SpatialHash.new()
	h.setup(s.arena, 16.0)
	h.build(s.px, s.py, s.state, s.n)
	return h

func _init() -> void:
	var t := TestKit.new()

	# 1. Normal hit: dmg = WEAPON_DMG[1]*WEAPON_DMG_MULT*(spin/SPIN_REF)*RANK_MULT[0]*force_mult = 8*1.5 = 12.0
	Damage.force_mult = 1.0
	var s1 := make()
	var a1 := s1.spawn(100.0, 100.0, 0, 0, 1, false)
	var b1 := s1.spawn(118.0, 100.0, 1, 0, 1, false)
	s1.weapon_angle[a1] = 0.0
	s1.weapon_angle[b1] = 0.0
	s1.target_id[a1] = b1
	Weapons.tick(s1, hash_for(s1), DT)
	t.check(t.approx(s1.hp[b1], 88.0, 1e-4), "case1 hp[B]")
	t.check(t.approx(s1.spin[a1], 94.0, 1e-4), "case1 spin[A] (94.0, decay not in Weapons)")
	t.check(t.approx(s1.spin[b1], 90.0, 1e-4), "case1 spin[B]")
	t.check(t.approx(s1.hit_cd[a1], 0.30, 1e-4), "case1 hit_cd[A]")
	t.check(s1.events.size() == 1, "case1 events.size")
	t.check(s1.events[0].size() == 4, "case1 events[0] has 4 elements")
	t.check(s1.events[0][0] == BattleState.Event.HIT and s1.events[0][1] == a1 and s1.events[0][2] == b1, "case1 events[0] type/actor/target")
	t.check(t.approx(s1.events[0][3], 12.0, 1e-4), "case1 events[0] dmg")

	# 2. force_mult = 1.5: dmg = 8*1.5*1.5 = 18.0
	Damage.force_mult = 1.5
	var s2 := make()
	var a2 := s2.spawn(100.0, 100.0, 0, 0, 1, false)
	var b2 := s2.spawn(118.0, 100.0, 1, 0, 1, false)
	s2.weapon_angle[a2] = 0.0
	s2.weapon_angle[b2] = 0.0
	s2.target_id[a2] = b2
	Weapons.tick(s2, hash_for(s2), DT)
	t.check(t.approx(s2.hp[b2], 82.0, 1e-4), "case2 hp[B] force_mult 1.5")

	# 3. Knockback uses pre-cost spins; recoil is RECOIL_FRAC of it, opposite direction
	Damage.force_mult = 1.0
	var s3 := make()
	var a3 := s3.spawn(100.0, 100.0, 0, 0, 1, false)
	var b3 := s3.spawn(118.0, 100.0, 1, 0, 1, false)
	s3.weapon_angle[a3] = 0.0
	s3.weapon_angle[b3] = 0.0
	s3.target_id[a3] = b3
	Weapons.tick(s3, hash_for(s3), DT)
	t.check(t.approx(s3.vx[b3], 120.0, 1e-3), "case3 vx[B] knockback")
	t.check(t.approx(s3.vy[b3], 0.0, 0.5), "case3 vy[B] knockback")
	t.check(t.approx(s3.vx[a3], -60.0, 1e-3), "case3 vx[A] recoil")
	t.check(t.approx(s3.vy[a3], 0.0, 0.5), "case3 vy[A] recoil")

	# 4. Shield victim facing attacker halves damage: 12 * SHIELD_DMG_MULT(0.5) = 6.0
	Damage.force_mult = 1.0
	var s4 := make()
	var a4 := s4.spawn(100.0, 100.0, 0, 0, 1, false)
	var b4 := s4.spawn(118.0, 100.0, 1, 0, 4, false)
	s4.weapon_angle[a4] = 0.0
	s4.weapon_angle[b4] = PI
	s4.target_id[a4] = b4
	Weapons.tick(s4, hash_for(s4), DT)
	t.check(t.approx(s4.hp[b4], 94.0, 1e-3), "case4 hp[B] shield blocks")
	t.check(t.approx(s4.events[0][3], 6.0, 1e-3), "case4 events[0] dmg halved")

	# 4b. Shield facing away: no reduction (kept: shield category)
	Damage.force_mult = 1.0
	var s4b := make()
	var a4b := s4b.spawn(100.0, 100.0, 0, 0, 1, false)
	var b4b := s4b.spawn(118.0, 100.0, 1, 0, 4, false)
	s4b.weapon_angle[a4b] = 0.0
	s4b.weapon_angle[b4b] = 0.0
	s4b.target_id[a4b] = b4b
	Weapons.tick(s4b, hash_for(s4b), DT)
	t.check(t.approx(s4b.hp[b4b], 88.0, 1e-3), "case4b hp[B] shield not facing")

	# 5. Dagger, force_mult = -1 (real rng draws through Damage.roll): determinism over 60 ticks
	Damage.force_mult = -1.0
	var s5a := make()
	var a5a := s5a.spawn(100.0, 100.0, 0, 0, 0, false)
	var b5a := s5a.spawn(112.0, 100.0, 1, 0, 0, false)
	s5a.weapon_angle[a5a] = 0.0
	s5a.weapon_angle[b5a] = 0.0
	s5a.target_id[a5a] = b5a
	s5a.target_id[b5a] = a5a
	for _t5a in range(60):
		Weapons.tick(s5a, hash_for(s5a), DT)

	var s5b := make()
	var a5b := s5b.spawn(100.0, 100.0, 0, 0, 0, false)
	var b5b := s5b.spawn(112.0, 100.0, 1, 0, 0, false)
	s5b.weapon_angle[a5b] = 0.0
	s5b.weapon_angle[b5b] = 0.0
	s5b.target_id[a5b] = b5b
	s5b.target_id[b5b] = a5b
	for _t5b in range(60):
		Weapons.tick(s5b, hash_for(s5b), DT)

	t.check(t.approx(s5a.hp[a5a], s5b.hp[a5b], 1e-6), "case5 hp[A] deterministic")
	t.check(t.approx(s5a.hp[b5a], s5b.hp[b5b], 1e-6), "case5 hp[B] deterministic")
	t.check(t.approx(s5a.spin[a5a], s5b.spin[a5b], 1e-6), "case5 spin[A] deterministic")
	t.check(t.approx(s5a.spin[b5a], s5b.spin[b5b], 1e-6), "case5 spin[B] deterministic")

	# 6. Spin floor: a spin 8 -> RPM_MIN after hit, b spin 12 -> RPM_MIN after hit
	Damage.force_mult = 1.0
	var s6 := make()
	var a6 := s6.spawn(100.0, 100.0, 0, 0, 1, false)
	var b6 := s6.spawn(118.0, 100.0, 1, 0, 1, false)
	s6.weapon_angle[a6] = 0.0
	s6.weapon_angle[b6] = 0.0
	s6.spin[a6] = 8.0
	s6.spin[b6] = 12.0
	s6.target_id[a6] = b6
	Weapons.tick(s6, hash_for(s6), DT)
	t.check(t.approx(s6.spin[a6], Tuning.RPM_MIN, 1e-4), "case6 spin[A] floored")
	t.check(t.approx(s6.spin[b6], Tuning.RPM_MIN, 1e-4), "case6 spin[B] floored")

	# 7. Cooldown guard: hit_cd[A] == WEAPON_COOLDOWN[1] after the hit; a second tick makes no second event
	Damage.force_mult = 1.0
	var s7 := make()
	var a7 := s7.spawn(100.0, 100.0, 0, 0, 1, false)
	var b7 := s7.spawn(118.0, 100.0, 1, 0, 1, false)
	s7.weapon_angle[a7] = 0.0
	s7.weapon_angle[b7] = 0.0
	s7.target_id[a7] = b7
	Weapons.tick(s7, hash_for(s7), DT)
	t.check(t.approx(s7.hit_cd[a7], Tuning.WEAPON_COOLDOWN[1], 1e-4), "case7 hit_cd[A] after hit")
	t.check(s7.events.size() == 1, "case7 events.size after first tick")
	Weapons.tick(s7, hash_for(s7), DT)
	t.check(s7.events.size() == 1, "case7 events.size after second tick (cooldown blocks)")

	# 8. Kill through weapons: [HIT, a, b, dmg] then [KILL, a, b]
	Damage.force_mult = 1.0
	var s8 := make()
	var a8 := s8.spawn(100.0, 100.0, 0, 0, 1, false)
	var b8 := s8.spawn(118.0, 100.0, 1, 0, 1, false)
	s8.weapon_angle[a8] = 0.0
	s8.weapon_angle[b8] = 0.0
	s8.hp[b8] = 5.0
	s8.target_id[a8] = b8
	Weapons.tick(s8, hash_for(s8), DT)
	t.check(s8.events.size() == 2, "case8 events.size")
	t.check(s8.events[0][0] == BattleState.Event.HIT and s8.events[0][1] == a8 and s8.events[0][2] == b8, "case8 events[0] HIT")
	t.check(s8.events[1][0] == BattleState.Event.KILL and s8.events[1][1] == a8 and s8.events[1][2] == b8, "case8 events[1] KILL")
	t.check(s8.state[b8] == BattleState.State.DEAD, "case8 state[B] dead")

	# 9. Out of reach: no hit, hit_cd set to WEAPON_RECHECK (geometry/hit-test)
	var s9 := make()
	var a9 := s9.spawn(100.0, 100.0, 0, 0, 1, false)
	var b9 := s9.spawn(140.0, 100.0, 1, 0, 1, false)
	s9.weapon_angle[a9] = 0.0
	s9.weapon_angle[b9] = 0.0
	s9.target_id[a9] = b9
	Weapons.tick(s9, hash_for(s9), DT)
	t.check(t.approx(s9.hit_cd[a9], Tuning.WEAPON_RECHECK, 1e-4), "case9 hit_cd[A]")
	t.check(t.approx(s9.hp[b9], 100.0, 1e-4), "case9 hp[B]")
	t.check(s9.events.size() == 0, "case9 events.size")

	# 10. Angle + cooldown advance (unaffected by M7)
	var s10 := make()
	var a10 := s10.spawn(100.0, 100.0, 0, 0, 1, false)
	s10.weapon_angle[a10] = 0.0
	s10.hit_cd[a10] = 0.1
	Weapons.tick(s10, hash_for(s10), DT)
	t.check(t.approx(s10.weapon_angle[a10], 0.174533, 1e-5), "case10 weapon_angle[A]")
	t.check(t.approx(s10.hit_cd[a10], 0.1 - DT, 1e-4), "case10 hit_cd[A]")

	# 11. Retreating attacker does not swing (geometry/state gating)
	var s11 := make()
	var a11 := s11.spawn(100.0, 100.0, 0, 0, 1, false)
	var b11 := s11.spawn(118.0, 100.0, 1, 0, 1, false)
	s11.weapon_angle[a11] = 0.0
	s11.weapon_angle[b11] = 0.0
	s11.state[a11] = BattleState.State.RETREAT
	Weapons.tick(s11, hash_for(s11), DT)
	t.check(t.approx(s11.hp[b11], 100.0, 1e-4), "case11 hp[B]")

	# 12. Dead attacker frozen
	var s12 := make()
	var a12 := s12.spawn(100.0, 100.0, 0, 0, 1, false)
	var b12 := s12.spawn(118.0, 100.0, 1, 0, 1, false)
	s12.weapon_angle[a12] = 0.0
	s12.weapon_angle[b12] = 0.0
	s12.state[a12] = BattleState.State.DEAD
	Weapons.tick(s12, hash_for(s12), DT)
	t.check(t.approx(s12.weapon_angle[a12], 0.0, 1e-6), "case12 weapon_angle[A] frozen")
	t.check(t.approx(s12.hp[b12], 100.0, 1e-4), "case12 hp[B]")

	# 13. Ally never hit (hit-test faction filter)
	var s13 := make()
	var a13 := s13.spawn(100.0, 100.0, 0, 0, 1, false)
	var b13 := s13.spawn(118.0, 100.0, 0, 0, 1, false)
	s13.weapon_angle[a13] = 0.0
	s13.weapon_angle[b13] = 0.0
	Weapons.tick(s13, hash_for(s13), DT)
	t.check(t.approx(s13.hp[b13], 100.0, 1e-4), "case13 hp[B] ally unharmed")

	# 14. No coarse-hash target: no gather, no recheck delay
	var s14 := make()
	var a14 := s14.spawn(100.0, 100.0, 0, 0, 1, false)
	var b14 := s14.spawn(118.0, 100.0, 1, 0, 1, false)
	s14.weapon_angle[a14] = 0.0
	s14.weapon_angle[b14] = 0.0
	s14.target_id[a14] = -1
	Weapons.tick(s14, hash_for(s14), DT)
	t.check(t.approx(s14.hp[b14], 100.0, 1e-4), "case14 hp[B]")
	t.check(t.approx(s14.hit_cd[a14], 0.0, 1e-6), "case14 hit_cd[A]")
	t.check(s14.events.size() == 0, "case14 events.size")

	# 15. Recheck delay expires (continues case9's s9 after its tick)
	for _t15 in range(6):
		Weapons.tick(s9, hash_for(s9), DT)
	t.check(t.approx(s9.hit_cd[a9], 0.0, 1e-6), "case15 hit_cd[A] delay expired")

	Damage.force_mult = -1.0
	t.finish()
	quit()
