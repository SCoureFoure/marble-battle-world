extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	var G := TerrainGrid.new()
	G.setup(Rect2(0, 0, 1600, 900), 40.0)

	# 1. setup
	t.check(G.cols == 40, "case1 cols")
	t.check(G.rows == 23, "case1 rows")
	t.check(G.kind.size() == 920, "case1 kind size")
	t.check(G.owner.size() == 920, "case1 owner size")
	t.check(G.owner[5] == -1, "case1 owner default")
	t.check(G.kind[5] == TerrainGrid.Kind.PLAIN, "case1 kind default")
	t.check(G.slope_x.size() == 920, "case1 slope_x size")

	# 2. cell_at
	t.check(G.cell_at(0, 0) == 0, "case2 cell_at origin")
	t.check(G.cell_at(45, 0) == 1, "case2 cell_at x")
	t.check(G.cell_at(0, 45) == 40, "case2 cell_at y")
	t.check(G.cell_at(-1, -1) == 0, "case2 cell_at negative clamp")
	t.check(G.cell_at(5000, 5000) == 919, "case2 cell_at overflow clamp")
	t.check(G.cell_at(800, 450) == 460, "case2 cell_at mid")

	# 3. set_cell / kind_at
	G.set_cell(2, 3, TerrainGrid.Kind.MUD)
	t.check(G.kind[122] == TerrainGrid.Kind.MUD, "case3 kind array")
	t.check(G.kind_at(85, 125) == TerrainGrid.Kind.MUD, "case3 kind_at hit")
	t.check(G.kind_at(85, 85) == TerrainGrid.Kind.PLAIN, "case3 kind_at miss")

	# 4. fill_rect clamp
	G.fill_rect(38, 21, 45, 30, TerrainGrid.Kind.ICE)
	var ice_count4 := 0
	for i in G.kind.size():
		if G.kind[i] == TerrainGrid.Kind.ICE:
			ice_count4 += 1
	t.check(ice_count4 == 4, "case4 ice count")
	t.check(G.kind[22 * 40 + 39] == TerrainGrid.Kind.ICE, "case4 ice corner")

	# 5. friction_of
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.PLAIN), 0.92), "case5 friction plain")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.MUD), 0.80), "case5 friction mud")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.COBBLE), 0.98), "case5 friction cobble")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.ICE), 0.99), "case5 friction ice")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.WATER), 0.70), "case5 friction water")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.ROCK), 0.92), "case5 friction rock")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.TOWER), 0.92), "case5 friction tower")
	t.check(t.approx(G.friction_of(TerrainGrid.Kind.FIRE), 0.92), "case5 friction fire")

	# 6. is_solid
	t.check(TerrainGrid.is_solid(TerrainGrid.Kind.ROCK), "case6 rock solid")
	t.check(TerrainGrid.is_solid(TerrainGrid.Kind.TREE), "case6 tree solid")
	t.check(not TerrainGrid.is_solid(TerrainGrid.Kind.WATER), "case6 water not solid")
	t.check(not TerrainGrid.is_solid(TerrainGrid.Kind.TOWER), "case6 tower not solid")
	t.check(not TerrainGrid.is_solid(TerrainGrid.Kind.PLAIN), "case6 plain not solid")

	# 7. cell_center
	t.check(G.cell_center(0) == Vector2(20, 20), "case7 cell_center 0")
	t.check(G.cell_center(41) == Vector2(60, 60), "case7 cell_center 41")
	t.check(G.cell_center(919) == Vector2(1580, 900), "case7 cell_center 919")

	# 8. set_slope
	G.set_slope(1, 1, Vector2(0, 50))
	t.check(G.slope_y[41] == 50.0, "case8 slope_y set")
	t.check(G.slope_x[41] == 0.0, "case8 slope_x unset")
	G.set_slope(99, 99, Vector2(1, 1))
	t.check(G.slope_y[41] == 50.0, "case8 out-of-range no-op")

	# 9. set_cell out of range
	var mud_count_before := 0
	for i in G.kind.size():
		if G.kind[i] == TerrainGrid.Kind.MUD:
			mud_count_before += 1
	G.set_cell(99, 99, TerrainGrid.Kind.MUD)
	var mud_count_after := 0
	for i in G.kind.size():
		if G.kind[i] == TerrainGrid.Kind.MUD:
			mud_count_after += 1
	t.check(mud_count_after == mud_count_before, "case9 set_cell out-of-range no-op")

	# 10. demo
	var G2 := TerrainGrid.new()
	G2.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	TerrainGen.demo(G2, rng)

	var tower_count := 0
	var tower_idx := -1
	var fire_count := 0
	var ice_count10 := 0
	var mud_count10 := 0
	var cobble_count10 := 0
	var rock_tree_count := 0
	var rock_tree_x_ok := true
	for i in G2.kind.size():
		var k: int = G2.kind[i]
		if k == TerrainGrid.Kind.TOWER:
			tower_count += 1
			tower_idx = i
		elif k == TerrainGrid.Kind.FIRE:
			fire_count += 1
		elif k == TerrainGrid.Kind.ICE:
			ice_count10 += 1
		elif k == TerrainGrid.Kind.MUD:
			mud_count10 += 1
		elif k == TerrainGrid.Kind.COBBLE:
			cobble_count10 += 1
		elif k == TerrainGrid.Kind.ROCK or k == TerrainGrid.Kind.TREE:
			rock_tree_count += 1
			var cx: float = G2.cell_center(i).x
			if cx < 640 or cx > 1000:
				rock_tree_x_ok = false

	t.check(tower_count == 1, "case10 one tower")
	t.check(tower_idx == 460, "case10 tower index")
	t.check(fire_count == 4, "case10 fire count")
	t.check(ice_count10 == 9, "case10 ice count")
	t.check(rock_tree_count >= 6 and rock_tree_count <= 12, "case10 rock/tree count range")
	t.check(rock_tree_x_ok, "case10 rock/tree x in spawn-free band")
	t.check(mud_count10 > 0, "case10 mud count positive")
	t.check(cobble_count10 >= 70, "case10 cobble count")
	var slope_ok := true
	for c in range(0, 80):
		if G2.slope_y[c] != 40.0:
			slope_ok = false
	t.check(slope_ok, "case10 slope band top two rows")
	t.check(G2.slope_y[80] == 0.0, "case10 slope band stops at row two")

	var G3 := TerrainGrid.new()
	G3.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 7
	TerrainGen.demo(G3, rng3)
	t.check(G2.kind == G3.kind, "case10 deterministic replay")

	# 11. finalize: near_solid + friction tables, dirty flag.
	var G4 := TerrainGrid.new()
	G4.setup(Rect2(0, 0, 1600, 900), 40.0)
	G4.set_cell(5, 5, TerrainGrid.Kind.ROCK)
	G4.finalize()
	t.check(G4.near_solid[5 * 40 + 5] == 1, "case11 near_solid center")
	t.check(G4.near_solid[4 * 40 + 4] == 1, "case11 near_solid corner in range")
	t.check(G4.near_solid[6 * 40 + 6] == 1, "case11 near_solid opposite corner in range")
	t.check(G4.near_solid[3 * 40 + 3] == 0, "case11 near_solid out of range")
	t.check(G4.near_solid[5 * 40 + 7] == 0, "case11 near_solid out of range x")
	t.check(t.approx(G4.friction[5 * 40 + 5], 0.92), "case11 friction rock approx 0.92")
	G4.set_cell(0, 0, TerrainGrid.Kind.MUD)
	t.check(G4.dirty == true, "case11 dirty after set_cell")
	G4.finalize()
	t.check(t.approx(G4.friction[0], 0.80), "case11 friction mud approx 0.80")

	t.finish()
	quit()
