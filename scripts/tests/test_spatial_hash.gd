extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1. setup basic grid
	var h1 := SpatialHash.new()
	h1.setup(Rect2(0, 0, 100, 50), 10.0)
	t.check(h1.cols == 10, "case1 cols")
	t.check(h1.rows == 5, "case1 rows")
	t.check(h1.cell_start.size() == 51, "case1 cell_start size")
	t.check(h1.scratch.size() == 64, "case1 scratch size")

	# 2. ceil rounding
	var h2 := SpatialHash.new()
	h2.setup(Rect2(0, 0, 95, 45), 10.0)
	t.check(h2.cols == 10, "case2 cols ceil")
	t.check(h2.rows == 5, "case2 rows ceil")

	# 3. cell_at (grid from case 1)
	t.check(h1.cell_at(0, 0) == 0, "case3 cell_at origin")
	t.check(h1.cell_at(15, 0) == 1, "case3 cell_at x")
	t.check(h1.cell_at(0, 15) == 10, "case3 cell_at y")
	t.check(h1.cell_at(-5, -5) == 0, "case3 cell_at negative clamp")
	t.check(h1.cell_at(1000, 1000) == 49, "case3 cell_at overflow clamp")

	# 4. build with 5 live marbles
	var px := PackedFloat32Array([5.0, 15.0, 5.0, 95.0, 5.0])
	var py := PackedFloat32Array([5.0, 5.0, 15.0, 45.0, 5.0])
	var state := PackedInt32Array([0, 0, 0, 0, 0])
	var h4 := SpatialHash.new()
	h4.setup(Rect2(0, 0, 100, 50), 10.0)
	h4.build(px, py, state, 5)
	t.check(h4.cell_of[0] == 0 and h4.cell_of[1] == 1 and h4.cell_of[2] == 10
		and h4.cell_of[3] == 49 and h4.cell_of[4] == 0, "case4 cell_of")
	t.check(h4.cell_start[0] == 0, "case4 cell_start[0]")
	t.check(h4.cell_start[1] == 2, "case4 cell_start[1]")
	t.check(h4.cell_start[2] == 3, "case4 cell_start[2]")
	t.check(h4.cell_start[11] == 4, "case4 cell_start[11]")
	t.check(h4.cell_start[50] == 5, "case4 cell_start[50]")
	var cell0_entries := [h4.entries[0], h4.entries[1]]
	t.check(cell0_entries.has(0) and cell0_entries.has(4), "case4 cell0 entries")

	# 5. one DEAD marble
	var state5 := PackedInt32Array([0, 2, 0, 0, 0])
	var h5 := SpatialHash.new()
	h5.setup(Rect2(0, 0, 100, 50), 10.0)
	h5.build(px, py, state5, 5)
	t.check(h5.cell_of[1] == -1, "case5 dead cell_of")
	t.check(h5.cell_start[50] == 4, "case5 live count")
	var k5 := h5.gather(15, 5)
	var found := []
	for idx in range(k5):
		found.append(h5.scratch[idx])
	t.check(k5 == 3, "case5 gather count")
	t.check(not found.has(1), "case5 dead absent")
	t.check(found.has(0) and found.has(2) and found.has(4), "case5 live present")

	# 6. corner gather
	var k6 := h4.gather(95, 45)
	t.check(k6 == 1, "case6 gather count")
	t.check(h4.scratch[0] == 3, "case6 gather value")

	# 7. truncation
	var h7 := SpatialHash.new()
	h7.setup(Rect2(0, 0, 10, 10), 10.0)
	var px7 := PackedFloat32Array()
	var py7 := PackedFloat32Array()
	var state7 := PackedInt32Array()
	px7.resize(100)
	py7.resize(100)
	state7.resize(100)
	for i in 100:
		px7[i] = 5.0
		py7[i] = 5.0
		state7[i] = 0
	h7.build(px7, py7, state7, 100)
	t.check(h7.gather(5, 5) == 64, "case7 truncation")

	# 8. rebuild is idempotent
	h4.build(px, py, state, 5)
	t.check(h4.cell_of[0] == 0 and h4.cell_of[1] == 1 and h4.cell_of[2] == 10
		and h4.cell_of[3] == 49 and h4.cell_of[4] == 0, "case8 rebuild cell_of")
	t.check(h4.cell_start[50] == 5, "case8 rebuild cell_start")

	# 9. n == 0
	var h9 := SpatialHash.new()
	h9.setup(Rect2(0, 0, 100, 50), 10.0)
	h9.build(PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(), 0)
	t.check(h9.cell_start[50] == 0, "case9 empty cell_start")
	t.check(h9.gather(5, 5) == 0, "case9 empty gather")

	t.finish()
	quit()
