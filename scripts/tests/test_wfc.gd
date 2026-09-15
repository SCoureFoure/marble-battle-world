extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# 1. Table
	var biome: PackedInt32Array = WorldWfc.biome_allow()
	t.check(biome == PackedInt32Array([7, 7, 15, 12]), "biome_allow == [7, 7, 15, 12]")
	t.check(WorldWfc.is_symmetric(biome), "is_symmetric(biome_allow)")
	t.check(WorldWfc.is_symmetric(PackedInt32Array([1, 2])), "is_symmetric([1, 2])")
	t.check(not WorldWfc.is_symmetric(PackedInt32Array([2, 0])), "not is_symmetric([2, 0])")

	# 2. violations on hand grids
	var grid1: PackedInt32Array = PackedInt32Array([0, 3])
	t.check(WorldWfc.violations(grid1, 2, 1, biome) == 1, "violations [0,3] 2x1 == 1")
	var grid2: PackedInt32Array = PackedInt32Array([2, 3])
	t.check(WorldWfc.violations(grid2, 2, 1, biome) == 0, "violations [2,3] 2x1 == 0")
	var grid3: PackedInt32Array = PackedInt32Array([3, 3, 3, 0])
	t.check(WorldWfc.violations(grid3, 2, 2, biome) == 2, "violations [3,3,3,0] 2x2 == 2")

	# 3. Small solve
	var r1: Dictionary = WorldWfc.solve(12, 8, biome, _ones(384), 2.0, _rng(5), 4)
	t.check(r1["grid"].size() == 96, "solve 12x8 grid size == 96")
	var all_valid_range1 := true
	for v in r1["grid"]:
		var val: int = v
		if val < 0 or val > 3:
			all_valid_range1 = false
			break
	t.check(all_valid_range1, "solve 12x8 all values in 0..3")
	t.check(WorldWfc.violations(r1["grid"], 12, 8, biome) == 0, "solve 12x8 violations == 0")
	t.check(r1["fallback"] == false, "solve 12x8 fallback == false")
	t.check(r1["attempts"] == 1, "solve 12x8 attempts == 1")

	var prior2: PackedFloat32Array = PackedFloat32Array()
	prior2.resize(64)
	prior2.fill(1.0)
	for i in range(16):
		prior2[i * 4 + 3] = 0.0
	var r2: Dictionary = WorldWfc.solve(4, 4, biome, prior2, 2.0, _rng(2), 4)
	var no_threes := true
	for v in r2["grid"]:
		var val: int = v
		if val == 3:
			no_threes = false
			break
	t.check(no_threes, "solve 4x4 no value == 3")

	var r3: Dictionary = WorldWfc.solve(0, 5, biome, PackedFloat32Array(), 2.0, _rng(1), 4)
	t.check(r3["grid"].size() == 0, "solve 0x5 grid size == 0")
	t.check(r3["attempts"] == 0, "solve 0x5 attempts == 0")
	t.check(r3["fallback"] == false, "solve 0x5 fallback == false")

	# 4. Determinism
	var r4a: Dictionary = WorldWfc.solve(12, 8, biome, _ones(384), 2.0, _rng(9), 4)
	var r4b: Dictionary = WorldWfc.solve(12, 8, biome, _ones(384), 2.0, _rng(9), 4)
	t.check(r4a["grid"] == r4b["grid"], "solve same seed -> identical grids")

	var g1 := WorldMap.new(96, 54, 11)
	var towns1: Array = WorldGen.generate(g1)
	var g2 := WorldMap.new(96, 54, 11)
	var towns2: Array = WorldGen.generate(g2)
	t.check(g1.kind == g2.kind, "generate same seed -> identical kind")
	t.check(towns1 == towns2, "generate same seed -> identical towns")

	# 5. Termination on 20 seeds (solver)
	for s in range(1, 21):
		var r5: Dictionary = WorldWfc.solve(48, 27, biome, _ones(5184), 2.0, _rng(s), 4)
		t.check(r5["grid"].size() == 1296, "s%d solve grid size == 1296" % s)
		t.check(r5["fallback"] == false, "s%d solve fallback == false" % s)
		t.check(WorldWfc.violations(r5["grid"], 48, 27, biome) == 0, "s%d solve violations == 0" % s)

	# 6. Fallback
	var r6a: Dictionary = WorldWfc.solve(3, 3, PackedInt32Array([0, 1]), _ones(18), 1.0, _rng(1), 3)
	t.check(r6a["fallback"] == true, "fallback [0,1] == true")
	t.check(r6a["attempts"] == 3, "fallback [0,1] attempts == 3")
	t.check(r6a["grid"].size() == 9, "fallback [0,1] grid size == 9")
	var all_ones := true
	for v in r6a["grid"]:
		var val: int = v
		if val != 1:
			all_ones = false
			break
	t.check(all_ones, "fallback [0,1] all values == 1")

	var r6b: Dictionary = WorldWfc.solve(3, 3, PackedInt32Array([0, 0]), _ones(18), 1.0, _rng(1), 3)
	t.check(r6b["fallback"] == true, "fallback [0,0] == true")
	var all_zeros := true
	for v in r6b["grid"]:
		var val: int = v
		if val != 0:
			all_zeros = false
			break
	t.check(all_zeros, "fallback [0,0] all values == 0")

	# 7. Rivers
	# Crafted A
	var ma := WorldMap.new(30, 30, 1)
	ma.kind[ma.idx(15, 15)] = WorldMap.Kind.HILLS
	var eleva: PackedFloat32Array = PackedFloat32Array()
	eleva.resize(900)
	eleva.fill(0.0)
	var paths_a: Array = WorldGen.carve_rivers(ma, eleva)
	t.check(paths_a.size() == 1, "carve_rivers A paths.size() == 1")
	var path_a: Array = paths_a[0]
	var expected_a: Array = []
	for x in range(15, 30):
		expected_a.append(Vector2i(x, 15))
	t.check(path_a.size() == expected_a.size(), "carve_rivers A path size == 15")
	var path_a_matches := true
	for i in range(path_a.size()):
		var p: Vector2i = path_a[i]
		var e: Vector2i = expected_a[i]
		if p != e:
			path_a_matches = false
			break
	t.check(path_a_matches, "carve_rivers A path matches [15,15]...[29,15]")
	var all_river_a := true
	for p in path_a:
		var pos: Vector2i = p
		if ma.kind[ma.idx(pos.x, pos.y)] != WorldMap.Kind.RIVER:
			all_river_a = false
			break
	t.check(all_river_a, "carve_rivers A all path tiles RIVER")

	# Crafted B
	var mb := WorldMap.new(30, 30, 1)
	mb.kind[mb.idx(15, 15)] = WorldMap.Kind.HILLS
	mb.kind[mb.idx(18, 14)] = WorldMap.Kind.MOUNTAIN
	mb.kind[mb.idx(18, 15)] = WorldMap.Kind.MOUNTAIN
	mb.kind[mb.idx(18, 16)] = WorldMap.Kind.MOUNTAIN
	mb.kind[mb.idx(19, 15)] = WorldMap.Kind.MOUNTAIN
	var elevb: PackedFloat32Array = PackedFloat32Array()
	elevb.resize(900)
	elevb.fill(0.0)
	var paths_b: Array = WorldGen.carve_rivers(mb, elevb)
	t.check(paths_b.size() >= 1, "carve_rivers B paths.size() >= 1")
	var path_b: Array = paths_b[0]
	var first_b: Vector2i = path_b[0]
	t.check(first_b == Vector2i(15, 15), "carve_rivers B paths[0][0] == (15,15)")
	var adjacent_ok := true
	for path_b_single in paths_b:
		var p_arr: Array = path_b_single
		for j in range(p_arr.size() - 1):
			var c1: Vector2i = p_arr[j]
			var c2: Vector2i = p_arr[j + 1]
			var dist: int = absi(c1.x - c2.x) + absi(c1.y - c2.y)
			if dist != 1:
				adjacent_ok = false
				break
		if not adjacent_ok:
			break
	t.check(adjacent_ok, "carve_rivers B consecutive tiles 4-adjacent")
	var no_mountain_neighbor := true
	for path_b_single in paths_b:
		var p_arr: Array = path_b_single
		for tile in p_arr:
			var t_pos: Vector2i = tile
			var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for d in neighbors:
				var nx := t_pos.x + d.x
				var ny := t_pos.y + d.y
				if mb.in_bounds(nx, ny):
					if mb.kind[mb.idx(nx, ny)] == WorldMap.Kind.MOUNTAIN:
						no_mountain_neighbor = false
						break
			if not no_mountain_neighbor:
				break
		if not no_mountain_neighbor:
			break
	t.check(no_mountain_neighbor, "carve_rivers B no MOUNTAIN neighbor")
	var last_b: Vector2i = path_b[path_b.size() - 1]
	var is_border_b := (last_b.x == 0 or last_b.x == 29 or last_b.y == 0 or last_b.y == 29)
	t.check(is_border_b, "carve_rivers B last tile is border")

	# Default maps (generate once for both case 7 and 8)
	var maps: Array = []
	var all_towns: Array = []
	for s in range(1, 21):
		var gd := WorldMap.new(96, 54, s)
		var td: Array = WorldGen.generate(gd)
		maps.append(gd)
		all_towns.append(td)

	for s_idx in range(20):
		var gm: WorldMap = maps[s_idx]
		var s: int = s_idx + 1

		# River border check
		var river_tiles: Array[Vector2i] = []
		for ty in range(gm.rows):
			for tx in range(gm.cols):
				if gm.kind[gm.idx(tx, ty)] == WorldMap.Kind.RIVER:
					river_tiles.append(Vector2i(tx, ty))

		var river_visited := {}
		var num_components := 0
		for start_tile in river_tiles:
			if river_visited.has(start_tile):
				continue
			num_components += 1
			var queue: Array[Vector2i] = [start_tile]
			river_visited[start_tile] = true
			var reaches_border := false
			while queue.size() > 0:
				var cur: Vector2i = queue.pop_front()
				if cur.x == 0 or cur.x == 95 or cur.y == 0 or cur.y == 53:
					reaches_border = true
				var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
				for d in neighbors:
					var nx := cur.x + d.x
					var ny := cur.y + d.y
					var npos := Vector2i(nx, ny)
					if gm.in_bounds(nx, ny) and not river_visited.has(npos):
						if gm.kind[gm.idx(nx, ny)] == WorldMap.Kind.RIVER:
							river_visited[npos] = true
							queue.append(npos)
			t.check(reaches_border, "s%d river comps reach border" % s)

		# Mountain neighbor check
		var mountain_neighbor_ok := true
		for ty in range(gm.rows):
			for tx in range(gm.cols):
				if gm.kind[gm.idx(tx, ty)] == WorldMap.Kind.MOUNTAIN:
					var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
					for d in neighbors:
						var nx := tx + d.x
						var ny := ty + d.y
						if gm.in_bounds(nx, ny):
							var nk: int = gm.kind[gm.idx(nx, ny)]
							if nk != WorldMap.Kind.MOUNTAIN and nk != WorldMap.Kind.HILLS:
								mountain_neighbor_ok = false
								break
					if not mountain_neighbor_ok:
						break
			if not mountain_neighbor_ok:
				break
		t.check(mountain_neighbor_ok, "s%d mountain neighbors" % s)

		# Counts
		var mountain_count := 0
		var hills_count := 0
		var forest_count := 0
		var river_count := 0
		var ruin_count := 0
		var graveyard_count := 0
		for k in gm.kind:
			var kind_val: int = k
			if kind_val == WorldMap.Kind.MOUNTAIN:
				mountain_count += 1
			elif kind_val == WorldMap.Kind.HILLS:
				hills_count += 1
			elif kind_val == WorldMap.Kind.FOREST:
				forest_count += 1
			elif kind_val == WorldMap.Kind.RIVER:
				river_count += 1
			elif kind_val == WorldMap.Kind.RUIN:
				ruin_count += 1
			elif kind_val == WorldMap.Kind.GRAVEYARD:
				graveyard_count += 1
		t.check(mountain_count >= 20, "s%d MOUNTAIN >= 20" % s)
		t.check(hills_count >= 60, "s%d HILLS >= 60" % s)
		t.check(forest_count >= 100, "s%d FOREST >= 100" % s)
		t.check(river_count >= 20, "s%d RIVER >= 20" % s)
		t.check(ruin_count == 6, "s%d RUIN == 6" % s)
		t.check(graveyard_count == 6, "s%d GRAVEYARD == 6" % s)

	# 8. Towns
	# Towns size check (using maps/towns from case 7 above)
	var towns_ref: Array = all_towns[0]
	t.check(towns_ref.size() == 24, "towns.size() == 24")

	# Towns with different count (s=1 only)
	var g_towns_17 := WorldMap.new(96, 54, 1)
	var towns_17: Array = WorldGen.generate(g_towns_17, 17)
	t.check(towns_17.size() >= 15 and towns_17.size() <= 17, "generate(m, 17) size in 15..17")

	# Town properties for all 20 seeds
	for s_idx in range(20):
		var gm: WorldMap = maps[s_idx]
		var towns_list: Array = all_towns[s_idx]
		var s: int = s_idx + 1

		# No town on border
		var border_ok := true
		for t_pos in towns_list:
			var pos: Vector2i = t_pos
			if pos.x == 0 or pos.x == 95 or pos.y == 0 or pos.y == 53:
				border_ok = false
				break
		t.check(border_ok, "s%d no town on border" % s)

		# No MOUNTAIN at Chebyshev distance 1
		var mountain_dist_ok := true
		for t_pos in towns_list:
			var pos: Vector2i = t_pos
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := pos.x + dx
					var ny := pos.y + dy
					if gm.in_bounds(nx, ny):
						if gm.kind[gm.idx(nx, ny)] == WorldMap.Kind.MOUNTAIN:
							mountain_dist_ok = false
							break
				if not mountain_dist_ok:
					break
			if not mountain_dist_ok:
				break
		t.check(mountain_dist_ok, "s%d no MOUNTAIN at Chebyshev 1" % s)

		# Every town tile is TOWN
		var all_town_kind := true
		for t_pos in towns_list:
			var pos: Vector2i = t_pos
			if gm.kind[gm.idx(pos.x, pos.y)] != WorldMap.Kind.TOWN:
				all_town_kind = false
				break
		t.check(all_town_kind, "s%d every town is TOWN kind" % s)

		# Pairwise Chebyshev spacing >= TOWN_MIN_SPACING
		var spacing_ok := true
		for i in range(towns_list.size()):
			for j in range(i + 1, towns_list.size()):
				var a: Vector2i = towns_list[i]
				var b: Vector2i = towns_list[j]
				var cheby_dist: int = maxi(absi(a.x - b.x), absi(a.y - b.y))
				if cheby_dist < Tuning.TOWN_MIN_SPACING:
					spacing_ok = false
					break
			if not spacing_ok:
				break
		t.check(spacing_ok, "s%d town Chebyshev spacing" % s)

		# Farthest-point property
		var farthest_ok := true
		for i in range(1, mini(5, towns_list.size())):
			var d_i: float = INF
			var pos_i: Vector2i = towns_list[i]
			for j in range(i):
				var pos_j: Vector2i = towns_list[j]
				var dist: float = Vector2(Vector2i(pos_i - pos_j)).length()
				if dist < d_i:
					d_i = dist
			for j in range(i + 1, towns_list.size()):
				var pos_j: Vector2i = towns_list[j]
				var dist_j: float = Vector2(Vector2i(pos_j - pos_i)).length()
				var min_to_prev: float = INF
				for k in range(i):
					var pos_k: Vector2i = towns_list[k]
					var dist_k: float = Vector2(Vector2i(pos_k - pos_j)).length()
					if dist_k < min_to_prev:
						min_to_prev = dist_k
				if min_to_prev > d_i + 0.0001:
					farthest_ok = false
					break
			if not farthest_ok:
				break
		t.check(farthest_ok, "s%d farthest-point property" % s)

		# Min pairwise Euclidean distance among towns[0..4]
		var min_pairwise: float = INF
		var check_count: int = mini(5, towns_list.size())
		for i in range(check_count):
			for j in range(i + 1, check_count):
				var a: Vector2i = towns_list[i]
				var b: Vector2i = towns_list[j]
				var dist: float = Vector2(Vector2i(a - b)).length()
				if dist < min_pairwise:
					min_pairwise = dist
		t.check(min_pairwise >= 16.0, "s%d min pairwise Euclidean >= 16" % s)

	t.finish()
	quit()


func _rng(s: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _ones(n: int) -> PackedFloat32Array:
	var arr: PackedFloat32Array = PackedFloat32Array()
	arr.resize(n)
	arr.fill(1.0)
	return arr
