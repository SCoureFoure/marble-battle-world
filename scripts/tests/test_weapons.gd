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

	# 1. Normal hit
	Weapons.force_roll = 0.5
	var s1 := make()
	var a1 := s1.spawn(100.0, 100.0, 0, 0, 1, false)
	var b1 := s1.spawn(118.0, 100.0, 1, 0, 1, false)
	s1.weapon_angle[a1] = 0.0
	s1.weapon_angle[b1] = 0.0
	s1.target_id[a1] = b1
	Weapons.tick(s1, hash_for(s1), DT)
	t.check(t.approx(s1.hp[b1], 92.0, 1e-4), "case1 hp[B]")
	t.check(s1.xp[a1] == 1, "case1 xp[A]")
	t.check(t.approx(s1.hit_cd[a1], 0.30, 1e-4), "case1 hit_cd[A]")
	t.check(t.approx(s1.vx[b1], 120.0, 1e-3), "case1 vx[B]")
	t.check(t.approx(s1.vy[b1], 0.0, 0.5), "case1 vy[B]")
	t.check(s1.events.size() == 1, "case1 events.size")
	t.check(s1.events[0][0] == BattleState.Event.HIT and s1.events[0][1] == a1 and s1.events[0][2] == b1, "case1 events[0]")

	# 2. Cooldown blocks (continue case 1's state; Weapons does not clear events)
	Weapons.tick(s1, hash_for(s1), DT)
	t.check(t.approx(s1.hp[b1], 92.0, 1e-4), "case2 hp[B] unchanged")
	t.check(t.approx(s1.hit_cd[a1], 0.30 - DT, 1e-4), "case2 hit_cd[A]")

	# 3. Crit
	Weapons.force_roll = 0.01
	var s3 := make()
	var a3 := s3.spawn(100.0, 100.0, 0, 0, 1, false)
	var b3 := s3.spawn(118.0, 100.0, 1, 0, 1, false)
	s3.weapon_angle[a3] = 0.0
	s3.weapon_angle[b3] = 0.0
	s3.target_id[a3] = b3
	Weapons.tick(s3, hash_for(s3), DT)
	t.check(t.approx(s3.hp[b3], 84.0, 1e-4), "case3 hp[B] crit")

	# 4. Fumble
	Weapons.force_roll = 0.06
	var s4 := make()
	var a4 := s4.spawn(100.0, 100.0, 0, 0, 1, false)
	var b4 := s4.spawn(118.0, 100.0, 1, 0, 1, false)
	s4.weapon_angle[a4] = 0.0
	s4.weapon_angle[b4] = 0.0
	s4.target_id[a4] = b4
	Weapons.tick(s4, hash_for(s4), DT)
	t.check(t.approx(s4.hp[b4], 100.0, 1e-4), "case4 hp[B] unchanged")
	t.check(t.approx(s4.spin[a4], 80.0, 1e-4), "case4 spin[A]")
	t.check(t.approx(s4.hit_cd[a4], 0.30, 1e-4), "case4 hit_cd[A]")
	t.check(s4.events.size() == 0, "case4 events.size")

	# 5a. Shield facing: attacker within the defender's facing cone -> damage halved
	Weapons.force_roll = 0.5
	var s5a := make()
	var a5a := s5a.spawn(100.0, 100.0, 0, 0, 1, false)
	var b5a := s5a.spawn(118.0, 100.0, 1, 0, 4, false)
	s5a.weapon_angle[a5a] = 0.0
	s5a.weapon_angle[b5a] = PI
	s5a.target_id[a5a] = b5a
	Weapons.tick(s5a, hash_for(s5a), DT)
	t.check(t.approx(s5a.hp[b5a], 96.0, 1e-3), "case5a hp[B] shield blocks")

	# 5b. Shield facing away: no reduction
	Weapons.force_roll = 0.5
	var s5b := make()
	var a5b := s5b.spawn(100.0, 100.0, 0, 0, 1, false)
	var b5b := s5b.spawn(118.0, 100.0, 1, 0, 4, false)
	s5b.weapon_angle[a5b] = 0.0
	s5b.weapon_angle[b5b] = 0.0
	s5b.target_id[a5b] = b5b
	Weapons.tick(s5b, hash_for(s5b), DT)
	t.check(t.approx(s5b.hp[b5b], 92.0, 1e-3), "case5b hp[B] shield not facing")

	# 6. Kill
	Weapons.force_roll = 0.5
	var s6 := make()
	var a6 := s6.spawn(100.0, 100.0, 0, 0, 1, false)
	var b6 := s6.spawn(118.0, 100.0, 1, 0, 1, false)
	s6.weapon_angle[a6] = 0.0
	s6.weapon_angle[b6] = 0.0
	s6.hp[b6] = 5.0
	s6.target_id[a6] = b6
	var c6 := s6.spawn(500.0, 500.0, 1, 0, 1, false)
	var alive_before6 := s6.faction_alive[1]
	Weapons.tick(s6, hash_for(s6), DT)
	t.check(t.approx(s6.hp[b6], 0.0, 1e-6), "case6 hp[B] dead")
	t.check(s6.state[b6] == BattleState.State.DEAD, "case6 state[B]")
	t.check(s6.kills[a6] == 1, "case6 kills[A]")
	t.check(s6.xp[a6] == 11, "case6 xp[A]")
	t.check(s6.faction_alive[1] == alive_before6 - 1, "case6 faction_alive[1]")
	t.check(t.approx(s6.morale[c6], 0.78, 1e-3), "case6 morale[C]")
	var has_kill6 := false
	var has_hit6 := false
	for e6 in s6.events:
		if e6[0] == BattleState.Event.KILL and e6[1] == a6 and e6[2] == b6:
			has_kill6 = true
		if e6[0] == BattleState.Event.HIT and e6[1] == a6 and e6[2] == b6:
			has_hit6 = true
	t.check(has_kill6, "case6 events has KILL")
	t.check(has_hit6, "case6 events has HIT")

	# 7. Captain kill (rank 2 captain -> radius 15.36, positioned so the hit still lands)
	Weapons.force_roll = 0.5
	var s7 := make()
	var a7 := s7.spawn(100.0, 100.0, 0, 0, 1, false)
	var b7 := s7.spawn(125.0, 100.0, 1, 2, 1, true)
	s7.weapon_angle[a7] = 0.0
	s7.weapon_angle[b7] = 0.0
	s7.hp[b7] = 5.0
	s7.target_id[a7] = b7
	var c7 := s7.spawn(500.0, 500.0, 1, 0, 1, false)
	Weapons.tick(s7, hash_for(s7), DT)
	t.check(t.approx(s7.morale[c7], 0.38, 1e-3), "case7 morale[C]")
	t.check(s7.faction_captain[1] == -1, "case7 faction_captain[1]")
	var has_capdead7 := false
	for e7 in s7.events:
		if e7[0] == BattleState.Event.CAPTAIN_DEAD and e7[1] == a7 and e7[2] == b7:
			has_capdead7 = true
	t.check(has_capdead7, "case7 events has CAPTAIN_DEAD")

	# 8. Rank up
	Weapons.force_roll = 0.5
	var s8 := make()
	var a8 := s8.spawn(100.0, 100.0, 0, 0, 1, false)
	var b8 := s8.spawn(118.0, 100.0, 1, 0, 1, false)
	s8.weapon_angle[a8] = 0.0
	s8.weapon_angle[b8] = 0.0
	s8.xp[a8] = 29
	s8.target_id[a8] = b8
	Weapons.tick(s8, hash_for(s8), DT)
	t.check(s8.xp[a8] == 30, "case8 xp[A]")
	t.check(s8.rank[a8] == 1, "case8 rank[A]")
	t.check(t.approx(s8.spin_cap[a8], 150.0, 1e-3), "case8 spin_cap[A]")
	t.check(t.approx(s8.hp_max[a8], 125.0, 1e-3), "case8 hp_max[A]")
	t.check(t.approx(s8.hp[a8], 125.0, 1e-3), "case8 hp[A]")
	t.check(t.approx(s8.mass[a8], 80.0, 1e-3), "case8 mass[A]")
	var has_level8 := false
	for e8 in s8.events:
		if e8[0] == BattleState.Event.LEVEL and e8[1] == a8 and e8[2] == 1:
			has_level8 = true
	t.check(has_level8, "case8 events has LEVEL")

	# 9. Out of reach
	Weapons.force_roll = 0.5
	var s9 := make()
	var a9 := s9.spawn(100.0, 100.0, 0, 0, 1, false)
	var b9 := s9.spawn(140.0, 100.0, 1, 0, 1, false)
	s9.weapon_angle[a9] = 0.0
	s9.weapon_angle[b9] = 0.0
	s9.target_id[a9] = b9
	Weapons.tick(s9, hash_for(s9), DT)
	t.check(t.approx(s9.hit_cd[a9], 0.1, 1e-4), "case9 hit_cd[A]")
	t.check(t.approx(s9.hp[b9], 100.0, 1e-4), "case9 hp[B]")
	t.check(s9.events.size() == 0, "case9 events.size")

	# 10. Angle + cooldown advance
	Weapons.force_roll = 0.5
	var s10 := make()
	var a10 := s10.spawn(100.0, 100.0, 0, 0, 1, false)
	s10.weapon_angle[a10] = 0.0
	s10.hit_cd[a10] = 0.1
	Weapons.tick(s10, hash_for(s10), DT)
	t.check(t.approx(s10.weapon_angle[a10], 0.174533, 1e-5), "case10 weapon_angle[A]")
	t.check(t.approx(s10.hit_cd[a10], 0.1 - DT, 1e-4), "case10 hit_cd[A]")

	# 11. Retreating attacker does not swing
	Weapons.force_roll = 0.5
	var s11 := make()
	var a11 := s11.spawn(100.0, 100.0, 0, 0, 1, false)
	var b11 := s11.spawn(118.0, 100.0, 1, 0, 1, false)
	s11.weapon_angle[a11] = 0.0
	s11.weapon_angle[b11] = 0.0
	s11.state[a11] = BattleState.State.RETREAT
	Weapons.tick(s11, hash_for(s11), DT)
	t.check(t.approx(s11.hp[b11], 100.0, 1e-4), "case11 hp[B]")
	t.check(t.approx(s11.weapon_angle[a11], 0.174533, 1e-5), "case11 weapon_angle[A] still advanced")

	# 12. Dead attacker frozen
	Weapons.force_roll = 0.5
	var s12 := make()
	var a12 := s12.spawn(100.0, 100.0, 0, 0, 1, false)
	var b12 := s12.spawn(118.0, 100.0, 1, 0, 1, false)
	s12.weapon_angle[a12] = 0.0
	s12.weapon_angle[b12] = 0.0
	s12.state[a12] = BattleState.State.DEAD
	Weapons.tick(s12, hash_for(s12), DT)
	t.check(t.approx(s12.weapon_angle[a12], 0.0, 1e-6), "case12 weapon_angle[A] frozen")
	t.check(t.approx(s12.hp[b12], 100.0, 1e-4), "case12 hp[B]")

	# 13. Ally never hit
	Weapons.force_roll = 0.5
	var s13 := make()
	var a13 := s13.spawn(100.0, 100.0, 0, 0, 1, false)
	var b13 := s13.spawn(118.0, 100.0, 0, 0, 1, false)
	s13.weapon_angle[a13] = 0.0
	s13.weapon_angle[b13] = 0.0
	Weapons.tick(s13, hash_for(s13), DT)
	t.check(t.approx(s13.hp[b13], 100.0, 1e-4), "case13 hp[B] ally unharmed")

	# 14. Determinism without the force_roll hook
	Weapons.force_roll = -1.0
	var s14a := make()
	var a14a := s14a.spawn(100.0, 100.0, 0, 0, 1, false)
	var b14a := s14a.spawn(118.0, 100.0, 1, 0, 1, false)
	s14a.weapon_angle[a14a] = 0.0
	s14a.weapon_angle[b14a] = 0.0
	s14a.target_id[a14a] = b14a
	s14a.target_id[b14a] = a14a
	for _t14a in range(20):
		Weapons.tick(s14a, hash_for(s14a), DT)

	var s14b := make()
	var a14b := s14b.spawn(100.0, 100.0, 0, 0, 1, false)
	var b14b := s14b.spawn(118.0, 100.0, 1, 0, 1, false)
	s14b.weapon_angle[a14b] = 0.0
	s14b.weapon_angle[b14b] = 0.0
	s14b.target_id[a14b] = b14b
	s14b.target_id[b14b] = a14b
	for _t14b in range(20):
		Weapons.tick(s14b, hash_for(s14b), DT)

	t.check(t.approx(s14a.hp[b14a], s14b.hp[b14b], 1e-6), "case14 hp[B] deterministic")
	t.check(t.approx(s14a.spin[a14a], s14b.spin[a14b], 1e-6), "case14 spin[A] deterministic")
	Weapons.force_roll = -1.0

	# 15. No coarse-hash target: no gather, no recheck delay
	Weapons.force_roll = 0.5
	var s15 := make()
	var a15 := s15.spawn(100.0, 100.0, 0, 0, 1, false)
	var b15 := s15.spawn(118.0, 100.0, 1, 0, 1, false)
	s15.weapon_angle[a15] = 0.0
	s15.weapon_angle[b15] = 0.0
	s15.target_id[a15] = -1
	Weapons.tick(s15, hash_for(s15), DT)
	t.check(t.approx(s15.hp[b15], 100.0, 1e-4), "case15 hp[B]")
	t.check(t.approx(s15.hit_cd[a15], 0.0, 1e-6), "case15 hit_cd[A]")
	t.check(s15.events.size() == 0, "case15 events.size")
	t.check(t.approx(s15.weapon_angle[a15], 0.174533, 1e-5), "case15 weapon_angle[A] still advanced")

	# 16. Recheck delay expires (continues case 9's s9 after its tick)
	for _t16 in range(6):
		Weapons.tick(s9, hash_for(s9), DT)
	t.check(t.approx(s9.hit_cd[a9], 0.0, 1e-6), "case16 hit_cd[A] delay expired")

	t.finish()
	quit()
