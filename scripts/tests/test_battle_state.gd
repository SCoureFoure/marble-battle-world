extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# Case 1: Initialization
	var s := BattleState.new(8, 42)
	t.check(s.n == 0, "n == 0 on init")
	t.check(s.cap == 8, "cap == 8")
	t.check(s.px.size() == 8, "px.size() == 8")
	t.check(s.captain_id[0] == -1, "captain_id[0] == -1")
	t.check(s.target_id[7] == -1, "target_id[7] == -1")
	t.check(s.faction_captain.size() == 16, "faction_captain.size() == 16")
	t.check(s.faction_captain[3] == -1, "faction_captain[3] == -1")
	t.check(s.arena == Rect2(0, 0, 1600, 900), "arena == Rect2(0, 0, 1600, 900)")

	# Case 2: Spawn non-captain marble
	var i := s.spawn(100.0, 200.0, 0, 0, 1, false)
	t.check(i == 0, "spawn returns 0")
	t.check(s.n == 1, "n == 1 after spawn")
	t.check(s.px[0] == 100.0, "px[0] == 100.0")
	t.check(s.py[0] == 200.0, "py[0] == 200.0")
	t.check(t.approx(s.radius[0], 8.0), "radius[0] approx 8.0")
	t.check(t.approx(s.mass[0], 64.0), "mass[0] approx 64.0")
	t.check(t.approx(s.hp[0], 100.0), "hp[0] approx 100.0")
	t.check(t.approx(s.hp_max[0], 100.0), "hp_max[0] approx 100.0")
	t.check(t.approx(s.spin[0], 100.0), "spin[0] approx 100.0")
	t.check(t.approx(s.spin_cap[0], 120.0), "spin_cap[0] approx 120.0")
	t.check(t.approx(s.morale[0], 0.8), "morale[0] approx 0.8")
	t.check(s.state[0] == BattleState.State.ENGAGE, "state[0] == ENGAGE")
	t.check(s.is_captain[0] == 0, "is_captain[0] == 0")
	t.check(s.faction_alive[0] == 1, "faction_alive[0] == 1")
	t.check(s.faction_count == 1, "faction_count == 1")
	t.check(s.weapon_id[0] == 1, "weapon_id[0] == 1")
	t.check(s.faction_id[0] == 0, "faction_id[0] == 0")

	# Case 3: Spawn captain marble with rank 2
	var c := s.spawn(300.0, 300.0, 1, 2, 3, true)
	t.check(c == 1, "captain spawn returns 1")
	# radius = 8.0 * 1.2 * 1.6 = 15.36
	t.check(t.approx(s.radius[1], 15.36), "radius[1] approx 15.36")
	# mass = 15.36 * 15.36 * 1.6
	t.check(t.approx(s.mass[1], 15.36 * 15.36 * 1.6), "mass[1] approx 15.36^2 * 1.6")
	# hp_max = 100.0 * 1.6 = 160.0
	t.check(t.approx(s.hp_max[1], 160.0), "hp_max[1] approx 160.0")
	# spin_cap = SPIN_CAP[2] = 190.0
	t.check(t.approx(s.spin_cap[1], 190.0), "spin_cap[1] approx 190.0")
	t.check(s.is_captain[1] == 1, "is_captain[1] == 1")
	t.check(s.faction_captain[1] == 1, "faction_captain[1] == 1")
	t.check(s.faction_count == 2, "faction_count == 2")

	# Case 4: Determinism
	var s1 := BattleState.new(2, 7)
	s1.spawn(0, 0, 0, 0, 0, false)
	var angle1 := s1.weapon_angle[0]

	var s2 := BattleState.new(2, 7)
	s2.spawn(0, 0, 0, 0, 0, false)
	var angle2 := s2.weapon_angle[0]

	t.check(angle1 == angle2, "weapon_angle deterministic with same seed")
	t.check(angle1 >= 0.0 and angle1 <= TAU, "weapon_angle in [0, TAU]")

	# Case 5: Error paths
	t.check(s.spawn(0, 0, 16, 0, 0, false) == -1, "spawn rejects faction >= 16")
	t.check(s.n == 2, "n unchanged after error")
	t.check(s.spawn(0, 0, 0, 4, 0, false) == -1, "spawn rejects rank > 3")
	t.check(s.spawn(0, 0, 0, 0, 5, false) == -1, "spawn rejects weapon >= 5")

	# Case 6: Capacity limit
	var f := BattleState.new(2, 1)
	t.check(f.spawn(0, 0, 0, 0, 0, false) != -1, "first spawn succeeds")
	t.check(f.spawn(0, 0, 0, 0, 0, false) != -1, "second spawn succeeds")
	t.check(f.spawn(0, 0, 0, 0, 0, false) == -1, "third spawn fails at capacity")
	t.check(f.n == 2, "n == 2 at capacity")

	# Case 7: spawn_block
	var b := BattleState.new(10, 3)
	b.spawn_block(2, 5, Rect2(10, 10, 100, 50), 0)
	t.check(b.n == 5, "spawn_block spawned 5 marbles")
	var all_in_range := true
	for marble_idx in range(5):
		if not (b.px[marble_idx] >= 10.0 and b.px[marble_idx] <= 110.0):
			all_in_range = false
		if not (b.py[marble_idx] >= 10.0 and b.py[marble_idx] <= 60.0):
			all_in_range = false
	t.check(all_in_range, "all marbles in rect range")
	t.check(b.faction_alive[2] == 5, "faction_alive[2] == 5")
	t.check(b.faction_count == 3, "faction_count == 3")

	# Case 8: alive_count
	b.state[0] = BattleState.State.DEAD
	t.check(b.alive_count() == 4, "alive_count == 4 after setting one to DEAD")

	t.finish()
	quit()
