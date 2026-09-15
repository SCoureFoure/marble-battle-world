class_name WorldWfc
extends RefCounted
## Simple tiled Wave Function Collapse over small kind sets. Pure static functions.
## Source: docs/ARCHITECTURE.md §11.2.


static func biome_allow() -> PackedInt32Array:
	return PackedInt32Array([7, 7, 15, 12])


static func is_symmetric(allow: PackedInt32Array) -> bool:
	var n: int = allow.size()
	for a in range(n):
		for b in range(n):
			if ((allow[a] >> b) & 1) != ((allow[b] >> a) & 1):
				return false
	return true


static func _pair_allowed(gu: int, gv: int, allow: PackedInt32Array, k_count: int) -> bool:
	if gu < 0 or gu >= k_count or gv < 0 or gv >= k_count:
		return false
	return ((allow[gu] >> gv) & 1) == 1


static func violations(grid: PackedInt32Array, cols: int, rows: int, allow: PackedInt32Array) -> int:
	if grid.size() != cols * rows:
		return -1
	var k_count: int = allow.size()
	var count: int = 0
	for y in range(rows):
		for x in range(cols):
			var u: int = y * cols + x
			var gu: int = grid[u]
			if x + 1 < cols:
				var right: int = u + 1
				if not _pair_allowed(gu, grid[right], allow, k_count):
					count += 1
			if y + 1 < rows:
				var down: int = u + cols
				if not _pair_allowed(gu, grid[down], allow, k_count):
					count += 1
	return count


static func _popcount(x: int) -> int:
	var n: int = x
	var count: int = 0
	while n != 0:
		count += n & 1
		n = n >> 1
	return count


static func _neighbors(c: int, cols: int, rows: int) -> Array:
	var x: int = c % cols
	var y: int = c / cols
	var out: Array = []
	if y > 0:
		out.append(c - cols) # N
	if x + 1 < cols:
		out.append(c + 1) # E
	if y + 1 < rows:
		out.append(c + cols) # S
	if x > 0:
		out.append(c - 1) # W
	return out


static func _propagate(stack: Array, dom: PackedInt32Array, grid: PackedInt32Array, buckets: Array, allow: PackedInt32Array, cols: int, rows: int, k_count: int) -> bool:
	while stack.size() > 0:
		var u: int = stack.pop_back()
		var support: int = 0
		for k in range(k_count):
			if (dom[u] >> k) & 1 == 1:
				support |= allow[k]
		var neigh: Array = _neighbors(u, cols, rows)
		for v in neigh:
			var nd: int = dom[v] & support
			if nd == dom[v]:
				continue
			if nd == 0:
				return false
			dom[v] = nd
			var pc: int = _popcount(nd)
			if pc == 1:
				var kind: int = 0
				for k in range(k_count):
					if (nd >> k) & 1 == 1:
						kind = k
						break
				grid[v] = kind
			else:
				buckets[pc].append(v)
			stack.append(v)
	return true


static func _fallback_grid(cell_count: int, allow: PackedInt32Array, k_count: int) -> PackedInt32Array:
	var best_k: int = 0
	var best_bits: int = -1
	for k in range(k_count):
		var bits: int = _popcount(allow[k])
		if bits > best_bits:
			best_bits = bits
			best_k = k
	var grid: PackedInt32Array = PackedInt32Array()
	grid.resize(cell_count)
	for i in range(cell_count):
		grid[i] = best_k
	return grid


static func solve(cols: int, rows: int, allow: PackedInt32Array, prior: PackedFloat32Array, affinity: float, rng: RandomNumberGenerator, max_attempts: int) -> Dictionary:
	var k_count: int = allow.size()
	if cols <= 0 or rows <= 0 or k_count == 0:
		return {"grid": PackedInt32Array(), "attempts": 0, "fallback": false}
	var cell_count: int = cols * rows
	var use_uniform: bool = prior.size() != cell_count * k_count
	if max_attempts < 1:
		return {"grid": _fallback_grid(cell_count, allow, k_count), "attempts": 0, "fallback": true}

	for a in range(max_attempts):
		var full: int = (1 << k_count) - 1
		var dom: PackedInt32Array = PackedInt32Array()
		dom.resize(cell_count)
		for i in range(cell_count):
			dom[i] = full
		var grid: PackedInt32Array = PackedInt32Array()
		grid.resize(cell_count)
		for i in range(cell_count):
			grid[i] = -1
		var buckets: Array = []
		buckets.resize(k_count + 1)
		for i in range(k_count + 1):
			buckets[i] = []
		for i in range(cell_count):
			buckets[k_count].append(i)
		if k_count == 1:
			for i in range(cell_count):
				grid[i] = 0

		var stack: Array = []
		for i in range(cell_count):
			stack.append(i)
		var ok: bool = _propagate(stack, dom, grid, buckets, allow, cols, rows, k_count)
		if not ok:
			continue

		while true:
			var chosen: int = -1
			for p in range(2, k_count + 1):
				while buckets[p].size() > 0:
					var j: int = rng.randi_range(0, buckets[p].size() - 1)
					var c: int = buckets[p][j]
					var last_idx: int = buckets[p].size() - 1
					buckets[p][j] = buckets[p][last_idx]
					buckets[p].remove_at(last_idx)
					if grid[c] != -1 or _popcount(dom[c]) != p:
						continue
					chosen = c
					break
				if chosen != -1:
					break

			if chosen == -1:
				return {"grid": grid, "attempts": a + 1, "fallback": false}

			var k_list: Array = []
			for k in range(k_count):
				if (dom[chosen] >> k) & 1 == 1:
					k_list.append(k)
			var neigh: Array = _neighbors(chosen, cols, rows)
			var weights: Array = []
			var total: float = 0.0
			for k in k_list:
				var n_same: int = 0
				for v in neigh:
					if grid[v] == k:
						n_same += 1
				var base_w: float = 1.0
				if not use_uniform:
					base_w = prior[chosen * k_count + k]
				var w: float = base_w * pow(affinity, n_same)
				weights.append(w)
				total += w

			var r: float = rng.randf() * total
			var chosen_k: int = -1
			var running: float = 0.0
			for idx in range(k_list.size()):
				running += weights[idx]
				if running > r:
					chosen_k = k_list[idx]
					break
			if chosen_k == -1:
				if total > 0.0:
					for idx in range(k_list.size() - 1, -1, -1):
						if weights[idx] > 0.0:
							chosen_k = k_list[idx]
							break
				else:
					chosen_k = k_list[0]

			dom[chosen] = 1 << chosen_k
			grid[chosen] = chosen_k
			var stack2: Array = [chosen]
			var ok2: bool = _propagate(stack2, dom, grid, buckets, allow, cols, rows, k_count)
			if not ok2:
				break

	return {"grid": _fallback_grid(cell_count, allow, k_count), "attempts": max_attempts, "fallback": true}
