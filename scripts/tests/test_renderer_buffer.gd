extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# Case 1: empty state -> buffer size 0
	var s1 := BattleState.new(4, 1)
	var buf1 := BattleRenderer.build_buffer(s1)
	t.check(buf1.size() == 0, "empty state buffer size 0")

	# Case 2: spawn A at (100, 200) faction 0 rank 0 -> spin 100, spin_cap 120
	var s2 := BattleState.new(4, 1)
	s2.spawn(100.0, 200.0, 0, 0, 0, false)
	var buf2 := BattleRenderer.build_buffer(s2)
	t.check(buf2.size() == 16, "one marble buffer size 16")
	t.check(t.approx(buf2[0], 8.0), "buf[0] approx 8.0")
	t.check(buf2[1] == 0.0, "buf[1] == 0")
	t.check(buf2[2] == 0.0, "buf[2] == 0")
	t.check(t.approx(buf2[3], 100.0), "buf[3] approx 100.0")
	t.check(buf2[4] == 0.0, "buf[4] == 0")
	t.check(t.approx(buf2[5], 8.0), "buf[5] approx 8.0")
	t.check(buf2[6] == 0.0, "buf[6] == 0")
	t.check(t.approx(buf2[7], 200.0), "buf[7] approx 200.0")
	t.check(t.approx(buf2[8], 100.0 / 120.0), "buf[8] glow approx spin/spin_cap")
	t.check(buf2[9] == 0.0, "buf[9] == 0")
	t.check(buf2[10] == 0.0, "buf[10] == 0")
	t.check(t.approx(buf2[11], 1.0), "buf[11] approx 1.0")
	t.check(t.approx(buf2[12], 0.85), "buf[12] approx 0.85")
	t.check(t.approx(buf2[13], 0.2), "buf[13] approx 0.2")
	t.check(t.approx(buf2[14], 0.2), "buf[14] approx 0.2")
	t.check(t.approx(buf2[15], 0.0), "buf[15] approx 0.0")

	# Case 3: spawn B at (300, 400) faction 1 rank 3 (not captain)
	s2.spawn(300.0, 400.0, 1, 3, 0, false)
	var buf3 := BattleRenderer.build_buffer(s2)
	t.check(buf3.size() == 32, "two marbles buffer size 32")
	t.check(t.approx(buf3[16], 10.4), "buf[16] approx 10.4")
	t.check(t.approx(buf3[19], 300.0), "buf[19] approx 300.0")
	t.check(t.approx(buf3[23], 400.0), "buf[23] approx 400.0")
	t.check(t.approx(buf3[24], 100.0 / 250.0), "buf[24] glow approx spin/spin_cap rank 3")
	t.check(t.approx(buf3[28], 0.2), "buf[28] approx 0.2")
	t.check(t.approx(buf3[29], 0.4), "buf[29] approx 0.4")
	t.check(t.approx(buf3[30], 0.9), "buf[30] approx 0.9")
	t.check(t.approx(buf3[31], 1.0), "buf[31] approx 1.0")

	# Case 4: mark marble 0 DEAD -> rebuild -> zero scale, position kept, glow 0
	s2.state[0] = BattleState.State.DEAD
	var buf4 := BattleRenderer.build_buffer(s2)
	t.check(buf4[0] == 0.0, "buf[0] == 0.0 after DEAD")
	t.check(buf4[5] == 0.0, "buf[5] == 0.0 after DEAD")
	t.check(buf4[8] == 0.0, "buf[8] glow == 0.0 after DEAD")
	t.check(t.approx(buf4[3], 100.0), "buf[3] still approx 100.0 after DEAD")

	# Case 5: faction 9 wraps to FACTION_COLORS[1]
	var s5 := BattleState.new(4, 1)
	s5.spawn(0.0, 0.0, 9, 0, 0, false)
	var buf5 := BattleRenderer.build_buffer(s5)
	t.check(t.approx(buf5[12], 0.2), "faction 9 wraps to color index 1, buf[12] approx 0.2")

	# Case 6: captain rank 1 -> ca approx 1/3 + 2 = 2.3333
	var s6 := BattleState.new(4, 1)
	s6.spawn(0.0, 0.0, 0, 1, 0, true)
	var buf6 := BattleRenderer.build_buffer(s6)
	t.check(t.approx(buf6[15], 2.3333, 1e-3), "captain rank 1 ca approx 2.3333")

	# Case 6b: explicit spin / spin_cap glow, spin 300 clamps to 1.0
	var s6b := BattleState.new(4, 1)
	var i6b := s6b.spawn(0.0, 0.0, 0, 0, 0, false)
	s6b.spin[i6b] = 60.0
	s6b.spin_cap[i6b] = 120.0
	var buf6b := BattleRenderer.build_buffer(s6b)
	t.check(t.approx(buf6b[8], 0.5), "glow 60/120 == 0.5")
	s6b.spin[i6b] = 300.0
	var buf6c := BattleRenderer.build_buffer(s6b)
	t.check(t.approx(buf6c[8], 1.0), "glow clamps to 1.0 above cap")

	# Case 7 (weapon buffer case 1): sword w=1 r=8 p=(100,100), angle 0
	# L = (REACH+HIT_R)*r = 1.7*8 = 13.6, H = HIT_R*r = 0.5*8 = 4.0
	var s7 := BattleState.new(4, 1)
	var i7 := s7.spawn(100.0, 100.0, 0, 0, 1, false)
	s7.weapon_angle[i7] = 0.0
	var wbuf7 := BattleRenderer.build_weapon_buffer(s7)
	t.check(wbuf7.size() == 12, "weapon buffer size 12")
	t.check(t.approx(wbuf7[0], 6.8), "wbuf[0] approx 6.8")
	t.check(t.approx(wbuf7[1], 0.0), "wbuf[1] approx 0")
	t.check(t.approx(wbuf7[3], 106.8), "wbuf[3] approx 106.8")
	t.check(t.approx(wbuf7[4], 0.0), "wbuf[4] approx 0")
	t.check(t.approx(wbuf7[5], 4.0), "wbuf[5] approx 4.0")
	t.check(t.approx(wbuf7[7], 100.0), "wbuf[7] approx 100.0")
	t.check(wbuf7[8] == 0.25, "wbuf[8] == 0.25")
	t.check(wbuf7[9] == 0.0, "wbuf[9] == 0.0")
	t.check(t.approx(wbuf7[10], 1.2 / 1.7), "wbuf[10] approx 1.2/1.7")
	t.check(t.approx(wbuf7[11], 1.7), "wbuf[11] approx 1.7")

	# Case 7b (weapon buffer case 2): angle PI/2
	s7.weapon_angle[i7] = PI / 2.0
	var wbuf7b := BattleRenderer.build_weapon_buffer(s7)
	t.check(t.approx(wbuf7b[0], 0.0), "wbuf2[0] approx 0")
	t.check(t.approx(wbuf7b[1], -4.0), "wbuf2[1] approx -4.0")
	t.check(t.approx(wbuf7b[3], 100.0), "wbuf2[3] approx 100.0")
	t.check(t.approx(wbuf7b[4], 6.8), "wbuf2[4] approx 6.8")
	t.check(t.approx(wbuf7b[5], 0.0), "wbuf2[5] approx 0")
	t.check(t.approx(wbuf7b[7], 106.8), "wbuf2[7] approx 106.8")

	# Case 7c (weapon buffer case 3): hitbox agreement guard at angle 0
	s7.weapon_angle[i7] = 0.0
	var wbuf7c := BattleRenderer.build_weapon_buffer(s7)
	var head_u7: float = wbuf7c[10]
	var head_x: float = wbuf7c[3] + wbuf7c[0] * (2.0 * head_u7 - 1.0)
	var head_y: float = wbuf7c[7] + wbuf7c[4] * (2.0 * head_u7 - 1.0)
	t.check(t.approx(head_x, 109.6), "weapon head centre x matches Weapons hit point 109.6")
	t.check(t.approx(head_y, 100.0), "weapon head centre y matches Weapons hit point 100.0")
	t.check(t.approx(wbuf7c[5], Tuning.WEAPON_HIT_R[1] * s7.radius[i7]), "half height == WEAPON_HIT_R[1]*r")

	# Case 7d (weapon buffer case 4): spear w=2
	var s7d := BattleState.new(4, 1)
	var i7d := s7d.spawn(100.0, 100.0, 0, 0, 2, false)
	var wbuf7d := BattleRenderer.build_weapon_buffer(s7d)
	t.check(t.approx(wbuf7d[10], 2.0 / 2.4), "spear wbuf[10] approx 2.0/2.4")
	t.check(t.approx(wbuf7d[11], 2.4 * 8.0 / (2.0 * 3.2)), "spear wbuf[11] approx 3.0")

	# Case 7e (weapon buffer case 5): flash array applies / defaults short
	var flash7 := PackedFloat32Array([0.15])
	var wbuf7e := BattleRenderer.build_weapon_buffer(s7, flash7)
	t.check(t.approx(wbuf7e[9], 0.15), "flash applied to wbuf[9]")
	s7d.spawn(300.0, 300.0, 0, 0, 2, false)
	var wbuf7f := BattleRenderer.build_weapon_buffer(s7d, flash7)
	t.check(wbuf7f[9 + 12] == 0.0, "flash missing entry defaults 0")

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

	# Case 9b (weapon buffer case 7): ingest HIT -> weapon_flash set and decays
	var r9b := BattleRenderer.new()
	var s9b := BattleState.new(4, 1)
	s9b.tick = 1
	var w0 := s9b.spawn(0.0, 0.0, 0, 0, 0, false)
	var w1 := s9b.spawn(50.0, 0.0, 0, 0, 0, false)
	s9b.events = [[BattleState.Event.HIT, w0, w1, 5.0]]
	r9b.ingest(s9b)
	t.check(t.approx(r9b.weapon_flash[0], 0.15), "weapon_flash[0] == 0.15 after HIT ingest")
	r9b.advance(0.1)
	t.check(t.approx(r9b.weapon_flash[0], 0.05), "weapon_flash decays to approx 0.05")
	r9b.advance(0.1)
	t.check(t.approx(r9b.weapon_flash[0], 0.0), "weapon_flash decays to 0.0, floor clamp")

	# Case 10: ingest a HIT event -> spark 0 active
	var r10 := BattleRenderer.new()
	var s10 := BattleState.new(4, 1)
	s10.tick = 5
	var m0 := s10.spawn(100.0, 100.0, 0, 0, 0, false)
	var m1 := s10.spawn(120.0, 100.0, 0, 0, 0, false)
	s10.events = [[BattleState.Event.HIT, m0, m1, 10.0]]
	r10.ingest(s10)
	t.check(r10.spark_head == 1, "spark_head 1 after one ingest")
	t.check(t.approx(r10.spark_x[0], 110.0), "spark0 x 110")
	t.check(t.approx(r10.spark_y[0], 100.0), "spark0 y 100")
	t.check(t.approx(r10.spark_r[0], 18.0), "spark0 r 18")
	t.check(t.approx(r10.spark_life[0], 0.25), "spark0 life 0.25")
	t.check(r10.spark_kind[0] == 0, "spark0 kind 0")

	# Case 11: same tick ingested twice -> spark_head unchanged (paused guard)
	r10.ingest(s10)
	t.check(r10.spark_head == 1, "spark_head still 1, paused guard")

	# Case 12: BUMP / BOOST / HIT-3-element spark shaping
	var r12 := BattleRenderer.new()
	var s12 := BattleState.new(4, 1)
	s12.tick = 1
	var n0 := s12.spawn(0.0, 0.0, 0, 0, 0, false)
	var n1 := s12.spawn(10.0, 0.0, 0, 0, 0, false)
	s12.events = [[BattleState.Event.BUMP, n0, n1, 20.0]]
	r12.ingest(s12)
	t.check(t.approx(r12.spark_r[0], 14.0), "BUMP spark r clamps to 14")
	t.check(r12.spark_kind[0] == 1, "BUMP spark kind 1")

	s12.tick = 2
	s12.events = [[BattleState.Event.BOOST, n0, n1, 3.0]]
	r12.ingest(s12)
	t.check(t.approx(r12.spark_r[1], 6.0), "BOOST spark r 6")
	t.check(t.approx(r12.spark_life[1], 0.18), "BOOST spark life 0.18")
	t.check(r12.spark_kind[1] == 2, "BOOST spark kind 2")

	s12.tick = 3
	s12.events = [[BattleState.Event.HIT, n0, n1]]
	r12.ingest(s12)
	t.check(t.approx(r12.spark_r[2], 15.6), "HIT 3-element default dmg 8.0 -> r 15.6")

	# Case 13: no spark for actor -1 (terrain kill) or KILL/LEVEL event types
	var r13 := BattleRenderer.new()
	var s13 := BattleState.new(4, 1)
	s13.tick = 1
	var p0 := s13.spawn(0.0, 0.0, 0, 0, 0, false)
	var p1 := s13.spawn(10.0, 0.0, 0, 0, 0, false)
	s13.events = [
		[BattleState.Event.KILL, p0, p1],
		[BattleState.Event.LEVEL, p0, p1],
		[BattleState.Event.HIT, -1, p1, 5.0],
	]
	r13.ingest(s13)
	t.check(r13.spark_head == 0, "no spark for KILL/LEVEL/actor -1")

	# Case 14: advance + build_spark_buffer
	r10.advance(0.125)
	var sbuf := r10.build_spark_buffer()
	t.check(sbuf.size() == BattleRenderer.SPARK_POOL * 12, "spark buffer size SPARK_POOL*12")
	t.check(t.approx(sbuf[0], 12.6), "spark0 scale b+0 12.6")
	t.check(t.approx(sbuf[5], 12.6), "spark0 scale b+5 12.6")
	t.check(t.approx(sbuf[3], 110.0), "spark0 tx b+3 110")
	t.check(t.approx(sbuf[7], 100.0), "spark0 ty b+7 100")
	t.check(t.approx(sbuf[8], 0.0), "spark0 custom b+8 0.0")
	t.check(t.approx(sbuf[9], 0.5), "spark0 custom b+9 0.5")
	var spark1_zero := true
	for k in range(12):
		if sbuf[12 + k] != 0.0:
			spark1_zero = false
	t.check(spark1_zero, "inactive spark 1 all 12 floats zero")

	# Case 15: advance past life -> spark 0 goes inactive
	r10.advance(0.2)
	var sbuf2 := r10.build_spark_buffer()
	var spark0_zero := true
	for k in range(12):
		if sbuf2[k] != 0.0:
			spark0_zero = false
	t.check(spark0_zero, "spark 0 inactive after life expires, all 12 floats zero")

	# Case 16: ring overwrite across 257 ticks
	var r16 := BattleRenderer.new()
	var s16 := BattleState.new(4, 1)
	var q0 := s16.spawn(0.0, 0.0, 0, 0, 0, false)
	var q1 := s16.spawn(50.0, 0.0, 0, 0, 0, false)
	for k in range(257):
		s16.tick = k
		s16.px[q1] = 50.0 + float(k)
		s16.events = [[BattleState.Event.HIT, q0, q1, 1.0]]
		r16.ingest(s16)
	t.check(r16.spark_head == 1, "ring buffer head wraps to 1 after 257 writes")
	t.check(t.approx(r16.spark_x[0], (0.0 + 50.0 + 256.0) / 2.0), "spark 0 holds the 257th event")

	t.finish()
	quit()
