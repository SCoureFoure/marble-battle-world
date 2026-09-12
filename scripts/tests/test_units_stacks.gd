extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# Case 1: Units.new(4), add
	var u := Units.new(4)
	t.check(u.add(0, 0, 1, false, 0) == 0, "add returns 0")
	t.check(u.add(0, 1, 1, true, 0) == 1, "add returns 1")
	t.check(u.faction[1] == 0, "faction[1] == 0")
	t.check(u.rank[1] == 1, "rank[1] == 1")
	t.check(u.is_captain[1] == 1, "is_captain[1] == 1")
	t.check(u.hp_frac[0] == 1.0, "hp_frac[0] == 1.0")
	t.check(u.alive[0] == 1, "alive[0] == 1")
	t.check(u.stack[0] == 0, "stack[0] == 0")
	t.check(u.add(0, 0, 0, false, 0) == 2, "third add returns 2")
	t.check(u.add(0, 0, 0, false, 0) == 3, "fourth add returns 3")
	t.check(u.add(0, 0, 0, false, 0) == -1, "fifth add returns -1 at capacity")

	# Case 2: kill
	u.kill(0)
	t.check(u.alive[0] == 0, "alive[0] == 0 after kill")
	t.check(u.stack[0] == -1, "stack[0] == -1 after kill")

	# Case 3: Stacks.new(3), add
	var st := Stacks.new(3)
	t.check(st.add(2, 100.0, 200.0, "Tomu") == 0, "stacks add returns 0")
	t.check(st.x[0] == 100.0, "x[0] == 100.0")
	t.check(st.prev_x[0] == 100.0, "prev_x[0] == 100.0")
	t.check(st.state[0] == Stacks.State.IDLE, "state[0] == IDLE")
	t.check(st.battle_id[0] == -1, "battle_id[0] == -1")
	t.check(st.path[0].size() == 0, "path[0].size() == 0")
	t.check(st.names[0] == "Tomu", "names[0] == 'Tomu'")

	# Case 4: tier
	st.count[0] = 0
	t.check(st.tier(0) == 0, "tier(0) count 0 == 0")
	st.count[0] = 29
	t.check(st.tier(0) == 0, "tier(0) count 29 == 0")
	st.count[0] = 30
	t.check(st.tier(0) == 1, "tier(0) count 30 == 1")
	st.count[0] = 99
	t.check(st.tier(0) == 1, "tier(0) count 99 == 1")
	st.count[0] = 100
	t.check(st.tier(0) == 2, "tier(0) count 100 == 2")
	st.count[0] = 249
	t.check(st.tier(0) == 2, "tier(0) count 249 == 2")
	st.count[0] = 250
	t.check(st.tier(0) == 3, "tier(0) count 250 == 3")

	# Case 5: label
	st.count[0] = 45
	t.check(st.label(0) == "(Company)Tomu 45/300", "label(0) == '(Company)Tomu 45/300'")

	# Case 6: recount
	var u6 := Units.new(4)
	var st6 := Stacks.new(3)
	st6.add(0, 0.0, 0.0, "A")
	st6.add(0, 0.0, 0.0, "B")
	st6.add(0, 0.0, 0.0, "C")
	var u0 := u6.add(0, 0, 0, false, 0)
	var u1 := u6.add(0, 0, 0, false, 0)
	var u2 := u6.add(0, 0, 0, false, 1)
	var u3 := u6.add(0, 0, 0, false, 2)
	u6.kill(u3)
	t.check(u0 == 0 and u1 == 1 and u2 == 2, "recount setup unit ids as expected")
	st6.recount(u6)
	t.check(st6.count[0] == 2, "recount count[0] == 2")
	t.check(st6.count[1] == 1, "recount count[1] == 1")
	t.check(st6.count[2] == 0, "recount count[2] == 0")
	t.check(st6.alive[2] == 1, "recount leaves alive[2] unchanged")

	# Case 7: NameGen
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 5
	var name_a := NameGen.stack_name(rng_a)
	t.check(name_a.length() > 0, "stack_name non-empty")
	t.check(name_a.substr(0, 1) == name_a.substr(0, 1).to_upper(), "stack_name first char uppercase")
	t.check(name_a.length() >= 3 and name_a.length() <= 12, "stack_name length between 3 and 12")

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 5
	var name_b := NameGen.stack_name(rng_b)
	t.check(name_a == name_b, "stack_name deterministic with same seed")

	var rng_c := RandomNumberGenerator.new()
	rng_c.seed = 5
	var captain_a := NameGen.captain_name(rng_c)
	t.check(captain_a.ends_with(" I"), "captain_name ends with ' I'")

	t.finish()
	quit()
