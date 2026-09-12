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

	# Case 9: fled and events fields
	var s9 := BattleState.new(8, 1)
	t.check(s9.fled.size() == 8, "fled.size() == 8")
	t.check(s9.fled[3] == 0, "fled[3] == 0")
	t.check(s9.events.size() == 0, "events.size() == 0")
	t.check(s9.events is Array, "events is Array")

	# Case 10: survivors_count with fled marbles
	var s10 := BattleState.new(8, 1)
	s10.spawn(10.0, 10.0, 0, 0, 1, false)
	s10.spawn(20.0, 20.0, 0, 0, 1, false)
	s10.spawn(30.0, 30.0, 0, 0, 1, false)
	s10.state[0] = BattleState.State.DEAD
	s10.fled[0] = 1
	s10.state[1] = BattleState.State.DEAD
	t.check(s10.survivors_count(0) == 2, "survivors_count(0) == 2")
	t.check(s10.survivors_count(1) == 0, "survivors_count(1) == 0")
	t.check(s10.alive_count() == 1, "alive_count() == 1")

	# Case 11: spawn_block with random weapons
	var s11a := BattleState.new(300, 11)
	s11a.spawn_block(0, 200, Rect2(0, 0, 100, 100), -1)
	t.check(s11a.n == 200, "n == 200 after spawn_block")
	var all_weapons_valid := true
	var weapon_set := {}
	for idx in range(200):
		if s11a.weapon_id[idx] < 0 or s11a.weapon_id[idx] > 4:
			all_weapons_valid = false
		weapon_set[s11a.weapon_id[idx]] = true
	t.check(all_weapons_valid, "all weapons in [0, 4]")
	t.check(weapon_set.size() >= 3, "at least 3 distinct weapon ids")

	var s11b := BattleState.new(300, 11)
	s11b.spawn_block(0, 200, Rect2(0, 0, 100, 100), -1)
	t.check(s11a.weapon_id == s11b.weapon_id, "weapon_id arrays equal with same seed")

	# Case 12: spawn_block with explicit weapon
	var s12 := BattleState.new(10, 2)
	s12.spawn_block(1, 5, Rect2(0, 0, 10, 10), 2)
	var all_weapon_2 := true
	for idx in range(5):
		if s12.weapon_id[idx] != 2:
			all_weapon_2 = false
	t.check(all_weapon_2, "all five marbles have weapon_id == 2")

	# Case 13: Event enum values
	t.check(BattleState.Event.CAPTAIN_DEAD == 3, "BattleState.Event.CAPTAIN_DEAD == 3")
	t.check(BattleState.Event.FLED == 4, "BattleState.Event.FLED == 4")

	t.finish()
	quit()
