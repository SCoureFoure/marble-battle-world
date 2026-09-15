class_name WorldGen
extends RefCounted
## Overworld map generation. Source: docs/ARCHITECTURE.md §11.2.

static func generate(m: WorldMap, town_count: int = -1) -> Array:
	if town_count == -1:
		town_count = Tuning.N_FACTIONS * Tuning.TOWNS_PER_FACTION + Tuning.NEUTRAL_TOWNS
	if not Tuning.WORLDGEN_WFC:
		return _generate_noise(m, town_count)

	# Order of rng use: elevation seed (forest seed derived, no draw), biome
	# WFC observations, rivers, ruins, graveyards, towns.
	var elevation := PackedFloat32Array()
	elevation.resize(m.cols * m.rows)

	var elev_seed := m.rng.randi()
	var forest_seed := elev_seed + 1

	var elev_noise := FastNoiseLite.new()
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.frequency = 0.05
	elev_noise.seed = elev_seed

	var forest_noise := FastNoiseLite.new()
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = 0.08
	forest_noise.seed = forest_seed

	for ty in range(m.rows):
		for tx in range(m.cols):
			elevation[m.idx(tx, ty)] = elev_noise.get_noise_2d(float(tx), float(ty))

	var ccols: int = ceili(float(m.cols) / Tuning.WFC_CELL)
	var crows: int = ceili(float(m.rows) / Tuning.WFC_CELL)
	var prior := PackedFloat32Array()
	prior.resize(ccols * crows * 4)
	for cy in range(crows):
		for cx in range(ccols):
			var px: float = cx * Tuning.WFC_CELL + (Tuning.WFC_CELL - 1) * 0.5
			var py: float = cy * Tuning.WFC_CELL + (Tuning.WFC_CELL - 1) * 0.5
			var e: float = elev_noise.get_noise_2d(px, py)
			var f: float = forest_noise.get_noise_2d(px, py)
			var fb: float = 2.0 if f > 0.15 else 0.25
			var ci: int = (cy * ccols + cx) * 4
			if e <= 0.10:
				prior[ci + 0] = 1.0
				prior[ci + 1] = 1.0 * fb
				prior[ci + 2] = 0.10
				prior[ci + 3] = 0.0
			elif e <= 0.30:
				prior[ci + 0] = 0.4
				prior[ci + 1] = 0.4 * fb
				prior[ci + 2] = 1.0
				prior[ci + 3] = 0.02
			elif e <= 0.45:
				prior[ci + 0] = 0.05
				prior[ci + 1] = 0.05
				prior[ci + 2] = 1.0
				prior[ci + 3] = 0.6
			else:
				prior[ci + 0] = 0.0
				prior[ci + 1] = 0.0
				prior[ci + 2] = 0.4
				prior[ci + 3] = 3.0

	var res: Dictionary = WorldWfc.solve(ccols, crows, WorldWfc.biome_allow(), prior, Tuning.WFC_AFFINITY, m.rng, Tuning.WFC_MAX_ATTEMPTS)
	var grid: PackedInt32Array = res["grid"]
	for ty in range(m.rows):
		for tx in range(m.cols):
			var cell: int = (ty / Tuning.WFC_CELL) * ccols + (tx / Tuning.WFC_CELL)
			m.kind[m.idx(tx, ty)] = grid[cell]

	carve_rivers(m, elevation)
	_cleanup_slivers(m)
	_scatter_bounded(m, WorldMap.Kind.RUIN, 6)
	_scatter_bounded(m, WorldMap.Kind.GRAVEYARD, 6)

	var towns := _place_towns_scored(m, town_count)
	_fix_isolated_towns(m, towns)
	towns = _farthest_point_order(m, towns)
	return towns


static func _generate_noise(m: WorldMap, town_count: int) -> Array:
	var elevation := PackedFloat32Array()
	elevation.resize(m.cols * m.rows)

	# Order of rng use: elevation seed, forest seed (derived, no extra draw),
	# then rivers, ruins, graveyards, towns.
	var elev_seed := m.rng.randi()
	var forest_seed := elev_seed + 1

	var elev_noise := FastNoiseLite.new()
	elev_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elev_noise.frequency = 0.05
	elev_noise.seed = elev_seed

	var forest_noise := FastNoiseLite.new()
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest_noise.frequency = 0.08
	forest_noise.seed = forest_seed

	for ty in range(m.rows):
		for tx in range(m.cols):
			var i := m.idx(tx, ty)
			var e := elev_noise.get_noise_2d(float(tx), float(ty))
			elevation[i] = e
			if e > 0.45:
				m.kind[i] = WorldMap.Kind.MOUNTAIN
			elif e > 0.2:
				m.kind[i] = WorldMap.Kind.HILLS
			else:
				m.kind[i] = WorldMap.Kind.PLAINS

	for ty in range(m.rows):
		for tx in range(m.cols):
			var i := m.idx(tx, ty)
			if m.kind[i] != WorldMap.Kind.PLAINS:
				continue
			var f := forest_noise.get_noise_2d(float(tx), float(ty))
			if f > 0.25:
				m.kind[i] = WorldMap.Kind.FOREST

	_carve_rivers(m, elevation)
	_scatter(m, WorldMap.Kind.RUIN, 6)
	_scatter(m, WorldMap.Kind.GRAVEYARD, 6)

	if town_count == -1:
		town_count = Tuning.N_FACTIONS * Tuning.TOWNS_PER_FACTION + Tuning.NEUTRAL_TOWNS
	var towns: Array[Vector2i] = []
	for i in range(town_count):
		var placed := _place_town(m, towns)
		if placed != Vector2i(-1, -1):
			towns.append(placed)

	_fix_isolated_towns(m, towns)

	return towns


static func carve_rivers(m: WorldMap, elevation: PackedFloat32Array) -> Array:
	var cols := m.cols
	var rows := m.rows
	var n := cols * rows
	var neigh: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	var ok := PackedByteArray()
	ok.resize(n)
	for ty in range(rows):
		for tx in range(cols):
			var i := m.idx(tx, ty)
			var tile_ok := true
			if m.kind[i] == WorldMap.Kind.MOUNTAIN:
				tile_ok = false
			else:
				for d in neigh:
					var nx: int = tx + d.x
					var ny: int = ty + d.y
					if m.in_bounds(nx, ny) and m.kind[m.idx(nx, ny)] == WorldMap.Kind.MOUNTAIN:
						tile_ok = false
						break
			ok[i] = 1 if tile_ok else 0

	# Multi-source BFS from all `ok` border tiles -> steps (unreached = -1).
	var steps := PackedInt32Array()
	steps.resize(n)
	steps.fill(-1)
	var queue: Array[int] = []
	for ty in range(rows):
		for tx in range(cols):
			var i := m.idx(tx, ty)
			if ok[i] == 1 and _is_border(tx, ty, cols, rows):
				steps[i] = 0
				queue.append(i)
	var qhead := 0
	while qhead < queue.size():
		var cur: int = queue[qhead]
		qhead += 1
		var cx: int = cur % cols
		var cy: int = cur / cols
		for d in neigh:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if not m.in_bounds(nx, ny):
				continue
			var ni: int = m.idx(nx, ny)
			if ok[ni] == 0 or steps[ni] != -1:
				continue
			steps[ni] = steps[cur] + 1
			queue.append(ni)

	# Multi-source Dijkstra from all `ok` border tiles -> flow (unreached = INF).
	var flow := PackedFloat32Array()
	flow.resize(n)
	flow.fill(INF)
	var heap_d := PackedFloat32Array()
	var heap_i := PackedInt32Array()
	for ty in range(rows):
		for tx in range(cols):
			var i := m.idx(tx, ty)
			if ok[i] == 1 and _is_border(tx, ty, cols, rows):
				flow[i] = 0.0
				_heap_push(heap_d, heap_i, 0.0, i)
	while heap_d.size() > 0:
		var top: Array = _heap_pop(heap_d, heap_i)
		var d0: float = top[0]
		var u: int = top[1]
		if d0 > flow[u]:
			continue
		var ux: int = u % cols
		var uy: int = u / cols
		for d in neigh:
			var vx: int = ux + d.x
			var vy: int = uy + d.y
			if not m.in_bounds(vx, vy):
				continue
			var v: int = m.idx(vx, vy)
			if ok[v] == 0:
				continue
			var cost: float = 1.0 + Tuning.RIVER_ELEV_COST * maxf(elevation[v], 0.0)
			var nd: float = d0 + cost
			if nd < flow[v]:
				flow[v] = nd
				_heap_push(heap_d, heap_i, nd, v)

	var rivers: Array = []
	var sources: Array[Vector2i] = []
	var river_count: int = maxi(2, cols / 32)
	for r in range(river_count):
		var candidates: Array[int] = []
		for ci in range(n):
			if m.kind[ci] != WorldMap.Kind.HILLS:
				continue
			if ok[ci] == 0:
				continue
			if steps[ci] < Tuning.RIVER_MIN_LENGTH:
				continue
			var tx3: int = ci % cols
			var ty3: int = ci / cols
			var far_enough := true
			for s in sources:
				if maxi(absi(tx3 - s.x), absi(ty3 - s.y)) <= Tuning.RIVER_SOURCE_SPACING:
					far_enough = false
					break
			if far_enough:
				candidates.append(ci)
		if candidates.is_empty():
			for ci in range(n):
				if m.kind[ci] == WorldMap.Kind.RIVER:
					continue
				if ok[ci] == 0:
					continue
				if steps[ci] < Tuning.RIVER_MIN_LENGTH:
					continue
				var tx4: int = ci % cols
				var ty4: int = ci / cols
				var far_enough2 := true
				for s in sources:
					if maxi(absi(tx4 - s.x), absi(ty4 - s.y)) <= Tuning.RIVER_SOURCE_SPACING:
						far_enough2 = false
						break
				if far_enough2:
					candidates.append(ci)
		if candidates.is_empty():
			continue
		var src_i: int = candidates[m.rng.randi_range(0, candidates.size() - 1)]
		var sx: int = src_i % cols
		var sy: int = src_i / cols
		sources.append(Vector2i(sx, sy))
		var path: Array[Vector2i] = []
		var cx2: int = sx
		var cy2: int = sy
		while true:
			m.kind[m.idx(cx2, cy2)] = WorldMap.Kind.RIVER
			path.append(Vector2i(cx2, cy2))
			if _is_border(cx2, cy2, cols, rows):
				break
			var best_flow: float = INF
			var best_x := -1
			var best_y := -1
			var cur_flow: float = flow[m.idx(cx2, cy2)]
			for d in neigh:
				var nx3: int = cx2 + d.x
				var ny3: int = cy2 + d.y
				if not m.in_bounds(nx3, ny3):
					continue
				if ok[m.idx(nx3, ny3)] == 0:
					continue
				var nf: float = flow[m.idx(nx3, ny3)]
				if nf < cur_flow and nf < best_flow:
					best_flow = nf
					best_x = nx3
					best_y = ny3
			if best_x == -1:
				break
			if m.kind[m.idx(best_x, best_y)] == WorldMap.Kind.RIVER:
				break
			cx2 = best_x
			cy2 = best_y
		rivers.append(path)
	return rivers


static func _cleanup_slivers(m: WorldMap) -> void:
	var before: PackedByteArray = m.kind.duplicate()
	var corners: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]
	var neigh: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for ty in range(m.rows):
		for tx in range(m.cols):
			var i := m.idx(tx, ty)
			var k: int = before[i]
			if k == WorldMap.Kind.FOREST:
				var in_block := false
				for o in corners:
					if _block_all(before, m, tx + o.x, ty + o.y, [WorldMap.Kind.FOREST]):
						in_block = true
						break
				if not in_block:
					m.kind[i] = WorldMap.Kind.PLAINS
			elif k == WorldMap.Kind.HILLS:
				var in_block2 := false
				for o in corners:
					if _block_all(before, m, tx + o.x, ty + o.y, [WorldMap.Kind.HILLS, WorldMap.Kind.MOUNTAIN]):
						in_block2 = true
						break
				if not in_block2:
					var near_mountain := false
					for d in neigh:
						var nx: int = tx + d.x
						var ny: int = ty + d.y
						if m.in_bounds(nx, ny) and before[m.idx(nx, ny)] == WorldMap.Kind.MOUNTAIN:
							near_mountain = true
							break
					if not near_mountain:
						m.kind[i] = WorldMap.Kind.PLAINS


static func _scatter_bounded(m: WorldMap, k: int, count: int) -> void:
	for i in range(count):
		for attempt in range(10000):
			var tx := m.rng.randi_range(0, m.cols - 1)
			var ty := m.rng.randi_range(0, m.rows - 1)
			if m.kind[m.idx(tx, ty)] == WorldMap.Kind.PLAINS:
				m.kind[m.idx(tx, ty)] = k
				break


static func _town_score(m: WorldMap, tx: int, ty: int) -> float:
	var has_river := false
	var has_forest := false
	var has_hills := false
	var has_mountain_2 := false
	var has_mountain_1 := false
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var nx: int = tx + dx
			var ny: int = ty + dy
			if not m.in_bounds(nx, ny):
				continue
			var k: int = m.kind[m.idx(nx, ny)]
			if k == WorldMap.Kind.RIVER:
				has_river = true
			elif k == WorldMap.Kind.FOREST:
				has_forest = true
			elif k == WorldMap.Kind.HILLS:
				has_hills = true
			if k == WorldMap.Kind.MOUNTAIN:
				has_mountain_2 = true
				if maxi(absi(dx), absi(dy)) == 1:
					has_mountain_1 = true
	if has_mountain_1:
		return 0.0
	var s := 1.0
	if has_river:
		s += Tuning.TOWN_SCORE_RIVER
	if has_forest:
		s += Tuning.TOWN_SCORE_FOREST
	if has_hills:
		s += Tuning.TOWN_SCORE_HILLS
	if has_mountain_2:
		s *= Tuning.TOWN_SCORE_MOUNTAIN
	return s


static func _place_towns_scored(m: WorldMap, town_count: int) -> Array[Vector2i]:
	var comp := _largest_component(m)
	var cand_idx: Array[int] = []
	var cand_score: Array[float] = []
	for ty in range(m.rows):
		for tx in range(m.cols):
			var i := m.idx(tx, ty)
			if m.kind[i] != WorldMap.Kind.PLAINS:
				continue
			if not comp.has(i):
				continue
			if tx < 1 or tx > m.cols - 2 or ty < 1 or ty > m.rows - 2:
				continue
			var sc: float = _town_score(m, tx, ty)
			if sc <= 0.0:
				continue
			cand_idx.append(i)
			cand_score.append(sc)

	var blocked := PackedByteArray()
	blocked.resize(m.cols * m.rows)
	var towns: Array[Vector2i] = []
	for t in range(town_count):
		var total := 0.0
		for ci in range(cand_idx.size()):
			if blocked[cand_idx[ci]] == 0:
				total += cand_score[ci]
		if total <= 0.0:
			break
		var r: float = m.rng.randf() * total
		var running := 0.0
		var chosen := -1
		for ci in range(cand_idx.size()):
			if blocked[cand_idx[ci]] != 0:
				continue
			running += cand_score[ci]
			if running > r:
				chosen = ci
				break
		if chosen == -1:
			for ci in range(cand_idx.size()):
				if blocked[cand_idx[ci]] == 0:
					chosen = ci
		var idx: int = cand_idx[chosen]
		var tx2: int = idx % m.cols
		var ty2: int = idx / m.cols
		m.kind[idx] = WorldMap.Kind.TOWN
		towns.append(Vector2i(tx2, ty2))
		for dy in range(-(Tuning.TOWN_MIN_SPACING - 1), Tuning.TOWN_MIN_SPACING):
			for dx in range(-(Tuning.TOWN_MIN_SPACING - 1), Tuning.TOWN_MIN_SPACING):
				var nx: int = tx2 + dx
				var ny: int = ty2 + dy
				if m.in_bounds(nx, ny):
					blocked[m.idx(nx, ny)] = 1
	return towns


static func _farthest_point_order(m: WorldMap, towns: Array[Vector2i]) -> Array[Vector2i]:
	if towns.is_empty():
		return []
	var remaining: Array[int] = []
	for i in range(towns.size()):
		remaining.append(i)

	var best_i := 0
	var best_score: float = _town_score(m, towns[0].x, towns[0].y)
	var best_idx: int = m.idx(towns[0].x, towns[0].y)
	for i in range(1, towns.size()):
		var sc: float = _town_score(m, towns[i].x, towns[i].y)
		var idx: int = m.idx(towns[i].x, towns[i].y)
		if sc > best_score or (sc == best_score and idx < best_idx):
			best_score = sc
			best_idx = idx
			best_i = i

	var ordered: Array[Vector2i] = [towns[best_i]]
	remaining.remove_at(remaining.find(best_i))

	while not remaining.is_empty():
		var pick_pos := 0
		var pick_dist := -1.0
		for p in range(remaining.size()):
			var t: Vector2i = towns[remaining[p]]
			var min_d: float = INF
			for o in ordered:
				var dd: float = Vector2(t - o).length()
				if dd < min_d:
					min_d = dd
			if min_d > pick_dist:
				pick_dist = min_d
				pick_pos = p
		ordered.append(towns[remaining[pick_pos]])
		remaining.remove_at(pick_pos)

	return ordered


static func _is_border(tx: int, ty: int, cols: int, rows: int) -> bool:
	return tx == 0 or ty == 0 or tx == cols - 1 or ty == rows - 1


static func _block_all(before: PackedByteArray, m: WorldMap, bx: int, by: int, allowed: Array) -> bool:
	if not m.in_bounds(bx, by) or not m.in_bounds(bx + 1, by + 1):
		return false
	for oy in range(2):
		for ox in range(2):
			var k: int = before[m.idx(bx + ox, by + oy)]
			if not allowed.has(k):
				return false
	return true


static func _heap_push(hd: PackedFloat32Array, hi: PackedInt32Array, d: float, i: int) -> void:
	hd.append(d)
	hi.append(i)
	var c := hd.size() - 1
	while c > 0:
		var p := (c - 1) / 2
		if hd[p] <= hd[c]:
			break
		var td: float = hd[p]
		hd[p] = hd[c]
		hd[c] = td
		var ti: int = hi[p]
		hi[p] = hi[c]
		hi[c] = ti
		c = p


static func _heap_pop(hd: PackedFloat32Array, hi: PackedInt32Array) -> Array:
	var top_d: float = hd[0]
	var top_i: int = hi[0]
	var last := hd.size() - 1
	hd[0] = hd[last]
	hi[0] = hi[last]
	hd.resize(last)
	hi.resize(last)
	var p := 0
	while true:
		var l := p * 2 + 1
		var rr := p * 2 + 2
		var smallest := p
		if l < hd.size() and hd[l] < hd[smallest]:
			smallest = l
		if rr < hd.size() and hd[rr] < hd[smallest]:
			smallest = rr
		if smallest == p:
			break
		var td: float = hd[p]
		hd[p] = hd[smallest]
		hd[smallest] = td
		var ti: int = hi[p]
		hi[p] = hi[smallest]
		hi[smallest] = ti
		p = smallest
	return [top_d, top_i]


static func _carve_rivers(m: WorldMap, elevation: PackedFloat32Array) -> void:
	var hills_tiles: Array[Vector2i] = []
	for ty in range(m.rows):
		for tx in range(m.cols):
			if m.kind[m.idx(tx, ty)] == WorldMap.Kind.HILLS:
				hills_tiles.append(Vector2i(tx, ty))

	var neighbours: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var river_count: int = maxi(2, m.cols / 32)
	for r in range(river_count):
		if hills_tiles.is_empty():
			continue
		var start: Vector2i = hills_tiles[m.rng.randi_range(0, hills_tiles.size() - 1)]
		var cx := start.x
		var cy := start.y
		for step in range(200):
			m.kind[m.idx(cx, cy)] = WorldMap.Kind.RIVER
			if cx == 0 or cx == m.cols - 1 or cy == 0 or cy == m.rows - 1:
				break
			var best_x := -1
			var best_y := -1
			var best_e := INF
			for d in neighbours:
				var nx := cx + d.x
				var ny := cy + d.y
				if not m.in_bounds(nx, ny):
					continue
				var ne: float = elevation[m.idx(nx, ny)]
				if ne < best_e:
					best_e = ne
					best_x = nx
					best_y = ny
			if best_x == -1:
				break
			if m.kind[m.idx(best_x, best_y)] == WorldMap.Kind.MOUNTAIN:
				break
			cx = best_x
			cy = best_y


static func _scatter(m: WorldMap, k: int, count: int) -> void:
	for i in range(count):
		while true:
			var tx := m.rng.randi_range(0, m.cols - 1)
			var ty := m.rng.randi_range(0, m.rows - 1)
			if m.kind[m.idx(tx, ty)] == WorldMap.Kind.PLAINS:
				m.kind[m.idx(tx, ty)] = k
				break


static func _place_town(m: WorldMap, towns: Array[Vector2i], exclude_i: int = -1) -> Vector2i:
	for attempt in range(5000):
		var tx := m.rng.randi_range(0, m.cols - 1)
		var ty := m.rng.randi_range(0, m.rows - 1)
		if m.kind[m.idx(tx, ty)] != WorldMap.Kind.PLAINS:
			continue
		var ok := true
		for j in range(towns.size()):
			if j == exclude_i:
				continue
			var t: Vector2i = towns[j]
			if maxi(absi(tx - t.x), absi(ty - t.y)) < Tuning.TOWN_MIN_SPACING:
				ok = false
				break
		if ok:
			m.kind[m.idx(tx, ty)] = WorldMap.Kind.TOWN
			return Vector2i(tx, ty)
	return Vector2i(-1, -1)


static func _largest_component(m: WorldMap) -> Dictionary:
	var visited := {}
	var best := {}
	var neighbours: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for ty in range(m.rows):
		for tx in range(m.cols):
			var i := m.idx(tx, ty)
			if visited.has(i):
				continue
			if not m.passable(tx, ty):
				visited[i] = true
				continue
			var comp := {}
			comp[i] = true
			visited[i] = true
			var queue: Array[Vector2i] = [Vector2i(tx, ty)]
			while queue.size() > 0:
				var cur: Vector2i = queue.pop_front()
				for d in neighbours:
					var nx := cur.x + d.x
					var ny := cur.y + d.y
					if not m.in_bounds(nx, ny):
						continue
					var ni := m.idx(nx, ny)
					if visited.has(ni):
						continue
					if not m.passable(nx, ny):
						visited[ni] = true
						continue
					visited[ni] = true
					comp[ni] = true
					queue.append(Vector2i(nx, ny))
			if comp.size() > best.size():
				best = comp
	return best


static func _fix_isolated_towns(m: WorldMap, towns: Array[Vector2i]) -> void:
	# Fork tag: towns outside the largest passable component are re-rolled
	# up to 20 rounds; still outside afterwards -> dropped from the list.
	for round_i in range(20):
		var comp := _largest_component(m)
		var outside: Array[int] = []
		for i in range(towns.size()):
			var t: Vector2i = towns[i]
			if not comp.has(m.idx(t.x, t.y)):
				outside.append(i)
		if outside.is_empty():
			return
		for i in outside:
			var old: Vector2i = towns[i]
			m.kind[m.idx(old.x, old.y)] = WorldMap.Kind.PLAINS
		var to_drop: Array[int] = []
		for i in outside:
			var placed := _place_town(m, towns, i)
			if placed != Vector2i(-1, -1):
				towns[i] = placed
			else:
				to_drop.append(i)
		if not to_drop.is_empty():
			to_drop.sort()
			to_drop.reverse()
			for i in to_drop:
				towns.remove_at(i)
