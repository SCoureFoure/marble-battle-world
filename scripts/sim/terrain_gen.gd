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
