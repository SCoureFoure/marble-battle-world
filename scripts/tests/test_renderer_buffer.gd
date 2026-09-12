extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# Case 1: empty state -> buffer size 0
	var s1 := BattleState.new(4, 1)
	var buf1 := BattleRenderer.build_buffer(s1)
	t.check(buf1.size() == 0, "empty state buffer size 0")

	# Case 2: spawn A at (100, 200) faction 0 rank 0
	var s2 := BattleState.new(4, 1)
	s2.spawn(100.0, 200.0, 0, 0, 0, false)
	var buf2 := BattleRenderer.build_buffer(s2)
	t.check(buf2.size() == 12, "one marble buffer size 12")
	t.check(t.approx(buf2[0], 8.0), "buf[0] approx 8.0")
	t.check(buf2[1] == 0.0, "buf[1] == 0")
	t.check(buf2[2] == 0.0, "buf[2] == 0")
	t.check(t.approx(buf2[3], 100.0), "buf[3] approx 100.0")
	t.check(buf2[4] == 0.0, "buf[4] == 0")
	t.check(t.approx(buf2[5], 8.0), "buf[5] approx 8.0")
	t.check(buf2[6] == 0.0, "buf[6] == 0")
	t.check(t.approx(buf2[7], 200.0), "buf[7] approx 200.0")
	t.check(t.approx(buf2[8], 0.85), "buf[8] approx 0.85")
	t.check(t.approx(buf2[9], 0.2), "buf[9] approx 0.2")
	t.check(t.approx(buf2[10], 0.2), "buf[10] approx 0.2")
	t.check(t.approx(buf2[11], 0.0), "buf[11] approx 0.0")

	# Case 3: spawn B at (300, 400) faction 1 rank 3 (not captain)
	s2.spawn(300.0, 400.0, 1, 3, 0, false)
	var buf3 := BattleRenderer.build_buffer(s2)
	t.check(buf3.size() == 24, "two marbles buffer size 24")
	t.check(t.approx(buf3[12], 10.4), "buf[12] approx 10.4")
	t.check(t.approx(buf3[15], 300.0), "buf[15] approx 300.0")
	t.check(t.approx(buf3[19], 400.0), "buf[19] approx 400.0")
	t.check(t.approx(buf3[20], 0.2), "buf[20] approx 0.2")
	t.check(t.approx(buf3[21], 0.4), "buf[21] approx 0.4")
	t.check(t.approx(buf3[22], 0.9), "buf[22] approx 0.9")
	t.check(t.approx(buf3[23], 1.0), "buf[23] approx 1.0")

	# Case 4: mark marble 0 DEAD -> rebuild -> zero scale, position kept
	s2.state[0] = BattleState.State.DEAD
	var buf4 := BattleRenderer.build_buffer(s2)
	t.check(buf4[0] == 0.0, "buf[0] == 0.0 after DEAD")
	t.check(buf4[5] == 0.0, "buf[5] == 0.0 after DEAD")
	t.check(t.approx(buf4[3], 100.0), "buf[3] still approx 100.0 after DEAD")

	# Case 5: faction 9 wraps to FACTION_COLORS[1]
	var s5 := BattleState.new(4, 1)
	s5.spawn(0.0, 0.0, 9, 0, 0, false)
	var buf5 := BattleRenderer.build_buffer(s5)
	t.check(t.approx(buf5[8], 0.2), "faction 9 wraps to color index 1, buf[8] approx 0.2")

	t.finish()
	quit()
