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

	# Case 6: captain rank 1 -> ca approx 1/3 + 2 = 2.3333
	var s6 := BattleState.new(4, 1)
	s6.spawn(0.0, 0.0, 0, 1, 0, true)
	var buf6 := BattleRenderer.build_buffer(s6)
	t.check(t.approx(buf6[11], 2.3333, 1e-3), "captain rank 1 ca approx 2.3333")

	# Case 7: build_weapon_buffer - one sword marble at (100,200) r 8, weapon_angle = 0
	var s7 := BattleState.new(4, 1)
	var i7 := s7.spawn(100.0, 200.0, 0, 0, 1, false)
	s7.weapon_angle[i7] = 0.0
	var wbuf7 := BattleRenderer.build_weapon_buffer(s7)
	t.check(wbuf7.size() == 12, "weapon buffer size 12")
	t.check(t.approx(wbuf7[0], 4.8), "wbuf[0] approx 4.8")
	t.check(t.approx(wbuf7[1], 0.0), "wbuf[1] approx 0")
	t.check(t.approx(wbuf7[3], 104.8), "wbuf[3] approx 104.8")
	t.check(t.approx(wbuf7[4], 0.0), "wbuf[4] approx 0")
	t.check(t.approx(wbuf7[5], 1.0), "wbuf[5] approx 1.0")
	t.check(t.approx(wbuf7[7], 200.0), "wbuf[7] approx 200.0")
	t.check(t.approx(wbuf7[8], 0.25), "wbuf[8] approx 0.25")

	s7.weapon_angle[i7] = PI / 2.0
	var wbuf7b := BattleRenderer.build_weapon_buffer(s7)
	t.check(t.approx(wbuf7b[0], 0.0), "wbuf2[0] approx 0")
	t.check(t.approx(wbuf7b[1], -1.0), "wbuf2[1] approx -1.0")
	t.check(t.approx(wbuf7b[4], 4.8), "wbuf2[4] approx 4.8")
	t.check(t.approx(wbuf7b[5], 0.0), "wbuf2[5] approx 0")
	t.check(t.approx(wbuf7b[3], 100.0), "wbuf2[3] approx 100.0")
	t.check(t.approx(wbuf7b[7], 204.8), "wbuf2[7] approx 204.8")

	# Case 8: build_hp_buffer - marble at (100,200) r 8, hp=50 hp_max=100
	var s8 := BattleState.new(4, 1)
	var i8 := s8.spawn(100.0, 200.0, 0, 0, 0, false)
	s8.hp[i8] = 50.0
	var hbuf8 := BattleRenderer.build_hp_buffer(s8)
	t.check(t.approx(hbuf8[0], 8.0), "hbuf[0] approx 8.0")
	t.check(t.approx(hbuf8[5], 1.5), "hbuf[5] approx 1.5")
	t.check(t.approx(hbuf8[3], 100.0), "hbuf[3] approx 100.0")
	t.check(t.approx(hbuf8[7], 188.0), "hbuf[7] approx 188.0")
	t.check(t.approx(hbuf8[8], 0.5), "hbuf[8] approx 0.5")

	s8.hp[i8] = s8.hp_max[i8]
	var hbuf8b := BattleRenderer.build_hp_buffer(s8)
	t.check(hbuf8b[0] == 0.0, "hbuf full hp -> buf[0] == 0.0")
	t.check(hbuf8b[5] == 0.0, "hbuf full hp -> buf[5] == 0.0")

	# Case 9: DEAD marble -> weapon buffer basis entries all 0
	var s9 := BattleState.new(4, 1)
	var i9 := s9.spawn(100.0, 200.0, 0, 0, 1, false)
	s9.state[i9] = BattleState.State.DEAD
	var wbuf9 := BattleRenderer.build_weapon_buffer(s9)
	t.check(wbuf9[0] == 0.0, "dead wbuf[0] == 0")
	t.check(wbuf9[1] == 0.0, "dead wbuf[1] == 0")
	t.check(wbuf9[4] == 0.0, "dead wbuf[4] == 0")
	t.check(wbuf9[5] == 0.0, "dead wbuf[5] == 0")

	t.finish()
	quit()
