extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1. straight line, start dropped, tile centres
	var m1 := WorldMap.new(12, 8, 1)
	var p1 := Pathing.new(m1)
	var path1 := p1.find(Vector2i(0, 0), Vector2i(3, 0))
	t.check(path1.size() == 3, "case1 size")
	t.check(path1[2] == m1.center_of(3, 0), "case1 last point")
	t.check(path1[0] == m1.center_of(1, 0), "case1 first point")

	# 2. from == to
	var m2 := WorldMap.new(12, 8, 1)
	var p2 := Pathing.new(m2)
	var path2 := p2.find(Vector2i(4, 4), Vector2i(4, 4))
	t.check(path2.size() == 0, "case2 size")

	# 3. wall with a gap at row 7 — refresh() picks up the edit
	var m3 := WorldMap.new(12, 8, 1)
	var p3 := Pathing.new(m3)
	for y in range(0, 7):
		m3.kind[m3.idx(5, y)] = WorldMap.Kind.MOUNTAIN
	p3.refresh(m3)
	var path3 := p3.find(Vector2i(0, 0), Vector2i(11, 0))
	t.check(path3.size() > 0, "case3 non-empty")
	var all_passable3 := true
	var found_gap3 := false
	for pt3 in path3:
		var tc3: Vector2i = m3.tile_of(pt3.x, pt3.y)
		if not m3.passable(tc3.x, tc3.y):
			all_passable3 = false
		if tc3.y == 7:
			found_gap3 = true
	t.check(all_passable3, "case3 all points passable")
	t.check(found_gap3, "case3 path uses the gap")
	t.check(path3.size() >= 13, "case3 path length (diagonal)")

	# 4. full wall, no gap — unreachable
	var m4 := WorldMap.new(12, 8, 1)
	var p4 := Pathing.new(m4)
	for y in range(0, 8):
		m4.kind[m4.idx(5, y)] = WorldMap.Kind.MOUNTAIN
	p4.refresh(m4)
	var path4 := p4.find(Vector2i(0, 0), Vector2i(11, 0))
	t.check(path4.size() == 0, "case4 unreachable")

	# 5. cost steers around an expensive row
	var m5 := WorldMap.new(12, 8, 1)
	var p5 := Pathing.new(m5)
	for x in range(1, 11):
		m5.kind[m5.idx(x, 0)] = WorldMap.Kind.HILLS
	p5.refresh(m5)
	var path5 := p5.find(Vector2i(0, 0), Vector2i(11, 0))
	var row0_count5 := 0
	for pt5 in path5:
		var tc5: Vector2i = m5.tile_of(pt5.x, pt5.y)
		if tc5.y == 0:
			row0_count5 += 1
	t.check(row0_count5 <= 3, "case5 avoids the costly row")

	# 6. diagonal steps
	var m6 := WorldMap.new(12, 8, 1)
	var p6 := Pathing.new(m6)
	var path6 := p6.find(Vector2i(0, 0), Vector2i(2, 2))
	t.check(path6.size() == 2, "case6 size")
	t.check(path6[0] == m6.center_of(1, 1), "case6 first point")
	t.check(path6[1] == m6.center_of(2, 2), "case6 last point")

	t.finish()
	quit()
