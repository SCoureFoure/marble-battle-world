extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1-5. facing_for
	t.check(BattleRenderer.facing_for(0.0, 0.0, 3) == 3, "case1 facing_for idle keeps prev")
	t.check(BattleRenderer.facing_for(-50.0, 10.0, 0) == 1, "case2 facing_for left")
	t.check(BattleRenderer.facing_for(50.0, -10.0, 0) == 2, "case3 facing_for right")
	t.check(BattleRenderer.facing_for(5.0, -60.0, 0) == 3, "case4 facing_for away")
	t.check(BattleRenderer.facing_for(5.0, 60.0, 2) == 0, "case5 facing_for toward camera")

	# 6-10. walk_frame
	t.check(BattleRenderer.walk_frame(7.0, 0.0) == 1, "case6 walk_frame idle")
	t.check(BattleRenderer.walk_frame(0.2, 50.0) == 0, "case7 walk_frame step 0")
	t.check(BattleRenderer.walk_frame(2.0, 50.0) == 2, "case8 walk_frame step 2")
	t.check(BattleRenderer.walk_frame(3.9, 50.0) == 1, "case9 walk_frame step 1 (wrap)")
	t.check(BattleRenderer.walk_frame(4.0, 50.0) == 0, "case10 walk_frame step 0 (wrap)")

	# Buffer
	var s := BattleState.new(4, 1)
	var a := s.spawn(100.0, 200.0, 1, 0, 0, false)
	var d := s.spawn(300.0, 50.0, 0, 0, 0, false)
	s.state[d] = BattleState.State.DEAD
	var buf := BattleRenderer.build_unit_buffer(s, PackedByteArray([2, 0]), PackedFloat32Array([2.0, 0.0]))

	t.check(buf.size() == 24, "case11 buffer size")
	t.check(t.approx(buf[0], 11.2) and t.approx(buf[5], 11.2), "case12 sprite half-size")
	t.check(t.approx(buf[3], 100.0) and t.approx(buf[7], 197.2), "case13 sprite position")
	t.check(t.approx(buf[8], 1.0), "case14 faction slot")
	t.check(t.approx(buf[9], 2.0), "case15 facing right")
	t.check(t.approx(buf[10], 1.0), "case16 idle frame")
	t.check(t.approx(buf[11], 1.0), "case17 alpha")
	t.check(buf[12] == 0.0 and buf[23] == 0.0 and t.approx(buf[15], 300.0) and t.approx(buf[19], 50.0), "case18 dead marble")

	t.check(BattleRenderer.build_unit_buffer(BattleState.new(4, 1), PackedByteArray(), PackedFloat32Array()).size() == 0, "case19 empty state")
	t.check(ResourceLoader.exists(BattleRenderer.UNIT_SHADER), "case20 unit shader exists")

	# 21. hero slot overrides faction slot
	var hero_buf := BattleRenderer.build_unit_buffer(s, PackedByteArray([2, 0]), PackedFloat32Array([2.0, 0.0]), PackedInt32Array([17, -1]))
	t.check(hero_buf[8] == 17.0, "case21 hero slot")

	# 22. -1 slot falls back to faction slot
	var no_hero_buf := BattleRenderer.build_unit_buffer(s, PackedByteArray([2, 0]), PackedFloat32Array([2.0, 0.0]), PackedInt32Array([-1, -1]))
	t.check(t.approx(no_hero_buf[8], 1.0), "case22 faction slot fallback")

	# 23. set_hero_looks assigns hero slots in ascending marble-index order
	var r := BattleRenderer.new()
	r.set_hero_looks({3: CharLooks.generic_warrior(), 1: CharLooks.generic_warrior()})
	t.check(r.hero_slots.size() == 4 and r.hero_slots[1] == 16 and r.hero_slots[3] == 17 and r.hero_slots[0] == -1 and r._hero_looks.size() == 2, "case23 set_hero_looks")
	r.free()

	t.finish()
	quit()
