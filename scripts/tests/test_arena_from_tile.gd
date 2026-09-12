extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()
	var edges := PackedInt32Array([0, 1])

	# 1. spawn_rect
	t.check(BattleBridge.spawn_rect(0) == Rect2(40, 100, 360, 700), "case1 spawn_rect 0")
	t.check(BattleBridge.spawn_rect(3) == Rect2(300, 620, 1000, 240), "case1 spawn_rect 3")

	# 2. edge_for
	var c := Vector2(800, 450)
	t.check(BattleBridge.edge_for(c, Vector2(100, 450), PackedInt32Array([])) == 0, "case2 edge_for west")
	t.check(BattleBridge.edge_for(c, Vector2(1500, 450), PackedInt32Array([])) == 1, "case2 edge_for east")
	t.check(BattleBridge.edge_for(c, Vector2(800, 0), PackedInt32Array([])) == 2, "case2 edge_for north")
	t.check(BattleBridge.edge_for(c, Vector2(800, 900), PackedInt32Array([])) == 3, "case2 edge_for south")
	t.check(BattleBridge.edge_for(c, Vector2(100, 450), PackedInt32Array([0])) == 1, "case2 edge_for west taken -> east")
	t.check(BattleBridge.edge_for(c, Vector2(100, 450), PackedInt32Array([0, 1])) == 2, "case2 edge_for west+east taken -> north")
	t.check(BattleBridge.edge_for(c, Vector2(100, 450), PackedInt32Array([0, 1, 2, 3])) == -1, "case2 edge_for all taken")
	t.check(BattleBridge.edge_for(c, Vector2(700, 350), PackedInt32Array([])) == 0, "case2 edge_for tie goes x")

	# 3. FOREST
	var g3 := TerrainGrid.new()
	g3.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 3
	TerrainGen.from_tile(g3, WorldMap.Kind.FOREST, edges, rng3)
	var tree_count3 := 0
	var mud_count3 := 0
	var tree_in_spawn3 := false
	for i in g3.kind.size():
		var k3: int = g3.kind[i]
		if k3 == TerrainGrid.Kind.TREE:
			tree_count3 += 1
			var p3: Vector2 = g3.cell_center(i)
			if BattleBridge.spawn_rect(0).has_point(p3) or BattleBridge.spawn_rect(1).has_point(p3):
				tree_in_spawn3 = true
		elif k3 == TerrainGrid.Kind.MUD:
			mud_count3 += 1
	t.check(tree_count3 >= 10 and tree_count3 <= 20, "case3 forest tree count range")
	t.check(mud_count3 > 0, "case3 forest mud count positive")
	t.check(not tree_in_spawn3, "case3 forest no tree in spawn rects 0/1")

	# 4. RIVER
	var g4 := TerrainGrid.new()
	g4.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 3
	TerrainGen.from_tile(g4, WorldMap.Kind.RIVER, edges, rng4)
	var water_count4 := 0
	for i in g4.kind.size():
		if g4.kind[i] == TerrainGrid.Kind.WATER:
			water_count4 += 1
	t.check(water_count4 == 2 * 23 - 6, "case4 river water count")
	var ford_ok4 := true
	for cy in range(10, 13):
		for cx in range(19, 21):
			if g4.kind[cy * g4.cols + cx] != TerrainGrid.Kind.COBBLE:
				ford_ok4 = false
	t.check(ford_ok4, "case4 river ford cobble")

	# 5. TOWN
	var g5 := TerrainGrid.new()
	g5.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng5 := RandomNumberGenerator.new()
	rng5.seed = 3
	TerrainGen.from_tile(g5, WorldMap.Kind.TOWN, edges, rng5)
	t.check(g5.kind[11 * 40 + 20] == TerrainGrid.Kind.TOWER, "case5 town tower")
	t.check(g5.kind[12 * 40 + 5] == TerrainGrid.Kind.COBBLE, "case5 town cobble row")
	t.check(g5.kind[3 * 40 + 19] == TerrainGrid.Kind.COBBLE, "case5 town cobble col")
	var tree_count5 := 0
	for i in g5.kind.size():
		if g5.kind[i] == TerrainGrid.Kind.TREE:
			tree_count5 += 1
	t.check(tree_count5 >= 1 and tree_count5 <= 4, "case5 town tree count range")

	# 6. HILLS
	var g6 := TerrainGrid.new()
	g6.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng6 := RandomNumberGenerator.new()
	rng6.seed = 3
	TerrainGen.from_tile(g6, WorldMap.Kind.HILLS, edges, rng6)
	t.check(g6.slope_y[0] == 40.0, "case6 hills slope row0")
	t.check(g6.slope_y[7 * 40] == 40.0, "case6 hills slope row7")
	t.check(g6.slope_y[8 * 40] == 0.0, "case6 hills slope row8")
	t.check(g6.slope_y[15 * 40] == -40.0, "case6 hills slope row15")
	t.check(g6.slope_y[22 * 40] == -40.0, "case6 hills slope row22")
	var rock_tree6 := 0
	for i in g6.kind.size():
		if g6.kind[i] == TerrainGrid.Kind.ROCK or g6.kind[i] == TerrainGrid.Kind.TREE:
			rock_tree6 += 1
	t.check(rock_tree6 <= 6, "case6 hills rock+tree count")

	# 7. RUIN
	var g7 := TerrainGrid.new()
	g7.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng7 := RandomNumberGenerator.new()
	rng7.seed = 3
	TerrainGen.from_tile(g7, WorldMap.Kind.RUIN, edges, rng7)
	var fire_count7 := 0
	var cobble_count7 := 0
	for i in g7.kind.size():
		if g7.kind[i] == TerrainGrid.Kind.FIRE:
			fire_count7 += 1
		elif g7.kind[i] == TerrainGrid.Kind.COBBLE:
			cobble_count7 += 1
	t.check(fire_count7 == 12, "case7 ruin fire count")
	t.check(cobble_count7 >= 70, "case7 ruin cobble count")

	# 8. GRAVEYARD
	var g8 := TerrainGrid.new()
	g8.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng8 := RandomNumberGenerator.new()
	rng8.seed = 3
	TerrainGen.from_tile(g8, WorldMap.Kind.GRAVEYARD, edges, rng8)
	var spike_count8 := 0
	var mud_count8 := 0
	for i in g8.kind.size():
		if g8.kind[i] == TerrainGrid.Kind.SPIKE:
			spike_count8 += 1
		elif g8.kind[i] == TerrainGrid.Kind.MUD:
			mud_count8 += 1
	t.check(spike_count8 == 4, "case8 graveyard spike count")
	t.check(mud_count8 > 0, "case8 graveyard mud count")

	# 9. MOUNTAIN
	var g9 := TerrainGrid.new()
	g9.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng9 := RandomNumberGenerator.new()
	rng9.seed = 3
	TerrainGen.from_tile(g9, WorldMap.Kind.MOUNTAIN, edges, rng9)
	var all_plain9 := true
	for i in g9.kind.size():
		if g9.kind[i] != TerrainGrid.Kind.PLAIN:
			all_plain9 = false
	t.check(all_plain9, "case9 mountain unchanged")

	# 10. Determinism
	var g10a := TerrainGrid.new()
	g10a.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng10a := RandomNumberGenerator.new()
	rng10a.seed = 3
	TerrainGen.from_tile(g10a, WorldMap.Kind.FOREST, edges, rng10a)

	var g10b := TerrainGrid.new()
	g10b.setup(Rect2(0, 0, 1600, 900), 40.0)
	var rng10b := RandomNumberGenerator.new()
	rng10b.seed = 3
	TerrainGen.from_tile(g10b, WorldMap.Kind.FOREST, edges, rng10b)
	t.check(g10a.kind == g10b.kind, "case10 forest deterministic replay")

	t.finish()
	quit()
