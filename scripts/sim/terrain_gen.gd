class_name TerrainGen
extends RefCounted
## Demo arena layout for the 1600x900 / cell 40 (40x23) grid. Source: docs/ARCHITECTURE.md §10.3
## and .warboss-horde/slices/m2-terrain-grid.md — draw order fixed so seeds reproduce.


static func demo(g: TerrainGrid, rng: RandomNumberGenerator) -> void:
	# 1. two mud blobs
	for i in 2:
		var cx := rng.randi_range(8, 31)
		var cy := rng.randi_range(3, 19)
		g.fill_rect(cx - 2, cy - 2, cx + 2, cy + 2, TerrainGrid.Kind.MUD)

	# 2. ice patch
	var icx := rng.randi_range(16, 23)
	var icy := rng.randi_range(2, 8)
	g.fill_rect(icx - 1, icy - 1, icx + 1, icy + 1, TerrainGrid.Kind.ICE)

	# 3. cobble road
	g.fill_rect(0, 11, g.cols - 1, 12, TerrainGrid.Kind.COBBLE)

	# 4. fire patch
	var fcx := rng.randi_range(16, 22)
	var fcy := rng.randi_range(14, 20)
	g.fill_rect(fcx, fcy, fcx + 1, fcy + 1, TerrainGrid.Kind.FIRE)

	# 5. rocks/trees
	for i in 12:
		var rcx := rng.randi_range(16, 24)
		var rcy := rng.randi_range(0, 22)
		var k: int = TerrainGrid.Kind.ROCK if rng.randf() < 0.5 else TerrainGrid.Kind.TREE
		if g.kind[rcy * g.cols + rcx] == TerrainGrid.Kind.PLAIN:
			g.set_cell(rcx, rcy, k)

	# 6. slope band, top two rows
	for cy in range(0, 2):
		for cx in range(0, g.cols):
			g.set_slope(cx, cy, Vector2(0, 40))

	# 7. tower at arena centre
	g.set_cell(g.cols / 2, g.rows / 2, TerrainGrid.Kind.TOWER)

	# 8. flowers
	_flowers_patches(g, rng, 1, 3, PackedInt32Array([]))


## Per-kind arena dressing for a world-map tile. Source: docs/ARCHITECTURE.md §11.5
## and .warboss-horde/slices/m3-arena-from-tile.md. `edges` are the local-faction
## edges already in use for this battle (from BattleBridge.edge_for) — obstacle
## and hazard cells whose centre lands inside any of those spawn rects are skipped
## (the rng draw for the attempt still happens, so later draws stay in sequence).
static func from_tile(g: TerrainGrid, kind: int, edges: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	match kind:
		WorldMap.Kind.PLAINS:
			_mud_blob(g, rng)
			_rocks_trees(g, rng, 3, 1.0, edges)
			_flowers_patches(g, rng, 2, 3, edges)
		WorldMap.Kind.FOREST:
			# UNDECIDED: §11.5 lists "20 trees, 1 mud" (trees first); placing the mud
			# blob before the tree attempts here instead, so a mud/tree overlap reads
			# as one of the "repeat cells" the slice's test comment already allows for,
			# rather than silently eating already-placed trees.
			_mud_blob(g, rng)
			_rocks_trees(g, rng, 20, 0.0, edges)
			_flowers_patches(g, rng, 1, 3, edges)
		WorldMap.Kind.HILLS:
			for cy in range(0, 8):
				for cx in range(g.cols):
					g.set_slope(cx, cy, Vector2(0, 40))
			for cy in range(15, g.rows):
				for cx in range(g.cols):
					g.set_slope(cx, cy, Vector2(0, -40))
			_rocks_trees(g, rng, 6, 1.0, edges)
			_flowers_patches(g, rng, 1, 4, edges)
		WorldMap.Kind.RIVER:
			g.fill_rect(19, 0, 20, g.rows - 1, TerrainGrid.Kind.WATER)
			g.fill_rect(19, 10, 20, 12, TerrainGrid.Kind.COBBLE)
			_rocks_trees(g, rng, 4, 1.0, edges)
			_flowers_patches(g, rng, 2, 3, edges)
		WorldMap.Kind.RUIN:
			g.fill_rect(0, 11, g.cols - 1, 12, TerrainGrid.Kind.COBBLE)
			_fire_patch(g, 17, 4, edges)
			_fire_patch(g, 21, 17, edges)
			_fire_patch(g, 23, 8, edges)
			_rocks_trees(g, rng, 6, 1.0, edges)
		WorldMap.Kind.GRAVEYARD:
			# UNDECIDED: §11.5 gives no fixed cells for the 4 SPIKE cells (unlike RUIN's
			# fire patches); placed here at arbitrary fixed tiles clear of the west/east
			# spawn rects so the exact-count test is deterministic. Placed after the mud
			# blobs so a blob can never eat a spike.
			_mud_blob(g, rng)
			_mud_blob(g, rng)
			_spike_cells(g, [Vector2i(15, 5), Vector2i(15, 17), Vector2i(24, 5), Vector2i(24, 17)], edges)
		WorldMap.Kind.TOWN:
			g.fill_rect(0, 11, g.cols - 1, 12, TerrainGrid.Kind.COBBLE)
			g.fill_rect(19, 0, 20, g.rows - 1, TerrainGrid.Kind.COBBLE)
			g.set_cell(20, 11, TerrainGrid.Kind.TOWER)
			_rocks_trees(g, rng, 4, 0.0, edges)
			_flowers_patches(g, rng, 2, 2, edges)
		WorldMap.Kind.MOUNTAIN:
			pass
		_:
			pass


static func _patch_intersects_spawn_rect(patch_cx: int, patch_cy: int, patch_size: int, g: TerrainGrid, edges: PackedInt32Array) -> bool:
	var patch_rect := Rect2(g.origin.x + patch_cx * g.cell, g.origin.y + patch_cy * g.cell, patch_size * g.cell, patch_size * g.cell)
	for e in edges:
		if patch_rect.intersects(BattleBridge.spawn_rect(e)):
			return true
	return false


static func _flowers_patches(g: TerrainGrid, rng: RandomNumberGenerator, patch_count: int, patch_size: int, edges: PackedInt32Array) -> void:
	for _patch_idx in patch_count:
		for _retry in range(50):
			var cx := rng.randi_range(0, g.cols - 1)
			var cy := rng.randi_range(0, g.rows - 1)

			# Check if patch intersects spawn rects
			if _patch_intersects_spawn_rect(cx, cy, patch_size, g, edges):
				continue

			# Place the patch (only on PLAIN cells)
			for dy in range(patch_size):
				for dx in range(patch_size):
					var gx := cx + dx
					var gy := cy + dy
					if gx < 0 or gx >= g.cols or gy < 0 or gy >= g.rows:
						continue
					if g.kind[gy * g.cols + gx] == TerrainGrid.Kind.PLAIN:
						g.set_cell(gx, gy, TerrainGrid.Kind.FLOWERS)

			break


static func _in_any_spawn_rect(p: Vector2, edges: PackedInt32Array) -> bool:
	for e in edges:
		if BattleBridge.spawn_rect(e).has_point(p):
			return true
	return false


## UNDECIDED: §11.5 gives no draw range for a mud blob's centre (unlike the
## rock/tree attempt loop below); reuses the same full-grid range for consistency.
## fill_rect is unconditional (mud is not an obstacle/hazard, so it is never
## spawn-rect-gated) and clamps to the grid, so this always adds mud cells.
static func _mud_blob(g: TerrainGrid, rng: RandomNumberGenerator) -> void:
	var cx := rng.randi_range(0, g.cols - 1)
	var cy := rng.randi_range(0, g.rows - 1)
	g.fill_rect(cx - 2, cy - 2, cx + 2, cy + 2, TerrainGrid.Kind.MUD)


static func _rocks_trees(g: TerrainGrid, rng: RandomNumberGenerator, attempts: int, rock_frac: float, edges: PackedInt32Array) -> void:
	for i in attempts:
		var cx := rng.randi_range(0, g.cols - 1)
		var cy := rng.randi_range(0, g.rows - 1)
		var roll := rng.randf()
		if g.kind[cy * g.cols + cx] != TerrainGrid.Kind.PLAIN:
			continue
		if _in_any_spawn_rect(g.cell_center(cy * g.cols + cx), edges):
			continue
		var k: int = TerrainGrid.Kind.ROCK if roll < rock_frac else TerrainGrid.Kind.TREE
		g.set_cell(cx, cy, k)


static func _fire_patch(g: TerrainGrid, cx: int, cy: int, edges: PackedInt32Array) -> void:
	for dy in range(2):
		for dx in range(2):
			var gx := cx + dx
			var gy := cy + dy
			if gx < 0 or gx >= g.cols or gy < 0 or gy >= g.rows:
				continue
			if _in_any_spawn_rect(g.cell_center(gy * g.cols + gx), edges):
				continue
			g.set_cell(gx, gy, TerrainGrid.Kind.FIRE)


static func _spike_cells(g: TerrainGrid, cells: Array, edges: PackedInt32Array) -> void:
	for c in cells:
		var cx: int = c.x
		var cy: int = c.y
		if _in_any_spawn_rect(g.cell_center(cy * g.cols + cx), edges):
			continue
		g.set_cell(cx, cy, TerrainGrid.Kind.SPIKE)
