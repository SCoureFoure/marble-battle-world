extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func make(seed: int) -> BattleState:
	return BattleState.new(16, seed)

func _init() -> void:
	var t := TestKit.new()

	# 1. force_mult = 1.3: roll returns 1.3, rng.state unchanged
	Damage.force_mult = 1.3
	var s1 := make(1)
	var state_before: int = s1.rng.state
	var result1: float = Damage.roll(s1, 0.9)
	var state_after: int = s1.rng.state
	t.check(t.approx(result1, 1.3, 1e-6), "case1 force_mult returns value")
	t.check(state_before == state_after, "case1 rng.state unchanged")

	# 2. force_mult = -1: determinism with seed 7, all values in [0.4, 1.6]
	Damage.force_mult = -1.0
	var s2a := make(7)
	var s2b := make(7)
	var seq_a: PackedFloat32Array = PackedFloat32Array()
	var seq_b: PackedFloat32Array = PackedFloat32Array()
	for i in range(200):
		seq_a.append(Damage.roll(s2a, 0.0))
	for i in range(200):
		seq_b.append(Damage.roll(s2b, 0.0))

	var same_seq: bool = true
	for i in range(200):
		if not t.approx(seq_a[i], seq_b[i], 1e-6):
			same_seq = false
			break
	t.check(same_seq, "case2 identical sequences")

	var all_in_range: bool = true
	for val in seq_a:
		if val < 0.4 - 1e-6 or val > 1.6 + 1e-6:
			all_in_range = false
			break
	t.check(all_in_range, "case2 all values in [0.4, 1.6]")

	# 3. Distribution: seed 11, 4000 rolls with crit 0.0
	var s3 := make(11)
	var rolls: PackedFloat32Array = PackedFloat32Array()
	for i in range(4000):
		rolls.append(Damage.roll(s3, 0.0))

	var sum: float = 0.0
	var min_val: float = rolls[0]
	var max_val: float = rolls[0]
	for val in rolls:
		sum += val
		min_val = minf(min_val, val)
		max_val = maxf(max_val, val)

	var mean: float = sum / 4000.0
	var var_sum: float = 0.0
	for val in rolls:
		var_sum += (val - mean) * (val - mean)
	var std: float = sqrt(var_sum / 4000.0)

	t.check(t.approx(mean, 1.0, 0.02), "case3 mean within 1.0 ± 0.02")
	t.check(t.approx(std, 0.20, 0.03), "case3 std within 0.20 ± 0.03")
	t.check(min_val >= 0.4 - 1e-6, "case3 min >= 0.4")
	t.check(max_val <= 1.6 + 1e-6, "case3 max <= 1.6")

	# 4. Crit: seed 5, 4000 rolls with crit_chance 1.0
	var s4 := make(5)
	var crit_rolls: PackedFloat32Array = PackedFloat32Array()
	for i in range(4000):
		crit_rolls.append(Damage.roll(s4, 1.0))

	var crit_sum: float = 0.0
	var crit_min: float = crit_rolls[0]
	var crit_max: float = crit_rolls[0]
	for val in crit_rolls:
		crit_sum += val
		crit_min = minf(crit_min, val)
		crit_max = maxf(crit_max, val)

	var crit_mean: float = crit_sum / 4000.0
	t.check(crit_min >= 0.8 - 1e-6, "case4 crit min >= 0.8")
	t.check(crit_max <= 3.2 + 1e-6, "case4 crit max <= 3.2")
	t.check(t.approx(crit_mean, 2.0, 0.05), "case4 crit mean within 2.0 ± 0.05")

	# 5. Crit draw count: A with crit 0.0, B with crit 0.5
	var s5a := make(3)
	var s5b := make(3)
	Damage.roll(s5a, 0.0)
	Damage.roll(s5b, 0.5)
	t.check(s5a.rng.state != s5b.rng.state, "case5 B drew extra randf")

	# 6. Apply HIT: hp reduced, xp gained, event pushed
	var s6 := make(1)
	var a6: int = s6.spawn(100.0, 100.0, 0, 0, 1, false)
	var b6: int = s6.spawn(118.0, 100.0, 1, 0, 1, false)
	s6.hp[b6] = 100.0
	Damage.apply(s6, a6, b6, 10.0, BattleState.Event.HIT)
	t.check(t.approx(s6.hp[b6], 90.0, 1e-6), "case6 hp reduced")
	t.check(s6.xp[a6] == Tuning.XP_PER_HIT, "case6 xp gained")
	t.check(s6.events.size() == 1, "case6 one event")
	t.check(s6.events[0][0] == BattleState.Event.HIT and s6.events[0][1] == a6 and s6.events[0][2] == b6 and t.approx(s6.events[0][3], 10.0, 1e-6), "case6 event correct")

	# 7. Apply BUMP event type
	var s7 := make(1)
	var a7: int = s7.spawn(100.0, 100.0, 0, 0, 1, false)
	var b7: int = s7.spawn(118.0, 100.0, 1, 0, 1, false)
	s7.hp[b7] = 100.0
	Damage.apply(s7, a7, b7, 7.5, BattleState.Event.BUMP)
	t.check(s7.events[0][0] == BattleState.Event.BUMP, "case7 event type BUMP")
	t.check(s7.events[0][1] == a7 and s7.events[0][2] == b7 and t.approx(s7.events[0][3], 7.5, 1e-6), "case7 event content")

	# 8. Kill: hp drops to 0, state becomes DEAD, kills increment, faction_alive decremented, morale hit
	var s8 := make(1)
	var a8: int = s8.spawn(100.0, 100.0, 0, 0, 1, false)
	var b8: int = s8.spawn(118.0, 100.0, 1, 0, 1, false)
	var c8: int = s8.spawn(500.0, 500.0, 1, 0, 1, false)  # alive ally of b
	s8.hp[b8] = 5.0
	var alive_before: int = s8.faction_alive[1]
	s8.morale[c8] = 0.8
	Damage.apply(s8, a8, b8, 6.0, BattleState.Event.HIT)
	t.check(t.approx(s8.hp[b8], 0.0, 1e-6), "case8 hp is 0")
	t.check(s8.state[b8] == BattleState.State.DEAD, "case8 state is DEAD")
	t.check(s8.kills[a8] == 1, "case8 kills incremented")
	t.check(s8.xp[a8] == Tuning.XP_PER_HIT + Tuning.XP_PER_KILL, "case8 xp includes kill bonus")
	t.check(s8.faction_alive[1] == alive_before - 1, "case8 faction_alive decremented")
	t.check(s8.events[0][0] == BattleState.Event.HIT, "case8 first event HIT")
	t.check(s8.events[1][0] == BattleState.Event.KILL, "case8 second event KILL")
	t.check(t.approx(s8.morale[c8], 0.8 + Tuning.MORALE_HIT_ALLY_DEATH, 1e-6), "case8 ally morale reduced")

	# 9. Captain kill: additional CAPTAIN_DEAD event, faction_captain set to -1, additional morale hit
	var s9 := make(1)
	var a9: int = s9.spawn(100.0, 100.0, 0, 0, 1, false)
	var b9: int = s9.spawn(118.0, 100.0, 1, 0, 1, true)  # b is captain
	var c9: int = s9.spawn(500.0, 500.0, 1, 0, 1, false)  # alive ally of b
	s9.hp[b9] = 5.0
	s9.morale[c9] = 0.8
	s9.faction_captain[1] = b9
	Damage.apply(s9, a9, b9, 6.0, BattleState.Event.HIT)
	t.check(s9.events[2][0] == BattleState.Event.CAPTAIN_DEAD, "case9 CAPTAIN_DEAD event")
	t.check(s9.faction_captain[1] == -1, "case9 faction_captain set to -1")
	t.check(t.approx(s9.morale[c9], maxf(0.0, 0.8 + Tuning.MORALE_HIT_ALLY_DEATH + Tuning.MORALE_HIT_CAPTAIN_DEAD), 1e-6), "case9 ally morale both penalties")

	# 10. Rank-up: xp = 29, apply damage -> rank increases, spin_cap and hp_max updated
	var s10 := make(1)
	var a10: int = s10.spawn(100.0, 100.0, 0, 0, 1, false)
	var b10: int = s10.spawn(118.0, 100.0, 1, 0, 1, false)
	s10.xp[a10] = 29
	s10.hp[b10] = 100.0
	var hp_max_before: float = s10.hp_max[a10]
	Damage.apply(s10, a10, b10, 5.0, BattleState.Event.HIT)
	t.check(s10.rank[a10] == 1, "case10 rank incremented")
	t.check(t.approx(s10.spin_cap[a10], Tuning.SPIN_CAP[1], 1e-6), "case10 spin_cap updated")
	t.check(t.approx(s10.hp_max[a10], Tuning.HP_BASE * Tuning.RANK_MULT[1], 1e-6), "case10 hp_max updated")
	t.check(s10.events[-1][0] == BattleState.Event.LEVEL and s10.events[-1][1] == a10 and s10.events[-1][2] == 1, "case10 last event is LEVEL")

	# 11. Wrong-reading guard: dmg 0.0 still pushes event and grants XP
	var s11 := make(1)
	var a11: int = s11.spawn(100.0, 100.0, 0, 0, 1, false)
	var b11: int = s11.spawn(118.0, 100.0, 1, 0, 1, false)
	var hp_before: float = s11.hp[b11]
	var xp_before: int = s11.xp[a11]
	Damage.apply(s11, a11, b11, 0.0, BattleState.Event.HIT)
	t.check(s11.events.size() == 1, "case11 event pushed")
	t.check(s11.xp[a11] == xp_before + Tuning.XP_PER_HIT, "case11 XP granted")
	t.check(t.approx(s11.hp[b11], hp_before, 1e-6), "case11 hp unchanged")

	# Reset force_mult
	Damage.force_mult = -1.0

	# 12. HIT event sets recoil_t on attacker, not victim
	var s12 := make(1)
	var a12: int = s12.spawn(100.0, 100.0, 0, 0, 1, false)
	var b12: int = s12.spawn(118.0, 100.0, 1, 0, 1, false)
	s12.hp[b12] = 100.0
	s12.recoil_t[a12] = 0.0
	s12.recoil_t[b12] = 0.0
	Damage.apply(s12, a12, b12, 5.0, BattleState.Event.HIT)
	t.check(t.approx(s12.recoil_t[a12], Tuning.RECOIL_TIME, 1e-6), "case12 recoil_t[attacker] == RECOIL_TIME")
	t.check(t.approx(s12.recoil_t[b12], 0.0, 1e-6), "case12 recoil_t[victim] unchanged")

	# 13. BUMP event sets recoil_t on attacker
	var s13 := make(1)
	var a13: int = s13.spawn(100.0, 100.0, 0, 0, 1, false)
	var b13: int = s13.spawn(118.0, 100.0, 1, 0, 1, false)
	s13.hp[b13] = 100.0
	s13.recoil_t[a13] = 0.0
	Damage.apply(s13, a13, b13, 5.0, BattleState.Event.BUMP)
	t.check(t.approx(s13.recoil_t[a13], Tuning.RECOIL_TIME, 1e-6), "case13 BUMP sets recoil_t")

	# 14. Lethal HIT still sets recoil_t on attacker
	var s14 := make(1)
	var a14: int = s14.spawn(100.0, 100.0, 0, 0, 1, false)
	var b14: int = s14.spawn(118.0, 100.0, 1, 0, 1, false)
	s14.hp[b14] = 5.0
	s14.recoil_t[a14] = 0.0
	Damage.apply(s14, a14, b14, 10.0, BattleState.Event.HIT)
	t.check(t.approx(s14.recoil_t[a14], Tuning.RECOIL_TIME, 1e-6), "case14 lethal HIT sets recoil_t")
	t.check(s14.state[b14] == BattleState.State.DEAD, "case14 victim is DEAD")

	# 15. Wrong-reading guard: non HIT/BUMP event doesn't set recoil_t
	var s15 := make(1)
	var a15: int = s15.spawn(100.0, 100.0, 0, 0, 1, false)
	var b15: int = s15.spawn(118.0, 100.0, 1, 0, 1, false)
	s15.hp[b15] = 100.0
	s15.recoil_t[a15] = 0.0
	Damage.apply(s15, a15, b15, 5.0, BattleState.Event.LEVEL)
	t.check(t.approx(s15.recoil_t[a15], 0.0, 1e-6), "case15 LEVEL event doesn't set recoil_t")

	t.finish()
	quit()
