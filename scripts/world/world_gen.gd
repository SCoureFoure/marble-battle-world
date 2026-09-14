class_name WorldGen
extends RefCounted
## Overworld map generation. Source: docs/ARCHITECTURE.md §11.2.

static func generate(m: WorldMap, town_count: int = -1) -> Array:
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
